const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const loadConfig = @import("load_config.zig").loadConfig;
const finalizePackages = @import("setup_packages.zig").finalizePackages;
const createPackageStatuses = @import("setup_packages.zig").createPackageStatusSlice;
const downloadPackages = @import("setup_packages.zig").downloadPackages;
const setupPackages = @import("setup_packages.zig").setupPackages;

pub fn main() !void {
    // TODO :: Add some sort of validation if there are two packages with different fields specified in config
    // TODO :: Printing a list of selected packages or just names (after selecting)
    // TODO :: Allow aboslute paths in config
    // TODO :: Detect missing fields when parsing config
    // TODO :: Check if passing a single slice (with spaces) to util.runCommand creates argv correctly
    // TODO :: allow rereading package statuses from some kind of lockfile
    // TODO :: Allow string literals in dependencies
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

    const package_statuses = try createPackageStatuses(final_packages, alloc);

    try downloadPackages(package_statuses);
    try setupPackages(package_statuses, config, alloc);
}

test {
    std.testing.refAllDecls(@This());
}
