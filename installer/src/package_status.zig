const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const Lexer = @import("lexer.zig").Lexer;
const Symbol = @import("lexer.zig").Symbol;
const ast = @import("ast.zig");
const util = @import("util.zig");

pub const SetupStatus = enum {
    // Package is yet to be downloaded
    download,
    // package is yet to be setup
    setup,
    // Package setup has finished
    finished,

    fn toString(self: @This()) []const u8 {
        return @tagName(self);
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

    try file_writer.print("{s}\n", .{Symbol.curly_left.toString()});

    for (statuses) |status| {
        try file_writer.print("\t{s} {s} {s};\n", .{ status.package.name, Symbol.assign.toString(), status.status.toString() });
    }

    try file_writer.print("{s}", .{Symbol.curly_right.toString()});
}

// Loads all previous packages statuses from cache file
// and sets the corresponding statuses of the input package statuses
// If the size of package cache doesn't match the statuses size error is returned
// If the package names in the cache dont match the names in statuses error is returned
pub fn loadPackageStatusCache(cache_file_path: []const u8, statuses: []PackageStatus, alloc: std.mem.Allocator) !void {
    var file = try util.openFileReadonly(cache_file_path);
    defer file.close();
    const cache_content = try util.readAllAlloc(file, alloc);
    defer alloc.free(cache_content);

    var lexer = Lexer.init(cache_content);
    var parser = ast.Parser.init(&lexer, alloc);
    var tree = try parser.build();
    defer tree.deinit();

    var cache_map = try parseCacheEntries(tree.root, alloc);
    defer cache_map.deinit();

    try mergePackageStatuses(statuses, cache_map);
}

fn mergePackageStatuses(statuses: []PackageStatus, cache_status_map: *const std.StringHashMap(PackageStatus)) !void {
    for (statuses) |*s| {
        if (cache_status_map.get(s.package.name)) |cache_status| {
            s.status = cache_status;
        } else {
            return error.PackageNotFoundInCache;
        }
    }
}

// Doesn't allocate new memory for keys and values. it should be valid as long as the output map is
fn parseCacheEntries(object: ast.Value, alloc: std.mem.Allocator) !std.StringHashMap(SetupStatus) {
    if (object != .object)
        std.log.err("Cache file root object has to be an object", .{});
    var map = std.StringHashMap(SetupStatus).init(alloc);
    errdefer map.deinit();

    var fields_iter = object.object.fields.iterator();

    while (fields_iter.next()) |v| {
        map.put(v.key_ptr, v.value_ptr);
    }

    return map;
}
