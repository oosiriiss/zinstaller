const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const Lexer = @import("lexer.zig").Lexer;
const Symbol = @import("lexer.zig").Symbol;
const ast = @import("ast.zig");
const util = @import("util.zig");
const cli = @import("cli.zig");
const log = @import("logger.zig").getGlobalLogger;

pub const SetupStatus = enum {
    // Package is yet to be downloaded
    download,
    // package is yet to be setup
    setup,
    // Package setup has finished
    finished,

    pub fn toString(self: @This()) []const u8 {
        return @tagName(self);
    }

    fn fromString(str: []const u8) !@This() {
        for (std.enums.values(SetupStatus)) |e| {
            if (std.mem.eql(u8, e.toString(), str)) return e;
        }
        return error.InvalidEnumString;
    }
};

pub const PackageStatus = struct {
    package: *const PackageDescriptor,
    status: SetupStatus,
};

pub fn createPackageStatusSlice(packages: []const PackageDescriptor, alloc: std.mem.Allocator) (std.mem.Allocator.Error)![]PackageStatus {
    const statuses = try alloc.alloc(PackageStatus, packages.len);
    for (packages, 0..) |*p, i| {
        statuses[i].package = p;
        statuses[i].status = .download;
    }
    return statuses;
}

pub fn saveCacheEntries(cache_file_path: []const u8, statuses: []const PackageStatus) !void {
    var file = try util.openFileWrite(cache_file_path);
    defer file.close();
    var file_writer = file.writer();

    try file_writer.print("[\n", .{});

    // Cache has to be stored as objects to allow package names with '-' sign.
    // Previous method of storign it as assignemnts caused errors when parsing.
    for (statuses) |status| {
        try file_writer.print("\tentry {{ name = \"{s}\"; status = \"{s}\"; }}\n", .{ status.package.name, status.status.toString() });
    }

    try file_writer.print("]", .{});
}

// Loads all previous packages statuses from cache file
// returns a map of package_name -> status
pub fn loadCacheEntries(cache_file_path: []const u8, alloc: std.mem.Allocator) !?std.StringHashMap(SetupStatus) {
    var file = util.openFileReadonly(cache_file_path) catch return null;
    defer file.close();

    if (!cli.askConfirmation("Cache file found ({s}). do you want to resume configuration?\n", .{cache_file_path})) {
        // cleaning it just because i can, it'll be overriden anyway
        cleanCache(cache_file_path) catch null;
        return null;
    }

    const cache_content = try util.readAllAlloc(file, alloc);
    defer alloc.free(cache_content);

    var lexer = Lexer.init(cache_content);
    var parser = ast.Parser.init(&lexer, alloc);
    var tree = try parser.build();
    defer tree.deinit();

    return try parseCacheEntries(tree.root, alloc);
}

pub fn mergePackageStatuses(statuses: []PackageStatus, cache_status_map: *const std.StringHashMap(SetupStatus)) !void {
    for (statuses) |*s| {
        if (cache_status_map.get(s.package.name)) |cache_status| {
            s.status = cache_status;
        } else {
            return error.PackageNotFoundInCache;
        }
    }
}

// allocate new memory for keys.
fn parseCacheEntries(l: ast.Value, alloc: std.mem.Allocator) !std.StringHashMap(SetupStatus) {
    if (l != .list) {
        log().err("Cache file root object has to be a list", .{});
        return error.CacheInvalid;
    }
    var map = std.StringHashMap(SetupStatus).init(alloc);
    errdefer map.deinit();

    for (l.list) |entry| {
        if (entry != .object) {
            log().err("Couldn't read cache. non-object element encountered", .{});
            return error.CacheInvalid;
        }

        const obj = entry.object;

        const package_name = obj.fields.get("name") orelse {
            log().err("Cache entry is missing 'name' field", .{});
            return error.CacheInvalid;
        };
        const status = obj.fields.get("status") orelse {
            log().err("Cache entry is missing 'status' field", .{});
            return error.CacheInvalid;
        };

        if (package_name != .string) {
            log().err("Cache entry's name isn't string.", .{});
            return error.CacheInvalid;
        }
        if (status != .string) {
            log().err("Cache entry's status isn't string.", .{});
            return error.CacheInvalid;
        }

        const name = try alloc.dupe(u8, package_name.string);
        const status_enum = SetupStatus.fromString(status.string) catch {
            log().err("Cache entry's status has invalid value.", .{});
            return error.CacheInvalid;
        };

        try map.put(name, status_enum);
    }

    return map;
}

pub fn cleanCache(cache_file_path: []const u8) !void {
    log().info("Deleting cache file: {s}", .{cache_file_path});
    if (std.fs.cwd().deleteFile(cache_file_path)) {
        log().info("Deleted successfully", .{});
    } else |err| {
        const e = std.fs.Dir.DeleteFileError;
        const err_str = switch (err) {
            e.AccessDenied => "Access Denied error",
            e.IsDir => "File is directory error",
            e.FileBusy => "File is in use error",
            else => "Unknown error",
        };
        log().err("Couldn't delete file due to {s}. The cache file can be safely removed manually if necessary.", .{err_str});
    }
}

test "SetupStatus to string" {
    try std.testing.expectEqualSlices(u8, "setup", SetupStatus.setup.toString());
    try std.testing.expectEqualSlices(u8, "download", SetupStatus.download.toString());
    try std.testing.expectEqualSlices(u8, "finished", SetupStatus.finished.toString());
}

test "SetupStatus from string" {
    try std.testing.expectEqual(SetupStatus.setup, SetupStatus.fromString("setup"));
    try std.testing.expectEqual(SetupStatus.download, SetupStatus.fromString("download"));
    try std.testing.expectEqual(SetupStatus.finished, SetupStatus.fromString("finished"));

    try std.testing.expectError(error.InvalidEnumString, SetupStatus.fromString("invalid_enum"));
}
