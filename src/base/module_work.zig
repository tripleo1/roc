//! The work done by a compiler stage for a module in a package, usually an IR.
//!
//! The [ModuleGraph] will determine the correct compilation order of packages
//! at time of import resolution by putting them in a row dependency-first.
//! Once that is done, all compiler stages will use the exact same order for
//! module compilation, meaning we can use the same indices for accessing data
//! in other modules based on the order of work in a [ModuleWork.Store].

const std = @import("std");
const base = @import("../base.zig");
const can = @import("../check/canonicalize.zig");
const collections = @import("../collections.zig");

const Package = base.Package;
const exitOnOom = collections.utils.exitOnOom;

/// An index that works for all ModuleWork.Store collections.
///
/// This allows references to a specific module's work for any value,
/// irrespective of which compiler stage is being referenced.
pub const ModuleWorkIdx = enum(u32) { _ };

pub const ModuleWorkIndexIter = struct {
    current: u32,
    len: u32,

    pub fn next(self: *ModuleWorkIndexIter) ?ModuleWorkIdx {
        if (self.current == self.len) return null;

        const out: ModuleWorkIdx = @enumFromInt(self.current);
        self.current += 1;

        return out;
    }
};

/// The work done by a compiler stage for a module in a package, usually an IR.
pub fn ModuleWork(comptime Work: type) type {
    return struct {
        package_idx: Package.Idx,
        module_idx: Package.Module.Idx,
        work: Work,

        pub const Store = struct {
            items: std.MultiArrayList(ModuleWork(Work)),

            pub fn fromCanIrs(
                gpa: std.mem.Allocator,
                can_irs: []const ModuleWork(can.IR),
            ) Store {
                var items = std.MultiArrayList(ModuleWork(Work)){};
                items.ensureTotalCapacity(gpa, can_irs.len) catch |err| exitOnOom(err);

                for (can_irs) |work| {
                    items.appendAssumeCapacity(.{
                        .package_idx = work.package_idx,
                        .module_idx = work.module_idx,
                        .work = work.work,
                    });
                }

                return Store{ .items = items };
            }

            pub fn initFromCanIrs(
                gpa: std.mem.Allocator,
                can_irs: *const ModuleWork(can.IR).Store,
            ) Store {
                var items = std.MultiArrayList(ModuleWork(Work)){};
                items.ensureTotalCapacity(gpa, can_irs.items.len) catch |err| exitOnOom(err);

                for (0..can_irs.items.len) |index| {
                    const work_idx: ModuleWorkIdx = @enumFromInt(index);

                    items.appendAssumeCapacity(.{
                        .package_idx = can_irs.getPackageIdx(work_idx),
                        .module_idx = can_irs.getModuleIdx(work_idx),
                        .work = Work.init(&can_irs.getWork(work_idx).env),
                    });
                }

                return Store{ .items = items };
            }

            pub fn deinit(self: *Store, gpa: std.mem.Allocator) void {
                for (0..self.items.len) |index| {
                    self.items.items(.work)[index].deinit();
                }

                self.items.deinit(gpa);
            }

            pub fn iterIndices(self: *const Store) ModuleWorkIndexIter {
                return ModuleWorkIndexIter{
                    .current = 0,
                    .len = @truncate(self.items.len),
                };
            }

            pub fn getPackageIdx(self: *const Store, idx: ModuleWorkIdx) Package.Idx {
                return self.items.items(.package_idx)[@as(usize, @intFromEnum(idx))];
            }

            pub fn getModuleIdx(self: *const Store, idx: ModuleWorkIdx) Package.Module.Idx {
                return self.items.items(.module_idx)[@as(usize, @intFromEnum(idx))];
            }

            pub fn getWork(self: *const Store, idx: ModuleWorkIdx) *Work {
                return &self.items.items(.work)[@as(usize, @intFromEnum(idx))];
            }

            pub fn getModule(self: *const Store, idx: ModuleWorkIdx, packages: *const Package.Store) *Package.Module {
                const package_idx = self.getPackageIdx(idx);
                const package = packages.packages.get(package_idx);
                const module_idx = self.getModuleIdx(idx);
                const module = package.modules.get(module_idx);

                return module;
            }
        };
    };
}
