const std = @import("std");
const loading = @import("loading_packages.zig");

pub fn main() !void {
    const PACKAGES_LIST_FILENAME = "packages.list";

    const packages = try loading.loadPackages(PACKAGES_LIST_FILENAME);
    defer {
        for (packages) |p| {
            p.deinit(std.heap.page_allocator);
        }
        std.heap.page_allocator.free(packages);
    }

    try packages[0].print(std.io.getStdOut().writer());
}
