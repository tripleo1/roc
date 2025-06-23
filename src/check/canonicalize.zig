const std = @import("std");
const base = @import("../base.zig");
const parse = @import("parse.zig");
const collections = @import("../collections.zig");
const types = @import("../types/types.zig");

const NodeStore = @import("./canonicalize/NodeStore.zig");
const Scope = @import("./canonicalize/Scope.zig");
const Node = @import("./canonicalize/Node.zig");

const AST = parse.AST;

can_ir: *CIR,
parse_ir: *AST,
scopes: std.ArrayListUnmanaged(Scope) = .{},
/// Stack of function regions for tracking var reassignment across function boundaries
function_regions: std.ArrayListUnmanaged(Region),
/// Maps var patterns to the function region they were declared in
var_function_regions: std.AutoHashMapUnmanaged(CIR.Pattern.Idx, Region),
/// Set of pattern indices that are vars
var_patterns: std.AutoHashMapUnmanaged(CIR.Pattern.Idx, void),
/// Tracks which pattern indices have been used/referenced
used_patterns: std.AutoHashMapUnmanaged(CIR.Pattern.Idx, void),
/// Maps identifier names to pending type annotations awaiting connection to declarations
pending_type_annos: std.StringHashMapUnmanaged(CIR.TypeAnno.Idx),

const Ident = base.Ident;
const Region = base.Region;
const TagName = base.TagName;
const ModuleEnv = base.ModuleEnv;
const CalledVia = base.CalledVia;
const exitOnOom = collections.utils.exitOnOom;

const TypeVar = types.Var;
const Content = types.Content;
const FlatType = types.FlatType;
const Num = types.Num;
const TagUnion = types.TagUnion;
const Tag = types.Tag;

const BUILTIN_BOOL: CIR.Pattern.Idx = @enumFromInt(0);
const BUILTIN_BOX: CIR.Pattern.Idx = @enumFromInt(1);
const BUILTIN_DECODE: CIR.Pattern.Idx = @enumFromInt(2);
const BUILTIN_DICT: CIR.Pattern.Idx = @enumFromInt(3);
const BUILTIN_ENCODE: CIR.Pattern.Idx = @enumFromInt(4);
const BUILTIN_HASH: CIR.Pattern.Idx = @enumFromInt(5);
const BUILTIN_INSPECT: CIR.Pattern.Idx = @enumFromInt(6);
const BUILTIN_LIST: CIR.Pattern.Idx = @enumFromInt(7);
const BUILTIN_NUM: CIR.Pattern.Idx = @enumFromInt(8);
const BUILTIN_RESULT: CIR.Pattern.Idx = @enumFromInt(9);
const BUILTIN_SET: CIR.Pattern.Idx = @enumFromInt(10);
const BUILTIN_STR: CIR.Pattern.Idx = @enumFromInt(11);

/// Deinitialize canonicalizer resources
pub fn deinit(
    self: *Self,
) void {
    const gpa = self.can_ir.env.gpa;

    // First deinit individual scopes
    for (0..self.scopes.items.len) |i| {
        var scope = &self.scopes.items[i];
        scope.deinit(gpa);
    }

    // Then deinit the collections
    self.scopes.deinit(gpa);
    self.function_regions.deinit(gpa);
    self.var_function_regions.deinit(gpa);
    self.var_patterns.deinit(gpa);
    self.used_patterns.deinit(gpa);
    self.pending_type_annos.deinit(gpa);
}

pub fn init(self: *CIR, parse_ir: *AST) Self {
    const gpa = self.env.gpa;

    // Create the canonicalizer with scopes
    var result = Self{
        .can_ir = self,
        .parse_ir = parse_ir,
        .scopes = .{},
        .function_regions = std.ArrayListUnmanaged(Region){},
        .var_function_regions = std.AutoHashMapUnmanaged(CIR.Pattern.Idx, Region){},
        .var_patterns = std.AutoHashMapUnmanaged(CIR.Pattern.Idx, void){},
        .used_patterns = std.AutoHashMapUnmanaged(CIR.Pattern.Idx, void){},
        .pending_type_annos = std.StringHashMapUnmanaged(CIR.TypeAnno.Idx){},
    };

    // Top-level scope is not a function boundary
    result.scopeEnter(gpa, false);

    // Simulate the builtins by adding to both the NodeStore and Scopes
    // Not sure if this is how we want to do it long term, but want something to
    // make a start on canonicalization.

    result.addBuiltin(self, "Bool", BUILTIN_BOOL);
    result.addBuiltin(self, "Box", BUILTIN_BOX);
    result.addBuiltin(self, "Decode", BUILTIN_DECODE);
    result.addBuiltin(self, "Dict", BUILTIN_DICT);
    result.addBuiltin(self, "Encode", BUILTIN_ENCODE);
    result.addBuiltin(self, "Hash", BUILTIN_HASH);
    result.addBuiltin(self, "Inspect", BUILTIN_INSPECT);
    result.addBuiltin(self, "List", BUILTIN_LIST);
    result.addBuiltin(self, "Num", BUILTIN_NUM);
    result.addBuiltin(self, "Result", BUILTIN_RESULT);
    result.addBuiltin(self, "Set", BUILTIN_SET);
    result.addBuiltin(self, "Str", BUILTIN_STR);

    // Add built-in types to the type scope
    // TODO: These should ultimately come from the platform/builtin files rather than being hardcoded
    result.addBuiltinType(self, "Bool");
    result.addBuiltinType(self, "Str");
    result.addBuiltinType(self, "U8");
    result.addBuiltinType(self, "U16");
    result.addBuiltinType(self, "U32");
    result.addBuiltinType(self, "U64");
    result.addBuiltinType(self, "U128");
    result.addBuiltinType(self, "I8");
    result.addBuiltinType(self, "I16");
    result.addBuiltinType(self, "I32");
    result.addBuiltinType(self, "I64");
    result.addBuiltinType(self, "I128");
    result.addBuiltinType(self, "F32");
    result.addBuiltinType(self, "F64");
    result.addBuiltinType(self, "Dec");
    result.addBuiltinType(self, "List");
    result.addBuiltinType(self, "Dict");
    result.addBuiltinType(self, "Set");
    result.addBuiltinType(self, "Result");
    result.addBuiltinType(self, "Box");

    return result;
}

fn addBuiltin(self: *Self, ir: *CIR, ident_text: []const u8, idx: CIR.Pattern.Idx) void {
    const gpa = ir.env.gpa;
    const ident_store = &ir.env.idents;
    const ident_add = ir.env.idents.insert(gpa, base.Ident.for_text(ident_text), Region.zero());
    const pattern_idx_add = ir.store.addPattern(CIR.Pattern{ .assign = .{ .ident = ident_add, .region = Region.zero() } });
    _ = self.scopeIntroduceInternal(gpa, ident_store, .ident, ident_add, pattern_idx_add, false, true);
    std.debug.assert(idx == pattern_idx_add);

    // TODO: Set correct type for builtins? But these types should ultimately
    // come from the builtins roc files, so maybe the resolve stage will handle?
    _ = ir.setTypeVarAtPat(pattern_idx_add, Content{ .flex_var = null });
}

fn addBuiltinType(self: *Self, ir: *CIR, type_name: []const u8) void {
    const gpa = ir.env.gpa;
    const type_ident = ir.env.idents.insert(gpa, base.Ident.for_text(type_name), Region.zero());

    // Create a type header for the built-in type
    const header_idx = ir.store.addTypeHeader(.{
        .name = type_ident,
        .args = .{ .span = .{ .start = 0, .len = 0 } }, // No type parameters for built-ins
        .region = Region.zero(),
    });

    // Create a type annotation that refers to itself (built-in types are primitive)
    const anno_idx = ir.store.addTypeAnno(.{ .ty = .{
        .symbol = type_ident,
        .region = Region.zero(),
    } });

    // Create the type declaration statement
    const type_decl_stmt = CIR.Statement{
        .type_decl = .{
            .header = header_idx,
            .anno = anno_idx,
            .where = null,
            .region = Region.zero(),
        },
    };

    const type_decl_idx = ir.store.addStatement(type_decl_stmt);

    // Add to scope without any error checking (built-ins are always valid)
    const current_scope = &self.scopes.items[self.scopes.items.len - 1];
    current_scope.put(gpa, .type_decl, type_ident, type_decl_idx);
}

const Self = @This();

/// The intermediate representation of a canonicalized Roc program.
pub const CIR = @import("canonicalize/CIR.zig");

/// After parsing a Roc program, the [ParseIR](src/check/parse/AST.zig) is transformed into a [canonical
/// form](src/check/canonicalize/ir.zig) called CanIR.
///
/// Canonicalization performs analysis to catch user errors, and sets up the state necessary to solve the types in a
/// program. Among other things, canonicalization;
/// - Uniquely identifies names (think variable and function names). Along the way,
///     canonicalization builds a graph of all variables' references, and catches
///     unused definitions, undefined definitions, and shadowed definitions.
/// - Resolves type signatures, including aliases, into a form suitable for type
///     solving.
/// - Determines the order definitions are used in, if they are defined
///     out-of-order.
/// - Eliminates syntax sugar (for example, renaming `+` to the function call `add`).
///
/// The canonicalization occurs on a single module (file) in isolation. This allows for this work to be easily parallelized and also cached. So where the source code for a module has not changed, the CanIR can simply be loaded from disk and used immediately.
pub fn canonicalize_file(
    self: *Self,
) void {
    const file = self.parse_ir.store.getFile();

    // canonicalize_header_packages();

    // Track the start of scratch defs and statements
    const scratch_defs_start = self.can_ir.store.scratchDefTop();
    const scratch_statements_start = self.can_ir.store.scratch_statements.top();

    // First pass: Process all type declarations to introduce them into scope
    for (self.parse_ir.store.statementSlice(file.statements)) |stmt_id| {
        const stmt = self.parse_ir.store.getStatement(stmt_id);
        switch (stmt) {
            .type_decl => |type_decl| {
                // Canonicalize the type declaration header first
                const header_idx = self.canonicalize_type_header(type_decl.header);

                // Process type parameters and annotation in a separate scope
                const anno_idx = blk: {
                    // Enter a new scope for type parameters
                    self.scopeEnter(self.can_ir.env.gpa, false);
                    defer self.scopeExit(self.can_ir.env.gpa) catch {};

                    // Introduce type parameters from the header into the scope
                    self.introduceTypeParametersFromHeader(header_idx);

                    // Now canonicalize the type annotation with type parameters in scope
                    break :blk self.canonicalize_type_anno(type_decl.anno);
                };

                // Create the CIR type declaration statement
                const region = self.parse_ir.tokenizedRegionToRegion(type_decl.region);
                const cir_type_decl = CIR.Statement{
                    .type_decl = .{
                        .header = header_idx,
                        .anno = anno_idx,
                        .where = null, // TODO: implement where clauses
                        .region = region,
                    },
                };

                const type_decl_idx = self.can_ir.store.addStatement(cir_type_decl);
                self.can_ir.store.addScratchStatement(type_decl_idx);

                // Introduce the type name into scope (now truly outside the parameter scope)
                const header = self.can_ir.store.getTypeHeader(header_idx);
                self.scopeIntroduceTypeDecl(header.name, type_decl_idx, region);
            },
            else => {
                // Skip non-type-declaration statements in first pass
            },
        }
    }

    // Second pass: Process all other statements
    for (self.parse_ir.store.statementSlice(file.statements)) |stmt_id| {
        const stmt = self.parse_ir.store.getStatement(stmt_id);
        switch (stmt) {
            .import => |_| {
                const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "top-level import");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .not_implemented = .{
                    .feature = feature,
                    .region = Region.zero(),
                } });
            },
            .decl => |decl| {
                const def_idx = self.canonicalize_decl(decl);
                self.can_ir.store.addScratchDef(def_idx);
            },
            .@"var" => {
                // Not valid at top-level
                const string_idx = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "var");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .invalid_top_level_statement = .{
                    .stmt = string_idx,
                } });
            },
            .expr => {
                // Not valid at top-level
                const string_idx = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "expr");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .invalid_top_level_statement = .{
                    .stmt = string_idx,
                } });
            },
            .crash => {
                // Not valid at top-level
                const string_idx = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "crash");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .invalid_top_level_statement = .{
                    .stmt = string_idx,
                } });
            },
            .expect => {
                const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "top-level expect");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .not_implemented = .{
                    .feature = feature,
                    .region = Region.zero(),
                } });
            },
            .@"for" => {
                // Not valid at top-level
                const string_idx = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "for");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .invalid_top_level_statement = .{
                    .stmt = string_idx,
                } });
            },
            .@"return" => {
                // Not valid at top-level
                const string_idx = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "return");
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .invalid_top_level_statement = .{
                    .stmt = string_idx,
                } });
            },
            .type_decl => {
                // Already processed in first pass, skip
            },
            .type_anno => |ta| {
                // Top-level type annotation - store for connection to next declaration
                const name = self.parse_ir.tokens.resolveIdentifier(ta.name) orelse {
                    // Malformed identifier - skip this annotation
                    continue;
                };

                // First, extract all type variables from the AST annotation
                var type_vars = std.ArrayList(Ident.Idx).init(self.can_ir.env.gpa);
                defer type_vars.deinit();
                self.extractTypeVarsFromASTAnno(ta.anno, &type_vars);

                // Enter a new scope for type variables
                self.scopeEnter(self.can_ir.env.gpa, false);
                defer self.scopeExit(self.can_ir.env.gpa) catch {};

                // Introduce type variables into scope
                for (type_vars.items) |type_var| {
                    // Create a dummy type annotation for the type variable
                    const region = Region.zero(); // TODO: get proper region from type variable
                    const dummy_anno = self.can_ir.store.addTypeAnno(.{ .ty_var = .{
                        .name = type_var,
                        .region = region,
                    } });
                    self.scopeIntroduceTypeVar(type_var, dummy_anno);
                }

                // Now canonicalize the annotation with type variables in scope
                const anno_idx = self.canonicalize_type_anno(ta.anno);

                // Store annotation for connection to next declaration
                const name_text = self.can_ir.env.idents.getText(name);
                self.pending_type_annos.put(self.can_ir.env.gpa, name_text, anno_idx) catch |err| exitOnOom(err);
            },
            .malformed => |malformed| {
                // We won't touch this since it's already a parse error.
                _ = malformed;
            },
        }
    }

    // Get the header and canonicalize exposes based on header type
    const header = self.parse_ir.store.getHeader(file.header);
    switch (header) {
        .module => |h| self.canonicalize_header_exposes(h.exposes),
        .package => |h| self.canonicalize_header_exposes(h.exposes),
        .platform => |h| self.canonicalize_header_exposes(h.exposes),
        .hosted => |h| self.canonicalize_header_exposes(h.exposes),
        .app => {
            // App headers have 'provides' instead of 'exposes'
            // TODO: Handle app provides differently
        },
        .malformed => {
            // Skip malformed headers
        },
    }

    // Create the span of all top-level defs and statements
    self.can_ir.all_defs = self.can_ir.store.defSpanFrom(scratch_defs_start);
    self.can_ir.all_statements = self.can_ir.store.statementSpanFrom(scratch_statements_start);
}

fn canonicalize_header_exposes(
    self: *Self,
    exposes: AST.Collection.Idx,
) void {
    const collection = self.parse_ir.store.getCollection(exposes);
    const exposed_items = self.parse_ir.store.exposedItemSlice(.{ .span = collection.span });

    for (exposed_items) |exposed_idx| {
        const exposed = self.parse_ir.store.getExposedItem(exposed_idx);
        switch (exposed) {
            .lower_ident => |ident| {
                // TODO -- do we need a Pattern for "exposed_lower" identifiers?
                _ = ident;
            },
            .upper_ident => |type_name| {
                // TODO -- do we need a Pattern for "exposed_upper" identifiers?
                _ = type_name;
            },
            .upper_ident_star => |type_with_constructors| {
                // TODO -- do we need a Pattern for "exposed_upper_star" identifiers?
                _ = type_with_constructors;
            },
        }
    }
}

fn bringImportIntoScope(
    self: *Self,
    import: *const AST.Statement,
) void {
    // const gpa = self.can_ir.env.gpa;
    // const import_name: []u8 = &.{}; // import.module_name_tok;
    // const shorthand: []u8 = &.{}; // import.qualifier_tok;
    // const region = Region{
    //     .start = Region.Position.zero(),
    //     .end = Region.Position.zero(),
    // };

    // const res = self.can_ir.imports.getOrInsert(gpa, import_name, shorthand);

    // if (res.was_present) {
    //     _ = self.can_ir.env.problems.append(gpa, Problem.Canonicalize.make(.{ .DuplicateImport = .{
    //         .duplicate_import_region = region,
    //     } }));
    // }

    const exposesSlice = self.parse_ir.store.exposedItemSlice(import.exposes);
    for (exposesSlice) |exposed_idx| {
        const exposed = self.parse_ir.store.getExposedItem(exposed_idx);
        switch (exposed) {
            .lower_ident => |ident| {

                // TODO handle `as` here using an Alias

                if (self.parse_ir.tokens.resolveIdentifier(ident.ident)) |ident_idx| {
                    _ = ident_idx;

                    // TODO Introduce our import

                    // _ = self.scope.levels.introduce(gpa, &self.can_ir.env.idents, .ident, .{ .scope_name = ident_idx, .ident = ident_idx });
                }
            },
            .upper_ident => |imported_type| {
                _ = imported_type;
                // const alias = Alias{
                //     .name = imported_type.name,
                //     .region = ir.env.tag_names.getRegion(imported_type.name),
                //     .is_builtin = false,
                //     .kind = .ImportedUnknown,
                // };
                // const alias_idx = ir.aliases.append(alias);
                //
                // _ = scope.levels.introduce(.alias, .{
                //     .scope_name = imported_type.name,
                //     .alias = alias_idx,
                // });
            },
            .upper_ident_star => |ident| {
                _ = ident;
            },
        }
    }
}

fn bringIngestedFileIntoScope(
    self: *Self,
    import: *const parse.AST.Stmt.Import,
) void {
    const res = self.can_ir.env.modules.getOrInsert(
        import.name,
        import.package_shorthand,
    );

    if (res.was_present) {
        // _ = self.can_ir.env.problems.append(Problem.Canonicalize.make(.DuplicateImport{
        //     .duplicate_import_region = import.name_region,
        // }));
    }

    // scope.introduce(self: *Scope, comptime item_kind: Level.ItemKind, ident: Ident.Idx)

    for (import.exposing.items.items) |exposed| {
        const exposed_ident = switch (exposed) {
            .Value => |ident| ident,
            .Type => |ident| ident,
            .CustomTagUnion => |custom| custom.name,
        };
        self.can_ir.env.addExposedIdentForModule(exposed_ident, res.module_idx);
        // TODO: Implement scope introduction for exposed identifiers
    }
}

fn canonicalize_decl(
    self: *Self,
    decl: AST.Statement.Decl,
) CIR.Def.Idx {
    const pattern_region = self.parse_ir.tokenizedRegionToRegion(self.parse_ir.store.getPattern(decl.pattern).to_tokenized_region());
    const expr_region = self.parse_ir.tokenizedRegionToRegion(self.parse_ir.store.getExpr(decl.body).to_tokenized_region());

    const pattern_idx = blk: {
        if (self.canonicalize_pattern(decl.pattern)) |idx| {
            break :blk idx;
        } else {
            const malformed_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .pattern_not_canonicalized = .{
                .region = pattern_region,
            } });
            break :blk malformed_idx;
        }
    };

    const expr_idx = blk: {
        if (self.canonicalize_expr(decl.body)) |idx| {
            break :blk idx;
        } else {
            const malformed_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .expr_not_canonicalized = .{
                .region = expr_region,
            } });
            break :blk malformed_idx;
        }
    };

    // Check for pending type annotation to connect to this declaration
    var annotation: ?CIR.Annotation.Idx = null;

    // Extract identifier from pattern if it's an identifier pattern
    const pattern = self.can_ir.store.getPattern(pattern_idx);
    if (pattern == .assign) {
        const ident = pattern.assign.ident;
        const ident_text = self.can_ir.env.idents.getText(ident);

        // Check if there's a pending type annotation for this identifier
        if (self.pending_type_annos.get(ident_text)) |type_anno_idx| {
            // Create a basic annotation from the type annotation
            const type_var = self.can_ir.pushFreshTypeVar(@enumFromInt(0), pattern_region);

            // For now, create a simple annotation with just the signature and region
            // TODO: Convert TypeAnno to proper type constraints and populate signature
            annotation = self.createAnnotationFromTypeAnno(type_anno_idx, type_var, pattern_region);

            _ = self.pending_type_annos.remove(ident_text);
        }
    }

    // Create the def entry
    const def_idx = self.can_ir.store.addDef(.{
        .pattern = pattern_idx,
        .pattern_region = pattern_region,
        .expr = expr_idx,
        .expr_region = expr_region,
        .annotation = annotation,
        .kind = .let,
    });
    _ = self.can_ir.setTypeVarAtDef(def_idx, Content{ .flex_var = null });

    return def_idx;
}

/// Canonicalize an expression.
pub fn canonicalize_expr(
    self: *Self,
    ast_expr_idx: AST.Expr.Idx,
) ?CIR.Expr.Idx {
    const expr = self.parse_ir.store.getExpr(ast_expr_idx);

    switch (expr) {
        .apply => |e| {
            // Mark the start of scratch expressions
            const scratch_top = self.can_ir.store.scratchExprTop();

            // Canonicalize the function being called and add as first element
            const fn_expr = self.canonicalize_expr(e.@"fn") orelse {
                self.can_ir.store.clearScratchExprsFrom(scratch_top);
                return null;
            };
            self.can_ir.store.addScratchExpr(fn_expr);

            // Canonicalize and add all arguments
            const args_slice = self.parse_ir.store.exprSlice(e.args);
            for (args_slice) |arg| {
                if (self.canonicalize_expr(arg)) |canonicalized_arg_expr_idx| {
                    self.can_ir.store.addScratchExpr(canonicalized_arg_expr_idx);
                }
            }

            // Create span from scratch expressions
            const args_span = self.can_ir.store.exprSpanFrom(scratch_top);

            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                .call = .{
                    .args = args_span,
                    .called_via = CalledVia.apply,
                    .region = self.parse_ir.tokenizedRegionToRegion(e.region),
                },
            });

            // Insert flex type variable
            _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .flex_var = null });

            return expr_idx;
        },
        .ident => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);
            if (self.parse_ir.tokens.resolveIdentifier(e.token)) |ident| {
                switch (self.scopeLookup(&self.can_ir.env.idents, .ident, ident)) {
                    .found => |pattern_idx| {
                        // Mark this pattern as used for unused variable checking
                        self.used_patterns.put(self.can_ir.env.gpa, pattern_idx, {}) catch |err| exitOnOom(err);

                        // Check if this is a used underscore variable
                        self.checkUsedUnderscoreVariable(ident, region);

                        // We found the ident in scope, lookup to reference the pattern
                        const expr_idx =
                            self.can_ir.store.addExpr(CIR.Expr{ .lookup = .{
                                .pattern_idx = pattern_idx,
                                .region = region,
                            } });
                        _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .flex_var = null });
                        return expr_idx;
                    },
                    .not_found => {
                        // We did not find the ident in scope
                        return self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .ident_not_in_scope = .{
                            .ident = ident,
                            .region = region,
                        } });
                    },
                }
            } else {
                const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "report an error when unable to resolve identifier");
                return self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                    .feature = feature,
                    .region = region,
                } });
            }
        },
        .int => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // resolve to a string slice from the source
            const token_text = self.parse_ir.resolve(e.token);

            // intern the string slice
            const literal = self.can_ir.env.strings.insert(self.can_ir.env.gpa, token_text);

            // parse the integer value
            const value = std.fmt.parseInt(i128, token_text, 10) catch {
                // Invalid number literal
                const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .invalid_num_literal = .{
                    .literal = literal,
                    .region = region,
                } });
                return expr_idx;
            };

            // create type vars, first "reserve" node slots
            const final_expr_idx = self.can_ir.store.predictNodeIndex(3);

            // then insert the type vars, setting the parent to be the final slot
            const precision_type_var = self.can_ir.pushFreshTypeVar(final_expr_idx, region);
            const int_type_var = self.can_ir.pushTypeVar(
                Content{ .structure = .{ .num = .{ .int_poly = precision_type_var } } },
                final_expr_idx,
                region,
            );

            // then in the final slot the actual expr is inserted
            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                .int = .{
                    .int_var = int_type_var,
                    .precision_var = precision_type_var,
                    .literal = literal,
                    .value = CIR.IntValue{
                        .bytes = @bitCast(value),
                        .kind = .i128,
                    },
                    .bound = Num.Int.Precision.fromValue(value),
                    .region = region,
                },
            });

            std.debug.assert(@intFromEnum(expr_idx) == @intFromEnum(final_expr_idx));

            // Insert concrete type variable
            _ = self.can_ir.setTypeVarAtExpr(
                expr_idx,
                Content{ .structure = .{ .num = .{ .num_poly = int_type_var } } },
            );

            return expr_idx;
        },
        .float => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // resolve to a string slice from the source
            const token_text = self.parse_ir.resolve(e.token);

            // intern the string slice
            const literal = self.can_ir.env.strings.insert(self.can_ir.env.gpa, token_text);

            // parse the float value
            const value = std.fmt.parseFloat(f64, token_text) catch {
                // Invalid number literal
                const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .invalid_num_literal = .{
                    .literal = literal,
                    .region = region,
                } });
                return expr_idx;
            };

            // create type vars, first "reserve" 3 can node slots
            const final_expr_idx = self.can_ir.store.predictNodeIndex(3);

            // then insert the type vars, setting the parent to be the final slot
            const precision_type_var = self.can_ir.pushFreshTypeVar(final_expr_idx, region);
            const float_type_var = self.can_ir.pushTypeVar(
                Content{ .structure = .{ .num = .{ .frac_poly = precision_type_var } } },
                final_expr_idx,
                region,
            );

            // then in the final slot the actual expr is inserted
            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                .float = .{
                    .frac_var = float_type_var,
                    .precision_var = precision_type_var,
                    .literal = literal,
                    .value = value,
                    .bound = Num.Frac.Precision.fromValue(value),
                    .region = region,
                },
            });

            std.debug.assert(@intFromEnum(expr_idx) == @intFromEnum(final_expr_idx));

            // Insert concrete type variable
            _ = self.can_ir.setTypeVarAtExpr(
                expr_idx,
                Content{ .structure = .{ .num = .{ .num_poly = float_type_var } } },
            );

            return expr_idx;
        },
        .string => |e| {
            // Get all the string parts
            const parts = self.parse_ir.store.exprSlice(e.parts);

            // Extract segments from the string, inserting them into the string interner
            // For non-string interpolation segments, canonicalize them
            //
            // Returns a Expr.Span containing the canonicalized string segments
            // a string may consist of multiple string literal or expression segments
            const str_segments_span = self.extractStringSegments(parts);

            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{ .str = .{
                .span = str_segments_span,
                .region = self.parse_ir.tokenizedRegionToRegion(e.region),
            } });

            // Insert concrete type variable
            _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .structure = .str });

            return expr_idx;
        },
        .list => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // Mark the start of scratch expressions for the list
            const scratch_top = self.can_ir.store.scratchExprTop();

            // Iterate over the list item, canonicalizing each one
            // Then append the result to the scratch list
            const items_slice = self.parse_ir.store.exprSlice(e.items);
            for (items_slice) |item| {
                if (self.canonicalize_expr(item)) |canonicalized| {
                    self.can_ir.store.addScratchExpr(canonicalized);
                }
            }

            // Create span of the new scratch expressions
            const elems_span = self.can_ir.store.exprSpanFrom(scratch_top);

            // create type vars, first "reserve" node slots
            const list_expr_idx = self.can_ir.store.predictNodeIndex(2);

            // then insert the type vars, setting the parent to be the final slot
            const elem_type_var = self.can_ir.pushFreshTypeVar(
                list_expr_idx,
                region,
            );

            // then in the final slot the actual expr is inserted
            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                .list = .{
                    .elems = elems_span,
                    .elem_var = elem_type_var,
                    .region = region,
                },
            });

            // Insert concrete type variable
            _ = self.can_ir.setTypeVarAtExpr(
                expr_idx,
                Content{ .structure = .{ .list = elem_type_var } },
            );

            return expr_idx;
        },
        .tag => |e| {
            if (self.parse_ir.tokens.resolveIdentifier(e.token)) |tag_name| {
                const region = self.parse_ir.tokenizedRegionToRegion(e.region);

                // create type vars, first "reserve" node slots
                const final_expr_idx = self.can_ir.store.predictNodeIndex(2);

                // then insert the type vars, setting the parent to be the final slot
                const ext_type_var = self.can_ir.pushFreshTypeVar(final_expr_idx, region);

                // then in the final slot the actual expr is inserted
                const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                    .tag = .{
                        .ext_var = ext_type_var,
                        .name = tag_name,
                        .args = .{ .span = .{ .start = 0, .len = 0 } }, // empty arguments
                        .region = region,
                    },
                });

                std.debug.assert(@intFromEnum(expr_idx) == @intFromEnum(final_expr_idx));

                // Insert concrete type variable
                const tag_union = self.can_ir.env.types.mkTagUnion(
                    &[_]Tag{Tag{ .name = tag_name, .args = types.Var.SafeList.Range.empty }},
                    ext_type_var,
                );
                _ = self.can_ir.setTypeVarAtExpr(expr_idx, tag_union);

                return expr_idx;
            } else {
                return null;
            }
        },
        .string_part => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize string_part expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .tuple => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // Mark the start of scratch expressions for the tuple
            const scratch_top = self.can_ir.store.scratchExprTop();

            // Iterate over the tuple items, canonicalizing each one
            // Then append the result to the scratch list
            const items_slice = self.parse_ir.store.exprSlice(e.items);
            for (items_slice) |item| {
                if (self.canonicalize_expr(item)) |canonicalized| {
                    self.can_ir.store.addScratchExpr(canonicalized);
                }
            }

            // Create span of the new scratch expressions
            const elems_span = self.can_ir.store.exprSpanFrom(scratch_top);

            // create type vars, first "reserve" node slots
            const tuple_expr_idx = self.can_ir.store.predictNodeIndex(2);

            // then insert the type vars, setting the parent to be the final slot
            const tuple_type_var = self.can_ir.pushFreshTypeVar(
                tuple_expr_idx,
                region,
            );

            // then in the final slot the actual expr is inserted
            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                .tuple = .{
                    .elems = elems_span,
                    .tuple_var = tuple_type_var,
                    .region = region,
                },
            });

            // Insert concrete type variable for tuple
            // TODO: Implement proper tuple type structure when tuple types are available
            _ = self.can_ir.setTypeVarAtExpr(
                expr_idx,
                Content{ .flex_var = null },
            );

            return expr_idx;
        },
        .record => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize record expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .lambda => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // Enter function boundary
            self.enterFunction(region);
            defer self.exitFunction();

            // Enter new scope for function parameters and body
            self.scopeEnter(self.can_ir.env.gpa, true); // true = is_function_boundary
            defer self.scopeExit(self.can_ir.env.gpa) catch {};

            // args
            const gpa = self.can_ir.env.gpa;
            const args_start = self.can_ir.store.scratch_patterns.top();
            for (self.parse_ir.store.patternSlice(e.args)) |arg_pattern_idx| {
                if (self.canonicalize_pattern(arg_pattern_idx)) |pattern_idx| {
                    self.can_ir.store.scratch_patterns.append(gpa, pattern_idx);
                } else {
                    const arg = self.parse_ir.store.getPattern(arg_pattern_idx);
                    const arg_region = self.parse_ir.tokenizedRegionToRegion(arg.to_tokenized_region());
                    const malformed_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .pattern_arg_invalid = .{
                        .region = arg_region,
                    } });
                    self.can_ir.store.scratch_patterns.append(gpa, malformed_idx);
                }
            }
            const args_span = self.can_ir.store.patternSpanFrom(args_start);

            // body
            const body_idx = blk: {
                if (self.canonicalize_expr(e.body)) |idx| {
                    break :blk idx;
                } else {
                    const ast_body = self.parse_ir.store.getExpr(e.body);
                    const body_region = self.parse_ir.tokenizedRegionToRegion(ast_body.to_tokenized_region());
                    break :blk self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{
                        .lambda_body_not_canonicalized = .{ .region = body_region },
                    });
                }
            };

            // Create lambda expression
            const lambda_expr = CIR.Expr{
                .lambda = .{
                    .args = args_span,
                    .body = body_idx,
                    .region = region,
                },
            };
            const expr_idx = self.can_ir.store.addExpr(lambda_expr);
            _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .flex_var = null });
            return expr_idx;
        },
        .record_updater => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize record_updater expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .field_access => |field_access| {
            // Canonicalize the receiver (left side of the dot)
            const receiver_idx = blk: {
                if (self.canonicalize_expr(field_access.left)) |idx| {
                    break :blk idx;
                } else {
                    // Failed to canonicalize receiver, return malformed
                    const region = self.parse_ir.tokenizedRegionToRegion(field_access.region);
                    return self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .expr_not_canonicalized = .{
                        .region = region,
                    } });
                }
            };

            // Parse the right side - this could be just a field name or a method call
            const right_expr = self.parse_ir.store.getExpr(field_access.right);

            var field_name: Ident.Idx = undefined;
            var args: ?CIR.Expr.Span = null;

            switch (right_expr) {
                .apply => |apply| {
                    // This is a method call like .map(fn)
                    const method_expr = self.parse_ir.store.getExpr(apply.@"fn");
                    switch (method_expr) {
                        .ident => |ident| {
                            // Get the method name
                            if (self.parse_ir.tokens.resolveIdentifier(ident.token)) |ident_idx| {
                                field_name = ident_idx;
                            } else {
                                // Fallback for malformed identifiers
                                field_name = self.can_ir.env.idents.insert(self.can_ir.env.gpa, base.Ident.for_text("unknown"), Region.zero());
                            }
                        },
                        else => {
                            // Fallback to a generic name
                            field_name = self.can_ir.env.idents.insert(self.can_ir.env.gpa, base.Ident.for_text("unknown"), Region.zero());
                        },
                    }

                    // Canonicalize the arguments using scratch system
                    const scratch_top = self.can_ir.store.scratchExprTop();
                    for (self.parse_ir.store.exprSlice(apply.args)) |arg_idx| {
                        if (self.canonicalize_expr(arg_idx)) |canonicalized| {
                            self.can_ir.store.addScratchExpr(canonicalized);
                        } else {
                            self.can_ir.store.clearScratchExprsFrom(scratch_top);
                            return null;
                        }
                    }
                    args = self.can_ir.store.exprSpanFrom(scratch_top);
                },
                .ident => |ident| {
                    // Get the field name
                    if (self.parse_ir.tokens.resolveIdentifier(ident.token)) |ident_idx| {
                        field_name = ident_idx;
                    } else {
                        // Fallback for malformed identifiers
                        field_name = self.can_ir.env.idents.insert(self.can_ir.env.gpa, base.Ident.for_text("unknown"), Region.zero());
                    }
                },
                else => {
                    // Fallback
                    field_name = self.can_ir.env.idents.insert(self.can_ir.env.gpa, base.Ident.for_text("unknown"), Region.zero());
                },
            }

            const dot_access_expr = CIR.Expr{
                .dot_access = .{
                    .receiver = receiver_idx,
                    .field_name = field_name,
                    .args = args,
                    .region = self.parse_ir.tokenizedRegionToRegion(field_access.region),
                },
            };

            const expr_idx = self.can_ir.store.addExpr(dot_access_expr);
            _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .flex_var = null });
            return expr_idx;
        },
        .local_dispatch => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize local_dispatch expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .bin_op => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // Canonicalize left and right operands
            const lhs = blk: {
                if (self.canonicalize_expr(e.left)) |left_expr_idx| {
                    break :blk left_expr_idx;
                } else {
                    // TODO should probably use LHS region here
                    const left_expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .expr_not_canonicalized = .{
                        .region = region,
                    } });
                    break :blk left_expr_idx;
                }
            };

            const rhs = blk: {
                if (self.canonicalize_expr(e.right)) |right_expr_idx| {
                    break :blk right_expr_idx;
                } else {
                    // TODO should probably use RHS region here
                    const right_expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .expr_not_canonicalized = .{
                        .region = region,
                    } });
                    break :blk right_expr_idx;
                }
            };

            // Get the operator token
            const op_token = self.parse_ir.tokens.tokens.get(e.operator);

            const op: CIR.Expr.Binop.Op = switch (op_token.tag) {
                .OpPlus => .add,
                .OpBinaryMinus => .sub,
                .OpStar => .mul,
                else => {
                    // Unknown operator
                    const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "binop");
                    const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                        .feature = feature,
                        .region = region,
                    } });
                    return expr_idx;
                },
            };

            const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                .binop = CIR.Expr.Binop.init(op, lhs, rhs, region),
            });

            _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .flex_var = null });

            return expr_idx;
        },
        .suffix_single_question => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize suffix_single_question expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .unary_op => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize unary_op expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .if_then_else => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize if_then_else expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .match => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize match expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .dbg => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize dbg expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .record_builder => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize record_builder expression");
            const expr_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return expr_idx;
        },
        .ellipsis => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "...");
            const diagnostic = self.can_ir.store.addDiagnostic(CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = region,
            } });
            const ellipsis_expr = self.can_ir.store.addExpr(CIR.Expr{ .runtime_error = .{
                .diagnostic = diagnostic,
                .region = region,
            } });
            return ellipsis_expr;
        },
        .block => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // Blocks don't introduce function boundaries, but may contain var statements
            self.scopeEnter(self.can_ir.env.gpa, false); // false = not a function boundary
            defer self.scopeExit(self.can_ir.env.gpa) catch {};

            // Keep track of the start position for statements
            const stmt_start = self.can_ir.store.scratch_statements.top();

            // Canonicalize all statements in the block
            const statements = self.parse_ir.store.statementSlice(e.statements);
            var last_expr: ?CIR.Expr.Idx = null;

            for (statements, 0..) |stmt_idx, i| {
                // Check if this is the last statement and if it's an expression
                const is_last = (i == statements.len - 1);
                const stmt = self.parse_ir.store.getStatement(stmt_idx);

                if (is_last and stmt == .expr) {
                    // For the last expression statement, canonicalize it directly as the final expression
                    // without adding it as a statement
                    last_expr = self.canonicalize_expr(stmt.expr.expr);
                } else {
                    // Regular statement processing
                    const result = self.canonicalize_statement(stmt_idx);
                    if (result) |expr_idx| {
                        last_expr = expr_idx;
                    }
                }
            }

            // Determine the final expression
            const final_expr = if (last_expr) |expr_idx| blk: {
                _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .flex_var = null });
                break :blk expr_idx;
            } else blk: {
                // Empty block - create empty record
                const expr_idx = self.can_ir.store.addExpr(CIR.Expr{
                    .empty_record = .{ .region = region },
                });
                _ = self.can_ir.setTypeVarAtExpr(expr_idx, Content{ .structure = .empty_record });
                break :blk expr_idx;
            };

            // Create statement span
            const stmt_span = self.can_ir.store.statementSpanFrom(stmt_start);

            // Create and return block expression
            const block_expr = CIR.Expr{
                .block = .{
                    .stmts = stmt_span,
                    .final_expr = final_expr,
                    .region = region,
                },
            };
            const block_idx = self.can_ir.store.addExpr(block_expr);

            // TODO: Propagate type from final expression during type checking
            // For now, create a fresh type var for the block
            _ = self.can_ir.setTypeVarAtExpr(block_idx, Content{ .flex_var = null });

            return block_idx;
        },
        .malformed => |malformed| {
            // We won't touch this since it's already a parse error.
            _ = malformed;
            return null;
        },
    }
}

/// Extract string segments from parsed string parts
fn extractStringSegments(self: *Self, parts: []const AST.Expr.Idx) CIR.Expr.Span {
    const gpa = self.can_ir.env.gpa;
    const start = self.can_ir.store.scratchExprTop();

    for (parts) |part| {
        const part_node = self.parse_ir.store.getExpr(part);
        switch (part_node) {
            .string_part => |sp| {
                // get the raw text of the string part
                const part_text = self.parse_ir.resolve(sp.token);

                // intern the string in the ModuleEnv
                const string_idx = self.can_ir.env.strings.insert(gpa, part_text);

                // create a node for the string literal
                const str_expr_idx = self.can_ir.store.addExpr(CIR.Expr{ .str_segment = .{
                    .literal = string_idx,
                    .region = self.parse_ir.tokenizedRegionToRegion(part_node.to_tokenized_region()),
                } });

                // add the node idx to our scratch expr stack
                self.can_ir.store.addScratchExpr(str_expr_idx);
            },
            else => {

                // Any non-string-part is an interpolation
                if (self.canonicalize_expr(part)) |expr_idx| {
                    // append our interpolated expression
                    self.can_ir.store.addScratchExpr(expr_idx);
                } else {
                    // unable to canonicalize the interpolation, push a malformed node
                    const region = self.parse_ir.tokenizedRegionToRegion(part_node.to_tokenized_region());
                    const malformed_idx = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .invalid_string_interpolation = .{
                        .region = region,
                    } });
                    self.can_ir.store.addScratchExpr(malformed_idx);
                }
            },
        }
    }

    return self.can_ir.store.exprSpanFrom(start);
}

fn canonicalize_pattern(
    self: *Self,
    ast_pattern_idx: AST.Pattern.Idx,
) ?CIR.Pattern.Idx {
    const gpa = self.can_ir.env.gpa;
    switch (self.parse_ir.store.getPattern(ast_pattern_idx)) {
        .ident => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);
            if (self.parse_ir.tokens.resolveIdentifier(e.ident_tok)) |ident_idx| {
                // Push a Pattern node for our identifier
                const assign_idx = self.can_ir.store.addPattern(CIR.Pattern{ .assign = .{
                    .ident = ident_idx,
                    .region = region,
                } });
                _ = self.can_ir.setTypeVarAtPat(assign_idx, .{ .flex_var = null });

                // Introduce the identifier into scope mapping to this pattern node
                switch (self.scopeIntroduceInternal(self.can_ir.env.gpa, &self.can_ir.env.idents, .ident, ident_idx, assign_idx, false, true)) {
                    .success => {},
                    .shadowing_warning => |shadowed_pattern_idx| {
                        const shadowed_pattern = self.can_ir.store.getPattern(shadowed_pattern_idx);
                        const original_region = shadowed_pattern.toRegion();
                        self.can_ir.pushDiagnostic(CIR.Diagnostic{ .shadowing_warning = .{
                            .ident = ident_idx,
                            .region = region,
                            .original_region = original_region,
                        } });
                    },
                    .top_level_var_error => {
                        return self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .invalid_top_level_statement = .{
                            .stmt = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "var"),
                        } });
                    },
                    .var_across_function_boundary => {
                        return self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .ident_already_in_scope = .{
                            .ident = ident_idx,
                            .region = region,
                        } });
                    },
                }

                return assign_idx;
            } else {
                const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "report an error when unable to resolve identifier");
                const malformed_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .not_implemented = .{
                    .feature = feature,
                    .region = Region.zero(),
                } });
                return malformed_idx;
            }
        },
        .underscore => |p| {
            const underscore_pattern = CIR.Pattern{
                .underscore = .{
                    .region = self.parse_ir.tokenizedRegionToRegion(p.region),
                },
            };

            const pattern_idx = self.can_ir.store.addPattern(underscore_pattern);

            _ = self.can_ir.setTypeVarAtPat(pattern_idx, Content{ .flex_var = null });

            return pattern_idx;
        },
        .number => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // resolve to a string slice from the source
            const token_text = self.parse_ir.resolve(e.number_tok);

            // intern the string slice
            const literal = self.can_ir.env.strings.insert(gpa, token_text);

            // parse the integer value
            const value = std.fmt.parseInt(i128, token_text, 10) catch {
                // Invalid num literal
                const malformed_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .invalid_num_literal = .{
                    .literal = literal,
                    .region = region,
                } });
                return malformed_idx;
            };

            // create type vars, first "reserve" node slots
            const final_pattern_idx = self.can_ir.store.predictNodeIndex(2);

            // then insert the type vars, setting the parent to be the final slot
            const num_type_var = self.can_ir.pushFreshTypeVar(final_pattern_idx, region);

            // then in the final slot the actual pattern is inserted
            const num_pattern = CIR.Pattern{
                .num_literal = .{
                    .num_var = num_type_var,
                    .literal = literal,
                    .value = CIR.IntValue{
                        .bytes = @bitCast(value),
                        .kind = .i128,
                    },
                    .bound = Num.Int.Precision.fromValue(value),
                    .region = region,
                },
            };
            const pattern_idx = self.can_ir.store.addPattern(num_pattern);

            std.debug.assert(@intFromEnum(pattern_idx) == @intFromEnum(final_pattern_idx));

            // Set the concrete type variable
            _ = self.can_ir.setTypeVarAtPat(pattern_idx, Content{
                .structure = .{ .num = .{ .num_poly = num_type_var } },
            });

            return pattern_idx;
        },
        .string => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // resolve to a string slice from the source
            const token_text = self.parse_ir.resolve(e.string_tok);

            // TODO: Handle escape sequences
            // For now, just intern the raw string
            const literal = self.can_ir.env.strings.insert(gpa, token_text);

            const str_pattern = CIR.Pattern{
                .str_literal = .{
                    .literal = literal,
                    .region = region,
                },
            };
            const pattern_idx = self.can_ir.store.addPattern(str_pattern);

            // Set the concrete type variable
            _ = self.can_ir.setTypeVarAtPat(pattern_idx, Content{ .structure = .str });

            return pattern_idx;
        },
        .tag => |e| {
            if (self.parse_ir.tokens.resolveIdentifier(e.tag_tok)) |tag_name| {
                const start = self.can_ir.store.scratch_patterns.top();

                for (self.parse_ir.store.patternSlice(e.args)) |sub_ast_pattern_idx| {
                    if (self.canonicalize_pattern(sub_ast_pattern_idx)) |idx| {
                        self.can_ir.store.scratch_patterns.append(gpa, idx);
                    } else {
                        const arg = self.parse_ir.store.getPattern(sub_ast_pattern_idx);
                        const arg_region = self.parse_ir.tokenizedRegionToRegion(arg.to_tokenized_region());
                        const malformed_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .pattern_arg_invalid = .{
                            .region = arg_region,
                        } });
                        self.can_ir.store.scratch_patterns.append(gpa, malformed_idx);
                    }
                }

                const region = self.parse_ir.tokenizedRegionToRegion(e.region);

                const args = self.can_ir.store.patternSpanFrom(start);

                // create type vars, first "reserve" node slots
                const final_pattern_idx = self.can_ir.store.predictNodeIndex(2);

                // then insert the type vars, setting the parent to be the final slot
                const ext_type_var = self.can_ir.pushFreshTypeVar(final_pattern_idx, region);

                // then in the final slot the actual pattern is inserted
                const tag_pattern = CIR.Pattern{
                    .applied_tag = .{
                        .ext_var = ext_type_var,
                        .tag_name = tag_name,
                        .arguments = args,
                        .region = region,
                    },
                };
                const pattern_idx = self.can_ir.store.addPattern(tag_pattern);

                std.debug.assert(@intFromEnum(pattern_idx) == @intFromEnum(final_pattern_idx));

                // Set the concrete type variable
                const tag_union_type = self.can_ir.env.types.mkTagUnion(
                    &[_]Tag{Tag{ .name = tag_name, .args = types.Var.SafeList.Range.empty }},
                    ext_type_var,
                );
                _ = self.can_ir.setTypeVarAtPat(pattern_idx, tag_union_type);

                return pattern_idx;
            }
            return null;
        },
        .record => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize record pattern");
            const pattern_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return pattern_idx;
        },
        .tuple => |e| {
            const region = self.parse_ir.tokenizedRegionToRegion(e.region);

            // Mark the start of scratch patterns for the tuple
            const scratch_top = self.can_ir.store.scratchPatternTop();

            // Iterate over the tuple patterns, canonicalizing each one
            // Then append the result to the scratch list
            const patterns_slice = self.parse_ir.store.patternSlice(e.patterns);
            for (patterns_slice) |pattern| {
                if (self.canonicalize_pattern(pattern)) |canonicalized| {
                    self.can_ir.store.addScratchPattern(canonicalized);
                }
            }

            // Create span of the new scratch patterns
            const patterns_span = self.can_ir.store.patternSpanFrom(scratch_top);

            // create type vars, first "reserve" node slots
            const tuple_pattern_idx = self.can_ir.store.predictNodeIndex(2);

            // then insert the type vars, setting the parent to be the final slot
            const tuple_type_var = self.can_ir.pushFreshTypeVar(
                tuple_pattern_idx,
                region,
            );

            // then in the final slot the actual pattern is inserted
            const pattern_idx = self.can_ir.store.addPattern(CIR.Pattern{
                .tuple = .{
                    .patterns = patterns_span,
                    .tuple_var = tuple_type_var,
                    .region = region,
                },
            });

            // Insert concrete type variable for tuple pattern
            // TODO: Implement proper tuple type structure when tuple types are available
            _ = self.can_ir.setTypeVarAtPat(
                pattern_idx,
                Content{ .flex_var = null },
            );

            return pattern_idx;
        },
        .list => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize list pattern");
            const pattern_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return pattern_idx;
        },
        .list_rest => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize list rest pattern");
            const pattern_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return pattern_idx;
        },
        .alternatives => |_| {
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "canonicalize alternatives pattern");
            const pattern_idx = self.can_ir.pushMalformed(CIR.Pattern.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
            return pattern_idx;
        },
        .malformed => |malformed| {
            // We won't touch this since it's already a parse error.
            _ = malformed;
            return null;
        },
    }
}

/// Enter a function boundary by pushing its region onto the stack
fn enterFunction(self: *Self, region: Region) void {
    self.function_regions.append(self.can_ir.env.gpa, region) catch |err| exitOnOom(err);
}

/// Exit a function boundary by popping from the stack
fn exitFunction(self: *Self) void {
    _ = self.function_regions.pop();
}

/// Get the current function region (the function we're currently in)
fn getCurrentFunctionRegion(self: *const Self) ?Region {
    if (self.function_regions.items.len > 0) {
        return self.function_regions.items[self.function_regions.items.len - 1];
    }
    return null;
}

/// Record which function a var pattern was declared in
fn recordVarFunction(self: *Self, pattern_idx: CIR.Pattern.Idx) void {
    // Mark this pattern as a var
    self.var_patterns.put(self.can_ir.env.gpa, pattern_idx, {}) catch |err| exitOnOom(err);

    if (self.getCurrentFunctionRegion()) |function_region| {
        self.var_function_regions.put(self.can_ir.env.gpa, pattern_idx, function_region) catch |err| exitOnOom(err);
    }
}

/// Check if a pattern is a var
fn isVarPattern(self: *const Self, pattern_idx: CIR.Pattern.Idx) bool {
    return self.var_patterns.contains(pattern_idx);
}

/// Check if a var reassignment crosses function boundaries
fn isVarReassignmentAcrossFunctionBoundary(self: *const Self, pattern_idx: CIR.Pattern.Idx) bool {
    if (self.var_function_regions.get(pattern_idx)) |var_function_region| {
        if (self.getCurrentFunctionRegion()) |current_function_region| {
            return !var_function_region.eq(current_function_region);
        }
    }
    return false;
}

/// Introduce a new identifier to the current scope, return an
/// index if
fn scopeIntroduceIdent(
    self: Self,
    ident_idx: Ident.Idx,
    pattern_idx: CIR.Pattern.Idx,
    region: Region,
    comptime T: type,
) T {
    const result = self.scopeIntroduceInternal(self.can_ir.env.gpa, &self.can_ir.env.idents, .ident, ident_idx, pattern_idx, false, true);

    switch (result) {
        .success => {
            return pattern_idx;
        },
        .shadowing_warning => |shadowed_pattern_idx| {
            const shadowed_pattern = self.can_ir.store.getPattern(shadowed_pattern_idx);
            const original_region = shadowed_pattern.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{ .shadowing_warning = .{
                .ident = ident_idx,
                .region = region,
                .original_region = original_region,
            } });
            return pattern_idx;
        },
        .top_level_var_error => {
            return self.can_ir.pushMalformed(T, CIR.Diagnostic{ .invalid_top_level_statement = .{
                .stmt = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "var"),
            } });
        },
        .var_across_function_boundary => |_| {
            // This shouldn't happen for regular identifiers
            return self.can_ir.pushMalformed(T, CIR.Diagnostic{ .not_implemented = .{
                .feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "var across function boundary for non-var identifier"),
                .region = region,
            } });
        },
    }
}

/// Introduce a var identifier to the current scope with function boundary tracking
fn scopeIntroduceVar(
    self: *Self,
    ident_idx: Ident.Idx,
    pattern_idx: CIR.Pattern.Idx,
    region: Region,
    is_declaration: bool,
    comptime T: type,
) T {
    const result = self.scopeIntroduceInternal(self.can_ir.env.gpa, &self.can_ir.env.idents, .ident, ident_idx, pattern_idx, true, is_declaration);

    switch (result) {
        .success => {
            // If this is a var declaration, record which function it belongs to
            if (is_declaration) {
                self.recordVarFunction(pattern_idx);
            }
            return pattern_idx;
        },
        .shadowing_warning => |shadowed_pattern_idx| {
            const shadowed_pattern = self.can_ir.store.getPattern(shadowed_pattern_idx);
            const original_region = shadowed_pattern.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{ .shadowing_warning = .{
                .ident = ident_idx,
                .region = region,
                .original_region = original_region,
            } });
            if (is_declaration) {
                self.recordVarFunction(pattern_idx);
            }
            return pattern_idx;
        },
        .top_level_var_error => {
            return self.can_ir.pushMalformed(T, CIR.Diagnostic{ .invalid_top_level_statement = .{
                .stmt = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "var"),
            } });
        },
        .var_across_function_boundary => |_| {
            // Generate crash expression for var reassignment across function boundary
            return self.can_ir.pushMalformed(T, CIR.Diagnostic{ .var_across_function_boundary = .{
                .region = region,
            } });
        },
    }
}

/// Canonicalize a statement within a block
fn canonicalize_type_anno(self: *Self, anno_idx: AST.TypeAnno.Idx) CIR.TypeAnno.Idx {
    const ast_anno = self.parse_ir.store.getTypeAnno(anno_idx);
    switch (ast_anno) {
        .apply => |apply| {
            const region = self.parse_ir.tokenizedRegionToRegion(apply.region);
            const args_slice = self.parse_ir.store.typeAnnoSlice(apply.args);

            // Validate we have arguments
            if (args_slice.len == 0) {
                return self.can_ir.pushMalformed(CIR.TypeAnno.Idx, CIR.Diagnostic{ .malformed_type_annotation = .{ .region = region } });
            }

            // First argument is the type constructor
            const base_type = self.parse_ir.store.getTypeAnno(args_slice[0]);
            const type_name = switch (base_type) {
                .ty => |ty| ty.ident,
                else => return self.can_ir.pushMalformed(CIR.TypeAnno.Idx, CIR.Diagnostic{ .malformed_type_annotation = .{ .region = region } }),
            };

            // Canonicalize type arguments (skip first which is the type name)
            const scratch_top = self.can_ir.store.scratchTypeAnnoTop();
            defer self.can_ir.store.clearScratchTypeAnnosFrom(scratch_top);

            for (args_slice[1..]) |arg_idx| {
                const canonicalized = self.canonicalize_type_anno(arg_idx);
                self.can_ir.store.addScratchTypeAnno(canonicalized);
            }

            const args = self.can_ir.store.typeAnnoSpanFrom(scratch_top);
            return self.can_ir.store.addTypeAnno(.{ .apply = .{
                .symbol = type_name,
                .args = args,
                .region = region,
            } });
        },
        .ty_var => |ty_var| {
            const region = self.parse_ir.tokenizedRegionToRegion(ty_var.region);
            const name_ident = self.parse_ir.tokens.resolveIdentifier(ty_var.tok) orelse {
                return self.can_ir.pushMalformed(CIR.TypeAnno.Idx, CIR.Diagnostic{ .malformed_type_annotation = .{
                    .region = region,
                } });
            };

            // Check if this type variable is in scope
            const type_var_in_scope = self.scopeLookupTypeVar(name_ident);
            if (type_var_in_scope == null) {
                // Type variable not found in scope - issue diagnostic
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .undeclared_type_var = .{
                    .name = name_ident,
                    .region = region,
                } });
            }

            return self.can_ir.store.addTypeAnno(.{ .ty_var = .{
                .name = name_ident,
                .region = region,
            } });
        },
        .ty => |ty| {
            const region = self.parse_ir.tokenizedRegionToRegion(ty.region);

            // Check if this type is declared in scope
            if (self.scopeLookupTypeDecl(ty.ident)) |_| {
                // Type found in scope - good!
                // TODO: We could store a reference to the type declaration for better error messages
            } else {
                // Type not found in scope - issue diagnostic
                self.can_ir.pushDiagnostic(CIR.Diagnostic{ .undeclared_type = .{
                    .name = ty.ident,
                    .region = region,
                } });
            }

            return self.can_ir.store.addTypeAnno(.{ .ty = .{
                .symbol = ty.ident,
                .region = region,
            } });
        },
        .mod_ty => |mod_ty| {
            const region = self.parse_ir.tokenizedRegionToRegion(mod_ty.region);
            return self.can_ir.store.addTypeAnno(.{ .mod_ty = .{
                .mod_symbol = mod_ty.mod_ident,
                .ty_symbol = mod_ty.ty_ident,
                .region = region,
            } });
        },
        .underscore => |underscore| {
            const region = self.parse_ir.tokenizedRegionToRegion(underscore.region);
            return self.can_ir.store.addTypeAnno(.{ .underscore = .{
                .region = region,
            } });
        },
        .tuple => |tuple| {
            const region = self.parse_ir.tokenizedRegionToRegion(tuple.region);
            // Canonicalize all tuple elements
            const scratch_top = self.can_ir.store.scratchTypeAnnoTop();
            defer self.can_ir.store.clearScratchTypeAnnosFrom(scratch_top);

            for (self.parse_ir.store.typeAnnoSlice(tuple.annos)) |elem_idx| {
                const canonicalized = self.canonicalize_type_anno(elem_idx);
                self.can_ir.store.addScratchTypeAnno(canonicalized);
            }

            const annos = self.can_ir.store.typeAnnoSpanFrom(scratch_top);
            return self.can_ir.store.addTypeAnno(.{ .tuple = .{
                .annos = annos,
                .region = region,
            } });
        },
        .record => |record| {
            const region = self.parse_ir.tokenizedRegionToRegion(record.region);

            // Canonicalize all record fields
            const scratch_top = self.can_ir.store.scratchAnnoRecordFieldTop();
            defer self.can_ir.store.clearScratchAnnoRecordFieldsFrom(scratch_top);

            for (self.parse_ir.store.annoRecordFieldSlice(record.fields)) |field_idx| {
                const ast_field = self.parse_ir.store.getAnnoRecordField(field_idx);

                // Resolve field name
                const field_name = self.parse_ir.tokens.resolveIdentifier(ast_field.name) orelse {
                    // Malformed field name - continue with placeholder
                    const malformed_field_ident = Ident.for_text("malformed_field");
                    const malformed_ident = self.can_ir.env.idents.insert(self.can_ir.env.gpa, malformed_field_ident, Region.zero());
                    const canonicalized_ty = self.canonicalize_type_anno(ast_field.ty);
                    const field_region = self.parse_ir.tokenizedRegionToRegion(ast_field.region);

                    const cir_field = CIR.AnnoRecordField{
                        .name = malformed_ident,
                        .ty = canonicalized_ty,
                        .region = field_region,
                    };
                    const field_cir_idx = self.can_ir.store.addAnnoRecordField(cir_field);
                    self.can_ir.store.addScratchAnnoRecordField(field_cir_idx);
                    continue;
                };

                // Canonicalize field type
                const canonicalized_ty = self.canonicalize_type_anno(ast_field.ty);
                const field_region = self.parse_ir.tokenizedRegionToRegion(ast_field.region);

                const cir_field = CIR.AnnoRecordField{
                    .name = field_name,
                    .ty = canonicalized_ty,
                    .region = field_region,
                };
                const field_cir_idx = self.can_ir.store.addAnnoRecordField(cir_field);
                self.can_ir.store.addScratchAnnoRecordField(field_cir_idx);
            }

            const fields = self.can_ir.store.annoRecordFieldSpanFrom(scratch_top);
            return self.can_ir.store.addTypeAnno(.{ .record = .{
                .fields = fields,
                .region = region,
            } });
        },
        .tag_union => |tag_union| {
            const region = self.parse_ir.tokenizedRegionToRegion(tag_union.region);

            // Canonicalize all tags in the union
            const scratch_top = self.can_ir.store.scratchTypeAnnoTop();
            defer self.can_ir.store.clearScratchTypeAnnosFrom(scratch_top);

            for (self.parse_ir.store.typeAnnoSlice(tag_union.tags)) |tag_idx| {
                const canonicalized = self.canonicalize_type_anno(tag_idx);
                self.can_ir.store.addScratchTypeAnno(canonicalized);
            }

            const tags = self.can_ir.store.typeAnnoSpanFrom(scratch_top);

            // Handle optional open annotation (for extensible tag unions)
            const open_anno = if (tag_union.open_anno) |open_idx|
                self.canonicalize_type_anno(open_idx)
            else
                null;

            return self.can_ir.store.addTypeAnno(.{ .tag_union = .{
                .tags = tags,
                .open_anno = open_anno,
                .region = region,
            } });
        },
        .@"fn" => |fn_anno| {
            const region = self.parse_ir.tokenizedRegionToRegion(fn_anno.region);

            // Canonicalize argument types
            const scratch_top = self.can_ir.store.scratchTypeAnnoTop();
            defer self.can_ir.store.clearScratchTypeAnnosFrom(scratch_top);

            for (self.parse_ir.store.typeAnnoSlice(fn_anno.args)) |arg_idx| {
                const canonicalized = self.canonicalize_type_anno(arg_idx);
                self.can_ir.store.addScratchTypeAnno(canonicalized);
            }

            const args = self.can_ir.store.typeAnnoSpanFrom(scratch_top);

            // Canonicalize return type
            const ret = self.canonicalize_type_anno(fn_anno.ret);

            return self.can_ir.store.addTypeAnno(.{ .@"fn" = .{
                .args = args,
                .ret = ret,
                .effectful = fn_anno.effectful,
                .region = region,
            } });
        },
        .parens => |parens| {
            const region = self.parse_ir.tokenizedRegionToRegion(parens.region);
            const inner_anno = self.canonicalize_type_anno(parens.anno);
            return self.can_ir.store.addTypeAnno(.{ .parens = .{
                .anno = inner_anno,
                .region = region,
            } });
        },
        .malformed => |malformed| {
            const region = self.parse_ir.tokenizedRegionToRegion(malformed.region);
            return self.can_ir.pushMalformed(CIR.TypeAnno.Idx, CIR.Diagnostic{ .malformed_type_annotation = .{
                .region = region,
            } });
        },
    }
}

fn canonicalize_type_header(self: *Self, header_idx: AST.TypeHeader.Idx) CIR.TypeHeader.Idx {
    const ast_header = self.parse_ir.store.getTypeHeader(header_idx);
    const region = self.parse_ir.tokenizedRegionToRegion(ast_header.region);

    // Get the type name identifier
    const name_ident = self.parse_ir.tokens.resolveIdentifier(ast_header.name) orelse {
        // If we can't resolve the identifier, create a malformed header with invalid identifier
        return self.can_ir.store.addTypeHeader(.{
            .name = base.Ident.Idx{ .attributes = .{ .effectful = false, .ignored = false, .reassignable = false }, .idx = 0 }, // Invalid identifier
            .args = .{ .span = .{ .start = 0, .len = 0 } },
            .region = region,
        });
    };

    // Canonicalize type arguments - these are parameter declarations, not references
    const scratch_top = self.can_ir.store.scratchTypeAnnoTop();
    defer self.can_ir.store.clearScratchTypeAnnosFrom(scratch_top);

    for (self.parse_ir.store.typeAnnoSlice(ast_header.args)) |arg_idx| {
        const ast_arg = self.parse_ir.store.getTypeAnno(arg_idx);
        // Type parameters should be treated as declarations, not lookups
        switch (ast_arg) {
            .ty_var => |ty_var| {
                const param_region = self.parse_ir.tokenizedRegionToRegion(ty_var.region);
                const param_ident = self.parse_ir.tokens.resolveIdentifier(ty_var.tok) orelse {
                    const malformed = self.can_ir.pushMalformed(CIR.TypeAnno.Idx, CIR.Diagnostic{ .malformed_type_annotation = .{
                        .region = param_region,
                    } });
                    self.can_ir.store.addScratchTypeAnno(malformed);
                    continue;
                };

                // Create type variable annotation for this parameter
                const param_anno = self.can_ir.store.addTypeAnno(.{ .ty_var = .{
                    .name = param_ident,
                    .region = param_region,
                } });
                self.can_ir.store.addScratchTypeAnno(param_anno);
            },
            else => {
                // Other types in parameter position - canonicalize normally but warn
                const canonicalized = self.canonicalize_type_anno(arg_idx);
                self.can_ir.store.addScratchTypeAnno(canonicalized);
            },
        }
    }

    const args = self.can_ir.store.typeAnnoSpanFrom(scratch_top);

    return self.can_ir.store.addTypeHeader(.{
        .name = name_ident,
        .args = args,
        .region = region,
    });
}

fn canonicalize_statement(self: *Self, stmt_idx: AST.Statement.Idx) ?CIR.Expr.Idx {
    const stmt = self.parse_ir.store.getStatement(stmt_idx);

    switch (stmt) {
        .decl => |d| {
            // Check if this is a var reassignment
            const pattern = self.parse_ir.store.getPattern(d.pattern);
            if (pattern == .ident) {
                const ident_tok = pattern.ident.ident_tok;
                if (self.parse_ir.tokens.resolveIdentifier(ident_tok)) |ident_idx| {
                    const region = self.parse_ir.tokenizedRegionToRegion(self.parse_ir.store.getPattern(d.pattern).to_tokenized_region());

                    // Check if this identifier exists and is a var
                    switch (self.scopeLookup(&self.can_ir.env.idents, .ident, ident_idx)) {
                        .found => |existing_pattern_idx| {
                            // Check if this is a var reassignment across function boundaries
                            if (self.isVarReassignmentAcrossFunctionBoundary(existing_pattern_idx)) {
                                // Generate error for var reassignment across function boundary
                                const error_expr = self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .var_across_function_boundary = .{
                                    .region = region,
                                } });

                                // Create a reassign statement with the error expression
                                const reassign_stmt = CIR.Statement{ .reassign = .{
                                    .pattern_idx = existing_pattern_idx,
                                    .expr = error_expr,
                                    .region = region,
                                } };
                                const reassign_idx = self.can_ir.store.addStatement(reassign_stmt);
                                self.can_ir.store.addScratchStatement(reassign_idx);

                                return error_expr;
                            }

                            // Check if this was declared as a var
                            if (self.isVarPattern(existing_pattern_idx)) {
                                // This is a var reassignment - canonicalize the expression and create reassign statement
                                const expr_idx = self.canonicalize_expr(d.body) orelse return null;

                                // Create reassign statement
                                const reassign_stmt = CIR.Statement{ .reassign = .{
                                    .pattern_idx = existing_pattern_idx,
                                    .expr = expr_idx,
                                    .region = region,
                                } };
                                const reassign_idx = self.can_ir.store.addStatement(reassign_stmt);
                                self.can_ir.store.addScratchStatement(reassign_idx);

                                return expr_idx;
                            }
                        },
                        .not_found => {
                            // Not found in scope, fall through to regular declaration
                        },
                    }
                }
            }

            // Regular declaration - canonicalize as usual
            const pattern_idx = self.canonicalize_pattern(d.pattern) orelse return null;
            const expr_idx = self.canonicalize_expr(d.body) orelse return null;

            // Create a declaration statement
            const decl_stmt = CIR.Statement{ .decl = .{
                .pattern = pattern_idx,
                .expr = expr_idx,
                .region = self.parse_ir.tokenizedRegionToRegion(d.region),
            } };
            const decl_idx = self.can_ir.store.addStatement(decl_stmt);
            self.can_ir.store.addScratchStatement(decl_idx);

            return expr_idx;
        },
        .@"var" => |v| {
            // Var declaration - handle specially with function boundary tracking
            const var_name = self.parse_ir.tokens.resolveIdentifier(v.name) orelse return null;
            const region = self.parse_ir.tokenizedRegionToRegion(v.region);

            // Canonicalize the initial value
            const init_expr_idx = self.canonicalize_expr(v.body) orelse return null;

            // Create pattern for the var
            const pattern_idx = self.can_ir.store.addPattern(CIR.Pattern{ .assign = .{ .ident = var_name, .region = region } });

            // Introduce the var with function boundary tracking
            _ = self.scopeIntroduceVar(var_name, pattern_idx, region, true, CIR.Pattern.Idx);

            // Create var statement
            const var_stmt = CIR.Statement{ .@"var" = .{
                .pattern_idx = pattern_idx,
                .expr = init_expr_idx,
                .region = region,
            } };
            const var_idx = self.can_ir.store.addStatement(var_stmt);
            self.can_ir.store.addScratchStatement(var_idx);

            return init_expr_idx;
        },
        .expr => |e| {
            // Expression statement
            const expr_idx = self.canonicalize_expr(e.expr) orelse return null;

            // Create expression statement
            const expr_stmt = CIR.Statement{ .expr = .{
                .expr = expr_idx,
                .region = self.parse_ir.tokenizedRegionToRegion(e.region),
            } };
            const expr_stmt_idx = self.can_ir.store.addStatement(expr_stmt);
            self.can_ir.store.addScratchStatement(expr_stmt_idx);

            return expr_idx;
        },
        .crash => |c| {
            // Crash statement
            const region = self.parse_ir.tokenizedRegionToRegion(c.region);

            // Create a crash diagnostic and runtime error expression
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "crash statement");
            const diagnostic = self.can_ir.store.addDiagnostic(CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = region,
            } });
            const crash_expr = self.can_ir.store.addExpr(CIR.Expr{ .runtime_error = .{
                .diagnostic = diagnostic,
                .region = region,
            } });
            return crash_expr;
        },
        .type_decl => |s| {
            // TODO type declarations in statement context
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "type_decl in statement context");
            return self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = self.parse_ir.tokenizedRegionToRegion(s.region),
            } });
        },
        .type_anno => |ta| {
            // Type annotation statement
            const region = self.parse_ir.tokenizedRegionToRegion(ta.region);

            // Resolve the identifier name
            const name_ident = self.parse_ir.tokens.resolveIdentifier(ta.name) orelse {
                const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "type annotation identifier resolution");
                return self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                    .feature = feature,
                    .region = region,
                } });
            };

            // Canonicalize the type annotation
            const type_anno_idx = self.canonicalize_type_anno(ta.anno);

            // Extract type variables from the annotation and introduce them into scope
            // This makes them available for the subsequent value declaration
            self.extractTypeVarsFromAnno(type_anno_idx);

            // Store the type annotation for connection with the next declaration
            const name_text = self.can_ir.env.idents.getText(name_ident);
            self.pending_type_annos.put(self.can_ir.env.gpa, name_text, type_anno_idx) catch |err| exitOnOom(err);

            // Type annotations don't produce runtime values, so return a unit expression
            // Create an empty tuple as a unit value
            const empty_span = CIR.Expr.Span{ .span = base.DataSpan{ .start = 0, .len = 0 } };
            const unit_expr = self.can_ir.store.addExpr(CIR.Expr{ .tuple = .{
                .tuple_var = self.can_ir.pushFreshTypeVar(@enumFromInt(0), region),
                .elems = empty_span,
                .region = region,
            } });
            _ = self.can_ir.setTypeVarAtExpr(unit_expr, Content{ .flex_var = null });
            return unit_expr;
        },
        else => {
            // Other statement types not yet implemented
            const feature = self.can_ir.env.strings.insert(self.can_ir.env.gpa, "statement type in block");
            return self.can_ir.pushMalformed(CIR.Expr.Idx, CIR.Diagnostic{ .not_implemented = .{
                .feature = feature,
                .region = Region.zero(),
            } });
        },
    }
}

/// Enter a new scope level
fn scopeEnter(self: *Self, gpa: std.mem.Allocator, is_function_boundary: bool) void {
    const scope = Scope.init(is_function_boundary);
    self.scopes.append(gpa, scope) catch |err| collections.utils.exitOnOom(err);
}

/// Exit the current scope level
fn scopeExit(self: *Self, gpa: std.mem.Allocator) Scope.Error!void {
    if (self.scopes.items.len <= 1) {
        return Scope.Error.ExitedTopScopeLevel;
    }

    // Check for unused variables in the scope we're about to exit
    const scope = &self.scopes.items[self.scopes.items.len - 1];
    self.checkScopeForUnusedVariables(scope);

    var popped_scope: Scope = self.scopes.pop().?;
    popped_scope.deinit(gpa);
}

/// Get the current scope
fn currentScope(self: *Self) *Scope {
    std.debug.assert(self.scopes.items.len > 0);
    return &self.scopes.items[self.scopes.items.len - 1];
}

/// Check if an identifier is in scope
fn scopeContains(
    self: *Self,
    ident_store: *const base.Ident.Store,
    comptime item_kind: Scope.ItemKind,
    name: base.Ident.Idx,
) ?CIR.Pattern.Idx {
    var scope_idx = self.scopes.items.len;
    while (scope_idx > 0) {
        scope_idx -= 1;
        const scope = &self.scopes.items[scope_idx];
        const map = scope.itemsConst(item_kind);

        var iter = map.iterator();
        while (iter.next()) |entry| {
            if (ident_store.identsHaveSameText(name, entry.key_ptr.*)) {
                return entry.value_ptr.*;
            }
        }
    }
    return null;
}

/// Look up an identifier in the scope
fn scopeLookup(
    self: *Self,
    ident_store: *const base.Ident.Store,
    comptime item_kind: Scope.ItemKind,
    name: base.Ident.Idx,
) Scope.LookupResult {
    if (self.scopeContains(ident_store, item_kind, name)) |pattern| {
        return Scope.LookupResult{ .found = pattern };
    }
    return Scope.LookupResult{ .not_found = {} };
}

/// Lookup a type variable in the scope hierarchy
fn scopeLookupTypeVar(self: *const Self, name_ident: Ident.Idx) ?CIR.TypeAnno.Idx {
    // Search from innermost to outermost scope
    var i = self.scopes.items.len;
    while (i > 0) {
        i -= 1;
        const scope = &self.scopes.items[i];

        switch (scope.lookupTypeVar(&self.can_ir.env.idents, name_ident)) {
            .found => |type_var_idx| return type_var_idx,
            .not_found => continue,
        }
    }
    return null;
}

/// Introduce a type variable into the current scope
fn scopeIntroduceTypeVar(self: *Self, name: Ident.Idx, type_var_anno: CIR.TypeAnno.Idx) void {
    const gpa = self.can_ir.env.gpa;
    const current_scope = &self.scopes.items[self.scopes.items.len - 1];

    // Don't use parent lookup function for now - just introduce directly
    // Type variable shadowing is allowed in Roc
    const result = current_scope.introduceTypeVar(gpa, &self.can_ir.env.idents, name, type_var_anno, null);

    switch (result) {
        .success => {},
        .shadowing_warning => |shadowed_type_var_idx| {
            // Type variable shadowing is allowed but should produce warning
            const shadowed_type_var = self.can_ir.store.getTypeAnno(shadowed_type_var_idx);
            const original_region = shadowed_type_var.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{ .shadowing_warning = .{
                .ident = name,
                .region = self.can_ir.store.getTypeAnno(type_var_anno).toRegion(),
                .original_region = original_region,
            } });
        },
        .already_in_scope => |_| {
            // Type variable already exists in this scope - this is fine for repeated references
        },
    }
}

/// Extract type variables from a type annotation and introduce them into scope
fn extractTypeVarsFromAnno(self: *Self, type_anno_idx: CIR.TypeAnno.Idx) void {
    const type_anno = self.can_ir.store.getTypeAnno(type_anno_idx);

    switch (type_anno) {
        .ty_var => |ty_var| {
            // This is a type variable - introduce it into scope
            self.scopeIntroduceTypeVar(ty_var.name, type_anno_idx);
        },
        .apply => |apply| {
            // Recursively extract from arguments
            for (self.can_ir.store.sliceTypeAnnos(apply.args)) |arg_idx| {
                self.extractTypeVarsFromAnno(arg_idx);
            }
        },
        .@"fn" => {
            // Function type annotations are not yet implemented in CIR
            // When implemented, extract from parameter and return types
        },
        .tuple => |tuple| {
            // Extract from tuple elements
            for (self.can_ir.store.sliceTypeAnnos(tuple.annos)) |elem_idx| {
                self.extractTypeVarsFromAnno(elem_idx);
            }
        },
        .parens => |parens| {
            // Extract from inner annotation
            self.extractTypeVarsFromAnno(parens.anno);
        },
        .ty, .underscore, .mod_ty, .record, .tag_union, .malformed => {
            // These don't contain type variables to extract
        },
    }
}

fn introduceTypeParametersFromHeader(self: *Self, header_idx: CIR.TypeHeader.Idx) void {
    const header = self.can_ir.store.getTypeHeader(header_idx);

    // Introduce each type parameter into the current scope
    for (self.can_ir.store.sliceTypeAnnos(header.args)) |param_idx| {
        const param = self.can_ir.store.getTypeAnno(param_idx);
        if (param == .ty_var) {
            self.scopeIntroduceTypeVar(param.ty_var.name, param_idx);
        }
    }
}

fn extractTypeVarsFromASTAnno(self: *Self, anno_idx: AST.TypeAnno.Idx, vars: *std.ArrayList(Ident.Idx)) void {
    const ast_anno = self.parse_ir.store.getTypeAnno(anno_idx);

    switch (ast_anno) {
        .ty_var => |ty_var| {
            if (self.parse_ir.tokens.resolveIdentifier(ty_var.tok)) |ident| {
                // Check if we already have this type variable
                for (vars.items) |existing| {
                    if (existing.idx == ident.idx) return; // Already added
                }
                vars.append(ident) catch |err| exitOnOom(err);
            }
        },
        .apply => |apply| {
            for (self.parse_ir.store.typeAnnoSlice(apply.args)) |arg_idx| {
                self.extractTypeVarsFromASTAnno(arg_idx, vars);
            }
        },
        .@"fn" => |fn_anno| {
            for (self.parse_ir.store.typeAnnoSlice(fn_anno.args)) |arg_idx| {
                self.extractTypeVarsFromASTAnno(arg_idx, vars);
            }
            self.extractTypeVarsFromASTAnno(fn_anno.ret, vars);
        },
        .tuple => |tuple| {
            for (self.parse_ir.store.typeAnnoSlice(tuple.annos)) |elem_idx| {
                self.extractTypeVarsFromASTAnno(elem_idx, vars);
            }
        },
        .parens => |parens| {
            self.extractTypeVarsFromASTAnno(parens.anno, vars);
        },
        .ty, .underscore, .mod_ty, .record, .tag_union, .malformed => {
            // These don't contain type variables to extract
        },
    }
}

/// Introduce a new identifier to the current scope level
fn scopeIntroduceInternal(
    self: *Self,
    gpa: std.mem.Allocator,
    ident_store: *const base.Ident.Store,
    comptime item_kind: Scope.ItemKind,
    ident_idx: base.Ident.Idx,
    pattern_idx: CIR.Pattern.Idx,
    is_var: bool,
    is_declaration: bool,
) Scope.IntroduceResult {
    // Check if var is being used at top-level
    if (is_var and self.scopes.items.len == 1) {
        return Scope.IntroduceResult{ .top_level_var_error = {} };
    }

    // Check for existing identifier in any scope level for shadowing detection
    if (self.scopeContains(ident_store, item_kind, ident_idx)) |existing_pattern| {
        // If it's a var reassignment (not declaration), check function boundaries
        if (is_var and !is_declaration) {
            // Find the scope where the var was declared and check for function boundaries
            var declaration_scope_idx: ?usize = null;
            var scope_idx = self.scopes.items.len;

            // First, find where the identifier was declared
            while (scope_idx > 0) {
                scope_idx -= 1;
                const scope = &self.scopes.items[scope_idx];
                const map = scope.itemsConst(item_kind);

                var iter = map.iterator();
                while (iter.next()) |entry| {
                    if (ident_store.identsHaveSameText(ident_idx, entry.key_ptr.*)) {
                        declaration_scope_idx = scope_idx;
                        break;
                    }
                }

                if (declaration_scope_idx != null) break;
            }

            // Now check if there are function boundaries between declaration and current scope
            if (declaration_scope_idx) |decl_idx| {
                var current_idx = decl_idx + 1;
                var found_function_boundary = false;

                while (current_idx < self.scopes.items.len) {
                    const scope = &self.scopes.items[current_idx];
                    if (scope.is_function_boundary) {
                        found_function_boundary = true;
                        break;
                    }
                    current_idx += 1;
                }

                if (found_function_boundary) {
                    // Different function, return error
                    return Scope.IntroduceResult{ .var_across_function_boundary = existing_pattern };
                } else {
                    // Same function, allow reassignment without warning
                    self.scopes.items[self.scopes.items.len - 1].put(gpa, item_kind, ident_idx, pattern_idx);
                    return Scope.IntroduceResult{ .success = {} };
                }
            }
        }

        // Regular shadowing case - produce warning but still introduce
        self.scopes.items[self.scopes.items.len - 1].put(gpa, item_kind, ident_idx, pattern_idx);
        return Scope.IntroduceResult{ .shadowing_warning = existing_pattern };
    }

    // Check the current level for duplicates
    const current_scope = &self.scopes.items[self.scopes.items.len - 1];
    const map = current_scope.itemsConst(item_kind);

    var iter = map.iterator();
    while (iter.next()) |entry| {
        if (ident_store.identsHaveSameText(ident_idx, entry.key_ptr.*)) {
            // Duplicate in same scope - still introduce but return shadowing warning
            self.scopes.items[self.scopes.items.len - 1].put(gpa, item_kind, ident_idx, pattern_idx);
            return Scope.IntroduceResult{ .shadowing_warning = entry.value_ptr.* };
        }
    }

    // No conflicts, introduce successfully
    self.scopes.items[self.scopes.items.len - 1].put(gpa, item_kind, ident_idx, pattern_idx);
    return Scope.IntroduceResult{ .success = {} };
}

/// Get all identifiers in scope
fn scopeAllIdents(self: *const Self, gpa: std.mem.Allocator, comptime item_kind: Scope.ItemKind) []base.Ident.Idx {
    var result = std.ArrayList(base.Ident.Idx).init(gpa);

    for (self.scopes.items) |scope| {
        const map = scope.itemsConst(item_kind);
        var iter = map.iterator();
        while (iter.next()) |entry| {
            result.append(entry.key_ptr.*) catch |err| collections.utils.exitOnOom(err);
        }
    }

    return result.toOwnedSlice() catch |err| collections.utils.exitOnOom(err);
}

/// Check if an identifier is marked as ignored (underscore prefix)
fn identIsIgnored(ident_idx: base.Ident.Idx) bool {
    return ident_idx.attributes.ignored;
}

/// Handle unused variable checking and diagnostics
fn checkUsedUnderscoreVariable(
    self: *Self,
    ident_idx: base.Ident.Idx,
    region: Region,
) void {
    const is_ignored = identIsIgnored(ident_idx);

    if (is_ignored) {
        // Variable prefixed with _ but is actually used - warning
        self.can_ir.pushDiagnostic(CIR.Diagnostic{ .used_underscore_variable = .{
            .ident = ident_idx,
            .region = region,
        } });
    }
}

fn checkScopeForUnusedVariables(self: *Self, scope: *const Scope) void {
    // Iterate through all identifiers in this scope
    var iterator = scope.idents.iterator();
    while (iterator.next()) |entry| {
        const ident_idx = entry.key_ptr.*;
        const pattern_idx = entry.value_ptr.*;

        // Skip if this variable was used
        if (self.used_patterns.contains(pattern_idx)) {
            continue;
        }

        // Skip if this is an ignored variable (starts with _)
        if (identIsIgnored(ident_idx)) {
            continue;
        }

        // Get the region for this pattern to provide good error location
        const pattern = self.can_ir.store.getPattern(pattern_idx);
        const region = pattern.toRegion();

        // Report unused variable
        self.can_ir.pushDiagnostic(CIR.Diagnostic{ .unused_variable = .{
            .ident = ident_idx,
            .region = region,
        } });
    }
}

/// Introduce a type declaration into the current scope
fn scopeIntroduceTypeDecl(
    self: *Self,
    name_ident: Ident.Idx,
    type_decl_stmt: CIR.Statement.Idx,
    region: Region,
) void {
    const gpa = self.can_ir.env.gpa;
    const current_scope = &self.scopes.items[self.scopes.items.len - 1];

    // Check for shadowing in parent scopes
    var shadowed_in_parent: ?CIR.Statement.Idx = null;
    if (self.scopes.items.len > 1) {
        var i = self.scopes.items.len - 1;
        while (i > 0) {
            i -= 1;
            const scope = &self.scopes.items[i];
            switch (scope.lookupTypeDecl(&self.can_ir.env.idents, name_ident)) {
                .found => |type_decl_idx| {
                    shadowed_in_parent = type_decl_idx;
                    break;
                },
                .not_found => continue,
            }
        }
    }

    const result = current_scope.introduceTypeDecl(gpa, &self.can_ir.env.idents, name_ident, type_decl_stmt, null);

    switch (result) {
        .success => {
            // Check if we're shadowing a type in a parent scope
            if (shadowed_in_parent) |shadowed_stmt| {
                const shadowed_statement = self.can_ir.store.getStatement(shadowed_stmt);
                const original_region = shadowed_statement.toRegion();
                self.can_ir.pushDiagnostic(CIR.Diagnostic{
                    .shadowing_warning = .{
                        .ident = name_ident,
                        .region = region,
                        .original_region = original_region,
                    },
                });
            }
        },
        .shadowing_warning => |shadowed_stmt| {
            // This shouldn't happen since we're not passing a parent lookup function
            // but handle it just in case the Scope implementation changes
            const shadowed_statement = self.can_ir.store.getStatement(shadowed_stmt);
            const original_region = shadowed_statement.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{
                .shadowing_warning = .{
                    .ident = name_ident,
                    .region = region,
                    .original_region = original_region,
                },
            });
        },
        .redeclared_error => |original_stmt| {
            // Extract region information from the original statement
            const original_statement = self.can_ir.store.getStatement(original_stmt);
            const original_region = original_statement.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{
                .type_redeclared = .{
                    .original_region = original_region,
                    .redeclared_region = region,
                    .name = name_ident,
                },
            });
        },
        .type_alias_redeclared => |original_stmt| {
            const original_statement = self.can_ir.store.getStatement(original_stmt);
            const original_region = original_statement.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{
                .type_alias_redeclared = .{
                    .name = name_ident,
                    .original_region = original_region,
                    .redeclared_region = region,
                },
            });
        },
        .custom_type_redeclared => |original_stmt| {
            const original_statement = self.can_ir.store.getStatement(original_stmt);
            const original_region = original_statement.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{
                .custom_type_redeclared = .{
                    .name = name_ident,
                    .original_region = original_region,
                    .redeclared_region = region,
                },
            });
        },
        .cross_scope_shadowing => |shadowed_stmt| {
            const shadowed_statement = self.can_ir.store.getStatement(shadowed_stmt);
            const original_region = shadowed_statement.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{
                .type_shadowed_warning = .{
                    .name = name_ident,
                    .region = region,
                    .original_region = original_region,
                    .cross_scope = true,
                },
            });
        },
        .parameter_conflict => |conflict| {
            const original_statement = self.can_ir.store.getStatement(conflict.original_stmt);
            const original_region = original_statement.toRegion();
            self.can_ir.pushDiagnostic(CIR.Diagnostic{
                .type_parameter_conflict = .{
                    .name = name_ident,
                    .parameter_name = conflict.conflicting_parameter,
                    .region = region,
                    .original_region = original_region,
                },
            });
        },
    }
}

/// Lookup a type declaration in the scope hierarchy
fn scopeLookupTypeDecl(self: *const Self, name_ident: Ident.Idx) ?CIR.Statement.Idx {
    // Search from innermost to outermost scope
    var i = self.scopes.items.len;
    while (i > 0) {
        i -= 1;
        const scope = &self.scopes.items[i];

        switch (scope.lookupTypeDecl(&self.can_ir.env.idents, name_ident)) {
            .found => |type_decl_idx| return type_decl_idx,
            .not_found => continue,
        }
    }

    return null;
}

/// Convert a parsed TypeAnno into a canonical TypeVar with appropriate Content
fn canonicalizeTypeAnnoToTypeVar(self: *Self, type_anno_idx: CIR.TypeAnno.Idx, parent_node_idx: Node.Idx, region: Region) TypeVar {
    const type_anno = self.can_ir.store.getTypeAnno(type_anno_idx);

    switch (type_anno) {
        .ty_var => |tv| {
            // Check if this type variable is already in scope
            const scope = self.currentScope();
            const ident_store = &self.can_ir.env.idents;

            switch (scope.lookupTypeVar(ident_store, tv.name)) {
                .found => |_| {
                    // Type variable already exists, create fresh var with same name
                    return self.can_ir.pushTypeVar(.{ .flex_var = tv.name }, parent_node_idx, region);
                },
                .not_found => {
                    // Create fresh flex var and add to scope
                    const fresh_var = self.can_ir.pushTypeVar(.{ .flex_var = tv.name }, parent_node_idx, region);

                    // Create a basic type annotation for the scope
                    const ty_var_anno = self.can_ir.store.addTypeAnno(.{ .ty_var = .{ .name = tv.name, .region = region } });

                    // Add to scope (simplified - ignoring result for now)
                    _ = scope.introduceTypeVar(self.can_ir.env.gpa, ident_store, tv.name, ty_var_anno, null);

                    return fresh_var;
                },
            }
        },
        .underscore => {
            // Create anonymous flex var
            return self.can_ir.pushFreshTypeVar(parent_node_idx, region);
        },
        .ty => |t| {
            // Look up built-in or user-defined type
            return self.canonicalizeBasicType(t.symbol, parent_node_idx, region);
        },
        .apply => |apply| {
            // Handle type application like List(String), Dict(a, b)
            return self.canonicalizeTypeApplication(apply, parent_node_idx, region);
        },
        .@"fn" => |func| {
            // Create function type
            return self.canonicalizeFunctionType(func, parent_node_idx, region);
        },
        .tuple => |tuple| {
            // Create tuple type
            return self.canonicalizeTupleType(tuple, parent_node_idx, region);
        },
        .record => |record| {
            // Create record type
            return self.canonicalizeRecordType(record, parent_node_idx, region);
        },
        .tag_union => |tag_union| {
            // Create tag union type
            return self.canonicalizeTagUnionType(tag_union, parent_node_idx, region);
        },
        .parens => |parens| {
            // Recursively canonicalize the inner type
            return self.canonicalizeTypeAnnoToTypeVar(parens.anno, parent_node_idx, region);
        },
        .mod_ty => |mod_ty| {
            // Handle module-qualified types
            return self.canonicalizeModuleType(mod_ty, parent_node_idx, region);
        },
        .malformed => {
            // Return error type for malformed annotations
            return self.can_ir.pushTypeVar(.err, parent_node_idx, region);
        },
    }
}

/// Handle basic type lookup (Bool, Str, Num, etc.)
fn canonicalizeBasicType(self: *Self, symbol: Ident.Idx, parent_node_idx: Node.Idx, region: Region) TypeVar {
    const name = self.can_ir.env.idents.getText(symbol);

    // Built-in types mapping
    if (std.mem.eql(u8, name, "Bool")) {
        return self.can_ir.pushTypeVar(.{ .flex_var = symbol }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "Str")) {
        return self.can_ir.pushTypeVar(.{ .structure = .str }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "Num")) {
        // Create a fresh TypeVar for the polymorphic number type
        const num_var = self.can_ir.pushFreshTypeVar(parent_node_idx, region);
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .num_poly = num_var } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "U8")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .u8 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "U16")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .u16 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "U32")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .u32 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "U64")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .u64 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "U128")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .u128 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "I8")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .i8 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "I16")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .i16 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "I32")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .i32 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "I64")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .i64 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "I128")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .int_precision = .i128 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "F32")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .frac_precision = .f32 } } }, parent_node_idx, region);
    } else if (std.mem.eql(u8, name, "F64")) {
        return self.can_ir.pushTypeVar(.{ .structure = .{ .num = .{ .frac_precision = .f64 } } }, parent_node_idx, region);
    } else {
        // Look up user-defined type in scope
        const scope = self.currentScope();
        const ident_store = &self.can_ir.env.idents;

        switch (scope.lookupTypeDecl(ident_store, symbol)) {
            .found => |_| {
                return self.can_ir.pushTypeVar(.{ .flex_var = symbol }, parent_node_idx, region);
            },
            .not_found => {
                // Unknown type - create error type
                return self.can_ir.pushTypeVar(.err, parent_node_idx, region);
            },
        }
    }
}

/// Handle type applications like List(a), Dict(k, v)
fn canonicalizeTypeApplication(self: *Self, apply: anytype, parent_node_idx: Node.Idx, region: Region) TypeVar {
    // Simplified implementation - create a flex var for the applied type
    return self.can_ir.pushTypeVar(.{ .flex_var = apply.symbol }, parent_node_idx, region);
}

/// Handle function types like a -> b
fn canonicalizeFunctionType(self: *Self, func: anytype, parent_node_idx: Node.Idx, region: Region) TypeVar {
    // Canonicalize argument types and return type
    const args_slice = self.can_ir.store.sliceTypeAnnos(func.args);

    // For each argument, canonicalize its type
    for (args_slice) |arg_anno_idx| {
        _ = self.canonicalizeTypeAnnoToTypeVar(arg_anno_idx, parent_node_idx, region);
    }

    // Canonicalize return type
    _ = self.canonicalizeTypeAnnoToTypeVar(func.ret, parent_node_idx, region);

    // For now, create a flex var representing the function type
    // TODO: Implement proper function type structure when the type system infrastructure is ready
    // This ensures that function types are at least recognized and processed, even if not fully structured
    return self.can_ir.pushFreshTypeVar(parent_node_idx, region);
}

/// Handle tuple types like (a, b, c)
fn canonicalizeTupleType(self: *Self, tuple: anytype, parent_node_idx: Node.Idx, region: Region) TypeVar {
    _ = tuple;
    // Simplified implementation - create flex var for tuples
    return self.can_ir.pushFreshTypeVar(parent_node_idx, region);
}

/// Handle record types like { name: Str, age: Num }
fn canonicalizeRecordType(self: *Self, record: anytype, parent_node_idx: Node.Idx, region: Region) TypeVar {
    _ = record;
    // Simplified implementation - create empty record type
    return self.can_ir.pushTypeVar(.{ .structure = .empty_record }, parent_node_idx, region);
}

/// Handle tag union types like [Some(a), None]
fn canonicalizeTagUnionType(self: *Self, tag_union: anytype, parent_node_idx: Node.Idx, region: Region) TypeVar {
    _ = tag_union;
    // Simplified implementation - create flex var for tag unions
    return self.can_ir.pushFreshTypeVar(parent_node_idx, region);
}

/// Handle module-qualified types like Json.Decoder
fn canonicalizeModuleType(self: *Self, mod_ty: anytype, parent_node_idx: Node.Idx, region: Region) TypeVar {
    // Simplified implementation - create flex var for module types
    return self.can_ir.pushTypeVar(.{ .flex_var = mod_ty.ty_symbol }, parent_node_idx, region);
}

/// Create an annotation from a type annotation
fn createAnnotationFromTypeAnno(self: *Self, type_anno_idx: CIR.TypeAnno.Idx, _: TypeVar, region: Region) ?CIR.Annotation.Idx {
    // Convert the type annotation to a type variable
    const signature = self.canonicalizeTypeAnnoToTypeVar(type_anno_idx, @enumFromInt(0), region);

    // Create the annotation structure
    const annotation = CIR.Annotation{
        .type_anno = type_anno_idx,
        .signature = signature,
        .region = region,
    };

    // Add to NodeStore and return the index
    const annotation_idx = self.can_ir.store.addAnnotation(annotation);

    return annotation_idx;
}

/// Context helper for Scope tests
const ScopeTestContext = struct {
    self: Self,
    cir: *CIR,
    env: *base.ModuleEnv,
    gpa: std.mem.Allocator,

    fn init(gpa: std.mem.Allocator) !ScopeTestContext {
        // heap allocate env for testing
        const env = try gpa.create(base.ModuleEnv);
        env.* = base.ModuleEnv.init(gpa);

        // heap allocate CIR for testing
        const cir = try gpa.create(CIR);
        cir.* = CIR.init(env);

        return ScopeTestContext{
            .self = Self.init(cir, undefined),
            .cir = cir,
            .env = env,
            .gpa = gpa,
        };
    }

    fn deinit(ctx: *ScopeTestContext) void {
        ctx.self.deinit();
        ctx.cir.deinit();
        ctx.gpa.destroy(ctx.cir);
        ctx.env.deinit();
        ctx.gpa.destroy(ctx.env);
    }
};

test "basic scope initialization" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    // Test that we start with one scope (top-level)
    try std.testing.expect(ctx.self.scopes.items.len == 1);
}

test "empty scope has no items" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    const foo_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("foo"), base.Region.zero());
    const result = ctx.self.scopeLookup(&ctx.env.idents, .ident, foo_ident);

    try std.testing.expectEqual(Scope.LookupResult{ .not_found = {} }, result);
}

test "can add and lookup idents at top level" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    const foo_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("foo"), base.Region.zero());
    const bar_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("bar"), base.Region.zero());
    const foo_pattern: CIR.Pattern.Idx = @enumFromInt(1);
    const bar_pattern: CIR.Pattern.Idx = @enumFromInt(2);

    // Add identifiers
    const foo_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, foo_ident, foo_pattern, false, true);
    const bar_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, bar_ident, bar_pattern, false, true);

    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, foo_result);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, bar_result);

    // Lookup should find them
    const foo_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, foo_ident);
    const bar_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, bar_ident);

    try std.testing.expectEqual(Scope.LookupResult{ .found = foo_pattern }, foo_lookup);
    try std.testing.expectEqual(Scope.LookupResult{ .found = bar_pattern }, bar_lookup);
}

test "nested scopes shadow outer scopes" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    const x_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("x"), base.Region.zero());
    const outer_pattern: CIR.Pattern.Idx = @enumFromInt(1);
    const inner_pattern: CIR.Pattern.Idx = @enumFromInt(2);

    // Add x to outer scope
    const outer_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, x_ident, outer_pattern, false, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, outer_result);

    // Enter new scope
    ctx.self.scopeEnter(gpa, false);

    // x from outer scope should still be visible
    const outer_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, x_ident);
    try std.testing.expectEqual(Scope.LookupResult{ .found = outer_pattern }, outer_lookup);

    // Add x to inner scope (shadows outer)
    const inner_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, x_ident, inner_pattern, false, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .shadowing_warning = outer_pattern }, inner_result);

    // Now x should resolve to inner scope
    const inner_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, x_ident);
    try std.testing.expectEqual(Scope.LookupResult{ .found = inner_pattern }, inner_lookup);

    // Exit inner scope
    try ctx.self.scopeExit(gpa);

    // x should resolve to outer scope again
    const after_exit_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, x_ident);
    try std.testing.expectEqual(Scope.LookupResult{ .found = outer_pattern }, after_exit_lookup);
}

test "top level var error" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    const var_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("count_"), base.Region.zero());
    const pattern: CIR.Pattern.Idx = @enumFromInt(1);

    // Should fail to introduce var at top level
    const result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, var_ident, pattern, true, true);

    try std.testing.expectEqual(Scope.IntroduceResult{ .top_level_var_error = {} }, result);
}

test "type variables are tracked separately from value identifiers" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    // Create identifiers for 'a' - one for value, one for type
    const a_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("a"), base.Region.zero());
    const pattern: CIR.Pattern.Idx = @enumFromInt(1);
    const type_anno: CIR.TypeAnno.Idx = @enumFromInt(1);

    // Introduce 'a' as a value identifier
    const value_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, a_ident, pattern, false, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, value_result);

    // Introduce 'a' as a type variable - should succeed because they're in separate namespaces
    const current_scope = &ctx.self.scopes.items[ctx.self.scopes.items.len - 1];
    const type_result = current_scope.introduceTypeVar(gpa, &ctx.env.idents, a_ident, type_anno, null);
    try std.testing.expectEqual(Scope.TypeVarIntroduceResult{ .success = {} }, type_result);

    // Lookup 'a' as value should find the pattern
    const value_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, a_ident);
    try std.testing.expectEqual(Scope.LookupResult{ .found = pattern }, value_lookup);

    // Lookup 'a' as type variable should find the type annotation
    const type_lookup = current_scope.lookupTypeVar(&ctx.env.idents, a_ident);
    try std.testing.expectEqual(Scope.TypeVarLookupResult{ .found = type_anno }, type_lookup);
}

test "var reassignment within same function" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    // Enter function scope
    ctx.self.scopeEnter(gpa, true);

    const count_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("count_"), base.Region.zero());
    const pattern1: CIR.Pattern.Idx = @enumFromInt(1);
    const pattern2: CIR.Pattern.Idx = @enumFromInt(2);

    // Declare var
    const declare_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, count_ident, pattern1, true, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, declare_result);

    // Reassign var (not a declaration)
    const reassign_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, count_ident, pattern2, true, false);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, reassign_result);

    // Should resolve to the reassigned value
    const lookup_result = ctx.self.scopeLookup(&ctx.env.idents, .ident, count_ident);
    try std.testing.expectEqual(Scope.LookupResult{ .found = pattern2 }, lookup_result);
}

test "var reassignment across function boundary fails" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    // Enter first function scope
    ctx.self.scopeEnter(gpa, true);

    const count_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("count_"), base.Region.zero());
    const pattern1: CIR.Pattern.Idx = @enumFromInt(1);
    const pattern2: CIR.Pattern.Idx = @enumFromInt(2);

    // Declare var in first function
    const declare_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, count_ident, pattern1, true, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, declare_result);

    // Enter second function scope (function boundary)
    ctx.self.scopeEnter(gpa, true);

    // Try to reassign var from different function - should fail
    const reassign_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, count_ident, pattern2, true, false);
    try std.testing.expectEqual(Scope.IntroduceResult{ .var_across_function_boundary = pattern1 }, reassign_result);
}

test "identifiers with and without underscores are different" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    const sum_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("sum"), base.Region.zero());
    const sum_underscore_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("sum_"), base.Region.zero());
    const pattern1: CIR.Pattern.Idx = @enumFromInt(1);
    const pattern2: CIR.Pattern.Idx = @enumFromInt(2);

    // Enter function scope so we can use var
    ctx.self.scopeEnter(gpa, true);

    // Introduce regular identifier
    const regular_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, sum_ident, pattern1, false, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, regular_result);

    // Introduce var with underscore - should not conflict
    const var_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, sum_underscore_ident, pattern2, true, true);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, var_result);

    // Both should be found independently
    const regular_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, sum_ident);
    const var_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, sum_underscore_ident);

    try std.testing.expectEqual(Scope.LookupResult{ .found = pattern1 }, regular_lookup);
    try std.testing.expectEqual(Scope.LookupResult{ .found = pattern2 }, var_lookup);
}

test "aliases work separately from idents" {
    const gpa = std.testing.allocator;

    var ctx = try ScopeTestContext.init(gpa);
    defer ctx.deinit();

    const foo_ident = ctx.env.idents.insert(gpa, base.Ident.for_text("Foo"), base.Region.zero());
    const ident_pattern: CIR.Pattern.Idx = @enumFromInt(1);
    const alias_pattern: CIR.Pattern.Idx = @enumFromInt(2);

    // Add as both ident and alias (they're in separate namespaces)
    const ident_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .ident, foo_ident, ident_pattern, false, true);
    const alias_result = ctx.self.scopeIntroduceInternal(gpa, &ctx.env.idents, .alias, foo_ident, alias_pattern, false, true);

    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, ident_result);
    try std.testing.expectEqual(Scope.IntroduceResult{ .success = {} }, alias_result);

    // Both should be found in their respective namespaces
    const ident_lookup = ctx.self.scopeLookup(&ctx.env.idents, .ident, foo_ident);
    const alias_lookup = ctx.self.scopeLookup(&ctx.env.idents, .alias, foo_ident);

    try std.testing.expectEqual(Scope.LookupResult{ .found = ident_pattern }, ident_lookup);
    try std.testing.expectEqual(Scope.LookupResult{ .found = alias_pattern }, alias_lookup);
}
