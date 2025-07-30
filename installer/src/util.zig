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

pub fn askConfirmation(comptime msg: []const u8, args: anytype) bool {
    // TODO :: Should this return an error?

    var buf: [64]u8 = undefined;

    while (true) {
        std.io.getStdOut().writer().print(msg, args) catch continue;

        if (readLine(&buf)) |lineRaw| {
            const lowered_line = std.ascii.lowerString(&buf, lineRaw);
            const line = clipWhitespace(lowered_line);

            // Defaults to confirmation
            if (line.len == 0)
                return true;

            if (std.mem.eql(u8, line, "y"))
                return true;

            if (line.len >= 3 and std.mem.eql(u8, line[0..3], "yes"))
                return true;

            return false;
        } else |err| {
            std.debug.print("Error encountered when reading input. Try Again. (error: {any})\n", .{err});
        }
    }
}
