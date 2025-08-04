const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const PackageContext = @import("load_packages.zig").PackageContext;
const Config = @import("load_config.zig").Config;
const util = @import("util.zig");

const SetupStatus = enum {
    // Package is yet to be downloaded
    download,
    // package is yet to be setup
    setup,
    // Package setup has finished
    finished,
};

const PackageStatus = struct {
    package: *const PackageDescriptor,
    status: SetupStatus,
};

// Allocates memory and merges packages and dependenices into one big slice.
// Dependencies are put before packages
// Dependency duplicates are ignored.
// Original package slice cannot be null
pub fn finalizePackages(original: []const PackageDescriptor, alloc: std.mem.Allocator) ![]PackageDescriptor {
    if (original.len == 0) {
        std.log.err("No packages selected.", .{});
        return error.NoPackages;
    }

    const Map = std.ArrayHashMap(PackageDescriptor, void, PackageContext, true);

    const dfs = comptime struct {
        pub fn run(pkgs: ?[]const PackageDescriptor, map: *Map) !void {
            if (pkgs) |packages| {
                for (packages) |p| {
                    if (p.dependencies) |d| {
                        try run(d, map);
                    }
                    // Value is undefined but we dont care about it anyway
                    _ = try map.getOrPut(p);
                }
            }
        }
    }.run;

    var map = Map.init(alloc);
    defer map.deinit();

    try dfs(original, &map);

    return try alloc.dupe(PackageDescriptor, map.keys());
}

pub fn downloadPackages(packages: []PackageStatus) !void {
    // For now only yay supported :)
    try assertYayExists();
    try performYaySync();

    for (packages) |*package| {
        if (package.status == .download) {
            downloadPackage(package.package.name) catch continue;
            package.status = .setup;
        } else {
            std.log.err("Package \"{s}\" is not set for download - skipping it (Status:{any})", .{ package.package.name, package.status });
        }
    }
}

pub fn createPackageStatusSlice(packages: []const PackageDescriptor, alloc: std.mem.Allocator) (std.mem.Allocator.Error)![]PackageStatus {
    const statuses = try alloc.alloc(PackageStatus, packages.len);
    for (packages, 0..) |*p, i| {
        statuses[i].package = p;
        statuses[i].status = .download;
    }
    return statuses;
}

// Proceeds to invoke setup command for each script that is at the setup stage.
// if the command fails the package is skipped
// Assumes config fields are validated.
pub fn setupPackages(packages: []PackageStatus, config: Config, alloc: std.mem.Allocator) !void {
    for (packages) |*p| {
        if (p.status == .setup) {
            if (setupPackage(p.package, config.dotfiles_dir_path, alloc)) {
                p.status = SetupStatus.finished;
            }
        } else {
            std.log.err("Package \"{s}\" is not set for setup - skipping it (Status:{any})", .{ p.package.name, p.status });
        }
    }
}

// Assumes the package is at a setup stage and dotfiles_dir_path is a valid directory
// Each package gets these ENV VARS
//  - DOTFILES_DIR_PATH - path to dotfiles directory
fn setupPackage(package: *const PackageDescriptor, dotfiles_dir_path: []const u8, alloc: std.mem.Allocator) bool {
    // setup command is null so basically setup is finished
    if (package.setup_command == null) return true;

    var child = std.process.Child.init(&.{ "bash", "-c", package.setup_command.? }, alloc);

    // Setting up child env
    // As for now it overrides the parent envs - dont know if it will be a problem
    var env = std.process.EnvMap.init(alloc);
    env.put("DOTFILES_DIR_PATH", dotfiles_dir_path) catch return false;

    child.env_map = &env;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = child.spawnAndWait() catch |err| {
        std.log.err("Error when running \"{s}\" setup command for package \"{s}\" (error: {any})", .{ package.setup_command.?, package.name, err });
        return false;
    };

    if (term == .Exited and term.Exited == 0)
        return true;

    std.log.err("The setup command \"{s}\" for package \"{s}\" didn't return successfully. (Termination:{any})", .{ package.setup_command.?, package.name, term });
    return false;
}

fn assertYayExists() !void {
    try util.runCommand(&[_][]const u8{ "yay", "--version" });
    std.log.info("Yay Found", .{});
}

fn performYaySync() !void {
    std.log.info("Syncing yay", .{});
    try util.runSilentCommand(&[_][]const u8{ "yay", "-Sy" });
    std.log.info("Yay -Sy", .{});
}

fn downloadPackage(package_name: []const u8) !void {
    std.log.info("Downloading package: {s}", .{package_name});

    util.runCommand(&[_][]const u8{ "yay", "-S", package_name }) catch {
        std.log.info("Download Failed", .{});
        return error.DownloadFailed;
    };

    std.log.info("Download success", .{});
}

test "finalizePackages removes packages with duplicate names on the same level" {
    const packages = [_]PackageDescriptor{
        .{ .name = "Test1", .description = null, .dependencies = null },
        .{ .name = "Test1", .description = null, .dependencies = null },
    };

    const out = try finalizePackages(&packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(1, out.len);
}

test "finalizePackages removes packages with duplicate  on the nested levels" {
    const packages = [_]PackageDescriptor{
        .{ .name = "Test1", .description = null, .dependencies = [_]PackageDescriptor{
            .{ .name = "Test1", .description = null, .dependencies = null },
        } },
        .{ .name = "Test2", .description = null, .dependencies = null },
    };

    const out = try finalizePackages(&packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(1, out.len);
}
