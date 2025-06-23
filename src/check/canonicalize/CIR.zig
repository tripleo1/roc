//! The canonical intermediate representation (CIR) is a representation of the
//! canonicalized abstract syntax tree (AST) that is used for interpreting code generation and type checking, and later compilation stages.

const std = @import("std");
const testing = std.testing;
const base = @import("../../base.zig");
const types = @import("../../types.zig");
const collections = @import("../../collections.zig");
const reporting = @import("../../reporting.zig");
const sexpr = @import("../../base/sexpr.zig");
const exitOnOom = collections.utils.exitOnOom;
const Scratch = base.Scratch;
const DataSpan = base.DataSpan;
const Ident = base.Ident;
const Region = base.Region;
const ModuleImport = base.ModuleImport;
const ModuleEnv = base.ModuleEnv;
const StringLiteral = base.StringLiteral;
const CalledVia = base.CalledVia;
const TypeVar = types.Var;
const Node = @import("Node.zig");
const NodeStore = @import("NodeStore.zig");

pub const Diagnostic = @import("Diagnostic.zig").Diagnostic;

const CIR = @This();

/// Reference to data that persists between compiler stages
env: *ModuleEnv,
/// Stores the raw nodes which represent the intermediate representation
///
/// Uses an efficient data structure, and provides helpers for storing and retrieving nodes.
store: NodeStore,
/// Temporary source text used for generating SExpr and Reports, required to calculate region info.
///
/// This field exists because:
/// - CIR may be loaded from cache without access to the original source file
/// - Region info calculation requires the source text to convert byte offsets to line/column
/// - The source is only needed temporarily during diagnostic reporting or SExpr generation
///
/// Lifetime: The caller must ensure the source remains valid for the duration of the
/// operation (e.g., `toSExprStr` or `diagnosticToReport` calls).
temp_source_for_sexpr: ?[]const u8 = null,
/// All the definitions and in the module, populated by calling `canonicalize_file`
all_defs: Def.Span,
/// All the top-level statements in the module, populated by calling `canonicalize_file`
all_statements: Statement.Span,

/// Initialize the IR for a module's canonicalization info.
///
/// When caching the can IR for a siloed module, we can avoid
/// manual deserialization of the cached data into IR by putting
/// the entirety of the IR into an arena that holds nothing besides
/// the IR. We can then load the cached binary data back into memory
/// with only 2 syscalls.
///
/// Since the can IR holds indices into the `ModuleEnv`, we need
/// the `ModuleEnv` to also be owned by the can IR to cache it.
///
/// Takes ownership of the module_env
pub fn init(env: *ModuleEnv) CIR {
    const NODE_STORE_CAPACITY = 10_000;

    return CIR{
        .env = env,
        .store = NodeStore.initCapacity(env.gpa, NODE_STORE_CAPACITY),
        .all_defs = .{ .span = .{ .start = 0, .len = 0 } },
        .all_statements = .{ .span = .{ .start = 0, .len = 0 } },
    };
}

/// Deinit the IR's memory.
pub fn deinit(self: *CIR) void {
    self.store.deinit();
}

/// Records a diagnostic error during canonicalization without blocking compilation.
///
/// This creates a diagnostic node that stores error information for later reporting.
/// The diagnostic is added to the diagnostic collection but does not create any
/// malformed nodes in the IR.
///
/// Use this when you want to record an error but don't need to replace a node
/// with a runtime error.
pub fn pushDiagnostic(self: *CIR, reason: CIR.Diagnostic) void {
    _ = self.store.addDiagnostic(reason);
}

/// Creates a malformed node that represents a runtime error in the IR. Returns and index of the requested type pointing to a malformed node.
///
/// This follows the "Inform Don't Block" principle: it allows compilation to continue
/// by creating a malformed node that will become a runtime_error in the CIR. If the
/// program execution reaches this node, it will crash with the associated diagnostic.
///
/// This function:
/// 1. Creates a diagnostic node to store the error details
/// 2. Creates a malformed node that references the diagnostic
/// 3. Creates an error type var this CIR index
/// 4. Returns an index of the requested type pointing to the malformed node
///
/// Use this when you need to replace a node (expression, pattern, etc.) with
/// something that represents a compilation error but allows the compiler to continue.
pub fn pushMalformed(self: *CIR, comptime t: type, reason: CIR.Diagnostic) t {
    const malformed_idx = self.store.addMalformed(t, reason);
    _ = self.setTypeVarAt(@enumFromInt(@intFromEnum(malformed_idx)), .err);
    return malformed_idx;
}

/// Retrieve all diagnostics collected during canonicalization.
pub fn getDiagnostics(self: *CIR) []CIR.Diagnostic {
    const all = self.store.diagnosticSpanFrom(0);

    var list = std.ArrayList(CIR.Diagnostic).init(self.env.gpa);

    for (self.store.sliceDiagnostics(all)) |idx| {
        list.append(self.store.getDiagnostic(idx)) catch |err| exitOnOom(err);
    }

    return list.toOwnedSlice() catch |err| exitOnOom(err);
}

/// Convert a canonicalization diagnostic to a Report for rendering.
///
/// The source parameter is not owned by this function - the caller must ensure it
/// remains valid for the duration of this call. The returned Report will contain
/// references to the source text but does not own it.
pub fn diagnosticToReport(self: *CIR, diagnostic: Diagnostic, allocator: std.mem.Allocator, source: []const u8, filename: []const u8) !reporting.Report {
    // Set temporary source for calcRegionInfo
    self.temp_source_for_sexpr = source;
    defer self.temp_source_for_sexpr = null;

    return switch (diagnostic) {
        .not_implemented => |data| blk: {
            const feature_text = self.env.strings.get(data.feature);
            break :blk Diagnostic.buildNotImplementedReport(allocator, feature_text);
        },
        .invalid_num_literal => |data| blk: {
            const literal_text = self.env.strings.get(data.literal);
            break :blk Diagnostic.buildInvalidNumLiteralReport(
                allocator,
                literal_text,
            );
        },
        .ident_already_in_scope => |data| blk: {
            const ident_name = self.env.idents.getText(data.ident);
            break :blk Diagnostic.buildIdentAlreadyInScopeReport(
                allocator,
                ident_name,
            );
        },
        .ident_not_in_scope => |data| blk: {
            const ident_name = self.env.idents.getText(data.ident);
            break :blk Diagnostic.buildIdentNotInScopeReport(
                allocator,
                ident_name,
            );
        },
        .invalid_top_level_statement => |data| blk: {
            const stmt_name = self.env.strings.get(data.stmt);
            break :blk Diagnostic.buildInvalidTopLevelStatementReport(
                allocator,
                stmt_name,
            );
        },
        .expr_not_canonicalized => Diagnostic.buildExprNotCanonicalizedReport(allocator),
        .invalid_string_interpolation => Diagnostic.buildInvalidStringInterpolationReport(allocator),
        .pattern_arg_invalid => Diagnostic.buildPatternArgInvalidReport(allocator),
        .pattern_not_canonicalized => Diagnostic.buildPatternNotCanonicalizedReport(allocator),
        .can_lambda_not_implemented => Diagnostic.buildCanLambdaNotImplementedReport(allocator),
        .lambda_body_not_canonicalized => Diagnostic.buildLambdaBodyNotCanonicalizedReport(allocator),
        .var_across_function_boundary => Diagnostic.buildVarAcrossFunctionBoundaryReport(allocator),
        .malformed_type_annotation => Diagnostic.buildMalformedTypeAnnotationReport(allocator),
        .shadowing_warning => |data| blk: {
            const ident_name = self.env.idents.getText(data.ident);
            const new_region_info = self.calcRegionInfo(data.region);
            const original_region_info = self.calcRegionInfo(data.original_region);
            break :blk Diagnostic.buildShadowingWarningReport(
                allocator,
                ident_name,
                new_region_info,
                original_region_info,
                source,
                filename,
            );
        },
        .type_redeclared => |data| blk: {
            const type_name = self.env.idents.getText(data.name);
            const original_region_info = self.calcRegionInfo(data.original_region);
            const redeclared_region_info = self.calcRegionInfo(data.redeclared_region);
            break :blk Diagnostic.buildTypeRedeclaredReport(
                allocator,
                type_name,
                original_region_info,
                redeclared_region_info,
                source,
                filename,
            );
        },
        .undeclared_type => |data| blk: {
            const type_name = self.env.idents.getText(data.name);
            const region_info = self.calcRegionInfo(data.region);
            break :blk Diagnostic.buildUndeclaredTypeReport(
                allocator,
                type_name,
                region_info,
                source,
                filename,
            );
        },
        .undeclared_type_var => |data| blk: {
            const type_var_name = self.env.idents.getText(data.name);
            const region_info = self.calcRegionInfo(data.region);
            break :blk Diagnostic.buildUndeclaredTypeVarReport(
                allocator,
                type_var_name,
                region_info,
                source,
                filename,
            );
        },
        .type_alias_redeclared => |data| blk: {
            const type_name = self.env.idents.getText(data.name);
            const original_region_info = self.calcRegionInfo(data.original_region);
            const redeclared_region_info = self.calcRegionInfo(data.redeclared_region);
            break :blk Diagnostic.buildTypeAliasRedeclaredReport(
                allocator,
                type_name,
                original_region_info,
                redeclared_region_info,
                source,
                filename,
            );
        },
        .custom_type_redeclared => |data| blk: {
            const type_name = self.env.idents.getText(data.name);
            const original_region_info = self.calcRegionInfo(data.original_region);
            const redeclared_region_info = self.calcRegionInfo(data.redeclared_region);
            break :blk Diagnostic.buildCustomTypeRedeclaredReport(
                allocator,
                type_name,
                original_region_info,
                redeclared_region_info,
                source,
                filename,
            );
        },
        .type_shadowed_warning => |data| blk: {
            const type_name = self.env.idents.getText(data.name);
            const new_region_info = self.calcRegionInfo(data.region);
            const original_region_info = self.calcRegionInfo(data.original_region);
            break :blk Diagnostic.buildTypeShadowedWarningReport(
                allocator,
                type_name,
                new_region_info,
                original_region_info,
                data.cross_scope,
                source,
                filename,
            );
        },
        .type_parameter_conflict => |data| blk: {
            const type_name = self.env.idents.getText(data.name);
            const parameter_name = self.env.idents.getText(data.parameter_name);
            const region_info = self.calcRegionInfo(data.region);
            const original_region_info = self.calcRegionInfo(data.original_region);
            break :blk Diagnostic.buildTypeParameterConflictReport(
                allocator,
                type_name,
                parameter_name,
                region_info,
                original_region_info,
                source,
                filename,
            );
        },
        .unused_variable => |data| blk: {
            const region_info = self.calcRegionInfo(data.region);
            break :blk try Diagnostic.buildUnusedVariableReport(
                allocator,
                &self.env.idents,
                region_info,
                data,
                source,
                filename,
            );
        },
        .used_underscore_variable => |data| blk: {
            const region_info = self.calcRegionInfo(data.region);
            break :blk try Diagnostic.buildUsedUnderscoreVariableReport(
                allocator,
                &self.env.idents,
                region_info,
                data,
                source,
                filename,
            );
        },
    };
}

/// Inserts a placeholder CIR node and creates a fresh variable in the types store at that index
pub fn pushFreshTypeVar(self: *CIR, parent_node_idx: Node.Idx, region: base.Region) types.Var {
    return self.pushTypeVar(.{ .flex_var = null }, parent_node_idx, region);
}

/// Inserts a placeholder CIR node and creates a type variable with the
/// specified content in the types store at that index
pub fn pushTypeVar(self: *CIR, content: types.Content, parent_node_idx: Node.Idx, region: base.Region) types.Var {
    // insert a placeholder can node
    const var_slot = self.store.addTypeVarSlot(parent_node_idx, region);

    // if the new can node idx is greater than the types store length, backfill
    const var_: types.Var = @enumFromInt(@intFromEnum(var_slot));
    self.env.types.fillInSlotsThru(var_) catch |err| exitOnOom(err);

    // set the type store slot based on the placeholder node idx
    self.env.types.setVarContent(var_, content);

    return var_;
}

/// Set a type variable To the specified content at the specified CIR node index.
pub fn setTypeVarAtDef(self: *CIR, at_idx: Def.Idx, content: types.Content) types.Var {
    return self.setTypeVarAt(@enumFromInt(@intFromEnum(at_idx)), content);
}

/// Set a type variable To the specified content at the specified CIR node index.
pub fn setTypeVarAtExpr(self: *CIR, at_idx: Expr.Idx, content: types.Content) types.Var {
    return self.setTypeVarAt(@enumFromInt(@intFromEnum(at_idx)), content);
}

/// Set a type variable To the specified content at the specified CIR node index.
pub fn setTypeVarAtPat(self: *CIR, at_idx: Pattern.Idx, content: types.Content) types.Var {
    return self.setTypeVarAt(@enumFromInt(@intFromEnum(at_idx)), content);
}

/// Set a type variable To the specified content at the specified CIR node index.
pub fn setTypeVarAt(self: *CIR, at_idx: Node.Idx, content: types.Content) types.Var {
    // if the new can node idx is greater than the types store length, backfill
    const var_: types.Var = @enumFromInt(@intFromEnum(at_idx));
    self.env.types.fillInSlotsThru(var_) catch |err| exitOnOom(err);

    // set the type store slot based on the placeholder node idx
    self.env.types.setVarContent(var_, content);

    return var_;
}

// Helper to add type index info to a s-expr node
fn appendTypeVar(node: *sexpr.Expr, gpa: std.mem.Allocator, name: []const u8, type_idx: TypeVar) void {
    var type_node = sexpr.Expr.init(gpa, name);
    type_node.appendUnsignedInt(gpa, @intCast(@intFromEnum(type_idx)));
    node.appendNode(gpa, &type_node);
}

// Helper to add identifier info to a s-expr node
fn appendIdent(node: *sexpr.Expr, gpa: std.mem.Allocator, ir: *const CIR, name: []const u8, ident_idx: Ident.Idx) void {
    const ident_text = ir.env.idents.getText(ident_idx);

    // Create a node with no pre-allocated children to avoid aliasing issues
    const ident_node = sexpr.Expr{
        .node = .{
            .value = gpa.dupe(u8, name) catch @panic("Failed to duplicate name"),
            .children = .{}, // Empty ArrayListUnmanaged - no allocation
        },
    };

    // Append the node to the parent first
    switch (node.*) {
        .node => |*n| {
            n.children.append(gpa, ident_node) catch @panic("Failed to append node");

            // Now add the string child directly to the node in its final location
            const last_idx = n.children.items.len - 1;
            n.children.items[last_idx].appendString(gpa, ident_text);
        },
        else => @panic("appendIdent called on non-node"),
    }
}

// Helper to format pattern index for s-expr output
fn formatPatternIdxNode(gpa: std.mem.Allocator, pattern_idx: Pattern.Idx) sexpr.Expr {
    var node = sexpr.Expr.init(gpa, "pid");
    node.appendUnsignedInt(gpa, @intFromEnum(pattern_idx));
    return node;
}

test "Node is 24 bytes" {
    try testing.expectEqual(24, @sizeOf(Node));
}

/// A single statement - either at the top-level or within a block.
pub const Statement = union(enum) {
    /// A simple immutable declaration
    decl: struct {
        pattern: Pattern.Idx,
        expr: Expr.Idx,
        region: Region,
    },
    /// A rebindable declaration using the "var" keyword
    /// Not valid at the top level of a module
    @"var": struct {
        pattern_idx: Pattern.Idx,
        expr: Expr.Idx,
        region: Region,
    },
    /// Reassignment of a previously declared var
    /// Not valid at the top level of a module
    reassign: struct {
        pattern_idx: Pattern.Idx,
        expr: Expr.Idx,
        region: Region,
    },
    /// The "crash" keyword instruct a runtime crash with message
    ///
    /// Not valid at the top level of a module
    crash: struct {
        msg: StringLiteral.Idx,
        region: Region,
    },
    /// Just an expression - usually the return value for a block
    ///
    /// Not valid at the top level of a module
    expr: struct {
        expr: Expr.Idx,
        region: Region,
    },
    /// An expression that will cause a panic (or some other error handling mechanism) if it evaluates to false
    expect: struct {
        body: Expr.Idx,
        region: Region,
    },
    /// A block of code that will be ran multiple times for each item in a list.
    ///
    /// Not valid at the top level of a module
    @"for": struct {
        patt: Pattern.Idx,
        expr: Expr.Idx,
        body: Expr.Idx,
        region: Region,
    },
    /// A early return of the enclosing function.
    ///
    /// Not valid at the top level of a module
    @"return": struct {
        expr: Expr.Idx,
        region: Region,
    },
    /// Brings in another module for use in the current module, optionally exposing only certain members of that module.
    ///
    /// Only valid at the top level of a module
    import: struct {
        module_name_tok: Ident.Idx,
        qualifier_tok: ?Ident.Idx,
        alias_tok: ?Ident.Idx,
        exposes: ExposedItem.Span,
        region: Region,
    },
    /// A declaration of a new type - whether an alias or a new nominal custom type
    ///
    /// Only valid at the top level of a module
    type_decl: struct {
        header: TypeHeader.Idx,
        anno: CIR.TypeAnno.Idx,
        where: ?WhereClause.Span,
        region: Region,
    },
    /// A type annotation, declaring that the value referred to by an ident in the same scope should be a given type.
    type_anno: struct {
        name: Ident.Idx,
        anno: CIR.TypeAnno.Idx,
        where: ?WhereClause.Span,
        region: Region,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };

    pub fn toSExpr(self: *const @This(), ir: *CIR, env: *ModuleEnv) sexpr.Expr {
        const gpa = ir.env.gpa;
        switch (self.*) {
            .decl => |d| {
                var node = sexpr.Expr.init(gpa, "s_let");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(d.region));

                var pattern_node = ir.store.getPattern(d.pattern).toSExpr(ir, d.pattern);
                node.appendNode(gpa, &pattern_node);

                var expr_node = ir.store.getExpr(d.expr).toSExpr(ir, env);
                node.appendNode(gpa, &expr_node);

                return node;
            },
            .@"var" => |v| {
                var node = sexpr.Expr.init(gpa, "s_var");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(v.region));

                var pattern_idx = formatPatternIdxNode(gpa, v.pattern_idx);
                node.appendNode(gpa, &pattern_idx);

                var pattern_node = ir.store.getPattern(v.pattern_idx).toSExpr(ir, v.pattern_idx);
                node.appendNode(gpa, &pattern_node);

                var expr_node = ir.store.getExpr(v.expr).toSExpr(ir, env);
                node.appendNode(gpa, &expr_node);

                return node;
            },
            .reassign => |r| {
                var node = sexpr.Expr.init(gpa, "s_reassign");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(r.region));

                var pattern_idx = formatPatternIdxNode(gpa, r.pattern_idx);
                node.appendNode(gpa, &pattern_idx);

                var expr_node = ir.store.getExpr(r.expr).toSExpr(ir, env);
                node.appendNode(gpa, &expr_node);
                return node;
            },
            .crash => |c| {
                var node = sexpr.Expr.init(gpa, "s_crash");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(c.region));

                const msg = env.strings.get(c.msg);
                node.appendString(gpa, msg);

                return node;
            },
            .expr => |s| {
                var node = sexpr.Expr.init(gpa, "s_expr");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                var expr_node = ir.store.getExpr(s.expr).toSExpr(ir, env);
                node.appendNode(gpa, &expr_node);

                return node;
            },
            .expect => |s| {
                var node = sexpr.Expr.init(gpa, "s_expect");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                var body_node = ir.store.getExpr(s.body).toSExpr(ir, env);
                node.appendNode(gpa, &body_node);

                return node;
            },
            .@"for" => |s| {
                var node = sexpr.Expr.init(gpa, "s_for");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                var pattern_node = ir.store.getPattern(s.patt).toSExpr(ir, s.patt);
                node.appendNode(gpa, &pattern_node);

                var expr_node = ir.store.getExpr(s.expr).toSExpr(ir, env);
                node.appendNode(gpa, &expr_node);

                var body_node = ir.store.getExpr(s.body).toSExpr(ir, env);
                node.appendNode(gpa, &body_node);

                return node;
            },
            .@"return" => |s| {
                var node = sexpr.Expr.init(gpa, "s_return");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                var expr_node = ir.store.getExpr(s.expr).toSExpr(ir, env);
                node.appendNode(gpa, &expr_node);

                return node;
            },
            .import => |s| {
                var node = sexpr.Expr.init(gpa, "s_import");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                const module_name = env.idents.getText(s.module_name_tok);
                node.appendString(gpa, module_name);

                if (s.qualifier_tok) |qualifier| {
                    const qualifier_name = env.idents.getText(qualifier);
                    node.appendString(gpa, qualifier_name);
                } else {
                    node.appendString(gpa, "");
                }

                if (s.alias_tok) |alias| {
                    const alias_name = env.idents.getText(alias);
                    node.appendString(gpa, alias_name);
                } else {
                    node.appendString(gpa, "");
                }

                var exposes_node = sexpr.Expr.init(gpa, "exposes");
                const exposes_slice = ir.store.sliceExposedItems(s.exposes);
                for (exposes_slice) |_| {
                    // TODO: Implement ExposedItem.toSExpr when ExposedItem structure is complete
                    exposes_node.appendString(gpa, "exposed_item");
                }
                node.appendNode(gpa, &exposes_node);

                return node;
            },
            .type_decl => |s| {
                var node = sexpr.Expr.init(gpa, "s_type_decl");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                // Add the type header
                var header_node = ir.store.getTypeHeader(s.header).toSExpr(ir, env);
                node.appendNode(gpa, &header_node);

                // Add the type annotation
                var anno_node = ir.store.getTypeAnno(s.anno).toSExpr(ir, env);
                node.appendNode(gpa, &anno_node);

                // TODO: Add where clause when implemented
                if (s.where) |_| {
                    node.appendString(gpa, "where_clause_todo");
                }

                return node;
            },
            .type_anno => |s| {
                var node = sexpr.Expr.init(gpa, "s_type_anno");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(s.region));

                const name = env.idents.getText(s.name);
                node.appendString(gpa, name);

                var anno_node = ir.store.getTypeAnno(s.anno).toSExpr(ir, env);
                node.appendNode(gpa, &anno_node);

                if (s.where) |where_span| {
                    var where_node = sexpr.Expr.init(gpa, "where");
                    const where_slice = ir.store.sliceWhereClauses(where_span);
                    for (where_slice) |_| {
                        // TODO: Implement WhereClause.toSExpr when WhereClause structure is complete
                        where_node.appendString(gpa, "where_clause");
                    }
                    node.appendNode(gpa, &where_node);
                } else {
                    node.appendString(gpa, "");
                }

                return node;
            },
        }
    }

    /// Extract the region from any Statement variant
    pub fn toRegion(self: *const @This()) Region {
        switch (self.*) {
            .decl => |s| return s.region,
            .@"var" => |s| return s.region,
            .reassign => |s| return s.region,
            .crash => |s| return s.region,
            .expr => |s| return s.region,
            .expect => |s| return s.region,
            .@"for" => |s| return s.region,
            .@"return" => |s| return s.region,
            .import => |s| return s.region,
            .type_decl => |s| return s.region,
            .type_anno => |s| return s.region,
        }
    }
};

/// A working representation of a record field
pub const RecordField = struct {
    name: Ident.Idx,
    value: Expr.Idx,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
};

/// TODO: implement WhereClause
pub const WhereClause = union(enum) {
    alias: WhereClause.Alias,
    method: Method,
    mod_method: ModuleMethod,

    pub const Alias = struct {
        var_tok: Ident.Idx,
        alias_tok: Ident.Idx,
        region: Region,
    };
    pub const Method = struct {
        var_tok: Ident.Idx,
        name_tok: Ident.Idx,
        args: TypeAnno.Span,
        ret_anno: TypeAnno.Idx,
        region: Region,
    };
    pub const ModuleMethod = struct {
        var_tok: Ident.Idx,
        name_tok: Ident.Idx,
        args: TypeAnno.Span,
        ret_anno: TypeAnno.Span,
        region: Region,
    };

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
};

/// TODO: implement PatternRecordField
pub const PatternRecordField = struct {
    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
};

/// Canonical representation of type annotations in Roc.
///
/// Type annotations appear on the right-hand side of type declarations and in other
/// contexts where types are specified. For example, in `Map(a, b) : List(a) -> List(b)`,
/// the `List(a) -> List(b)` part is represented by these TypeAnno variants.
pub const TypeAnno = union(enum) {
    /// Type application: applying a type constructor to arguments.
    /// Examples: `List(Str)`, `Dict(String, Int)`, `Result(a, b)`
    apply: struct {
        symbol: Ident.Idx, // The type constructor being applied (e.g., "List", "Dict")
        args: TypeAnno.Span, // The type arguments (e.g., [Str], [String, Int])
        region: Region,
    },

    /// Type variable: a placeholder type that can be unified with other types.
    /// Examples: `a`, `b`, `elem` in generic type signatures
    ty_var: struct {
        name: Ident.Idx, // The variable name (e.g., "a", "b")
        region: Region,
    },

    /// Inferred type `_`
    underscore: struct {
        region: Region,
    },

    /// Basic type identifier: a concrete type name without arguments.
    /// Examples: `Str`, `U64`, `Bool`
    ty: struct {
        symbol: Ident.Idx, // The type name
        region: Region,
    },

    /// Module-qualified type: a type name prefixed with its module.
    /// Examples: `Shape.Rect`, `Json.Decoder`
    mod_ty: struct {
        mod_symbol: Ident.Idx, // The module name (e.g., "Json")
        ty_symbol: Ident.Idx, // The type name (e.g., "Decoder")
        region: Region,
    },

    /// Tag union type: a union of tags, possibly with payloads.
    /// Examples: `[Some(a), None]`, `[Red, Green, Blue]`, `[Cons(a, (List a)), Nil]`
    tag_union: struct {
        tags: TypeAnno.Span, // The individual tags in the union
        open_anno: ?TypeAnno.Idx, // Optional extension variable for open unions
        region: Region,
    },

    /// Tuple type: a fixed-size collection of heterogeneous types.
    /// Examples: `(Str, U64)`, `(a, b, c)`
    tuple: struct {
        annos: TypeAnno.Span, // The types of each tuple element
        region: Region,
    },

    /// Record type: a collection of named fields with their types.
    /// Examples: `{ name: Str, age: U64 }`, `{ x: F64, y: F64 }`
    record: struct {
        fields: AnnoRecordField.Span, // The field definitions
        region: Region,
    },

    /// Function type: represents function signatures.
    /// Examples: `a -> b`, `Str, U64 -> Str`, `{} => Str`
    @"fn": struct {
        args: TypeAnno.Span, // Argument types
        ret: TypeAnno.Idx, // Return type
        effectful: bool, // Whether the function can perform effects, i.e. uses fat arrow `=>`
        region: Region,
    },

    /// Parenthesized type: used for grouping and precedence.
    /// Examples: `(a -> b)` in `a, (a -> b) -> b`
    parens: struct {
        anno: TypeAnno.Idx, // The type inside the parentheses
        region: Region,
    },

    /// Malformed type annotation: represents a type that couldn't be parsed correctly.
    /// This follows the "Inform Don't Block" principle - compilation continues with
    /// an error marker that will be reported to the user.
    malformed: struct {
        diagnostic: Diagnostic.Idx, // The error that occurred
        region: Region,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };

    pub fn toSExpr(self: *const @This(), ir: *const CIR, env: *ModuleEnv) sexpr.Expr {
        const gpa = ir.env.gpa;
        switch (self.*) {
            .apply => |a| {
                var node = sexpr.Expr.init(gpa, "apply");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(a.region));

                const symbol_name = env.idents.getText(a.symbol);
                node.appendString(gpa, symbol_name);

                const args_slice = ir.store.sliceTypeAnnos(a.args);
                for (args_slice) |arg_idx| {
                    const arg = ir.store.getTypeAnno(arg_idx);
                    var arg_node = arg.toSExpr(ir, env);
                    node.appendNode(gpa, &arg_node);
                }

                return node;
            },
            .ty_var => |tv| {
                var node = sexpr.Expr.init(gpa, "ty_var");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(tv.region));

                const var_name = env.idents.getText(tv.name);
                node.appendString(gpa, var_name);

                return node;
            },
            .underscore => |u| {
                var node = sexpr.Expr.init(gpa, "underscore");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(u.region));
                return node;
            },
            .ty => |t| {
                var node = sexpr.Expr.init(gpa, "ty");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(t.region));

                const type_name = env.idents.getText(t.symbol);
                node.appendString(gpa, type_name);

                return node;
            },
            .mod_ty => |mt| {
                var node = sexpr.Expr.init(gpa, "mod_ty");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(mt.region));

                const mod_name = env.idents.getText(mt.mod_symbol);
                const type_name = env.idents.getText(mt.ty_symbol);
                node.appendString(gpa, mod_name);
                node.appendString(gpa, type_name);

                return node;
            },
            .tag_union => |tu| {
                var node = sexpr.Expr.init(gpa, "tag_union");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(tu.region));

                const tags_slice = ir.store.sliceTypeAnnos(tu.tags);
                for (tags_slice) |tag_idx| {
                    const tag = ir.store.getTypeAnno(tag_idx);
                    var tag_node = tag.toSExpr(ir, env);
                    node.appendNode(gpa, &tag_node);
                }

                if (tu.open_anno) |open_idx| {
                    const open_anno = ir.store.getTypeAnno(open_idx);
                    var open_node = open_anno.toSExpr(ir, env);
                    node.appendNode(gpa, &open_node);
                }

                return node;
            },
            .tuple => |tup| {
                var node = sexpr.Expr.init(gpa, "tuple");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(tup.region));

                const annos_slice = ir.store.sliceTypeAnnos(tup.annos);
                for (annos_slice) |anno_idx| {
                    const anno = ir.store.getTypeAnno(anno_idx);
                    var anno_node = anno.toSExpr(ir, env);
                    node.appendNode(gpa, &anno_node);
                }

                return node;
            },
            .record => |r| {
                var node = sexpr.Expr.init(gpa, "record");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(r.region));

                const fields_slice = ir.store.sliceAnnoRecordFields(r.fields);
                for (fields_slice) |field_idx| {
                    const field = ir.store.getAnnoRecordField(field_idx);
                    var field_node = sexpr.Expr.init(gpa, "record_field");

                    const field_name = env.idents.getText(field.name);
                    field_node.appendString(gpa, field_name);

                    var type_node = ir.store.getTypeAnno(field.ty).toSExpr(ir, env);
                    field_node.appendNode(gpa, &type_node);

                    node.appendNode(gpa, &field_node);
                }

                return node;
            },
            .@"fn" => |f| {
                var node = sexpr.Expr.init(gpa, "fn");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(f.region));

                const args_slice = ir.store.sliceTypeAnnos(f.args);
                for (args_slice) |arg_idx| {
                    const arg = ir.store.getTypeAnno(arg_idx);
                    var arg_node = arg.toSExpr(ir, env);
                    node.appendNode(gpa, &arg_node);
                }

                var ret_node = ir.store.getTypeAnno(f.ret).toSExpr(ir, env);
                node.appendNode(gpa, &ret_node);

                const effectful_str = if (f.effectful) "true" else "false";
                node.appendString(gpa, effectful_str);

                return node;
            },
            .parens => |p| {
                var node = sexpr.Expr.init(gpa, "parens");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                const inner_anno = ir.store.getTypeAnno(p.anno);
                var inner_node = inner_anno.toSExpr(ir, env);
                node.appendNode(gpa, &inner_node);

                return node;
            },
            .malformed => |m| {
                var node = sexpr.Expr.init(gpa, "malformed_type_anno");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(m.region));
                return node;
            },
        }
    }

    /// Extract the region from any TypeAnno variant
    pub fn toRegion(self: *const @This()) Region {
        switch (self.*) {
            .apply => |a| return a.region,
            .ty_var => |tv| return tv.region,
            .underscore => |u| return u.region,
            .ty => |t| return t.region,
            .mod_ty => |mt| return mt.region,
            .tuple => |t| return t.region,
            .tag_union => |tu| return tu.region,
            .record => |r| return r.region,
            .@"fn" => |f| return f.region,
            .parens => |p| return p.region,
            .malformed => |m| return m.region,
        }
    }
};

/// Canonical representation of type declaration headers.
///
/// The type header is the left-hand side of a type declaration, specifying the type name
/// and its parameters. For example, in `Map(a, b) : List(a) -> List(b)`, the header is
/// `Map(a, b)` with name "Map" and type parameters `[a, b]`.
///
/// Examples:
/// - `Foo` - simple type with no parameters
/// - `List(a)` - generic type with one parameter
/// - `Dict(k, v)` - generic type with two parameters
/// - `Result(ok, err)` - generic type with named parameters
pub const TypeHeader = struct {
    name: Ident.Idx, // The type name (e.g., "Map", "List", "Dict")
    args: TypeAnno.Span, // Type parameters (e.g., [a, b] for generic types)
    region: Region, // Source location of the entire header

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };

    pub fn toSExpr(self: *const @This(), ir: *CIR, env: *ModuleEnv) sexpr.Expr {
        const gpa = ir.env.gpa;
        var node = sexpr.Expr.init(gpa, "type_header");
        node.appendRegionInfo(gpa, ir.calcRegionInfo(self.region));

        // Add the type name
        const type_name = env.idents.getText(self.name);
        node.appendString(gpa, type_name);

        // Add the type arguments
        const args_slice = ir.store.sliceTypeAnnos(self.args);
        if (args_slice.len > 0) {
            var args_node = sexpr.Expr.init(gpa, "args");
            for (args_slice) |arg_idx| {
                const arg = ir.store.getTypeAnno(arg_idx);
                var arg_node = arg.toSExpr(ir, env);
                args_node.appendNode(gpa, &arg_node);
            }
            node.appendNode(gpa, &args_node);
        }

        return node;
    }
};

/// Record field in a type annotation: `{ field_name: Type }`
pub const AnnoRecordField = struct {
    name: Ident.Idx,
    ty: TypeAnno.Idx,
    region: Region,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
};

/// An item exposed from an imported module
/// Examples: `line!`, `Type as ValueCategory`, `Custom.*`
pub const ExposedItem = struct {
    /// The identifier being exposed
    name: Ident.Idx,
    /// Optional alias for the exposed item (e.g., `function` in `func as function`)
    alias: ?Ident.Idx,
    /// Whether this is a wildcard import (e.g., `Custom.*`)
    is_wildcard: bool,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
};

/// An expression that has been canonicalized.
pub const Expr = union(enum) {
    num: struct {
        num_var: TypeVar,
        literal: StringLiteral.Idx,
        value: IntValue,
        bound: types.Num.Int.Precision,
        region: Region,
    },
    int: struct {
        int_var: TypeVar,
        precision_var: TypeVar,
        literal: StringLiteral.Idx,
        value: IntValue,
        bound: types.Num.Int.Precision,
        region: Region,
    },
    float: struct {
        frac_var: TypeVar,
        precision_var: TypeVar,
        literal: StringLiteral.Idx,
        value: f64,
        bound: types.Num.Frac.Precision,
        region: Region,
    },
    // A single segment of a string literal
    // a single string may be made up of a span sequential segments
    // for example if it was split across multiple lines
    str_segment: struct {
        literal: StringLiteral.Idx,
        region: Region,
    },
    // A string is combined of one or more segments, some of which may be interpolated
    // An interpolated string contains one or more non-string_segment's in the span
    str: struct {
        span: Expr.Span,
        region: Region,
    },
    single_quote: struct {
        num_var: TypeVar,
        precision_var: TypeVar,
        value: u32,
        bound: types.Num.Int.Precision,
        region: Region,
    },
    lookup: Lookup,
    // TODO introduce a new node for re-assign here, used by Var instead of lookup
    list: struct {
        elem_var: TypeVar,
        elems: Expr.Span,
        region: Region,
    },
    tuple: struct {
        tuple_var: TypeVar,
        elems: Expr.Span,
        region: Region,
    },
    when: When,
    @"if": struct {
        cond_var: TypeVar,
        branch_var: TypeVar,
        branches: IfBranch.Span,
        final_else: Expr.Idx,
        region: Region,
    },
    /// This is *only* for calling functions, not for tag application.
    /// The Tag variant contains any applied values inside it.
    call: struct {
        args: Expr.Span,
        called_via: CalledVia,
        region: Region,
    },
    record: struct {
        ext_var: TypeVar,
        region: Region,
        // TODO:
        // fields: SendMap<Lowercase, Field>,
    },
    /// Empty record constant
    empty_record: struct {
        region: Region,
    },
    block: struct {
        /// Statements executed in sequence
        stmts: Statement.Span,
        /// Final expression that produces the block's value
        final_expr: Expr.Idx,
        region: Region,
    },
    record_access: struct {
        record_var: TypeVar,
        ext_var: TypeVar,
        field_var: TypeVar,
        loc_expr: Expr.Idx,
        field: Ident.Idx,
        region: Region,
    },
    tag: struct {
        ext_var: TypeVar,
        name: Ident.Idx,
        args: Expr.Span,
        region: Region,
    },
    zero_argument_tag: struct {
        closure_name: Ident.Idx,
        variant_var: TypeVar,
        ext_var: TypeVar,
        name: Ident.Idx,
        region: Region,
    },
    lambda: struct {
        args: Pattern.Span,
        body: Expr.Idx,
        region: Region,
    },
    binop: Binop,
    /// Dot access that could be either record field access or static dispatch
    /// The decision is deferred until after type inference based on the receiver's type
    dot_access: struct {
        receiver: Expr.Idx, // Expression before the dot (e.g., `list` in `list.map`)
        field_name: Ident.Idx, // Identifier after the dot (e.g., `map` in `list.map`)
        args: ?Expr.Span, // Optional arguments for method calls (e.g., `fn` in `list.map(fn)`)
        region: Region,
    },
    /// Compiles, but will crash if reached
    runtime_error: struct {
        diagnostic: Diagnostic.Idx,
        region: Region,
    },

    pub const Lookup = struct {
        pattern_idx: Pattern.Idx,
        region: Region,
    };

    pub const Idx = enum(u32) { _ };

    pub const Span = struct { span: DataSpan };

    pub fn init_str(expr_span: Expr.Span, region: Region) Expr {
        return .{ .str = .{
            .span = expr_span,
            .region = region,
        } };
    }

    pub fn init_str_segment(literal: StringLiteral.Idx, region: Region) Expr {
        return .{ .str_segment = .{
            .literal = literal,
            .region = region,
        } };
    }

    pub const Binop = struct {
        op: Op,
        lhs: Expr.Idx,
        rhs: Expr.Idx,
        region: Region,

        pub const Op = enum {
            add,
            sub,
            mul,
            div,
            rem,
            lt,
            gt,
            le,
            ge,
            eq,
            ne,
        };

        pub fn init(op: Op, lhs: Expr.Idx, rhs: Expr.Idx, region: Region) Binop {
            return .{ .lhs = lhs, .op = op, .rhs = rhs, .region = region };
        }
    };

    pub fn toRegion(self: *const @This()) ?Region {
        switch (self.*) {
            .num => |e| return e.region,
            .int => |e| return e.region,
            .float => |e| return e.region,
            .str_segment => |e| return e.region,
            .str => |e| return e.region,
            .single_quote => |e| return e.region,
            .lookup => |e| return e.region,
            .list => |e| return e.region,
            .tuple => |e| return e.region,
            .when => |e| return e.region,
            .@"if" => |e| return e.region,
            .call => |e| return e.region,
            .record => |e| return e.region,
            .empty_record => |e| return e.region,
            .record_access => |e| return e.region,
            .dot_access => |e| return e.region,
            .tag => |e| return e.region,
            .zero_argument_tag => |e| return e.region,
            .binop => |e| return e.region,
            .block => |e| return e.region,
            .lambda => |e| return e.region,
            .runtime_error => |e| return e.region,
        }
    }

    pub fn toSExpr(self: *const @This(), ir: *CIR, env: *ModuleEnv) sexpr.Expr {
        const gpa = ir.env.gpa;
        switch (self.*) {
            .num => |num_expr| {
                var num_node = sexpr.Expr.init(gpa, "e_num");
                num_node.appendRegionInfo(gpa, ir.calcRegionInfo(num_expr.region));

                // Add num_var
                var num_var_node = sexpr.Expr.init(gpa, "num_var");
                num_var_node.appendUnsignedInt(gpa, @intFromEnum(num_expr.num_var));
                num_node.appendNode(gpa, &num_var_node);

                // Add literal
                var literal_node = sexpr.Expr.init(gpa, "literal");
                const literal_str = ir.env.strings.get(num_expr.literal);
                literal_node.appendString(gpa, literal_str);
                num_node.appendNode(gpa, &literal_node);

                // Add value info
                var value_node = sexpr.Expr.init(gpa, "value");
                // TODO: Format the actual integer value properly
                value_node.appendString(gpa, "TODO");
                num_node.appendNode(gpa, &value_node);

                // Add bound info
                var bound_node = sexpr.Expr.init(gpa, "bound");
                bound_node.appendString(gpa, @tagName(num_expr.bound));
                num_node.appendNode(gpa, &bound_node);

                return num_node;
            },
            .int => |int_expr| {
                var int_node = sexpr.Expr.init(gpa, "e_int");
                int_node.appendRegionInfo(gpa, ir.calcRegionInfo(int_expr.region));

                // Add int_var
                var int_var_node = sexpr.Expr.init(gpa, "int_var");
                int_var_node.appendUnsignedInt(gpa, @intFromEnum(int_expr.int_var));
                int_node.appendNode(gpa, &int_var_node);

                // Add precision_var
                var prec_var_node = sexpr.Expr.init(gpa, "precision_var");
                prec_var_node.appendUnsignedInt(gpa, @intFromEnum(int_expr.precision_var));
                int_node.appendNode(gpa, &prec_var_node);

                // Add literal
                var literal_node = sexpr.Expr.init(gpa, "literal");
                const literal_str = ir.env.strings.get(int_expr.literal);
                literal_node.appendString(gpa, literal_str);
                int_node.appendNode(gpa, &literal_node);

                // Add value info
                var value_node = sexpr.Expr.init(gpa, "value");
                value_node.appendString(gpa, "TODO");
                int_node.appendNode(gpa, &value_node);

                // Add bound info
                var bound_node = sexpr.Expr.init(gpa, "bound");
                bound_node.appendString(gpa, @tagName(int_expr.bound));
                int_node.appendNode(gpa, &bound_node);

                return int_node;
            },
            .float => |float_expr| {
                var float_node = sexpr.Expr.init(gpa, "e_float");
                float_node.appendRegionInfo(gpa, ir.calcRegionInfo(float_expr.region));

                // Add frac_var
                var frac_var_node = sexpr.Expr.init(gpa, "frac_var");
                frac_var_node.appendUnsignedInt(gpa, @intFromEnum(float_expr.frac_var));
                float_node.appendNode(gpa, &frac_var_node);

                // Add precision_var
                var prec_var_node = sexpr.Expr.init(gpa, "precision_var");
                prec_var_node.appendUnsignedInt(gpa, @intFromEnum(float_expr.precision_var));
                float_node.appendNode(gpa, &prec_var_node);

                // Add literal
                var literal_node = sexpr.Expr.init(gpa, "literal");
                const literal = ir.env.strings.get(float_expr.literal);
                literal_node.appendString(gpa, literal);
                float_node.appendNode(gpa, &literal_node);

                // Add value
                var value_node = sexpr.Expr.init(gpa, "value");
                const value_str = std.fmt.allocPrint(gpa, "{d}", .{float_expr.value}) catch |err| exitOnOom(err);
                defer gpa.free(value_str);
                value_node.appendString(gpa, value_str);
                float_node.appendNode(gpa, &value_node);

                // Add bound info
                var bound_node = sexpr.Expr.init(gpa, "bound");
                bound_node.appendString(gpa, @tagName(float_expr.bound));
                float_node.appendNode(gpa, &bound_node);

                return float_node;
            },
            .str_segment => |e| {
                var str_node = sexpr.Expr.init(gpa, "e_literal");
                str_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));

                const value = ir.env.strings.get(e.literal);
                str_node.appendString(gpa, value);

                return str_node;
            },
            .str => |e| {
                var str_node = sexpr.Expr.init(gpa, "e_string");
                str_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));

                for (ir.store.sliceExpr(e.span)) |segment| {
                    var segment_node = ir.store.getExpr(segment).toSExpr(ir, env);
                    str_node.appendNode(gpa, &segment_node);
                }

                return str_node;
            },
            .single_quote => |e| {
                var single_quote_node = sexpr.Expr.init(gpa, "e_single_quote");
                single_quote_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));

                // Add num_var
                var num_var_node = sexpr.Expr.init(gpa, "num_var");
                const num_var_str = e.num_var.allocPrint(gpa);
                defer gpa.free(num_var_str);
                num_var_node.appendString(gpa, num_var_str);
                single_quote_node.appendNode(gpa, &num_var_node);

                // Add precision_var
                var prec_var_node = sexpr.Expr.init(gpa, "precision_var");
                prec_var_node.appendUnsignedInt(gpa, @intFromEnum(e.precision_var));
                single_quote_node.appendNode(gpa, &prec_var_node);

                // Add value
                var value_node = sexpr.Expr.init(gpa, "value");
                const value_str = std.fmt.allocPrint(gpa, "'\\u{{{x}}}'", .{e.value}) catch |err| exitOnOom(err);
                defer gpa.free(value_str);
                value_node.appendString(gpa, value_str);
                single_quote_node.appendNode(gpa, &value_node);

                // Add bound info
                var bound_node = sexpr.Expr.init(gpa, "bound");
                bound_node.appendString(gpa, @tagName(e.bound));
                single_quote_node.appendNode(gpa, &bound_node);

                return single_quote_node;
            },
            .list => |l| {
                var list_node = sexpr.Expr.init(gpa, "e_list");
                list_node.appendRegionInfo(gpa, ir.calcRegionInfo(l.region));

                // Add elem_var
                var elem_var_node = sexpr.Expr.init(gpa, "elem_var");
                elem_var_node.appendUnsignedInt(gpa, @intFromEnum(l.elem_var));
                list_node.appendNode(gpa, &elem_var_node);

                // Add list elements
                var elems_node = sexpr.Expr.init(gpa, "elems");
                for (ir.store.sliceExpr(l.elems)) |elem_idx| {
                    var elem_node = ir.store.getExpr(elem_idx).toSExpr(ir, env);
                    elems_node.appendNode(gpa, &elem_node);
                }
                list_node.appendNode(gpa, &elems_node);

                return list_node;
            },
            .tuple => |t| {
                var tuple_node = sexpr.Expr.init(gpa, "e_tuple");
                tuple_node.appendRegionInfo(gpa, ir.calcRegionInfo(t.region));

                // Add tuple_var
                var tuple_var_node = sexpr.Expr.init(gpa, "tuple_var");
                const tuple_var_str = t.tuple_var.allocPrint(gpa);
                defer gpa.free(tuple_var_str);
                tuple_var_node.appendString(gpa, tuple_var_str);
                tuple_node.appendNode(gpa, &tuple_var_node);

                // Add tuple elements
                var elems_node = sexpr.Expr.init(gpa, "elems");
                for (ir.store.sliceExpr(t.elems)) |elem_idx| {
                    var elem_node = ir.store.getExpr(elem_idx).toSExpr(ir, env);
                    elems_node.appendNode(gpa, &elem_node);
                }
                tuple_node.appendNode(gpa, &elems_node);

                return tuple_node;
            },
            .lookup => |l| {
                var lookup_node = sexpr.Expr.init(gpa, "e_lookup");
                lookup_node.appendRegionInfo(gpa, ir.calcRegionInfo(l.region));

                var pattern_idx = formatPatternIdxNode(gpa, l.pattern_idx);
                lookup_node.appendNode(gpa, &pattern_idx);

                return lookup_node;
            },
            .when => |e| {
                var when_branch_node = sexpr.Expr.init(gpa, "e_when");
                when_branch_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));
                when_branch_node.appendString(gpa, "TODO when branch");

                return when_branch_node;
            },
            .@"if" => |if_expr| {
                var if_node = sexpr.Expr.init(gpa, "e_if");
                if_node.appendRegionInfo(gpa, ir.calcRegionInfo(if_expr.region));

                // Add cond_var
                var cond_var_node = sexpr.Expr.init(gpa, "cond_var");
                const cond_var_str = if_expr.cond_var.allocPrint(gpa);
                defer gpa.free(cond_var_str);
                cond_var_node.appendString(gpa, cond_var_str);
                if_node.appendNode(gpa, &cond_var_node);

                // Add branch_var
                var branch_var_node = sexpr.Expr.init(gpa, "branch_var");
                const branch_var_str = if_expr.branch_var.allocPrint(gpa);
                defer gpa.free(branch_var_str);
                branch_var_node.appendString(gpa, branch_var_str);
                if_node.appendNode(gpa, &branch_var_node);

                // Add branches
                // const if_branch_slice = ir.store.sliceIfBranch(if_expr.branches);
                var branches_node = sexpr.Expr.init(gpa, "branches");
                // for (if_branch_slice) |if_branch_idx| {
                //     const if_branch = ir.store.getIfBranch(if_branch_idx);
                //     _ = if_branch;
                // var cond_node = cond.toSExpr(env, ir);
                // var body_node = body.toSExpr(env, ir);
                // var branch_node = sexpr.Expr.init(gpa, "branch");
                // branch_node.appendNode(gpa, &cond_node);
                // branch_node.appendNode(gpa, &body_node);
                // branches_node.appendNode(gpa, &branch_node);
                // }
                // node.appendNode(gpa, &branches_node);

                // var else_node = sexpr.Expr.init(gpa, "else");
                // const final_else_expr = ir.exprs_at_regions.get(i.final_else);
                // var else_sexpr = final_else_expr.toSExpr(env, ir);
                // else_node.appendNode(gpa, &else_sexpr);
                // node.appendNode(gpa, &else_node);
                branches_node.appendString(gpa, "TODO: access if branches");
                if_node.appendNode(gpa, &branches_node);

                // Add final_else
                var else_node = sexpr.Expr.init(gpa, "else");
                // TODO: Implement proper final_else access
                else_node.appendString(gpa, "TODO: access final else");
                if_node.appendNode(gpa, &else_node);

                return if_node;
            },
            .call => |c| {
                var call_node = sexpr.Expr.init(gpa, "e_call");
                call_node.appendRegionInfo(gpa, ir.calcRegionInfo(c.region));

                // Get all expressions from the args span
                const all_exprs = ir.store.exprSlice(c.args);

                // First element is the function being called
                if (all_exprs.len > 0) {
                    const fn_expr = ir.store.getExpr(all_exprs[0]);
                    var fn_node = fn_expr.toSExpr(ir, env);
                    call_node.appendNode(gpa, &fn_node);
                }

                // Remaining elements are the arguments
                if (all_exprs.len > 1) {
                    for (all_exprs[1..]) |arg_idx| {
                        const arg_expr = ir.store.getExpr(arg_idx);
                        var arg_node = arg_expr.toSExpr(ir, env);
                        call_node.appendNode(gpa, &arg_node);
                    }
                }

                return call_node;
            },
            .record => |record_expr| {
                var record_node = sexpr.Expr.init(gpa, "e_record");
                record_node.appendRegionInfo(gpa, ir.calcRegionInfo(record_expr.region));

                // Add record_var
                var record_var_node = sexpr.Expr.init(gpa, "ext_var");
                record_var_node.appendUnsignedInt(gpa, @intFromEnum(record_expr.ext_var));
                record_node.appendNode(gpa, &record_var_node);

                // TODO: Add fields when implemented
                var fields_node = sexpr.Expr.init(gpa, "fields");
                fields_node.appendString(gpa, "TODO");
                record_node.appendNode(gpa, &fields_node);

                return record_node;
            },
            .empty_record => |e| {
                var empty_record_node = sexpr.Expr.init(gpa, "e_empty_record");
                empty_record_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));
                return empty_record_node;
            },
            .block => |block_expr| {
                var block_node = sexpr.Expr.init(gpa, "e_block");
                block_node.appendRegionInfo(gpa, ir.calcRegionInfo(block_expr.region));

                // Add statements
                for (ir.store.sliceStatements(block_expr.stmts)) |stmt_idx| {
                    var stmt_node = ir.store.getStatement(stmt_idx).toSExpr(ir, env);
                    block_node.appendNode(gpa, &stmt_node);
                }

                // Add final expression
                var expr_node = ir.store.getExpr(block_expr.final_expr).toSExpr(ir, env);
                block_node.appendNode(gpa, &expr_node);

                return block_node;
            },
            .record_access => |access_expr| {
                var access_node = sexpr.Expr.init(gpa, "e_record_access");
                access_node.appendRegionInfo(gpa, ir.calcRegionInfo(access_expr.region));

                // Add record_var
                var record_var_node = sexpr.Expr.init(gpa, "record_var");
                const record_var_str = access_expr.record_var.allocPrint(gpa);
                defer gpa.free(record_var_str);
                record_var_node.appendString(gpa, record_var_str);
                access_node.appendNode(gpa, &record_var_node);

                // Add ext_var
                var ext_var_node = sexpr.Expr.init(gpa, "ext_var");
                const ext_var_str = access_expr.ext_var.allocPrint(gpa);
                defer gpa.free(ext_var_str);
                ext_var_node.appendString(gpa, ext_var_str);
                access_node.appendNode(gpa, &ext_var_node);

                // Add field_var
                var field_var_node = sexpr.Expr.init(gpa, "field_var");
                const field_var_str = access_expr.field_var.allocPrint(gpa);
                defer gpa.free(field_var_str);
                field_var_node.appendString(gpa, field_var_str);
                access_node.appendNode(gpa, &field_var_node);

                // Add loc_expr
                var loc_expr_node = ir.store.getExpr(access_expr.loc_expr).toSExpr(ir, env);
                access_node.appendNode(gpa, &loc_expr_node);

                // Add field
                var field_node = sexpr.Expr.init(gpa, "field");
                const field_str = ir.env.idents.getText(access_expr.field);
                field_node.appendString(gpa, field_str);
                access_node.appendNode(gpa, &field_node);

                return access_node;
            },
            .tag => |tag_expr| {
                var tag_node = sexpr.Expr.init(gpa, "e_tag");
                tag_node.appendRegionInfo(gpa, ir.calcRegionInfo(tag_expr.region));

                // Add ext_var
                var ext_var_node = sexpr.Expr.init(gpa, "ext_var");
                ext_var_node.appendUnsignedInt(gpa, @intFromEnum(tag_expr.ext_var));
                tag_node.appendNode(gpa, &ext_var_node);

                // Add name
                var name_node = sexpr.Expr.init(gpa, "name");
                const name_str = ir.env.idents.getText(tag_expr.name);
                name_node.appendString(gpa, name_str);
                tag_node.appendNode(gpa, &name_node);

                // Add args
                var args_node = sexpr.Expr.init(gpa, "args");
                // const args_slice = ir.typed_exprs_at_regions.rangeToSlice(tag_expr.args);
                args_node.appendString(gpa, "TODO");
                tag_node.appendNode(gpa, &args_node);

                return tag_node;
            },
            .zero_argument_tag => |tag_expr| {
                var tag_node = sexpr.Expr.init(gpa, "e_zero_argument_tag");
                tag_node.appendRegionInfo(gpa, ir.calcRegionInfo(tag_expr.region));

                // Add closure_name
                var closure_name_node = sexpr.Expr.init(gpa, "closure_name");
                const closure_name_str = ir.env.idents.getText(tag_expr.closure_name);
                closure_name_node.appendString(gpa, closure_name_str);
                tag_node.appendNode(gpa, &closure_name_node);

                // Add variant_var
                var variant_var_node = sexpr.Expr.init(gpa, "variant_var");
                variant_var_node.appendUnsignedInt(gpa, @intFromEnum(tag_expr.variant_var));
                tag_node.appendNode(gpa, &variant_var_node);

                // Add ext_var
                var ext_var_node = sexpr.Expr.init(gpa, "ext_var");
                ext_var_node.appendUnsignedInt(gpa, @intFromEnum(tag_expr.ext_var));
                tag_node.appendNode(gpa, &ext_var_node);

                // Add name
                var name_node = sexpr.Expr.init(gpa, "name");
                const name_str = ir.env.idents.getText(tag_expr.name);
                name_node.appendString(gpa, name_str);
                tag_node.appendNode(gpa, &name_node);

                return tag_node;
            },
            .lambda => |lambda_expr| {
                var lambda_node = sexpr.Expr.init(gpa, "e_lambda");
                lambda_node.appendRegionInfo(gpa, ir.calcRegionInfo(lambda_expr.region));

                // Handle args span
                var args_node = sexpr.Expr.init(gpa, "args");
                for (ir.store.slicePatterns(lambda_expr.args)) |arg_idx| {
                    var pattern_node = ir.store.getPattern(arg_idx).toSExpr(ir, arg_idx);
                    args_node.appendNode(gpa, &pattern_node);
                }
                lambda_node.appendNode(gpa, &args_node);

                // Handle body
                var body_node = ir.store.getExpr(lambda_expr.body).toSExpr(ir, env);
                lambda_node.appendNode(gpa, &body_node);

                return lambda_node;
            },
            .binop => |e| {
                var binop_node = sexpr.Expr.init(gpa, "e_binop");
                binop_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));
                binop_node.appendString(gpa, @tagName(e.op));

                var lhs_node = ir.store.getExpr(e.lhs).toSExpr(ir, env);
                var rhs_node = ir.store.getExpr(e.rhs).toSExpr(ir, env);
                binop_node.appendNode(gpa, &lhs_node);
                binop_node.appendNode(gpa, &rhs_node);

                return binop_node;
            },
            .dot_access => |e| {
                var dot_access_node = sexpr.Expr.init(gpa, "e_dot_access");
                dot_access_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));

                var receiver_node = ir.store.getExpr(e.receiver).toSExpr(ir, env);
                dot_access_node.appendNode(gpa, &receiver_node);

                const field_name = env.idents.getText(e.field_name);
                dot_access_node.appendString(gpa, field_name);

                if (e.args) |args| {
                    for (ir.store.exprSlice(args)) |arg_idx| {
                        var arg_node = ir.store.getExpr(arg_idx).toSExpr(ir, env);
                        dot_access_node.appendNode(gpa, &arg_node);
                    }
                }

                return dot_access_node;
            },
            .runtime_error => |e| {
                var runtime_err_node = sexpr.Expr.init(gpa, "e_runtime_error");
                runtime_err_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));

                var buf = std.ArrayList(u8).init(gpa);
                defer buf.deinit();

                const diagnostic = ir.store.getDiagnostic(e.diagnostic);

                buf.writer().writeAll(@tagName(diagnostic)) catch |err| exitOnOom(err);

                runtime_err_node.appendString(gpa, buf.items);

                return runtime_err_node;
            },
        }
    }
};

/// A file of any type that has been ingested into a Roc module
/// as raw data, e.g. `import "lookups.txt" as lookups : Str`.
///
/// These ingestions aren't resolved until the import resolution
/// compiler stage.
pub const IngestedFile = struct {
    relative_path: StringLiteral.Idx,
    ident: Ident.Idx,
    type: Annotation,

    pub const List = collections.SafeList(@This());
    pub const Idx = List.Idx;
    pub const Range = List.Range;
    pub const NonEmptyRange = List.NonEmptyRange;

    pub fn toSExpr(self: *const @This(), ir: *const CIR, line_starts: std.ArrayList(u32)) sexpr.Expr {
        _ = line_starts;
        const gpa = ir.env.gpa;
        var node = sexpr.Expr.init(gpa, "ingested_file");
        node.appendString(gpa, "path"); // TODO: use self.relative_path
        appendIdent(&node, gpa, ir.env, "ident", self.ident);
        var type_node = self.type.toSExpr(ir);
        node.appendNode(gpa, &type_node);
        return node;
    }
};

/// A definition of a value (or destructured values) that
/// takes its value from an expression.
pub const Def = struct {
    pattern: Pattern.Idx,
    pattern_region: Region,
    expr: Expr.Idx,
    expr_region: Region,
    // TODO:
    // pattern_vars: SendMap<Symbol, Variable>,
    annotation: ?Annotation.Idx,
    kind: Kind,

    pub const Kind = union(enum) {
        /// A def that introduces identifiers
        let,
        /// A standalone statement with an fx variable
        stmt: TypeVar,
        /// Ignored result, must be effectful
        ignored: TypeVar,

        /// encode the kind of def into two u32 values
        pub fn encode(self: *const Kind) [2]u32 {
            switch (self.*) {
                .let => return .{ 0, 0 },
                .stmt => |ty_var| return .{ 1, @intFromEnum(ty_var) },
                .ignored => |ty_var| return .{ 2, @intFromEnum(ty_var) },
            }
        }

        /// decode the kind of def from two u32 values
        pub fn decode(data: [2]u32) Kind {
            if (data[0] == 0) {
                return .let;
            } else if (data[0] == 1) {
                return .{ .stmt = @as(TypeVar, @enumFromInt(data[1])) };
            } else if (data[0] == 2) {
                return .{ .ignored = @as(TypeVar, @enumFromInt(data[1])) };
            } else {
                @panic("invalid def kind");
            }
        }

        test "encode and decode def kind" {
            const kind: Kind = Kind.let;
            const encoded = kind.encode();
            const decoded = Kind.decode(encoded);
            try std.testing.expect(decoded == Kind.let);
        }

        test "encode and decode def kind with type var" {
            const kind: Kind = .{ .stmt = @as(TypeVar, @enumFromInt(42)) };
            const encoded = kind.encode();
            const decoded = Kind.decode(encoded);
            switch (decoded) {
                .stmt => |stmt| {
                    try std.testing.expect(stmt == @as(TypeVar, @enumFromInt(42)));
                },
                else => @panic("invalid def kind"),
            }
        }
    };

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
    pub const Range = struct { start: u32, len: u32 };

    pub fn toSExpr(self: *const @This(), ir: *CIR, env: *ModuleEnv) sexpr.Expr {
        const gpa = ir.env.gpa;

        const kind = switch (self.kind) {
            .let => "d_let",
            .stmt => "d_stmt",
            .ignored => "d_ignored",
        };

        var node = sexpr.Expr.init(gpa, kind);

        var pattern_node = sexpr.Expr.init(gpa, "def_pattern");
        var pattern_sexpr = ir.store.getPattern(self.pattern).toSExpr(ir, self.pattern);
        pattern_node.appendNode(gpa, &pattern_sexpr);
        node.appendNode(gpa, &pattern_node);

        var expr_node = sexpr.Expr.init(gpa, "def_expr");
        var expr_sexpr = ir.store.getExpr(self.expr).toSExpr(ir, env);
        expr_node.appendNode(gpa, &expr_sexpr);
        node.appendNode(gpa, &expr_node);

        if (self.annotation) |anno_idx| {
            const anno = ir.store.getAnnotation(anno_idx);
            var anno_node = anno.toSExpr(ir, env.line_starts);
            node.appendNode(gpa, &anno_node);
        }

        return node;
    }
};

/// todo
/// An annotation represents a canonicalized type signature that connects
/// a type declaration to a value definition
pub const Annotation = struct {
    /// The canonicalized declared type structure (what the programmer wrote)
    type_anno: TypeAnno.Idx,
    /// The canonical type signature as a type variable (for type inference)
    signature: TypeVar,
    /// Source region of the annotation
    region: Region,

    pub const Idx = enum(u32) { _ };

    pub fn toSExpr(self: *const @This(), ir: *const CIR, line_starts: std.ArrayList(u32)) sexpr.Expr {
        _ = line_starts;
        const gpa = ir.env.gpa;
        var node = sexpr.Expr.init(gpa, "annotation");
        node.appendRegionInfo(gpa, ir.calcRegionInfo(self.region));

        // Add the signature type variable info
        appendTypeVar(&node, gpa, "signature", self.signature);

        // Add the declared type annotation structure
        var type_anno_node = sexpr.Expr.init(gpa, "declared_type");
        const type_anno = ir.store.getTypeAnno(self.type_anno);
        var anno_sexpr = type_anno.toSExpr(ir, ir.env);
        type_anno_node.appendNode(gpa, &anno_sexpr);
        node.appendNode(gpa, &type_anno_node);

        return node;
    }
};

/// Tracks type variables introduced during annotation canonicalization
pub const IntroducedVariables = struct {
    /// Named type variables (e.g., 'a' in 'a -> a')
    named: std.ArrayListUnmanaged(NamedVariable),
    /// Wildcard type variables (e.g., '*' in some contexts)
    wildcards: std.ArrayListUnmanaged(TypeVar),
    /// Inferred type variables (e.g., '_')
    inferred: std.ArrayListUnmanaged(TypeVar),

    pub fn init() IntroducedVariables {
        return IntroducedVariables{
            .named = .{},
            .wildcards = .{},
            .inferred = .{},
        };
    }

    pub fn deinit(self: *IntroducedVariables, gpa: std.mem.Allocator) void {
        self.named.deinit(gpa);
        self.wildcards.deinit(gpa);
        self.inferred.deinit(gpa);
    }

    /// Insert a named type variable
    pub fn insertNamed(self: *IntroducedVariables, gpa: std.mem.Allocator, name: Ident.Idx, var_type: TypeVar, region: Region) void {
        const named_var = NamedVariable{
            .name = name,
            .variable = var_type,
            .first_seen = region,
        };
        self.named.append(gpa, named_var) catch |err| collections.exitOnOom(err);
    }

    /// Insert a wildcard type variable
    pub fn insertWildcard(self: *IntroducedVariables, gpa: std.mem.Allocator, var_type: TypeVar) void {
        self.wildcards.append(gpa, var_type) catch |err| collections.exitOnOom(err);
    }

    /// Insert an inferred type variable
    pub fn insertInferred(self: *IntroducedVariables, gpa: std.mem.Allocator, var_type: TypeVar) void {
        self.inferred.append(gpa, var_type) catch |err| collections.exitOnOom(err);
    }

    /// Find a type variable by name
    pub fn varByName(self: *const IntroducedVariables, name: Ident.Idx) ?TypeVar {
        // Check named variables
        for (self.named.items) |named_var| {
            if (named_var.name == name) {
                return named_var.variable;
            }
        }

        return null;
    }

    /// Union with another IntroducedVariables
    pub fn unionWith(self: *IntroducedVariables, other: *const IntroducedVariables) void {
        // This is a simplified union - in practice we'd want to avoid duplicates
        // For now, just append all items
        const gpa = std.heap.page_allocator; // TODO: pass proper allocator

        self.named.appendSlice(gpa, other.named.items) catch |err| collections.exitOnOom(err);
        self.wildcards.appendSlice(gpa, other.wildcards.items) catch |err| collections.exitOnOom(err);
        self.inferred.appendSlice(gpa, other.inferred.items) catch |err| collections.exitOnOom(err);
    }
};

/// A named type variable in an annotation
pub const NamedVariable = struct {
    variable: TypeVar,
    name: Ident.Idx,
    first_seen: Region,
};

/// Tracks references to symbols and modules made by an annotation
pub const References = struct {
    /// References to value symbols
    value_lookups: std.ArrayListUnmanaged(Ident.Idx),
    /// References to type symbols
    type_lookups: std.ArrayListUnmanaged(Ident.Idx),
    /// References to modules
    module_lookups: std.ArrayListUnmanaged(Ident.Idx),

    pub fn init() References {
        return .{
            .value_lookups = .{},
            .type_lookups = .{},
            .module_lookups = .{},
        };
    }

    pub fn deinit(self: *References, gpa: std.mem.Allocator) void {
        self.value_lookups.deinit(gpa);
        self.type_lookups.deinit(gpa);
        self.module_lookups.deinit(gpa);
    }

    /// Insert a value symbol reference
    pub fn insertValueLookup(self: *References, gpa: std.mem.Allocator, symbol: Ident.Idx) void {
        self.value_lookups.append(gpa, symbol) catch |err| exitOnOom(err);
    }
};

/// todo
pub const IntValue = struct {
    bytes: [16]u8,
    kind: Kind,

    /// todo
    pub const Kind = enum { i128, u128 };

    pub fn placeholder() IntValue {
        return IntValue{
            .bytes = [16]u8{ 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            .kind = .i128,
        };
    }
};

/// todo - evaluate if we need this?
pub const IfBranch = struct {
    cond: Expr.Idx,
    body: Expr.Idx,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    // Note: toSExpr is handled within Expr.if because the slice reference is there
};

/// TODO
pub const When = struct {
    /// The actual condition of the when expression.
    loc_cond: Expr.Idx,
    cond_var: TypeVar,
    /// Type of each branch (and therefore the type of the entire `when` expression)
    expr_var: TypeVar,
    region: Region,
    /// The branches of the when, and the type of the condition that they expect to be matched
    /// against.
    branches: WhenBranch.Span,
    branches_cond_var: TypeVar,
    /// Whether the branches are exhaustive.
    exhaustive: ExhaustiveMark,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toSExpr(self: *const @This(), ir: *const CIR, line_starts: std.ArrayList(u32)) sexpr.Expr {
        const gpa = ir.env.gpa;
        var node = sexpr.Expr.init(gpa, "when");

        node.appendRegionInfo(gpa, self.region);

        var cond_node = sexpr.Expr.init(gpa, "cond");
        const cond_expr = ir.store.getExpr(self.loc_cond);
        var cond_sexpr = cond_expr.toSExpr(ir, line_starts);
        cond_node.appendNode(gpa, &cond_sexpr);

        node.appendNode(gpa, &cond_node);

        appendTypeVar(&node, gpa, "cond_var", self.cond_var);
        appendTypeVar(&node, gpa, "expr_var", self.expr_var);
        appendTypeVar(&node, gpa, "branches_cond_var", self.branches_cond_var);
        appendTypeVar(&node, gpa, "exhaustive_mark", self.exhaustive);

        var branches_node = sexpr.Expr.init(gpa, "branches");
        for (ir.store.whenBranchSlice(self.branches)) |branch_idx| {
            const branch = ir.store.getWhenBranch(branch_idx);

            var branch_sexpr = branch.toSExpr(ir);
            branches_node.appendNode(gpa, &branch_sexpr);
        }
        node.appendNode(gpa, &branches_node);

        return node;
    }
};

/// todo - evaluate if we need this?
pub const WhenBranchPattern = struct {
    pattern: Pattern.Idx,
    /// Degenerate branch patterns are those that don't fully bind symbols that the branch body
    /// needs. For example, in `A x | B y -> x`, the `B y` pattern is degenerate.
    /// Degenerate patterns emit a runtime error if reached in a program.
    degenerate: bool,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toSExpr(self: *const @This(), ir: *const CIR, line_starts: std.ArrayList(u32)) sexpr.Expr {
        _ = line_starts;
        const gpa = ir.gpa;
        var node = sexpr.Expr.init(gpa, "when_branch_pattern");
        var pattern_sexpr = self.pattern.toSExpr(ir);
        node.appendNode(gpa, &pattern_sexpr);
        if (self.degenerate) {
            node.appendString(gpa, "degenerate=true");
        }
        return node;
    }
};

/// todo - evaluate if we need this?
pub const WhenBranch = struct {
    patterns: WhenBranchPattern.Span,
    value: Expr.Idx,
    guard: ?Expr.Idx,
    /// Whether this branch is redundant in the `when` it appears in
    redundant: RedundantMark,

    pub fn toSExpr(self: *const @This(), ir: *const CIR, line_starts: std.ArrayList(u32)) sexpr.Expr {
        const gpa = ir.env.gpa;
        var node = sexpr.Expr.init(gpa, "when_branch");

        var patterns_node = sexpr.Expr.init(gpa, "patterns");
        // Need WhenBranchPattern.List storage in IR to resolve slice
        // Assuming `ir.when_branch_patterns` exists:
        // for (ir.when_branch_patterns.getSlice(self.patterns)) |patt| {
        //     var patt_sexpr = patt.toSExpr(env, ir);
        //     patterns_node.appendNode(gpa, &patt_sexpr);
        // }
        patterns_node.appendString(gpa, "TODO: Store and represent WhenBranchPattern slice");
        node.appendNode(gpa, &patterns_node);

        var value_node = sexpr.Expr.init(gpa, "value");
        const value_expr = ir.exprs_at_regions.get(self.value);
        var value_sexpr = value_expr.toSExpr(ir, line_starts);
        value_node.appendNode(gpa, &value_sexpr);
        node.appendNode(gpa, &value_node);

        if (self.guard) |guard_idx| {
            var guard_node = sexpr.Expr.init(gpa, "guard");
            const guard_expr = ir.exprs_at_regions.get(guard_idx);
            var guard_sexpr = guard_expr.toSExpr(ir, line_starts);
            guard_node.appendNode(gpa, &guard_sexpr);
            node.appendNode(gpa, &guard_node);
        }

        return node;
    }

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: DataSpan };
};

/// A pattern, including possible problems (e.g. shadowing) so that
/// codegen can generate a runtime error if this pattern is reached.
pub const Pattern = union(enum) {
    /// An identifier in the assignment position, e.g. the `x` in `x = foo(1)`
    assign: struct {
        ident: Ident.Idx,
        region: Region,
    },
    as: struct {
        pattern: Pattern.Idx,
        ident: Ident.Idx,
        region: Region,
    },
    applied_tag: struct {
        ext_var: TypeVar,
        tag_name: Ident.Idx,
        arguments: Pattern.Span,
        region: Region,
    },
    record_destructure: struct {
        whole_var: TypeVar,
        ext_var: TypeVar,
        destructs: RecordDestruct.Span,
        region: Region,
    },
    list: struct {
        list_var: TypeVar,
        elem_var: TypeVar,
        patterns: Pattern.Span,
        region: Region,
    },
    tuple: struct {
        tuple_var: TypeVar,
        patterns: Pattern.Span,
        region: Region,
    },
    num_literal: struct {
        num_var: TypeVar,
        literal: StringLiteral.Idx,
        value: IntValue,
        bound: types.Num.Int.Precision,
        region: Region,
    },
    int_literal: struct {
        num_var: TypeVar,
        precision_var: TypeVar,
        literal: StringLiteral.Idx,
        value: IntValue,
        bound: types.Num.Int.Precision,
        region: Region,
    },
    float_literal: struct {
        num_var: TypeVar,
        precision_var: TypeVar,
        literal: StringLiteral.Idx,
        value: f64,
        bound: types.Num.Frac.Precision,
        region: Region,
    },
    str_literal: struct {
        literal: StringLiteral.Idx,
        region: Region,
    },
    char_literal: struct {
        num_var: TypeVar,
        precision_var: TypeVar,
        value: u32,
        bound: types.Num.Int.Precision,
        region: Region,
    },
    underscore: struct {
        region: Region,
    },
    /// Compiles, but will crash if reached
    runtime_error: struct {
        diagnostic: Diagnostic.Idx,
        region: Region,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toRegion(self: *const @This()) Region {
        switch (self.*) {
            .assign => |p| return p.region,
            .as => |p| return p.region,
            .applied_tag => |p| return p.region,
            .record_destructure => |p| return p.region,
            .list => |p| return p.region,
            .tuple => |p| return p.region,
            .num_literal => |p| return p.region,
            .int_literal => |p| return p.region,
            .float_literal => |p| return p.region,
            .str_literal => |p| return p.region,
            .char_literal => |p| return p.region,
            .underscore => |p| return p.region,
            .runtime_error => |p| return p.region,
        }
    }

    pub fn toSExpr(self: *const @This(), ir: *CIR, pattern_idx: Pattern.Idx) sexpr.Expr {
        const gpa = ir.env.gpa;
        switch (self.*) {
            .assign => |p| {
                var node = sexpr.Expr.init(gpa, "p_assign");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                appendIdent(&node, gpa, ir, "ident", p.ident);
                return node;
            },
            .as => |a| {
                var node = sexpr.Expr.init(gpa, "p_as");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(a.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                appendIdent(&node, gpa, ir, "ident", a.ident);

                var pattern_node = ir.store.getPattern(a.pattern).toSExpr(ir, a.pattern);
                node.appendNode(gpa, &pattern_node);

                return node;
            },
            .applied_tag => |p| {
                var node = sexpr.Expr.init(gpa, "p_applied_tag");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                node.appendString(gpa, "TODO");
                return node;
            },
            .record_destructure => |p| {
                var node = sexpr.Expr.init(gpa, "p_record_destructure");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                var destructs_node = sexpr.Expr.init(gpa, "destructs");
                destructs_node.appendString(gpa, "TODO");
                node.appendNode(gpa, &destructs_node);

                return node;
            },
            .list => |p| {
                var pattern_list_node = sexpr.Expr.init(gpa, "p_list");
                pattern_list_node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                pattern_list_node.appendNode(gpa, &pattern_idx_node);

                var patterns_node = sexpr.Expr.init(gpa, "patterns");

                for (ir.store.slicePatterns(p.patterns)) |patt_idx| {
                    var patt_sexpr = ir.store.getPattern(patt_idx).toSExpr(ir, patt_idx);
                    patterns_node.appendNode(gpa, &patt_sexpr);
                }

                pattern_list_node.appendNode(gpa, &patterns_node);

                return pattern_list_node;
            },
            .tuple => |p| {
                var node = sexpr.Expr.init(gpa, "p_tuple");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                // Add tuple_var
                var tuple_var_node = sexpr.Expr.init(gpa, "tuple_var");
                const tuple_var_str = p.tuple_var.allocPrint(gpa);
                defer gpa.free(tuple_var_str);
                tuple_var_node.appendString(gpa, tuple_var_str);
                node.appendNode(gpa, &tuple_var_node);

                var patterns_node = sexpr.Expr.init(gpa, "patterns");

                for (ir.store.slicePatterns(p.patterns)) |patt_idx| {
                    var patt_sexpr = ir.store.getPattern(patt_idx).toSExpr(ir, patt_idx);
                    patterns_node.appendNode(gpa, &patt_sexpr);
                }

                node.appendNode(gpa, &patterns_node);

                return node;
            },
            .num_literal => |p| {
                var node = sexpr.Expr.init(gpa, "p_num");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                node.appendString(gpa, "literal"); // TODO: use l.literal
                node.appendString(gpa, "value=<int_value>");
                node.appendString(gpa, @tagName(p.bound));
                return node;
            },
            .int_literal => |p| {
                var node = sexpr.Expr.init(gpa, "p_int");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                node.appendString(gpa, "literal"); // TODO: use l.literal
                node.appendString(gpa, "value=<int_value>");
                node.appendString(gpa, @tagName(p.bound));
                return node;
            },
            .float_literal => |p| {
                var node = sexpr.Expr.init(gpa, "p_float");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                node.appendString(gpa, "literal"); // TODO: use l.literal
                const val_str = std.fmt.allocPrint(gpa, "{d}", .{p.value}) catch "<oom>";
                defer gpa.free(val_str);

                node.appendString(gpa, val_str);
                node.appendString(gpa, @tagName(p.bound));

                return node;
            },
            .str_literal => |p| {
                var node = sexpr.Expr.init(gpa, "p_str");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                const text = ir.env.strings.get(p.literal);
                node.appendString(gpa, text);

                return node;
            },
            .char_literal => |l| {
                var node = sexpr.Expr.init(gpa, "p_char");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(l.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                node.appendString(gpa, "value");
                const char_str = std.fmt.allocPrint(gpa, "'\\u({d})'", .{l.value}) catch "<oom>";
                defer gpa.free(char_str);
                node.appendString(gpa, char_str);
                node.appendString(gpa, @tagName(l.bound));
                return node;
            },
            .underscore => |p| {
                var node = sexpr.Expr.init(gpa, "p_underscore");
                node.appendRegionInfo(gpa, ir.calcRegionInfo(p.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                node.appendNode(gpa, &pattern_idx_node);

                return node;
            },
            .runtime_error => |e| {
                var runtime_err_node = sexpr.Expr.init(gpa, "p_runtime_error");
                runtime_err_node.appendRegionInfo(gpa, ir.calcRegionInfo(e.region));

                var pattern_idx_node = formatPatternIdxNode(gpa, pattern_idx);
                runtime_err_node.appendNode(gpa, &pattern_idx_node);

                var buf = std.ArrayList(u8).init(gpa);
                defer buf.deinit();

                const diagnostic = ir.store.getDiagnostic(e.diagnostic);

                buf.writer().writeAll(@tagName(diagnostic)) catch |err| exitOnOom(err);

                runtime_err_node.appendString(gpa, buf.items);
                return runtime_err_node;
            },
        }
    }
};

/// todo
pub const RecordDestruct = struct {
    type_var: TypeVar,
    region: Region,
    label: Ident.Idx,
    ident: Ident.Idx,
    kind: Kind,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    /// todo
    pub const Kind = union(enum) {
        Required,
        Guard: Pattern.Idx,

        pub fn toSExpr(self: *const @This(), ir: *const CIR, line_starts: std.ArrayList(u32)) sexpr.Expr {
            const gpa = ir.env.gpa;

            switch (self.*) {
                .Required => return sexpr.Expr.init(gpa, "required"),
                .Guard => |guard_idx| {
                    var guard_kind_node = sexpr.Expr.init(gpa, "guard");

                    const guard_patt = ir.typed_patterns_at_regions.get(guard_idx);
                    var guard_sexpr = guard_patt.toSExpr(ir.env, ir, line_starts);
                    guard_kind_node.appendNode(gpa, &guard_sexpr);

                    return guard_kind_node;
                },
            }
        }
    };

    pub fn toSExpr(self: *const @This(), ir: *const CIR) sexpr.Expr {
        const gpa = ir.env.gpa;

        var record_destruct_node = sexpr.Expr.init(gpa, "record_destruct");

        record_destruct_node.appendTypeVar(&record_destruct_node, gpa, "type_var", self.type_var);
        record_destruct_node.appendRegionInfo(gpa, ir.calcRegionInfo(self.region));

        appendIdent(&record_destruct_node, gpa, ir, "label", self.label);
        appendIdent(&record_destruct_node, gpa, ir, "ident", self.ident);

        var kind_node = self.kind.toSExpr(ir);
        record_destruct_node.appendNode(gpa, &kind_node);

        return record_destruct_node;
    }
};

/// Marks whether a when branch is redundant using a variable.
pub const RedundantMark = TypeVar;

/// Marks whether a when expression is exhaustive using a variable.
pub const ExhaustiveMark = TypeVar;

/// Helper function to convert the entire Canonical IR to a string in S-expression format
/// and write it to the given writer.
///
/// If a single expression is provided we only print that expression
pub fn toSExprStr(ir: *CIR, env: *ModuleEnv, writer: std.io.AnyWriter, maybe_expr_idx: ?Expr.Idx, source: []const u8) !void {
    // Set temporary source for region info calculation during SExpr generation
    ir.temp_source_for_sexpr = source;
    defer ir.temp_source_for_sexpr = null;
    const gpa = ir.env.gpa;

    if (maybe_expr_idx) |expr_idx| {
        // Get the expression from the store
        const expr = ir.store.getExpr(expr_idx);

        var expr_node = expr.toSExpr(ir, env);
        defer expr_node.deinit(gpa);

        expr_node.toStringPretty(writer);
    } else {
        var root_node = sexpr.Expr.init(gpa, "can_ir");
        defer root_node.deinit(gpa);

        // Iterate over all the definitions in the file and convert each to an S-expression
        const defs_slice = ir.store.sliceDefs(ir.all_defs);
        const statements_slice = ir.store.sliceStatements(ir.all_statements);

        if (defs_slice.len == 0 and statements_slice.len == 0) {
            root_node.appendString(gpa, "empty");
        }

        for (defs_slice) |def_idx| {
            const d = ir.store.getDef(def_idx);
            var def_node = d.toSExpr(ir, env);
            root_node.appendNode(gpa, &def_node);
        }

        for (statements_slice) |stmt_idx| {
            const s = ir.store.getStatement(stmt_idx);
            var stmt_node = s.toSExpr(ir, env);
            root_node.appendNode(gpa, &stmt_node);
        }

        root_node.toStringPretty(writer);
    }
}

test "NodeStore - init and deinit" {
    var store = CIR.NodeStore.init(testing.allocator);
    defer store.deinit();

    try testing.expect(store.nodes.len() == 0);
    try testing.expect(store.extra_data.items.len == 0);
}

/// Returns diagnostic position information for the given region.
/// This is a standalone utility function that takes the source text as a parameter
/// to avoid storing it in the cacheable IR structure.
pub fn calcRegionInfo(self: *const CIR, region: Region) base.RegionInfo {
    const empty = base.RegionInfo{
        .start_line_idx = 0,
        .start_col_idx = 0,
        .end_line_idx = 0,
        .end_col_idx = 0,
        .line_text = "",
    };

    // In the Can IR, regions store byte offsets directly, not token indices.
    // We can use these offsets directly to calculate the diagnostic position.
    const source = self.temp_source_for_sexpr orelse {
        // No source available, return empty region info
        return empty;
    };

    const info = base.RegionInfo.position(source, self.env.line_starts.items, region.start.offset, region.end.offset) catch {
        // Return a zero position if we can't calculate it
        return empty;
    };

    return info;
}

/// Helper function to convert type information from the Canonical IR to a string
/// in S-expression format for snapshot testing. Implements the definition-focused
/// format showing final types for defs, expressions, and builtins.
pub fn toSexprTypesStr(ir: *CIR, writer: std.io.AnyWriter, maybe_expr_idx: ?Expr.Idx, source: []const u8) !void {
    // Set temporary source for region info calculation during SExpr generation
    ir.temp_source_for_sexpr = source;
    defer ir.temp_source_for_sexpr = null;

    const gpa = ir.env.gpa;

    // Create TypeWriter for converting types to strings
    var type_string_buf = std.ArrayList(u8).init(gpa);
    defer type_string_buf.deinit();

    var type_writer = types.writers.TypeWriter.init(type_string_buf.writer(), ir.env);

    if (maybe_expr_idx) |expr_idx| {
        const expr_var = @as(types.Var, @enumFromInt(@intFromEnum(expr_idx)));

        var expr_node = sexpr.Expr.init(gpa, "expr");
        defer expr_node.deinit(gpa);

        expr_node.appendUnsignedInt(gpa, @intFromEnum(expr_idx));

        if (@intFromEnum(expr_var) > ir.env.types.slots.backing.items.len) {
            const unknown_node = sexpr.Expr.init(gpa, "unknown");
            expr_node.appendNode(gpa, &unknown_node);
        } else {
            if (type_writer.writeVar(expr_var)) {
                var type_node = sexpr.Expr.init(gpa, "type");
                type_node.appendString(gpa, type_string_buf.items);
                expr_node.appendNode(gpa, &type_node);
            } else |err| {
                var err_node = sexpr.Expr.init(gpa, "err");

                // If type writing fails, show the error
                const error_str = std.fmt.allocPrint(gpa, "Error: {}", .{err}) catch "UnknownError";
                defer if (!std.mem.eql(u8, error_str, "UnknownError")) gpa.free(error_str);
                err_node.appendString(gpa, error_str);

                expr_node.appendNode(gpa, &err_node);
            }
        }

        expr_node.toStringPretty(writer);
    } else {
        var root_node = sexpr.Expr.init(gpa, "inferred_types");
        defer root_node.deinit(gpa);

        // Collect definitions
        var defs_node = sexpr.Expr.init(gpa, "defs");
        const defs_slice = ir.store.sliceDefs(ir.all_defs);

        for (defs_slice) |def_idx| {
            const def = ir.store.getDef(def_idx);

            // Extract identifier name from the pattern (assuming it's an assign pattern)
            const pattern = ir.store.getPattern(def.pattern);
            switch (pattern) {
                .assign => |assign_pat| {
                    const ident_name = ir.env.idents.getText(assign_pat.ident);

                    // Get the type of the expression
                    const def_var = @as(types.Var, @enumFromInt(@intFromEnum(def_idx)));

                    var def_node = sexpr.Expr.init(gpa, "def");
                    def_node.appendString(gpa, ident_name);
                    def_node.appendUnsignedInt(gpa, @intFromEnum(def_var));

                    if (@intFromEnum(def_var) > ir.env.types.slots.backing.items.len) {
                        const unknown_node = sexpr.Expr.init(gpa, "unknown");
                        def_node.appendNode(gpa, &unknown_node);
                    } else {

                        // Clear the buffer and write the type
                        type_string_buf.clearRetainingCapacity();
                        if (type_writer.writeVar(def_var)) {
                            var type_node = sexpr.Expr.init(gpa, "type");
                            type_node.appendString(gpa, type_string_buf.items);
                            def_node.appendNode(gpa, &type_node);
                        } else |err| {
                            var err_node = sexpr.Expr.init(gpa, "err");

                            // If type writing fails, show the error
                            const error_str = std.fmt.allocPrint(gpa, "Error: {}", .{err}) catch "UnknownError";
                            defer if (!std.mem.eql(u8, error_str, "UnknownError")) gpa.free(error_str);
                            err_node.appendString(gpa, error_str);

                            def_node.appendNode(gpa, &err_node);
                        }
                    }
                    defs_node.appendNode(gpa, &def_node);
                },
                else => {
                    // For non-assign patterns, we could handle destructuring, but for now skip
                    continue;
                },
            }
        }

        root_node.appendNode(gpa, &defs_node);

        // Collect expression types (for significant expressions with regions)
        var expressions_node = sexpr.Expr.init(gpa, "expressions");

        // Walk through all expressions and collect those with meaningful types
        // We'll collect expressions that have regions and aren't just intermediate nodes
        for (defs_slice) |def_idx| {
            const def = ir.store.getDef(def_idx);

            // Get the expression type
            const expr_var = @as(types.Var, @enumFromInt(@intFromEnum(def.expr)));

            var expr_node = sexpr.Expr.init(gpa, "expr");
            expr_node.appendRegionInfo(gpa, ir.calcRegionInfo(def.expr_region));
            expr_node.appendUnsignedInt(gpa, @intFromEnum(expr_var));

            if (@intFromEnum(expr_var) > ir.env.types.slots.backing.items.len) {
                const unknown_node = sexpr.Expr.init(gpa, "unknown");
                expr_node.appendNode(gpa, &unknown_node);
            } else {
                // Clear the buffer and write the type
                type_string_buf.clearRetainingCapacity();
                if (type_writer.writeVar(expr_var)) {
                    var type_node = sexpr.Expr.init(gpa, "type");
                    type_node.appendString(gpa, type_string_buf.items);
                    expr_node.appendNode(gpa, &type_node);
                } else |err| {
                    var err_node = sexpr.Expr.init(gpa, "err");

                    // If type writing fails, show the error
                    const error_str = std.fmt.allocPrint(gpa, "Error: {}", .{err}) catch "UnknownError";
                    defer if (!std.mem.eql(u8, error_str, "UnknownError")) gpa.free(error_str);
                    err_node.appendString(gpa, error_str);

                    expr_node.appendNode(gpa, &err_node);
                }
            }

            expressions_node.appendNode(gpa, &expr_node);
        }

        root_node.appendNode(gpa, &expressions_node);

        root_node.toStringPretty(writer);
    }
}
