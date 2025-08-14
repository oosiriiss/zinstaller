const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const selectPackagesFromCache = @import("select_packages.zig").selectPackagesFromCache;
const loadConfig = @import("load_config.zig").loadConfig;
const printSelected = @import("setup_packages.zig").printSelected;
const finalizePackages = @import("setup_packages.zig").finalizePackages;
const createPackageStatuses = @import("package_status.zig").createPackageStatusSlice;
const saveCacheEntries = @import("package_status.zig").saveCacheEntries;
const loadCacheEntries = @import("package_status.zig").loadCacheEntries;
const loadPackageStatusesFromCache = @import("package_status.zig").loadPackageStatusesFromCache;
const cleanCache = @import("package_status.zig").cleanCache;
const downloadPackages = @import("setup_packages.zig").downloadPackages;
const setupPackages = @import("setup_packages.zig").setupPackages;
// Logger
const initializeLog = @import("logger.zig").initGlobalLogger;
const shutdownLog = @import("logger.zig").shutdownGlobalLogger;
const log = @import("logger.zig").getGlobalLogger;

pub fn main() !void {
    // TODO :: Add some sort of validation if there are two packages with different fields specified in config
    // TODO :: Allow aboslute paths in config - should i really?
    // TODO :: Check if passing a single slice (with spaces) to util.runCommand creates argv correctly
    // TODO :: add lexer.getError() where lexer is used
    // TODO :: Writer to stdout instead of logging?
    // TODO :: Fix the config load_config default parameter copying - the u8 shit
    // TODO :: add cli argumenst handling e.g. config_path
    // TODO :: Refactor selectPackagesFromCache and filterSelectedPackages - these do basically the same but with different filter
    // TODO :: Specyfing bonus env vars in config?
    // TODO :: Generic recursive method for debug print of a struct
    // TODO :: Refactor setup_package to some craeteSetupCommand stuff
    // TODO :: There seems to be some kind of error with cache redownloading packages?
    // TODO :: Add more setup tests
    // TODO :: Refactor loading cache objects to the new initstruct api
    // POSSIBLE_TODO :: setup commands are sometimes called scripts which may be confusing.
    // POSSIBLE_TODO :: Is there really a need to copy the default string values in ast.initObjectFromFields? Possible solution is to introduce getters and make the field nullable and then if it is null just return the default value. but i am not sure if i like this.
    const CONFIG_PATH = "./installer.cfg";

    // The logger is initialized automatically.
    // shutdown should only will happend here.
    defer shutdownLog();

    // All allocations done with arena so no real need for memory cleanup
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var config = try loadConfig(CONFIG_PATH, alloc);
    defer config.deinit(alloc);

    try log().initLogFile(config.log_file);

    const packages = try loadPackages(config.packages_file, alloc);
    defer {
        for (packages) |pkg| {
            pkg.deinit(alloc);
        }
        alloc.free(packages);
    }

    var cache_entries = try loadCacheEntries(config.cache_file, alloc);
    defer {
        if (cache_entries) |*c| {
            var it = c.iterator();
            while (it.next()) |e| {
                alloc.free(e.key_ptr.*);
            }
            c.deinit();
        }
    }

    const selected_packages = if (cache_entries) |*cache|
        selectPackagesFromCache(packages, cache)
    else
        try selectPackages(packages, std.io.getStdOut().writer().any());

    const final_packages = try finalizePackages(selected_packages, alloc);
    defer alloc.free(final_packages);

    try printSelected(final_packages, alloc);

    const package_statuses = try createPackageStatuses(final_packages, alloc);

    if (cache_entries) |*cache| {
        log().info("Updating the packages to match statuses in cache.", .{});
        loadPackageStatusesFromCache(package_statuses, cache);
    }

    const download_ok = downloadPackages(package_statuses, alloc);
    try saveCacheEntries(config.cache_file, package_statuses);
    if (!download_ok) {
        log().err("Couldn't download all packages", .{});
        return;
    }

    const setup_ok = setupPackages(package_statuses, config, alloc);
    try saveCacheEntries(config.cache_file, package_statuses);
    if (!setup_ok) {
        log().err("Couldn't setup all packages", .{});
        return;
    }

    log().info("Everyting went successfully cleaning up", .{});
    try cleanCache(config.cache_file);
}

test {
    std.testing.refAllDecls(@This());
}
