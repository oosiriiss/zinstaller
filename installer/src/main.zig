const std = @import("std");
const loading = @import("loading_packages.zig");

pub fn main() !void {
    const PACKAGES_LIST_FILENAME = "packages.list";

    const packages = try loading.loadPackages(PACKAGES_LIST_FILENAME);
    defer {
        for (packages) |p| {
            p.deinit();
        }
    }
}

test "simple test" {}
