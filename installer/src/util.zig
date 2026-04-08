const std = @import("std");
const log = @import("logger.zig").getGlobalLogger;

pub const IndentPrinter = struct {
    indent: u8,
    writer: *std.io.Writer,

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

pub fn printCharN(c: u8, n: usize, writer: *std.io.Writer) !void {
    for (0..n) |_|
        try writer.print("{c}", .{c});
}

// returns a slice without leading and trailing whitespace
pub fn clipWhitespace(buf: []const u8) []const u8 {
    if (buf.len <= 0)
        return buf;

    var start: usize = 0;
    var end: usize = buf.len - 1;

    while (start < buf.len and std.ascii.isWhitespace(buf[start])) {
        if (start >= end) {
            return &.{};
        }
        start = start + 1;
    }

    while (std.ascii.isWhitespace(buf[end])) {
        if (end <= start) {
            return &.{};
        }
        end = end - 1;
    }

    return buf[start .. end + 1];
}

pub fn readLine(buffer: []u8) ![]u8 {
    var stdin_reader = std.fs.File.stdin().reader(buffer);
    var stdin = &stdin_reader.interface;

    if (stdin.takeDelimiter('\n')) |lineOptional| {
        if (lineOptional) |line| {
            if (line.len > 0 and line[line.len - 1] == '\r')
                return line[0 .. line.len - 1];
            return line;
        } else {
            return error.EOF;
        }
    } else |err| {
        return err;
    }
}

pub const OpenError = error{ AccessDenied, NotFound, UnknownError, IsDirectory };

// Utility method for opening a file, Handles basic errors by printing to the stdout
pub fn openFileReadonly(path: []const u8) OpenError!std.fs.File {
    const flags: std.fs.File.OpenFlags = .{ .mode = .read_only };
    const file = std.fs.cwd().openFile(path, flags) catch |err| {
        const e = std.fs.File.OpenError;
        switch (err) {
            e.AccessDenied => {
                log().err("Access to file: '{s}' denied", .{path});
                return OpenError.AccessDenied;
            },
            e.FileNotFound => {
                log().err("File '{s}' not found", .{path});
                return OpenError.NotFound;
            },
            e.IsDir => {
                log().err("Path '{s}' is directory when file was expected", .{path});
                return OpenError.IsDirectory;
            },
            else => {
                log().err("An unknown error occurred when trying to open file {s}", .{path});
                return OpenError.UnknownError;
            },
        }
    };
    return file;
}

pub fn openFileWrite(path: []const u8) OpenError!std.fs.File {
    const flags: std.fs.File.CreateFlags = .{
        .exclusive = false,
    };
    const file = std.fs.cwd().createFile(path, flags) catch |err| {
        const e = std.fs.File.OpenError;
        switch (err) {
            e.AccessDenied => {
                log().err("Access to file: '{s}' denied", .{path});
                return OpenError.AccessDenied;
            },
            e.FileNotFound => {
                log().err("File '{s}' not found", .{path});
                return OpenError.NotFound;
            },
            e.IsDir => {
                log().err("Path '{s}' is directory when file was expected", .{path});
                return OpenError.IsDirectory;
            },
            else => {
                log().err("An unknown error occurred when trying to open file {s} (err: {any})", .{ path, err });
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

pub fn readWholeStreamAlloc(file: std.fs.File, alloc: std.mem.Allocator) ![]const u8 {
    var file_buf: [4096]u8 = undefined;
    var reader = file.reader(&file_buf).interface;

    var buffer = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer buffer.deinit(alloc);

    var data_buffer: [1024]u8 = undefined;

    while (true) {
        reader.readSliceAll(&data_buffer) catch break;
        const read = data_buffer.len;
        if (read == 0) break;
        try buffer.appendSlice(alloc, data_buffer[0..read]);
    }

    return try buffer.toOwnedSlice(
        alloc,
    );
}

pub fn runSilentCommand(argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    const exit = try child.spawnAndWait();

    if (exit == .Exited and exit.Exited == 0) return;

    return error.ProgramFailed;
}

pub fn runCommand(argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, std.heap.page_allocator);
    const exit = try child.spawnAndWait();

    if (exit == .Exited and exit.Exited == 0) return;

    return error.ProgramFailed;
}

// Computes a relative path from "from to "to" and puts it in a new allocated buffer.
// Also handles HOME directory  by parsing '~'.
pub fn prepareRelativePath(from: []const u8, to: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    const expanded_from = try expandTilde(from, alloc);
    const expanded_to = try expandTilde(to, alloc);
    defer alloc.free(expanded_from);
    defer alloc.free(expanded_to);

    return try std.fs.path.relative(alloc, expanded_from, expanded_to);
}

pub fn expandTilde(path: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (path.len > 0 and path[0] == '~') {
        const home = std.process.getEnvVarOwned(alloc, "HOME") catch {
            std.debug.panic("Couldn't access $HOME environment variable", .{});
            return error.InvalidHome;
        };
        defer alloc.free(home);

        var rest = path[1..];
        if (rest.len > 0 and rest[0] == '/') {
            rest = rest[1..];
        }

        return std.fs.path.join(alloc, &[2][]const u8{ home, rest });
    }
    return alloc.dupe(u8, path);
}
