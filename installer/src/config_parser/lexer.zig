const std = @import("std");
const assert = std.debug.assert;

const Symbol = enum {
    curly_left,
    curly_right,
};

const ParseError = error{ InvalidSymbol, EOF };

const Token = union(enum) { identifier: []const u8, symbol: Symbol };

pub const Lexer = struct {
    /// The content that is parsed
    content: []const u8,
    /// Current position inside content
    index: usize,
    alloc: std.mem.Allocator,
    tokens: std.ArrayList(Token),

    const Self = @This();

    /// content must be valid as long as
    pub fn init(content: []const u8, alloc: std.mem.Allocator) !Lexer {
        return .{ .content = content, .index = 0, .alloc = alloc, .tokens = std.ArrayList(Token).init(alloc) };
    }

    // ?? Change this to polling-like behavior instead of storing the tokens?
    //pub fn tokenize(self: Self) std.ArrayList(Token) {}

    fn nextToken(self: Self) ParseError!Token {
        const token = try self.separateToken();

        // TODO :: IDK extracting the tokens and then doing almost the same checks feels redundant but idc right now
        if (isSymbol(token)) {

        }
    }

    // Returns a slice from self.content that should represent a single token
    fn separateToken(self: *Self) ParseError![]const u8 {
        self.skipWhitespace();

        if (self.index >= self.content.len)
            return ParseError.EOF;

        const start_index = self.index;
        var token_length: u32 = 1;

        var curr = self.content[start_index .. start_index + token_length];

        if (isSymbol(curr[0])) {
            self.index = start_index + token_length;
            return curr;
        }

        // Reading the rest of the token (identifier or keyword)
        while (start_index + token_length < self.content.len) {
            const next_char = self.content[start_index + token_length];
            if (isWhitespace(next_char) or isSymbol(next_char))
                break;

            token_length = token_length + 1;
        }

        curr = self.content[start_index .. start_index + token_length];
        self.index = start_index + token_length;
        return curr;
    }

    fn isSymbol(str_token: []const u8) bool {
        return str_token.len == 1 and isSymbol(str_token[0]);
    }
    fn isSymbol(str_token: u8) bool {
        return str_token == '{' or str_token == '}';
    }

    fn parseSymbol(str_token: []const u8) ParseError!Symbol {
        // TODO :: Change this function to trust the caller that it's a symbol?
        if (!isSymbol(str_token)) {
            std.log.err("Token: {s} is not a symbol", .{str_token});
            return ParseError.InvalidSymbol;
        }
    }

    // Moves the index to the next non-whitespace character
    fn skipWhitespace(self: *Self) void {
        while (self.index < self.content.len and isWhitespace(self.content[self.index]))
            self.index = self.index + 1;
    }

    fn isWhitespace(c: u8) bool {
        const whitespace = [_]u8{ ' ', '\t', '\x0B', '\n', '\r' };

        for (whitespace) |wc| {
            if (c == wc)
                return true;
        }
        return false;
    }
};

test "Separating symbols" {
    const t1 = "{";
    const t2 = "}";

    var l1 = try Lexer.init(t1, std.heap.page_allocator);
    var l2 = try Lexer.init(t2, std.heap.page_allocator);

    const a1 = try l1.separateToken();
    const a2 = try l2.separateToken();

    try std.testing.expectEqualSlices(u8, "{", a1);
    try std.testing.expectEqualSlices(u8, "}", a2);
}

test "Separating longer tokens" {
    const t3 = "token";

    var l3 = try Lexer.init(t3, std.heap.page_allocator);

    const a3 = try l3.separateToken();

    try std.testing.expectEqualSlices(u8, "token", a3);
}

test "Separating token chains tokens" {
    const sample_content = "{token} tokeninho";

    var lexer = try Lexer.init(sample_content, std.heap.page_allocator);

    const t1 = try lexer.separateToken();
    const t2 = try lexer.separateToken();
    const t3 = try lexer.separateToken();
    const t4 = try lexer.separateToken();

    try std.testing.expectEqualSlices(u8, "{", t1);
    try std.testing.expectEqualSlices(u8, "token", t2);
    try std.testing.expectEqualSlices(u8, "}", t3);
    try std.testing.expectEqualSlices(u8, "tokeninho", t4);
}
