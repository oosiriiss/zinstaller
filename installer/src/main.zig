const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const loadConfig = @import("load_config.zig").loadConfig;
const finalizePackages = @import("setup_packages.zig").finalizePackages;
const downloadPackages = @import("setup_packages.zig").downloadPackages;

pub fn main() !void {
    // TODO :: Add some sort of validation if there are two packages with different fields specified in config
    // TODO :: Review the allocators - change page_allocator?
    // TODO :: Introduce detection of duplicate packages when reading package list;
    // TODO :: Printing a list of selected packages or just names

    const PACKAGES_LIST_PATH = "./packages.list";
    const CONFIG_PATH = "./installer.cfg";

    // All allocations done with arena
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    const config = try loadConfig(CONFIG_PATH, alloc);
    _ = config;
    // defer config.deinit();

    const packages = try loadPackages(PACKAGES_LIST_PATH, alloc);
    //defer {
    //    for (packages) |pkg| {
    //        pkg.deinit(alloc);
    //    }
    //    alloc.free(packages);
    //}

    const selected_packages = try selectPackages(packages, std.io.getStdOut().writer().any());

    const final_packages = try finalizePackages(selected_packages, alloc);
    // defer alloc.free(final_packages);

    try downloadPackages(final_packages);
}

test {
    std.testing.refAllDecls(@This());
}
