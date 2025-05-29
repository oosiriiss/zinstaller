const std = @import("std");
const lxr = @import("config_parser/lexer.zig");

pub const PackageDescriptor = struct {};

pub const PackageLoadError = error{ FileNotFound, FileAccessDenied, UnkownError };

pub fn loadConfig(filename: []const u8) !void {
    const flags: std.fs.File.OpenFlags = .{ .mode = .read_only };

    const file = std.fs.cwd().openFile(filename, flags) catch |err| {
        const oerr = std.fs.File.OpenError;
        switch (err) {
            oerr.AccessDenied => {
                std.log.err("Access to packages file: '{s}' denied", .{filename});
                return PackageLoadError.FileAccessDenied;
            },
            oerr.FileNotFound => {
                std.log.err("packages file '{s}' not found\n", .{filename});
                return PackageLoadError.FileNotFound;
            },
            else => {
                std.log.err("An unknown error occurred when trying to open file {s}", .{filename});
                return PackageLoadError.UnkownError;
            },
        }
    };

    defer file.close();

    const file_size = try file.getEndPos();
    try file.seekTo(0);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const file_content = try allocator.alloc(u8, file_size);
    defer allocator.free(file_content);

    _ = try file.readAll(file_content);

    var lexer = try lxr.Lexer.init(file_content, allocator);

    while (lexer.nextToken()) |token| {
        std.debug.print(" ", .{});
        try token.debugPrint();
    }
}
