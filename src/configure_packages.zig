const std = @import("std");
const main = @import("main.zig");
const testing = std.testing;

const ConfigurationError = error{ConfigurationNotFound};

fn configure(packageName: []const u8) ConfigurationError!void {
    const is = struct {
        fn cmp(b: []const u8) bool {
            return std.mem.eql(u8, packageName, b);
        }
    }.cmp;

    if (is("nvidia-dkms"))
        configureNvidiaDKMS()
    else if (is("sddm"))
        configureSDDM()
    else {
        return ConfigurationError.ConfigurationNotFound;
    }
}

// Allocates and returns a slice of packges names that have not been configured yet
fn loadConfigurePackages(fileName: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(fileName, std.fs.File.OpenFlags{ .mode = .read_only });

    const buf: [4096]u8 = undefined;
    try file.readAll(file, buf);
}

// Saves packages
fn saveConfigurePackages(fileName: []const u8, packages: []const main.Package) !void {
    var file = try std.fs.cwd().createFile(fileName, .{ .truncate = true });
    defer file.close();

    var fileWriter = std.io.bufferedWriter(file.writer());
    var out = fileWriter.writer();

    for (packages.items) |package| {
        try package.print(&out);
    }
    try fileWriter.flush();
}

// Runs the configurations
fn runConfigurations(selected: *const std.ArrayList(main.Package)) !void {
    _ = selected;
}

fn configureNvidiaDKMS() !void {}

fn configureSDDM() !void {}
