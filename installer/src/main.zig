const std = @import("std");
const selecting = @import("selecting_packages.zig");

pub fn main() !void {
    const PACKAGES_LIST_FILENAME = "packages.list";

    const packages = try selecting.loadPackages(PACKAGES_LIST_FILENAME);
    _ = packages;
}

test "simple test" {}
