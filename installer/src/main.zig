const std = @import("std");
const config = @import("config.zig");




pub fn main() !void {
    const PACKAGES_LIST_FILENAME = "packages.list";

    try config.loadConfig(PACKAGES_LIST_FILENAME);

    //const packages = try loading.loadPackages(PACKAGES_LIST_FILENAME);
    //defer {
    //    for (packages) |p| {
    //        p.deinit(std.heap.page_allocator);
    //    }
    //    std.heap.page_allocator.free(packages);
    //}

    //const selected = try selecting.selectPackages(packages, std.io.getStdOut().writer());

    //for (selected) |p| {
    //    try p.debugPrint(std.io.getStdOut().writer());
    //}
}
