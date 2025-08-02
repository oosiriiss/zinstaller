const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const loadConfig = @import("load_config.zig").loadConfig;
const downloadPackages = @import("setup_packages.zig").downloadPackages;

pub fn main() !void {
    // TODO :: Add some sort of validation if there are two packages with different fields specified in config
    // TODO :: Review the allocators - change page_allocator?
    // TODO :: Introduce detection of duplicate packages when reading package list;

    const PACKAGES_LIST_PATH = "./packages.list";
    const CONFIG_PATH = "./installer.cfg";

    const alloc = std.heap.page_allocator;

    const config = try loadConfig(CONFIG_PATH);
    defer config.deinit();

    const packages = try loadPackages(PACKAGES_LIST_PATH, alloc);
    defer alloc.free(packages);

    const selected_packages = try selectPackages(packages, std.io.getStdOut().writer().any());

    try downloadPackages(selected_packages);
}

test {
    std.testing.refAllDecls(@This());
}
