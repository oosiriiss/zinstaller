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
};

const symbol_map = std.StaticStringMap(Symbol).initComptime([_]struct { []const u8, Symbol }{
    .{ "{", .curly_left },
    .{ "}", .curly_right },
    .{ "[", .square_left },
    .{ "]", .square_right },
    .{ "=", .assign },
    .{ ";", .semicolon },
    .{ ",", .comma },
});

// This symbol doesn't get matched with other symbols and the rest of the line after it is ignored by the lexer
const COMMENT_SYMBOL = "//";
const LONGEST_SYMBOL_LENGTH = blk: {
    var max: usize = 0;
    for (symbol_map.keys()) |k| {
        if (k.len > max) {
            max = k.len;
        }
    }
    break :blk max;
};

const ParseError = error{
    InvalidSymbol,
    InvalidKeyword,
    UnknownToken,
    UnterminatedString,
    EOF,
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
                if (std.enums.tagName(Symbol, symbol)) |name| {
                    std.debug.print("SYMBOL({s})", .{name});
                } else {
                    std.debug.print("UNKNOWN_SYMBOL({any})", .{symbol});
                }
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

// The lexer doesn't allocate anything all the slices come directly from the source text.
pub const Lexer = struct {
    /// The content that is parsed
    content: []const u8,
    /// Current position inside content
    index: usize,

    const Self = @This();
    pub fn init(content: []const u8) Self {
        return .{
            .content = content,
            .index = 0,
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

    // Returns a slice from self.content that should represent a single token
    pub fn nextToken(self: *Self) ?Token {
        self.skipIgnorable();

        if (self.index >= self.content.len)
            return null;

        if (self.matchSymbol()) |symbol| {
            return Token{ .symbol = symbol };
        } else |_| {}

        const curr_char = self.content[self.index];
        const token = switch (curr_char) {
            '"' => {
                const start_index = self.index;

                if (self.readString()) |str| {
                    return Token{ .string_literal = str };
                } else |err| {
                    if (err == error.UnterminatedString) {
                        // TODO :: Change this to errors bubbling to main
                        std.debug.panic("Unterminated string encountered at index:{d}\n", .{start_index});
                    }
                }
                return null;
            },
            'a'...'z', 'A'...'Z' => {
                const ident = self.readIdentifier();

                if (parseKeyword(ident)) |kw| {
                    return Token{ .keyword = kw };
                } else |_| {
                    //
                    return Token{ .identifier = ident };
                }
            },
            else => {
                std.debug.panic("Unknown token encountered: {c}, int_code: {d}", .{ curr_char, @as(i32, curr_char) });
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
        // TODO :: ????? Implement individual method for each token type like symbol etc. ?????
        const saved_index = self.index;
        const token = self.nextToken();
        self.index = saved_index;
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
                self.index = self.index + current_length;
                return s;
            }

            current_length = current_length - 1;
        }

        return error.InvalidSymbol;
    }

    fn readString(self: *Self) error{UnterminatedString}![]const u8 {
        // Skipping Beggining of string (")

        self.index = self.index + 1;
        const start_pos = self.index;

        while (self.index < self.content.len and self.content[self.index] != '"') {
            self.index = self.index + 1;
        }

        if (self.index >= self.content.len) {
            return error.UnterminatedString;
        }

        // Skipping end of string (")
        self.index = self.index + 1;
        return self.content[start_pos .. self.index - 1];
    }

    fn readIdentifier(self: *Self) []const u8 {
        const start_pos = self.index;

        while (self.index < self.content.len and std.ascii.isAlphanumeric(self.content[self.index]))
            self.index = self.index + 1;

        return self.content[start_pos..self.index];
    }

    fn parseKeyword(str_token: []const u8) ParseError!Keyword {
        if (keyword_map.get(str_token)) |token| {
            return token;
        }

        return ParseError.InvalidKeyword;
    }

    fn isSymbol(str_token: []const u8) bool {
        return str_token.len == 1 and str_token == '{' or str_token == '}';
    }

    fn parseSymbol(str_token: []const u8) ParseError!Symbol {
        // TODO :: Change this function to trust the caller that it's a symbol?
        if (!isSymbol(str_token)) {
            std.log.err("Token: {s} is not a symbol", .{str_token});
            return ParseError.InvalidSymbol;
        }
    }

    // Skips all whitespace and comments
    fn skipIgnorable(self: *Self) void {
        if (self.index >= self.content.len)
            return;

        var curr = self.content[self.index];

        while (std.ascii.isWhitespace(curr) or self.isComment()) {
            self.skipWhitespace();

            self.skipComment();

            if (self.index >= self.content.len)
                break;
            curr = self.content[self.index];
        }
    }

    fn skipWhitespace(self: *Self) void {
        while (self.index < self.content.len and std.ascii.isWhitespace(self.content[self.index])) {
            self.index = self.index + 1;
        }
    }

    fn isComment(self: Self) bool {
        return self.index + COMMENT_SYMBOL.len - 1 < self.content.len and
            std.mem.eql(u8, COMMENT_SYMBOL, self.content[self.index..(self.index + COMMENT_SYMBOL.len)]);
    }

    fn skipComment(self: *Self) void {
        if (self.index + 1 >= self.content.len)
            return;

        if (!self.isComment())
            return;

        // Skipping the comment
        while (self.index < self.content.len and self.content[self.index] != '\n')
            self.index = self.index + 1;

        // Finally skipping the newline
        self.index = self.index + 1;
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
