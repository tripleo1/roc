//! Generate Reports for type checking errors

const std = @import("std");
const base = @import("../../base.zig");
const collections = @import("../../collections.zig");
const types = @import("../../types/types.zig");
const reporting = @import("../../reporting.zig");
const store_mod = @import("../../types/store.zig");
const snapshot = @import("./snapshot.zig");

const Report = reporting.Report;

const TypesStore = store_mod.Store;
const Allocator = std.mem.Allocator;
const Ident = base.Ident;

const MkSafeMultiList = collections.SafeMultiList;

const SnapshotContentIdx = snapshot.SnapshotContentIdx;

const Var = types.Var;
const Content = types.Content;

/// The kind of problem we're dealing with
pub const Problem = union(enum) {
    type_mismatch: VarProblem2,
    infinite_recursion: struct { var_: Var },
    anonymous_recursion: struct { var_: Var },
    invalid_number_type: VarProblem1,
    invalid_record_ext: VarProblem1,
    invalid_tag_union_ext: VarProblem1,
    bug: VarProblem2,

    pub const SafeMultiList = MkSafeMultiList(@This());
    pub const Tag = std.meta.Tag(@This());

    /// Build a report for a problem
    pub fn buildReport(
        problem: Problem,
        gpa: Allocator,
        buf: *std.ArrayList(u8),
        snapshots: *const snapshot.Store,
        idents: *const Ident.Store,
        source: []const u8,
        filename: []const u8,
        module_env: *base.ModuleEnv,
    ) !Report {
        var snapshot_writer = snapshot.SnapshotWriter.init(
            buf.writer(),
            snapshots,
            idents,
        );

        switch (problem) {
            .type_mismatch => |vars| {
                return buildTypeMismatchReport(gpa, buf, &snapshot_writer, vars, source, filename, module_env);
            },
            .infinite_recursion => |_| return buildUnimplementedReport(gpa),
            .anonymous_recursion => |_| return buildUnimplementedReport(gpa),
            .invalid_number_type => |_| return buildUnimplementedReport(gpa),
            .invalid_record_ext => |_| return buildUnimplementedReport(gpa),
            .invalid_tag_union_ext => |_| return buildUnimplementedReport(gpa),
            .bug => |_| return buildUnimplementedReport(gpa),
        }
    }

    /// Build a report for type mismatch diagnostic
    pub fn buildTypeMismatchReport(
        allocator: Allocator,
        buf: *std.ArrayList(u8),
        writer: *snapshot.SnapshotWriter,
        vars: VarProblem2,
        source: []const u8,
        filename: []const u8,
        module_env: *base.ModuleEnv,
    ) !Report {
        var report = Report.init(allocator, "TYPE MISMATCH", .runtime_error);

        try writer.write(vars.expected);
        const owned_expected = try report.addOwnedString(buf.items[0..]);

        const buf_len = buf.items.len;
        try writer.write(vars.actual);
        const owned_actual = try report.addOwnedString(buf.items[buf_len..]);

        try report.document.addReflowingText("This expression is used in an unexpected way:");
        try report.document.addLineBreak();

        // Add source region highlighting
        const region_info = module_env.calcRegionInfo(source, vars.region.start.offset, vars.region.end.offset) catch |err| switch (err) {
            else => base.RegionInfo{
                .start_line_idx = 0,
                .start_col_idx = 0,
                .end_line_idx = 0,
                .end_col_idx = 0,
                .line_text = "",
            },
        };

        try report.document.addSourceRegion(
            source,
            region_info.start_line_idx,
            region_info.start_col_idx,
            region_info.end_line_idx,
            region_info.end_col_idx,
            .error_highlight,
            filename,
        );
        try report.document.addLineBreak();

        try report.document.addText("It is of type:");
        try report.document.addLineBreak();
        try report.document.addText("    ");
        try report.document.addAnnotated(owned_actual, .type_variable);
        try report.document.addLineBreak();
        try report.document.addLineBreak();

        try report.document.addText("But you are trying to use it as:");
        try report.document.addLineBreak();
        try report.document.addText("    ");
        try report.document.addAnnotated(owned_expected, .type_variable);

        return report;
    }

    /// Build a report for "invalid number literal" diagnostic
    pub fn buildUnimplementedReport(allocator: Allocator) !Report {
        const report = Report.init(allocator, "UNIMPLEMENTED", .runtime_error);
        return report;
    }
};

/// A single var problem
pub const VarProblem1 = struct {
    var_: Var,
    snapshot: SnapshotContentIdx,
};

/// A two var problem
pub const VarProblem2 = struct {
    expected_var: Var,
    expected: SnapshotContentIdx,
    actual_var: Var,
    actual: SnapshotContentIdx,
    region: base.Region,
};

/// Self-contained problems store with resolved snapshots of type content
///
/// Whenever a type error occurs, we update the `Var` in the type store to
/// have `.err` content. This is necessary to continue type-checking but
/// looses essential error information. So before doing this, we create a fully
/// resolved snapshot of the type that we can use in reporting
///
/// Entry points are `appendProblem` and `createSnapshot`
pub const Store = struct {
    const Self = @This();

    problems: Problem.SafeMultiList,

    pub fn initCapacity(gpa: Allocator, capacity: usize) Self {
        return .{
            .problems = Problem.SafeMultiList.initCapacity(gpa, capacity),
        };
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        self.problems.deinit(gpa);
    }

    /// Create a deep snapshot from a Var, storing it in this SnapshotStore
    pub fn appendProblem(self: *Self, gpa: Allocator, problem: Problem) Problem.SafeMultiList.Idx {
        return self.problems.append(gpa, problem);
    }
};
