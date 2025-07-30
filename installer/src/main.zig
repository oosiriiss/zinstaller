const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;

pub fn main() !void {
    const PACKAGES_LIST_FILENAME = "packages.list";

    const packages = try loadPackages(PACKAGES_LIST_FILENAME);

    const selected_packages = try selectPackages(packages, std.io.getStdOut().writer().any());

    _ = selected_packages;
}
