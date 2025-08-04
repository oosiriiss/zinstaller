const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const loadConfig = @import("load_config.zig").loadConfig;
const finalizePackages = @import("setup_packages.zig").finalizePackages;
const downloadPackages = @import("setup_packages.zig").downloadPackages;


pub fn main() !void {
    // TODO :: Add some sort of validation if there are two packages with different fields specified in config
    // TODO :: Printing a list of selected packages or just names (after selecting)
    // TODO :: Allow aboslute paths in config
    // TODO :: Detect missing fields when parsing config
    // POSSBILE_TODO :: improve creating package and config objects by introducing some shared methods like for parsing string/ creating the field maps etc.

    const CONFIG_PATH = "./installer.cfg";

    // All allocations done with arena so no real need for memory cleanup
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var config = try loadConfig(CONFIG_PATH, alloc);
    defer config.deinit(alloc);

    const packages = try loadPackages(config.packages_file_path, alloc);
    defer {
        for (packages) |pkg| {
            pkg.deinit(alloc);
        }
        alloc.free(packages);
    }

    const selected_packages = try selectPackages(packages, std.io.getStdOut().writer().any());
    const final_packages = try finalizePackages(selected_packages, alloc);
    defer alloc.free(final_packages);

    try downloadPackages(final_packages);

}

test {
    std.testing.refAllDecls(@This());
}
