const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const loadConfig = @import("load_config.zig").loadConfig;

pub fn main() !void {
    const PACKAGES_LIST_PATH = "./packages.list";
    const CONFIG_PATH = "./installer.config";

    const alloc = std.heap.page_allocator;

    const config = try loadConfig(CONFIG_PATH);
    defer config.deinit();

    const packages = try loadPackages(PACKAGES_LIST_PATH, alloc);
    defer alloc.free(packages);

    const selected_packages = try selectPackages(packages, std.io.getStdOut().writer().any());

    _ = selected_packages;
}
