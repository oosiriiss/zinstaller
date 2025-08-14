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

pub const Cache = struct {
    package_status_map: std.StringHashMap(SetupStatus),
    alloc: std.mem.Allocator,

    pub fn deinit(self: *@This()) void {
        var it = self.package_status_map.iterator();
        while (it.next()) |e| {
            self.alloc.free(e.key_ptr.*);
        }
        self.package_status_map.deinit();
    }
};

const CacheEntry = struct {
    name: []const u8,
    status: SetupStatus,

    const Self = @This();
    const WRITER_IDENTIFIER = "entry";

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
    }

    pub fn serialize(self: Self, writer: std.fs.File.Writer) !void {
        try writer.print("{s} {{ name= \"{s}\"; status = \"{s}\"; }}", .{
            WRITER_IDENTIFIER,
            self.name,
            self.status.toString(),
        });
    }
    pub fn deserialize(v: ast.Value, alloc: std.mem.Allocator) !CacheEntry {
        if (v != .object) return error.InvalidCacheEntry;
        var fields = v.object.fields;
        return try ast.initObjectFromFields(Self, &fields, alloc);
    }
};

pub fn createPackageStatusSlice(packages: []const PackageDescriptor, alloc: std.mem.Allocator) (std.mem.Allocator.Error)![]PackageStatus {
    const statuses = try alloc.alloc(PackageStatus, packages.len);
    for (packages, 0..) |*p, i| {
        statuses[i].package = p;
        statuses[i].status = .download;
    }
    return statuses;
}

pub fn saveCache(cache_file_path: []const u8, statuses: []const PackageStatus) !void {
    var file = try util.openFileWrite(cache_file_path);
    defer file.close();
    var file_writer = file.writer();

    try file_writer.print("[\n", .{});

    // Cache has to be stored as objects to allow package names with '-' sign.
    // Previous method of storign it as assignemnts caused errors when parsing.
    for (statuses) |status| {
        try file_writer.print("\t", .{});
        try (CacheEntry{ .name = status.package.name, .status = status.status }).serialize(file_writer);
        try file_writer.print(",\n", .{});
    }

    try file_writer.print("]", .{});
}

// Loads all previous packages statuses from cache file
// returns a map of package_name -> status
pub fn loadCache(cache_file_path: []const u8, alloc: std.mem.Allocator) !?Cache {
    var file = util.openFileReadonly(cache_file_path) catch return null;
    defer file.close();

    if (!cli.askConfirmation("Cache file found ({s}). do you want to resume configuration?\n", .{cache_file_path})) {
        // cleaning it just because i can, it'll be overriden anyway
        cleanCache(cache_file_path) catch return null;
    }

    const cache_content = try util.readAllAlloc(file, alloc);
    defer alloc.free(cache_content);

    var lexer = Lexer.init(cache_content);
    var parser = ast.Parser.init(&lexer, alloc);
    var tree = try parser.build();
    defer tree.deinit();

    return try parseCacheEntries(tree.root, alloc);
}

// Just sets the corresponding package status to its corresponding package (matched by name) in the cache.
pub fn loadPackageStatusesFromCache(statuses: []PackageStatus, cache_status_map: *const std.StringHashMap(SetupStatus)) void {
    for (statuses) |*s| {
        if (cache_status_map.get(s.package.name)) |cache_status| {
            s.status = cache_status;
        } else {
            // Cache was modified or corrupted and doesn't accurately reflect the state of the config.
            log().warn("Cache file doesn't contain {s} package. it's setup state wasn't modified and is: {s}", .{ s.package.name, s.status.toString() });
            // return error.PackageNotFoundInCache;
        }
    }
}

// allocate new memory for keys.
fn parseCacheEntries(l: ast.Value, alloc: std.mem.Allocator) !Cache {
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

        // Memory needed for the map, so no need to free it.
        const cache_entry = try CacheEntry.deserialize(entry, alloc);

        try map.put(cache_entry.name, cache_entry.status);
    }

    return Cache{
        .package_status_map = map,
        .alloc = alloc,
    };
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
        return err;
    }
}

//////////////////////////////////////////////////
//////////////////////////////////////////////////
///////////////////// TEST ///////////////////////
//////////////////////////////////////////////////
//////////////////////////////////////////////////

const test_alloc = std.testing.allocator;
const testing = std.testing;

fn test_cache_obj(name: []const u8, status: SetupStatus) ast.Value {
    const V = ast.Value;
    var map = std.StringHashMap(V).init(test_alloc);
    map.put(test_alloc.dupe(u8, "name") catch unreachable, V{ .string = test_alloc.dupe(u8, name) catch unreachable }) catch unreachable;
    map.put(test_alloc.dupe(u8, "status") catch unreachable, V{ .string = test_alloc.dupe(u8, status.toString()) catch unreachable }) catch unreachable;

    return ast.Value{ .object = ast.Object{ .name = test_alloc.dupe(u8, "entry") catch unreachable, .fields = map } };
}

fn test_arr_to_slice(arr: []const ast.Value) []ast.Value {
    return test_alloc.dupe(ast.Value, arr) catch unreachable;
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

test "Parsing cache entries" {
    const V = ast.Value;

    var valid_cache_entries = V{
        .list = test_arr_to_slice(&[3]V{
            test_cache_obj("t1", SetupStatus.finished),
            test_cache_obj("t2", SetupStatus.download),
            test_cache_obj("t3", SetupStatus.setup),
        }),
    };

    defer valid_cache_entries.deinit(test_alloc);

    var cache = try parseCacheEntries(valid_cache_entries, test_alloc);
    defer cache.deinit();

    try testing.expectEqual(SetupStatus.finished, cache.package_status_map.get("t1").?);
    try testing.expectEqual(SetupStatus.download, cache.package_status_map.get("t2").?);
    try testing.expectEqual(SetupStatus.setup, cache.package_status_map.get("t3").?);
}
