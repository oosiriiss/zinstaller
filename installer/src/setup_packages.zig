const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const SetupStatus = @import("package_status.zig").SetupStatus;
const PackageStatus = @import("package_status.zig").PackageStatus;
const PackageContext = @import("load_packages.zig").PackageContext;
const Config = @import("load_config.zig").Config;
const util = @import("util.zig");
const log = @import("logger.zig").getGlobalLogger;

pub fn printSelected(packages: []const PackageDescriptor, alloc: std.mem.Allocator) !void {
    const SETUP_FOUND_STR = "(Setup found)";
    const SETUP_NOT_FOUND_STR = "(No setup)";

    var str = std.ArrayList(u8).init(alloc);
    defer str.deinit();

    for (packages, 1..) |p, num| {
        const after_str = if (p.setup_command == null) SETUP_NOT_FOUND_STR else SETUP_FOUND_STR;
        const line = try std.fmt.allocPrint(alloc, " {d}. {s} {s}\n", .{ num, p.name, after_str });
        try str.appendSlice(line);
        alloc.free(line);
    }
    log().info("These packages will be downloaded: \n{s}", .{str.items});
}

// Allocates memory and merges packages and dependenices into one big slice.
// Dependencies are put before packages
// Dependency duplicates are ignored.
// Original package slice cannot be null
pub fn finalizePackages(original: []const PackageDescriptor, alloc: std.mem.Allocator) ![]PackageDescriptor {
    if (original.len == 0) {
        log().err("No packages selected.", .{});
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

pub fn downloadPackages(packages: []PackageStatus, alloc: std.mem.Allocator) bool {
    // For now only yay supported :)
    assertYayExists() catch return false;
    performYaySync() catch return false;

    var all_ok = true;

    for (packages) |*package| {
        if (package.status == .download) {
            downloadPackage(package.package.name, alloc) catch {
                all_ok = false;
                continue;
            };
            package.status = .setup;
        } else {
            log().err("Package \"{s}\" is not set for download - skipping it (Status:{any})", .{ package.package.name, package.status });
        }
    }

    return all_ok;
}

// Proceeds to invoke setup command for each script that is at the setup stage.
// if the command fails the package is skipped
// Assumes config fields are validated.
pub fn setupPackages(packages: []PackageStatus, config: Config, alloc: std.mem.Allocator) bool {
    const scripts_cwd = std.fs.cwd().openDir(config.scripts_dir_path, .{}) catch |err| {
        const OpenError = std.fs.Dir.OpenError;

        const reason = switch (err) {
            OpenError.NotDir => "is not a directory",
            OpenError.FileNotFound => "not found",
            OpenError.AccessDenied => "access denied",
            else => "unknown error occurred",
        };

        log().info("Scripts working directory path: \"{s}\" {s}", .{ config.scripts_dir_path, reason });

        return false;
    };

    var all_ok = true;
    for (packages) |*p| {
        if (p.status == .setup) {
            if (setupPackage(p.package, config.dotfiles_dir_path, scripts_cwd, alloc)) {
                p.status = SetupStatus.finished;
            } else {
                all_ok = false;
            }
        } else {
            log().warn("Package \"{s}\" is not set for setup - skipping it (Status:{s})", .{ p.package.name, p.status.toString() });
        }
    }
    return all_ok;
}

// Assumes the package is at a setup stage and dotfiles_dir_path is a valid directory
// Each package gets these ENV VARS
//  - DOTFILES_DIR_PATH - path to dotfiles directory
fn setupPackage(
    package: *const PackageDescriptor,
    dotfiles_dir_path: []const u8,
    cwd_dir: std.fs.Dir,
    alloc: std.mem.Allocator,
) bool {
    // setup command is null so basically setup is finished
    if (package.setup_command == null) return true;

    var child = std.process.Child.init(&.{ "bash", "-c", package.setup_command.? }, alloc);

    // Setting up child env
    // As for now it overrides the parent envs - dont know if it will be a problem
    var env = std.process.EnvMap.init(alloc);
    env.put("DOTFILES_DIR_PATH", dotfiles_dir_path) catch return false;

    child.cwd_dir = cwd_dir;
    child.env_map = &env;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = child.spawnAndWait() catch |err| {
        log().err("Error when running \"{s}\" setup command for package \"{s}\" (error: {any})", .{ package.setup_command.?, package.name, err });
        return false;
    };

    if (term == .Exited and term.Exited == 0)
        return true;

    log().nextFileOnly();
    log().err("The setup command \"{s}\" for package \"{s}\" didn't return successfully. (Termination:{any})", .{ package.setup_command.?, package.name, term });
    return false;
}

fn assertYayExists() !void {
    try util.runCommand(&[_][]const u8{ "yay", "--version" });
    log().info("Yay Found", .{});
}

fn performYaySync() !void {
    log().info("Syncing yay", .{});
    try util.runSilentCommand(&[_][]const u8{ "yay", "-Sy" });
    log().info("Yay -Sy", .{});
}

fn downloadPackage(package_name: []const u8, alloc: std.mem.Allocator) !void {
    log().info("Downloading package: {s}", .{package_name});

    var child = std.process.Child.init(&[_][]const u8{ "yay", "-S", "--noconfirm", package_name }, std.heap.page_allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.stdin_behavior = .Inherit;

    child.spawn() catch {
        log().err("Couldn't spawn download process for package {s}", .{package_name});
        return error.DownloadFailed;
    };
    const child_stdout = util.readWholeStreamAlloc(child.stdout.?, alloc) catch return error.DownloadFailed;
    const child_stderr = util.readWholeStreamAlloc(child.stderr.?, alloc) catch return error.DownloadFailed;

    defer alloc.free(child_stdout);
    defer alloc.free(child_stderr);

    const exit = try child.wait();

    if (exit != .Exited or (exit == .Exited and exit.Exited != 0)) {
        log().nextStdoutOnly();
        log().err("Download failed of {s}.", .{package_name});
        log().nextFileOnly();
        log().err("Download failed of {s}. \nSubprocess stdout is:\n{s}\nSubprocess stderr is:\n{s}", .{ package_name, child_stdout, child_stderr });
        return error.DownloadFailed;
    }

    log().info("Download success", .{});
}

test "finalizePackages removes packages with duplicate names on the same level" {
    const packages = [_]PackageDescriptor{
        .{ .name = "Test1", .description = null, .dependencies = null, .setup_command = null },
        .{ .name = "Test1", .description = null, .dependencies = null, .setup_command = null },
    };

    const out = try finalizePackages(&packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(1, out.len);
}

test "finalizePackages removes packages with duplicate name on the single nested level" {
    var t1_s: [1]PackageDescriptor = .{.{
        .name = "Test1",
        .description = null,
        .dependencies = null,
        .setup_command = null,
    }};
    var t2_s: [2]PackageDescriptor = .{ .{
        .name = "Test2",
        .description = null,
        .dependencies = null,
        .setup_command = null,
    }, .{
        .name = "Test3",
        .description = null,
        .dependencies = null,
        .setup_command = null,
    } };

    const packages = [_]PackageDescriptor{
        .{
            .name = "Test1",
            .description = null,
            .dependencies = &t1_s,
            .setup_command = null,
        },
        .{
            .name = "Test2",
            .description = null,
            .dependencies = &t2_s,
            .setup_command = null,
        },
    };

    const out = try finalizePackages(&packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(3, out.len);
    try std.testing.expectEqualSlices(u8, "Test1", out[0].name);
    try std.testing.expectEqualSlices(u8, "Test2", out[1].name);
    try std.testing.expectEqualSlices(u8, "Test3", out[2].name);
}

test "finalizePackages removes packages with duplicate name on the multiple nested levels" {
    var t1_s: [1]PackageDescriptor = .{.{
        .name = "Test6",
        .description = null,
        .dependencies = null,
        .setup_command = null,
    }};
    var t3_s: [3]PackageDescriptor = .{
        .{
            .name = "Test3",
            .description = null,
            .dependencies = null,
            .setup_command = null,
        },
        .{
            .name = "Test3",
            .description = null,
            .dependencies = null,
            .setup_command = null,
        },
        .{
            .name = "Test4",
            .description = null,
            .dependencies = null,
            .setup_command = null,
        },
    };
    var t2_s: [2]PackageDescriptor = .{ .{
        .name = "Test2",
        .description = null,
        .dependencies = &t3_s,
        .setup_command = null,
    }, .{
        .name = "Test3",
        .description = null,
        .dependencies = null,
        .setup_command = null,
    } };

    const packages = [_]PackageDescriptor{ .{
        .name = "Test1",
        .description = null,
        .dependencies = &t1_s,
        .setup_command = null,
    }, .{
        .name = "Test2",
        .description = null,
        .dependencies = &t2_s,
        .setup_command = null,
    }, .{
        .name = "Test5",
        .description = null,
        .dependencies = null,
        .setup_command = null,
    } };

    const out = try finalizePackages(&packages, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(6, out.len);
    try std.testing.expectEqualSlices(u8, "Test6", out[0].name);
    try std.testing.expectEqualSlices(u8, "Test1", out[1].name);
    try std.testing.expectEqualSlices(u8, "Test3", out[2].name);
    try std.testing.expectEqualSlices(u8, "Test4", out[3].name);
    try std.testing.expectEqualSlices(u8, "Test2", out[4].name);
    try std.testing.expectEqualSlices(u8, "Test5", out[5].name);
}
