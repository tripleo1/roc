const std = @import("std");
const base = @import("../../base.zig");
const types = @import("../../types.zig");
const problem = @import("../../problem.zig");
const collections = @import("../../collections.zig");

const Ident = base.Ident;
const ModuleIdent = base.ModuleIdent;
const TagName = collections.TagName;
const FieldName = collections.FieldName;
const StringLiteral = collections.StringLiteral;

pub const IR = @This();

env: *base.ModuleEnv,
procedures: std.AutoHashMap(Ident.Idx, Procedure),
constants: std.AutoHashMap(Ident.Idx, StmtWithLayout),
exprs: Expr.List,
layouts: Layout.List,
stmts: Stmt.List,
idents_with_layouts: IdentWithLayout.List,
list_literal_elems: ListLiteralElem.List,

pub fn init(env: *base.ModuleEnv, allocator: std.mem.Allocator) IR {
    return IR{
        .env = env,
        .procedures = std.AutoHashMap(Ident.Idx, Procedure).init(allocator),
        .constants = std.AutoHashMap(Ident.Idx, StmtWithLayout).init(allocator),
        .exprs = Expr.List.init(allocator),
        .layouts = Layout.List.init(allocator),
        .stmts = Stmt.List.init(allocator),
        .idents_with_layouts = IdentWithLayout.List.init(allocator),
        .list_literal_elems = ListLiteralElem.List.init(allocator),
    };
}

pub fn deinit(self: *IR) void {
    self.procedures.deinit();
    self.constants.deinit();
    self.exprs.deinit();
    self.layouts.deinit();
    self.stmts.deinit();
    self.idents_with_layouts.deinit();
    self.list_literal_elems.deinit();
}

pub const Procedure = struct {
    arguments: IdentWithLayout.Slice,
    body: Stmt.Idx,
    return_layout: Layout.Idx,
};

// TODO: is this necessary?
pub const TagIdIntType = u16;

pub const Layout = union(enum) {
    Primitive: types.Primitive,
    Box: Layout.Idx,
    List: Layout.Idx,
    Struct: Layout.NonEmptySlice,
    TagUnion: Layout.NonEmptySlice,
    // probably necessary for returning empty structs, but would be good to remove this if that's not the case
    Unit,

    pub const List = collections.SafeList(@This());
    pub const Idx = List.Idx;
    pub const Slice = List.Slice;
    pub const NonEmptySlice = List.NonEmptySlice;
};

pub const IdentWithLayout = struct {
    ident: Ident.Idx,
    layout: Layout.Idx,

    pub const List = collections.SafeList(@This());
    pub const Idx = List.Idx;
    pub const Slice = List.Slice;
};

pub const StmtWithLayout = struct {
    stmt: Stmt.Idx,
    layout: Layout.Idx,
};

// TODO: should these use `NonEmptySlice`s?
//
// Copied (and adapted) from:
// https://github.com/roc-lang/roc/blob/689c58f35e0a39ca59feba549f7fcf375562a7a6/crates/compiler/mono/src/layout.rs#L733
pub const UnionLayout = union(enum) {
    // TODO: 3 types:
    // - Unwrapped (1 variant converted to the inner type)
    // - Flat (compile normally)
    // - Recursive ("box" the recursion point)
};

pub const Expr = union(enum) {
    Literal: base.Literal,

    // Functions
    Call: Call,

    Tag: struct {
        // TODO: should this be an index instead?
        tag_layout: UnionLayout,
        tag_id: TagIdIntType,
        arguments: collections.SafeList(Ident.Idx).Slice,
    },
    Struct: collections.SafeList(Ident.Idx).NonEmptySlice,
    NullPointer,
    StructAtIndex: struct {
        index: u64,
        field_layouts: Layout.Slice,
        structure: Ident.Idx,
    },

    GetTagId: struct {
        structure: ModuleIdent,
        union_layout: UnionLayout,
    },

    UnionAtIndex: struct {
        structure: ModuleIdent,
        tag_id: TagIdIntType,
        union_layout: UnionLayout,
        index: u64,
    },

    GetElementPointer: struct {
        structure: ModuleIdent,
        union_layout: UnionLayout,
        indices: []u64,
    },

    Array: struct {
        elem_layout: Layout.Idx,
        elems: ListLiteralElem.Slice,
    },

    EmptyArray,

    /// Returns a pointer to the given function.
    FunctionPointer: struct {
        module_ident: ModuleIdent,
    },

    Alloca: struct {
        element_layout: Layout.Idx,
        initializer: ?ModuleIdent,
    },

    Reset: struct {
        module_ident: ModuleIdent,
    },

    // Just like Reset, but does not recursively decrement the children.
    // Used in reuse analysis to replace a decref with a resetRef to avoid decrementing when the dec ref didn't.
    ResetRef: struct {
        module_ident: ModuleIdent,
    },

    pub const List = collections.SafeList(@This());
    pub const Id = List.Id;
    pub const Slice = List.Slice;
    pub const NonEmptySlice = List.NonEmptySlice;
};

pub const ListLiteralElem = union(enum) {
    StringLiteralId: []const u8,
    Number: base.NumberLiteral,
    Ident: ModuleIdent,

    pub const List = collections.SafeList(@This());
    pub const Slice = List.Slice;
};

pub const Call = struct {
    kind: Kind,
    arguments: IdentWithLayout.Slice,

    pub const Kind = union(enum) {
        ByName: struct {
            ident: ModuleIdent,
            ret_layout: Layout.Idx,
            arg_layouts: Layout.Slice,
        },
        ByPointer: struct {
            pointer: ModuleIdent,
            ret_layout: Layout.Idx,
            arg_layouts: []Layout.Idx,
        },
        // Foreign: struct {
        //     foreign_symbol: usize, //ForeignSymbolId,
        //     ret_layout: LayoutId,
        // },
        // LowLevel: struct {
        //     op: usize, //LowLevel,
        // },
        // TODO: presumably these should be removed in an earlier stage
        // HigherOrder(&'a HigherOrderLowLevel<'a>),
    };
};

pub const Stmt = union(enum) {
    Let: struct {
        ident: Ident.Idx,
        expr: Expr.Idx,
        layout: Expr.Idx,
        continuation: Stmt.Idx,
    },
    Switch: struct {
        /// This *must* stand for an integer, because Switch potentially compiles to a jump table.
        cond_ident: Ident.Idx,
        // TODO: can we make this layout a number type?
        cond_layout: Layout.Idx,
        /// The u64 in the tuple will be compared directly to the condition Expr.
        /// If they are equal, this branch will be taken.
        branches: Branch,
        /// If no other branches pass, this default branch will be taken.
        default_branch: struct {
            info: Branch.Kind,
            stmt: Stmt.Idx,
        },
        /// Each branch must return a value of this type.
        ret_layout: Layout.Idx,
    },
    Ret: Ident.Idx,
    RefCount: struct {
        symbol: base.ModuleIdent,
        change: ModifyRefCount,
    },
    /// a join point `join f <params> = <continuation> in remainder`
    Join: struct {
        id: JoinPoint.Idx,
        parameters: IdentWithLayout.Slice,
        /// body of the join point
        /// what happens after _jumping to_ the join point
        body: Stmt.Idx,
        /// what happens after _defining_ the join point
        remainder: Stmt.Idx,
    },
    Jump: struct {
        join_point: JoinPoint.Idx,
        idents: collections.SafeList(Ident.Idx).Slice,
    },
    Crash: struct {
        message: Ident.Idx,
    },

    pub const List = collections.SafeList(@This());
    pub const Idx = List.Idx;
    pub const Slice = List.Slice;
    pub const NonEmptySlice = List.NonEmptySlice;
};

pub const Branch = struct {
    discriminant: u64,
    kind: Kind,
    stmt: Stmt.Idx,

    /// in the block below, symbol `scrutinee` is assumed be be of shape `tag_id`
    pub const Kind = union(enum) {
        None,
        Constructor: struct {
            scrutinee: ModuleIdent,
            layout: Layout.Idx,
            tag_id: TagIdIntType,
        },
        List: struct {
            scrutinee: ModuleIdent,
            len: u64,
        },
        Unique: struct {
            scrutinee: ModuleIdent,
            unique: bool,
        },
    };
};

pub const ModifyRefCount = union(enum) {
    /// Increment a reference count
    Inc: struct {
        target: base.ModuleIdent,
        count: u64,
    },

    /// Decrement a reference count
    Dec: base.ModuleIdent,

    /// A DecRef is a non-recursive reference count decrement
    /// e.g. If we Dec a list of lists, then if the reference count of the outer list is one,
    /// a Dec will recursively decrement all elements, then free the memory of the outer list.
    /// A DecRef would just free the outer list.
    /// That is dangerous because you may not free the elements, but in our Zig builtins,
    /// sometimes we know we already dealt with the elements (e.g. by copying them all over
    /// to a new list) and so we can just do a DecRef, which is much cheaper in such a case.
    DecRef: base.ModuleIdent,

    /// Unconditionally deallocate the memory. For tag union that do pointer tagging (store the tag
    /// id in the pointer) the backend has to clear the tag id!
    Free: base.ModuleIdent,
};

pub const JoinPoint = struct {
    pub const Idx = base.Ident.Idx;
};
