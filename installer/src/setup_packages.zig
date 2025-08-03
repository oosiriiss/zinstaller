const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const PackageContext = @import("load_packages.zig").PackageContext;
const util = @import("util.zig");


// Allocates memory and merges packages and dependenices into one big slice.
// Dependencies are put before packages
// Dependency duplicates are ignored.
// Original package slice cannot be null
pub fn finalizePackages(original: []const PackageDescriptor, alloc: std.mem.Allocator) ![]PackageDescriptor {
    if (original.len == 0) return error.NoPackages;

    const Map = std.ArrayHashMap(PackageDescriptor, void, PackageContext, true);

    const dfs = comptime struct {
        pub fn run(pkgs: ?[]const PackageDescriptor, map: *Map) !void {
            if (pkgs) |packages| {
                for (packages) |p| {
                    if (p.dependencies) |d| {
                        try run(d, map);
                    }
                    // Value is undefined but we dont care about it anyway
                    _ = try map.getOrPut(p);
                }
            }
        }
    }.run;

    var map = Map.init(alloc);
    defer map.deinit();

    try dfs(original, &map);

    return try alloc.dupe(PackageDescriptor, map.keys());
}

pub fn downloadPackages(packages: []const PackageDescriptor) !void {
    // For now only yay supported :)
    try assertYayExists();
    try performYaySync();

    // const packages = preparePackagesSlice(original_packages, std.heap.page_allocator)

    for (packages) |package| {
        try downloadPackage(package);
    }
}

fn assertYayExists() !void {
    try util.runCommand(&[_][]const u8{ "yay", "--version" });
    std.log.info("Yay Found", .{});
}

fn performYaySync() !void {
    std.log.info("Syncing yay", .{});
    try util.runSilentCommand(&[_][]const u8{ "yay", "-Sy" });
    std.log.info("Yay -Sy", .{});
}

fn downloadPackage(package: PackageDescriptor) !void {
    std.log.info("Downloading package: {s}", .{package.name});

    util.runCommand(&[_][]const u8{ "yay", "-S", package.name }) catch {
        std.log.info("Download Failed", .{});
        return error.DownloadFailed;
    };

    std.log.info("Download success", .{});
}

////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////

test "preparePackagesSlice removes packages with duplicate names on the same level" {
    const packages = [_]PackageDescriptor{
        .{ .name = "Test1", .description = null, .dependencies = null, .setup_command=null},
        .{ .name = "Test1", .description = null, .dependencies = null, .setup_command=null},
    };

    const out = try finalizePackages(&packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(1, out.len);
}

test "preparePackagesSlice removes packages with duplicate on the nested levels" {
    var test1_deps: [1]PackageDescriptor = .{
        .{ .name = "Test1", .description = null, .dependencies = null, .setup_command=null},
    };
    var test2_deps: [1]PackageDescriptor = .{
        .{ .name = "Test2", .description = null, .dependencies = null, .setup_command=null},
    };
    var test22_deps: [1]PackageDescriptor = .{
        .{ .name = "Test2", .description = null, .dependencies = null, .setup_command=null},
    };

    var test5_deps: [1]PackageDescriptor = .{
        .{ .name = "Test5", .description = null, .dependencies = &test22_deps, .setup_command=null},
    };

    const packages: []const PackageDescriptor = &.{
        .{ .name = "Test1", .description = null, .dependencies = &test1_deps, .setup_command=null},
        .{ .name = "Test2", .description = null, .dependencies = null, .setup_command=null},
        .{ .name = "Test3", .description = null, .dependencies = &test2_deps, .setup_command=null},
        .{ .name = "Test4", .description = null, .dependencies = &test5_deps, .setup_command=null},
    };

    const out = try finalizePackages(packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(5, out.len);
}

test "preparePackagesSlice removes packages with nested packages come before " {
    var depth4: [1]PackageDescriptor = .{
        .{ .name = "Depth4", .description = null, .dependencies = null, .setup_command=null},
    };
    var depth3: [1]PackageDescriptor = .{
        .{ .name = "Depth3", .description = null, .dependencies = &depth4, .setup_command=null},
    };
    var depth2: [1]PackageDescriptor = .{
        .{ .name = "Depth2", .description = null, .dependencies = &depth3, .setup_command=null},
    };

    var depth1: [1]PackageDescriptor = .{
        .{ .name = "Depth1", .description = null, .dependencies = &depth2, .setup_command=null},
    };

    const packages: []const PackageDescriptor = &.{
        .{ .name = "Test1", .description = null, .dependencies = null, .setup_command=null},
        .{ .name = "Test2", .description = null, .dependencies = null, .setup_command=null},
        .{ .name = "Test3", .description = null, .dependencies = &depth1, .setup_command=null},
        .{ .name = "Test4", .description = null, .dependencies = null, .setup_command=null},
    };

    const out = try finalizePackages(packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(8, out.len);
    try std.testing.expectEqualSlices(u8, "Test1", out[0].name);
    try std.testing.expectEqualSlices(u8, "Test2", out[1].name);
    try std.testing.expectEqualSlices(u8, "Depth4", out[2].name);
    try std.testing.expectEqualSlices(u8, "Depth3", out[3].name);
    try std.testing.expectEqualSlices(u8, "Depth2", out[4].name);
    try std.testing.expectEqualSlices(u8, "Depth1", out[5].name);
    try std.testing.expectEqualSlices(u8, "Test3", out[6].name);
    try std.testing.expectEqualSlices(u8, "Test4", out[7].name);
}

test "preparePackagesSlice removes packages with duplicate packages are ignored" {
    var depth11: [1]PackageDescriptor = .{.{ .name = "Depth11", .description = null, .dependencies = null, .setup_command=null}};
    var depth2: [1]PackageDescriptor = .{.{ .name = "Depth2", .description = null, .dependencies = null, .setup_command=null}};
    var depth1: [1]PackageDescriptor = .{.{ .name = "Depth1", .description = null, .dependencies = &depth2, .setup_command=null}};
    var depth3_dup: [1]PackageDescriptor = .{.{ .name = "Depth3", .description = null, .dependencies = null, .setup_command=null}};
    var depth2_dup: [1]PackageDescriptor = .{.{ .name = "Depth2", .description = null, .dependencies = &depth3_dup, .setup_command=null}};
    var depth1_dup: [1]PackageDescriptor = .{.{ .name = "Depth1", .description = null, .dependencies = &depth2_dup, .setup_command=null}};

    const packages: []const PackageDescriptor = &.{
        .{ .name = "Test1", .description = null, .dependencies = &depth11, .setup_command=null},
        .{ .name = "Test2", .description = null, .dependencies = &depth1, .setup_command=null},
        .{ .name = "Test3", .description = null, .dependencies = null, .setup_command=null},
        .{ .name = "Test4", .description = null, .dependencies = &depth1_dup, .setup_command=null},
    };

    const out = try finalizePackages(packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(8, out.len);
    try std.testing.expectEqualSlices(u8, "Depth11", out[0].name);
    try std.testing.expectEqualSlices(u8, "Test1", out[1].name);
    try std.testing.expectEqualSlices(u8, "Depth2", out[2].name);
    try std.testing.expectEqualSlices(u8, "Depth1", out[3].name);
    try std.testing.expectEqualSlices(u8, "Test2", out[4].name);
    try std.testing.expectEqualSlices(u8, "Test3", out[5].name);
    try std.testing.expectEqualSlices(u8, "Depth3", out[6].name);
    try std.testing.expectEqualSlices(u8, "Test4", out[7].name);
}
