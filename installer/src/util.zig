const std = @import("std");

pub const INDENT_SPACE_COUNT = 3;

pub const IndentPrinter = struct {
    indent: u8,
    writer: std.io.AnyWriter,

    const Self = @This();

    // ignores all errors
    pub fn printSilent(self: Self, comptime fmt: []const u8, args: anytype) void {
        printCharN(' ', self.indent * 4, self.writer) catch {};
        self.writer.print(fmt, args) catch {};
    }

    pub fn print(self: Self, comptime fmt: []const u8, args: anytype) !void {
        try printCharN(' ', self.indent * 2, self.writer);
        try self.writer.print(fmt, args);
    }

    pub fn increase(self: *Self) void {
        self.indent = self.indent + 1;
    }

    pub fn decrease(self: *Self) void {
        self.indent = self.indent - 1;
    }
};

pub fn print(comptime format: []const u8, args: anytype) !void {
    try std.io.getStdOut().writer().print(format, args);
}

pub fn printCharN(c: u8, n: usize, writer: anytype) !void {
    for (0..n) |_|
        _ = try writer.print("{c}", .{c});
}

// returns a slice without leading and trailing whitespace
pub fn clipWhitespace(buf: []const u8) []const u8 {
    if (buf.len <= 0)
        return buf;

    var start: usize = 0;
    var end: usize = buf.len - 1;

    while (std.ascii.isWhitespace(buf[start]))
        start = start + 1;

    while (std.ascii.isWhitespace(buf[end]))
        end = end - 1;

    return buf[start .. end + 1];
}

pub fn readLine(buffer: []u8) ![]u8 {
    const stdin = std.io.getStdIn().reader();

    if (stdin.readUntilDelimiter(buffer, '\n')) |line| {
        if (line.len > 0 and line[line.len - 1] == '\r')
            return line[0 .. line.len - 1];
        return line;
    } else |err| {
        return err;
    }
}

const OpenError = error{ AccessDenied, NotFound, UnknownError };

// Utility method for opening a file, Handles basic errors by printing to the stdout
pub fn openFileReadonly(path: []const u8) OpenError!std.fs.File {
    const flags: std.fs.File.OpenFlags = .{ .mode = .read_only };
    const file = std.fs.cwd().openFile(path, flags) catch |err| {
        const oerr = std.fs.File.OpenError;
        switch (err) {
            oerr.AccessDenied => {
                std.log.err("Access to file: '{s}' denied", .{path});
                return OpenError.AccessDenied;
            },
            oerr.FileNotFound => {
                std.log.err("File '{s}' not found\n", .{path});
                return OpenError.NotFound;
            },
            else => {
                std.log.err("An unknown error occurred when trying to open file {s}", .{path});
                return OpenError.UnknownError;
            },
        }
    };
    return file;
}

pub fn getFileSize(file: std.fs.File) !u64 {
    const saved_pos = try file.getPos();
    const file_size = try file.getEndPos();
    try file.seekTo(saved_pos);

    return file_size;
}

pub fn readAllAlloc(file: std.fs.File, alloc: std.mem.Allocator) ![]const u8 {
    const file_size = try getFileSize(file);

    const file_content = try alloc.alloc(u8, file_size);
    _ = try file.readAll(file_content);

    return file_content;
}
