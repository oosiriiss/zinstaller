const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const PackageContext =  @import("load_packages.zig").PackageContext;
const util = @import("util.zig");


// Allocates memory and merges packages and dependenices into one big slice.
// Dependencies are put before packages
// Dependency duplicates are ignored.
// Original package slice cannot be null
pub fn preparePackagesSlice(original: []const PackageDescriptor, alloc: std.mem.Allocator) ![] PackageDescriptor {
    if(original.len == 0) return error.NoPackages;
    _ = alloc;

    //for(original) |package| {
    //    map.put(key: K, value: V)
    //}
    //
    return error.NoPackages;
}

pub fn downloadPackages(original_packages: []const PackageDescriptor) !void {
    // For now only yay supported :)
    try assertYayExists();
    try performYaySync();

    // const packages = preparePackagesSlice(original_packages, std.heap.page_allocator)

    for (original_packages) |package| {
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
