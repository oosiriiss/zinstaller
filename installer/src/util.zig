const std = @import("std");

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
pub fn countIndent(s: []const u8) IndentError!usize {
    if (s.len <= 0)
        return 0;

    const INDENT_SPACE_COUNT = 4;

    var indents: usize = 0;

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
