const std = @import("std");

pub const INDENT_SPACE_COUNT = 3;

pub const IndentPrinter = struct {
    indent: u8,
    writer: std.io.AnyWriter,

    const Self = @This();

    // ignores all errors
    pub fn printSilent(self: Self, comptime fmt: []const u8, args: anytype) void {
        printCharN(' ', self.indent * 2, self.writer) catch {};
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

pub fn countChar(comptime str: []const u8, comptime char: u8) comptime_int {
    comptime {
        var count: usize = 0;
        for (str) |c|
            count = count + if (c == char) 1 else 0;

        return count;
    }
}

pub const IndentError = error{
    // number of spaces doesn't match specfieid number of spaces in an indent
    InvalidSpaceIndent};

// Counts numer of tabs or sequences of 4*space from the left of the slice
pub fn countIndent(s: []const u8) IndentError!u8 {
    if (s.len <= 0)
        return 0;

    var indents: u8 = 0;

    var i: usize = 0;
    while (i < s.len) {
        const isSpaceIndent = try validSpaceIndent(s[i..], INDENT_SPACE_COUNT);

        if (isSpaceIndent) {
            i = i + INDENT_SPACE_COUNT;
            indents = indents + 1;
        } else if (s[i] == '\t') {
            indents = indents + 1;
            i = i + 1;
        } else break;
    }

    return indents;
}

// Check if all {spaceCount} first characters of slice are spaces
//
// if yes => true
// if the first character isn't space returns false
// if first char is space but any other isn't returns InvalidSpaceIndent
//
fn validSpaceIndent(s: []const u8, comptime spaceCount: usize) IndentError!bool {
    if (s[0] != ' ')
        return false;

    const end = if (s.len < spaceCount) s.len else spaceCount;

    for (1..end) |i|
        if (s[i] != ' ')
            return IndentError.InvalidSpaceIndent;

    return true;
}

pub fn isWhitespace(c: u8) bool {
    return c == '\t' or c == ' ' or c == '\n' or c == '\r';
}

// returns a slice without leading and trailing whitespace
pub fn clipWhitespace(buf: []const u8) []const u8 {
    if (buf.len <= 0)
        return buf;

    var start: usize = 0;
    var end: usize = buf.len - 1;

    while (isWhitespace(buf[start]))
        start = start + 1;

    while (isWhitespace(buf[end]))
        end = end - 1;

    return buf[start .. end + 1];
}
