const std = @import("std");
const loading = @import("loading_packages.zig");
const selecting = @import("selecting_packages.zig");

pub fn main() !void {
    const PACKAGES_LIST_FILENAME = "packages.list";
    const CONFIGURATION_

    const packages = try loading.loadPackages(PACKAGES_LIST_FILENAME);
    defer {
        for (packages) |p| {
            p.deinit(std.heap.page_allocator);
        }
        std.heap.page_allocator.free(packages);
    }

    const selected = try selecting.selectPackages(packages, std.io.getStdOut().writer());

    for (selected) |p| {
        try p.debugPrint(std.io.getStdOut().writer());
    }
}
