const std = @import("std");
const assert = std.debug.assert;

const Keyword = enum {
    if_keyword,
    else_keyword,
    switch_keyword,
};

const keyword_map = std.StaticStringMap(Keyword).initComptime([_]struct { []const u8, Keyword }{
    .{ "if", Keyword.if_keyword },
    .{ "else", Keyword.else_keyword },
    .{ "switch", Keyword.switch_keyword },
});

pub const Symbol = enum {
    curly_left,
    curly_right,
    square_left,
    square_right,
    assign,
    comma,
    semicolon,

    pub fn toString(self: @This()) []const u8 {
        return symbol_reverse_map.get(self);
    }
};

const symbol_map = std.StaticStringMap(Symbol).initComptime([_]struct { []const u8, Symbol }{
    .{ "{", .curly_left },
    .{ "}", .curly_right },
    .{ "[", .square_left },
    .{ "]", .square_right },
    .{ "=", .assign },
    .{ ",", .comma },
    .{ ";", .semicolon },
});

const symbol_reverse_map = blk: {
    var map = std.EnumArray(Symbol, []const u8).initUndefined();
    for (symbol_map.keys()) |key| {
        map.set(symbol_map.get(key).?, key);
    }
    break :blk map;
};

const LONGEST_SYMBOL_LENGTH = blk: {
    var max: usize = 0;
    for (symbol_map.keys()) |k| {
        if (k.len > max) {
            max = k.len;
        }
    }
    break :blk max;
};

const Token = union(enum) {
    identifier: []const u8,
    symbol: Symbol,
    keyword: Keyword,
    string_literal: []const u8,

    const Self = @This();

    pub fn debugPrint(self: Self) void {
        switch (self) {
            .identifier => |ident| {
                std.debug.print("IDENTIFIER({s})", .{ident});
            },
            .symbol => |symbol| {
                std.debug.print("SYMBOL({s})", .{symbol.toString()});
            },
            .keyword => |kw| {
                if (std.enums.tagName(Keyword, kw)) |name| {
                    std.debug.print("KEYWORD({s})", .{name});
                } else {
                    std.debug.print("UNKNOWN_KEYWORD", .{});
                }
            },
            .string_literal => |str| {
                std.debug.print("STRING_LITERAL({s})", .{str});
            },
        }
    }
};

const LexerError = error{ UnknownToken, UnterminatedString, EOF };

// The lexer doesn't allocate anything all the slices come directly from the source text.
pub const Lexer = struct {
    /// The content that is parsed
    content: []const u8,
    /// Current position inside content
    index: usize,

    // only for errors
    // Line number of current content
    current_line: usize,
    // Column of the
    current_line_char: usize,

    current_error: ?LexerError,

    const Self = @This();
    pub fn init(content: []const u8) Self {
        return .{
            .content = content,
            .index = 0,
            .current_line = 1,
            .current_line_char = 1,
            .current_error = null,
        };
    }
    pub fn debugPrint(self: *Self) void {
        const saved_index = self.index;
        self.index = 0;

        while (self.nextToken()) |token| {
            token.debugPrint();
            std.debug.print(" ", .{});
        }
        self.index = saved_index;
    }

    // Returns last encountered error or void if no error was encountered
    // Line number and column can be retrieved with self.current_line and self.current_line_char fields
    pub fn getError(self: Self) LexerError!void {
        if (self.current_error) |err| return err;
    }

    // Tries to parse the token from give content
    // if self.content is finished returns null and self.current_error is LexerError.EOF
    // if an error is encountered self.current_error is set and the function returns null
    pub fn nextToken(self: *Self) ?Token {
        if (self.current_error != null) return null;
        self.skipIgnorable();

        if (!self.canReadChar()) {
            self.current_error = LexerError.EOF;
            return null;
        }

        if (self.matchSymbol()) |symbol| {
            return Token{ .symbol = symbol };
        } else |_| {}

        const curr_char = self.content[self.index];
        const token = switch (curr_char) {
            '"' => {
                if (self.readString()) |str| {
                    return Token{ .string_literal = str };
                } else |err| {
                    self.current_error = err;
                    return null;
                }
            },
            '_', 'a'...'z', 'A'...'Z' => {
                const ident = self.readIdentifier();

                if (parseKeyword(ident)) |kw| {
                    return Token{ .keyword = kw };
                } else |_| {
                    //
                    return Token{ .identifier = ident };
                }
            },
            else => {
                self.current_error = LexerError.UnknownToken;
                return null;
            },
        };
        return token;
    }

    // Asserts that the next token is expected symbol. doesn't advance the lexer.
    pub fn assertSymbol(self: *Self, symbol: Symbol) !void {
        const t = self.peek() orelse {
            std.debug.print("Symbol {any} expected but got null token\n", .{symbol});
            return error.SymbolAssertionFailed;
        };
        if (t != .symbol) {
            std.debug.print("Token {any} isn't a symbol\n", .{t});
            return error.SymbolAssertionFailed;
        }
        if (t.symbol != symbol) {
            std.debug.print("Token {any} isn't expected symbol: {any}\n", .{ t, symbol });
            return error.SymbolAssertionFailed;
        }
    }

    // Asserts that the next token is expected keyword. doesn't advance the lexer.
    pub fn assertKeyword(self: *Self, keyword: Keyword) !void {
        const t = self.peek() orelse {
            std.debug.print("Kewyord {any} expected but got null token\n", .{keyword});
            return error.KeywordAssertionFailed;
        };
        if (t != .keyword) {
            std.debug.print("Token {any} isn't a Keyword\n", .{t});
            return error.KeywordAssertionFailed;
        }
        if (t.keyword != keyword) {
            std.debug.print("Token {any} isn't expected Keyword: {any}\n", .{ t, keyword });
            return error.KeywordAssertionFailed;
        }
    }

    // Asserts that the  next token is an identifier. doesn't advance the lexer.
    pub fn assertIdentifier(self: *Self) !void {
        const t = self.peek() orelse {
            std.debug.print("Identifier expected but got null\n", .{});
            return error.IdentifierAssertionFailed;
        };
        if (t != .identifier) {
            std.debug.print("Identifier expected but got {any}\n", .{t});
            return error.IdentifierAssertionFailed;
        }
    }

    pub fn peek(self: *Self) ?Token {
        const index = self.index;
        const line_number = self.current_line;
        const line_number_char = self.current_line_char;

        const token = self.nextToken();

        self.index = index;
        self.current_line = line_number;
        self.current_line_char = line_number_char;

        return token;
    }

    pub fn skipToken(self: *Self) void {
        _ = self.nextToken();
    }

    fn matchSymbol(self: *Self) !Symbol {

        // Matching from longset to shortest
        var current_length: usize = LONGEST_SYMBOL_LENGTH;

        while (current_length > 0) {
            if (self.index + current_length - 1 >= self.content.len) {
                current_length = current_length - 1;
                continue;
            }

            const key = self.content[self.index..(self.index + current_length)];

            if (symbol_map.get(key)) |s| {
                for (0..current_length) |_| _ = self.readChar();
                return s;
            }

            current_length = current_length - 1;
        }

        return error.InvalidSymbol;
    }

    fn readString(self: *Self) error{UnterminatedString}![]const u8 {
        const start_line = self.current_line;
        const start_line_char = self.current_line_char;
        // Skipping Beggining of string (")
        _ = self.readChar();
        const content_start = self.index;

        while (self.canReadChar() and self.peekChar() != '"') {
            _ = self.readChar();
        }
        if (!self.canReadChar()) {
            // Returning the string to
            self.index = content_start - 1;
            self.current_line = start_line;
            self.current_line_char = start_line_char;
            return error.UnterminatedString;
        }
        // Skipping end of string (")
        _ = self.readChar();
        return self.content[content_start .. self.index - 1];
    }

    fn readIdentifier(self: *Self) []const u8 {
        const start_pos = self.index;

        while (self.canReadChar() and (std.ascii.isAlphanumeric(self.peekChar()) or self.peekChar() == '_'))
            _ = self.readChar();

        return self.content[start_pos..self.index];
    }

    fn parseKeyword(str_token: []const u8) (error{InvalidKeyword})!Keyword {
        if (keyword_map.get(str_token)) |token| {
            return token;
        }
        return error.InvalidKeyword;
    }

    // Skips all whitespace and comments
    fn skipIgnorable(self: *Self) void {
        if (!self.canReadChar()) return;

        while (self.canReadChar() and std.ascii.isWhitespace(self.peekChar()) or self.isComment()) {
            self.skipWhitespace();
            self.skipComment();
        }
    }

    fn canReadChar(self: Self) bool {
        return self.index < self.content.len;
    }

    fn readChar(self: *Self) u8 {
        const char = self.content[self.index];
        self.index = self.index + 1;

        self.current_line_char = self.current_line_char + 1;
        if (char == '\n') {
            self.current_line = self.current_line + 1;
            self.current_line_char = 1;
        }

        return char;
    }

    fn peekChar(self: *Self) u8 {
        return self.content[self.index];
    }

    fn skipWhitespace(self: *Self) void {
        while (self.canReadChar() and std.ascii.isWhitespace(self.peekChar())) {
            _ = self.readChar();
        }
    }

    fn isComment(self: Self) bool {
        // This symbol doesn't get matched with other symbols and the rest of the line after it is ignored by the lexer
        const COMMENT_SYMBOL = "//";
        return self.index + COMMENT_SYMBOL.len - 1 < self.content.len and
            std.mem.eql(u8, COMMENT_SYMBOL, self.content[self.index..(self.index + COMMENT_SYMBOL.len)]);
    }

    fn skipComment(self: *Self) void {
        if (!self.isComment())
            return;

        // Skipping the comment
        while (self.canReadChar() and self.peekChar() != '\n')
            _ = self.readChar();

        // Finally skipping the newline
        _ = self.readChar();
    }
};

const TestKeywords = if (@import("builtin").is_test) enum {
    if_keyword,
    else_keyword,
    switch_keyword,
} else void;

const test_keyword_map = if (@import("builtin").is_test) std.StaticStringMap(TestKeywords).initComptime([_]struct { []const u8, TestKeywords }{
    .{ "if", TestKeywords.if_keyword },
    .{ "else", TestKeywords.else_keyword },
    .{ "switch", TestKeywords.switch_keyword },
}) else void;

test "Separating single-char symbols" {
    const t1 = "{}";

    var l1 = Lexer.init(t1);

    try std.testing.expectEqual(Symbol.curly_left, l1.nextToken().?.symbol);
    try std.testing.expectEqual(Symbol.curly_right, l1.nextToken().?.symbol);
}

test "Skipping comments" {
    const t1 =
        \\ // {}//{}";
        \\ // This is also a comment :)
        \\
        \\ huj = "123";
        \\
        \\ // {}//{}";
        \\ // This is a seoncd comment
        \\
        \\ lala = "234";
    ;

    var l1 = Lexer.init(t1);

    try std.testing.expectEqualSlices(u8, "huj", l1.nextToken().?.identifier);
    try std.testing.expectEqual(Symbol.assign, l1.nextToken().?.symbol);
    try std.testing.expectEqualSlices(u8, "123", l1.nextToken().?.string_literal);
    try std.testing.expectEqual(Symbol.semicolon, l1.nextToken().?.symbol);
    try std.testing.expectEqualSlices(u8, "lala", l1.nextToken().?.identifier);
    try std.testing.expectEqual(Symbol.assign, l1.nextToken().?.symbol);
    try std.testing.expectEqualSlices(u8, "234", l1.nextToken().?.string_literal);
    try std.testing.expectEqual(Symbol.semicolon, l1.nextToken().?.symbol);
}

test "Separating longer tokens" {
    const t3 = "token";

    var lexer = Lexer.init(t3);

    try std.testing.expectEqualSlices(u8, "token", lexer.nextToken().?.identifier);
}

test "Separating token chains tokens" {
    const sample_content = "{token} tokeninho";

    var lexer = Lexer.init(sample_content);

    try std.testing.expectEqual(Symbol.curly_left, lexer.nextToken().?.symbol);
    try std.testing.expectEqualSlices(u8, "token", lexer.nextToken().?.identifier);
    try std.testing.expectEqual(Symbol.curly_right, lexer.nextToken().?.symbol);
    try std.testing.expectEqualSlices(u8, "tokeninho", lexer.nextToken().?.identifier);
}

test "Parsing keywords" {
    const sample_content = "if else switch";

    var lexer = Lexer.init(sample_content);

    const t1 = lexer.nextToken().?;
    const t2 = lexer.nextToken().?;
    const t3 = lexer.nextToken().?;

    try std.testing.expectEqual(Keyword.if_keyword, t1.keyword);
    try std.testing.expectEqual(Keyword.else_keyword, t2.keyword);
    try std.testing.expectEqual(Keyword.switch_keyword, t3.keyword);
}

test "Unterminated string should set lexer error" {
    const sample_content = "\"Some string content that is not terminated";
    var lexer = Lexer.init(sample_content);

    try std.testing.expectEqual(null, lexer.nextToken());
    try std.testing.expectEqual(LexerError.UnterminatedString, lexer.getError());
}

test "Unknown symbol should set lexer error" {
    const sample_content = "%";
    var lexer = Lexer.init(sample_content);

    try std.testing.expectEqual(null, lexer.nextToken());
    try std.testing.expectEqual(LexerError.UnknownToken, lexer.getError());
}
