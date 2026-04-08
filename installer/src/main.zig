const std = @import("std");
const loadPackages = @import("load_packages.zig").loadPackages;
const selectPackages = @import("select_packages.zig").selectPackages;
const selectPackagesFromCache = @import("select_packages.zig").selectPackagesFromCache;
const loadConfig = @import("load_config.zig").loadConfig;
const printSelected = @import("setup_packages.zig").printSelected;
const finalizePackages = @import("setup_packages.zig").finalizePackages;
const createPackageStatuses = @import("package_status.zig").createPackageStatusSlice;
const saveCache = @import("package_status.zig").saveCache;
const loadCache = @import("package_status.zig").loadCache;
const loadPackageStatusesFromCache = @import("package_status.zig").loadPackageStatusesFromCache;
const cleanCache = @import("package_status.zig").cleanCache;
const downloadPackages = @import("setup_packages.zig").downloadPackages;
const setupPackages = @import("setup_packages.zig").setupPackages;
// Logger
const initializeLog = @import("logger.zig").initializeGlobalLogger;
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
    // TODO :: Add more setup tests
    // TODO :: if initObjectFromFields fails midway it may leak memory and refactor it because its getting a little freaky :)
    // POSSIBLE_TODO :: setup commands are sometimes called scripts which may be confusing.
    // TODO :: I mean i cna switch to c_allocator instead o fstd.heap.page_allocator but i am having severe skill issue linking libc
    // Maybe add some on startup script and on finished script for things like regenerate grub config etc.
    // TODO ::
    // add section in packages list for packages that will be included in download/setup no matter what and for optional (normal) packages
    // POSSIBLE_TODO :: Is there really a need to copy the default string values in ast.initObjectFromFields? Possible solution is to introduce getters and make the field nullable and then if it is null just return the default value. but i am not sure if i like this.
    const CONFIG_PATH = "./installer.cfg";

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    initializeLog();
    // The logger is initialized automatically.
    // shutdown should only happen here.
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

    var cache = try loadCache(config.cache_file, alloc);
    defer if (cache) |*c| c.deinit();

    const selected_packages = if (cache) |c|
        selectPackagesFromCache(packages, &c.package_status_map)
    else
        try selectPackages(packages, alloc, stdout);

    const final_packages = try finalizePackages(selected_packages, alloc);
    defer alloc.free(final_packages);

    try printSelected(final_packages, alloc);

    const package_statuses = try createPackageStatuses(final_packages, alloc);

    if (cache) |c| {
        log().info("Updating the packages to match statuses in cache.", .{});
        loadPackageStatusesFromCache(package_statuses, &c.package_status_map);
    }

    const download_ok = downloadPackages(package_statuses, alloc);
    try saveCache(config.cache_file, package_statuses);
    if (!download_ok) {
        log().err("Couldn't download all packages", .{});
        return;
    }

    const setup_ok = setupPackages(package_statuses, config, alloc);
    if (!setup_ok) {
        //Only if it failse, because there is no point in saving cache if were gonna delete it on the next line
        try saveCache(config.cache_file, package_statuses);

        log().err("Couldn't setup all packages", .{});
        return;
    }

    log().info("Everyting went successfully, cleaning up", .{});
    _ = try cleanCache(config.cache_file);
}

test {
    initializeLog();
    std.testing.refAllDecls(@This());
}
