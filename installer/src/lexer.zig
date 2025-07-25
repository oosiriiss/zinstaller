const std = @import("std");
const assert = std.debug.assert;

pub const Symbol = enum {
    curly_left,
    curly_right,
    square_left,
    square_right,
    equal,
    colon,
    semicolon,
    // for nicer printing
    new_line,
};

const ParseError = error{
    InvalidSymbol,
    InvalidKeyword,
    UnknownToken,
    UnterminatedString,
    EOF,
};

// Accepts custom Kewyord enums and only enums that will be produced by the lexer
pub fn Token(comptime KEYWORDS: type) type {
    // TODO ::  Allow only enums?

    return union(enum) {
        identifier: []const u8,
        symbol: Symbol,
        keyword: KEYWORDS,
        string_literal: []const u8,

        const Self = @This();

        pub fn debugPrint(self: Self) void {
            switch (self) {
                .identifier => |ident| {
                    std.debug.print("IDENTIFIER({s})", .{ident});
                },
                .symbol => |symbol| {
                    if (symbol == Symbol.new_line) {
                        std.debug.print("\n", .{});
                        return;
                    }

                    if (std.enums.tagName(Symbol, symbol)) |name| {
                        std.debug.print("SYMBOL({s})", .{name});
                    } else {
                        std.debug.print("UNKNOWN_SYMBOL({})", .{symbol});
                    }
                },
                .keyword => |kw| {
                    if (std.enums.tagName(KEYWORDS, kw)) |name| {
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
}

pub fn Lexer(comptime KEYWORDS: type) type {
    const TokenType = comptime Token(KEYWORDS);

    return comptime struct {
        /// The content that is parsed
        content: []const u8,
        /// Current position inside content
        index: usize,
        alloc: std.mem.Allocator,
        keyword_map: std.StaticStringMap(KEYWORDS),
        allow_whitespace_tokens: bool,

        const Self = @This();

        /// content must be valid as long as lexer lives
        pub fn init(content: []const u8, alloc: std.mem.Allocator, keyword_map: std.StaticStringMap(KEYWORDS)) Self {
            return .{
                .content = content,
                .index = 0,
                .alloc = alloc,
                .keyword_map = keyword_map,
                .allow_whitespace_tokens = false,
            };
        }

        pub fn debugPrint(self: *Self) !void {
            const saved_index = self.index;
            const saved_ws = self.allow_whitespace_tokens;

            self.allow_whitespace_tokens = true;
            self.index = 0;

            while (self.nextToken()) |token| {
                token.debugPrint();
                std.debug.print(" ", .{});
            }
            self.index = saved_index;
            self.allow_whitespace_tokens = saved_ws;
        }

        // Returns a slice from self.content that should represent a single token
        // Retuirns also newlines
        pub fn nextToken(self: *Self) ?TokenType {
            // Todo :: Add whitespace indent handling
            self.skipWhitespace();

            if (self.index >= self.content.len)
                return null;

            const curr_char = self.content[self.index];

            const token = switch (curr_char) {
                '{' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.curly_left };
                },
                '}' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.curly_right };
                },
                '[' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.square_left };
                },
                ']' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.square_right };
                },
                '=' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.equal };
                },
                '\n' => {
                    self.index = self.index + 1;
                    // TODO :: :)
                    if (self.allow_whitespace_tokens)
                        return TokenType{ .symbol = Symbol.new_line }
                    else
                        return null;
                },
                ':' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.colon };
                },
                ';' => {
                    self.index = self.index + 1;
                    return TokenType{ .symbol = Symbol.semicolon };
                },
                '"' => {
                    const start_index = self.index;

                    if (self.readString()) |str| {
                        return TokenType{ .string_literal = str };
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
                    if (parseKeyword(ident, self.keyword_map)) |kw| {
                        return TokenType{ .keyword = kw };
                    } else |_| {
                        //
                        return TokenType{ .identifier = ident };
                    }
                },
                else => {
                    std.debug.panic("Unknown token encountered: {c}, int_code: {d}", .{ curr_char, @as(i32, curr_char) });
                    return null;
                },
            };
            return token;
        }

        //  Advances to the next token and return it if it is the given symbol {symbol} or else returns null
        pub fn assertSymbol(self: *Self, symbol: Symbol) ?Symbol {
            const token = self.nextToken() orelse return null;
            if (token != .symbol) return null;
            if (token.symbol != symbol) return null;
            return symbol;
        }
        pub fn peekSymbol(self: *Self) ?Symbol {
            const saved_index = self.index;
            const token = self.nextToken();
            self.index = saved_index;

            if (token != null and token.? == .symbol) {
                return token.?.symbol;
            }
            return null;
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

        fn parseKeyword(str_token: []const u8, kw_map: std.StaticStringMap(KEYWORDS)) ParseError!KEYWORDS {
            if (kw_map.get(str_token)) |token| {
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

        // Skips all whitespace if allow_whitespace_tokens is false
        // if allow_whitespace_tokens is true it will skip all spaces etc. and still allow for indents and newlines
        fn skipWhitespace(self: *Self) void {
            // TODO :: Add indents
            while (self.index < self.content.len){
                if (self.allow_whitespace_tokens and self.content[self.index] == '\n')
                    break
                else if (std.ascii.isWhitespace(self.content[self.index]))
                    self.index = self.index + 1
                else
                    break;
            }
        }

        fn skipWhitespaceTokens(self: *Self) void {
            var fallback_index = self.index;

            while (self.nextTokenWithWhitespace()) |token| {
                if (token == .symbol and (token.symbol == Symbol.new_line)) {
                    fallback_index = self.index;
                    continue;
                }
                // "Unreading" a token if it is a valid one (nonwhitespace)
                self.index = fallback_index;
                return;
            }
        }
    };
}

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

test "Separating symbols" {
    const t1 = "{";
    const t2 = "}";

    var l1 = Lexer(TestKeywords).init(t1, std.heap.page_allocator, test_keyword_map);
    var l2 = Lexer(TestKeywords).init(t2, std.heap.page_allocator, test_keyword_map);

    const a1 = l1.nextToken().?;
    const a2 = l2.nextToken().?;

    try std.testing.expectEqual(Symbol.curly_left, a1.symbol);
    try std.testing.expectEqual(Symbol.curly_right, a2.symbol);
}

test "Separating longer tokens" {
    const t3 = "token";

    var l3 = Lexer(TestKeywords).init(t3, std.heap.page_allocator, test_keyword_map);

    const a3 = l3.nextToken().?;

    try std.testing.expectEqualSlices(u8, "token", a3.identifier);
}

test "Separating token chains tokens" {
    const sample_content = "{token} tokeninho";

    var lexer = Lexer(TestKeywords).init(sample_content, std.heap.page_allocator, test_keyword_map);

    const t1 = lexer.nextToken().?;
    const t2 = lexer.nextToken().?;
    const t3 = lexer.nextToken().?;
    const t4 = lexer.nextToken().?;

    try std.testing.expectEqual(Symbol.curly_left, t1.symbol);
    try std.testing.expectEqualSlices(u8, "token", t2.identifier);
    try std.testing.expectEqual(Symbol.curly_right, t3.symbol);
    try std.testing.expectEqualSlices(u8, "tokeninho", t4.identifier);
}
