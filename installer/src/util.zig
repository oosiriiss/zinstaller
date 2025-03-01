const std = @import("std");

pub fn countChar(comptime str: []const u8, comptime char: u8) comptime_int {
    comptime {
        var count: usize = 0;
        for (str) |c|
            count = count + if (c == char) 1 else 0;

        return count;
    }
}

// Counts numer of tabs or sequences of 4*space from the left of the slice
pub fn countIndent(s: []const u8) u32 {
    const SPACE_INDENT: []const u8 = "    ";
    const INDENT_SPACE_COUNT = comptime countChar(SPACE_INDENT, ' ');

    var i: usize = 0;
    var indents: u32 = 0;
    while (i < s.len) {
        if (s[i] == '\t') {
            i = i + 1;
            indents = indents + 1;
        } else if (s.len > 4 and i < s.len - 4 and std.mem.eql(u8, s[i .. i + 4], SPACE_INDENT)) {
            i = i + INDENT_SPACE_COUNT;
            indents = indents + 1;
        } else break;
    }
    return indents;
}

pub fn isWhitespace(c: u8) bool {
    return c == '\t' or c == ' ' or c == '\n';
}

// returns a slice without leading and trailing whitespace
pub fn clipWhitespace(buf: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = buf.len - 1;

    while (isWhitespace(buf[start]))
        start = start + 1;

    while (isWhitespace(buf[end]))
        end = end - 1;

    return buf[start..end];
}
