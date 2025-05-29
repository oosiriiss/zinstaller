const std = @import("std");
const assert = std.debug.assert;

const Symbol = enum {
    curly_left,
    curly_right,
    equal,
    colon;
    semicolon,
    // for nicer printing
    new_line,
};

const Keyword = enum {
    if_keyword,
    else_keyword,
    switch_keyword,
};

const kw_map = std.StaticStringMap(Keyword).initComptime([_]struct { []const u8, Keyword }{
    .{ "if", Keyword.if_keyword },
    .{ "else", Keyword.else_keyword },
    .{ "switch", Keyword.switch_keyword },
});

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

    pub fn debugPrint(self: Self) !void {
        switch (self) {
            .identifier => |ident| {
                std.debug.print("IDENTIFIER({s})", .{ident});
            },
            .symbol => |symbol| {
                if (std.enums.tagName(Symbol, symbol)) |name| {
                    std.debug.print("SYMBOL({s})", .{name});
                } else {
                    std.debug.print("UNKNOWN_SYMBOL", .{});
                }

                if (symbol == Symbol.new_line) {
                    std.debug.print("\n", .{});
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

pub const Lexer = struct {
    /// The content that is parsed
    content: []const u8,
    /// Current position inside content
    index: usize,
    alloc: std.mem.Allocator,

    const Self = @This();

    /// content must be valid as long as
    pub fn init(content: []const u8, alloc: std.mem.Allocator) !Lexer {
        return .{ .content = content, .index = 0, .alloc = alloc };
    }

    // Returns a slice from self.content that should represent a single token
    pub fn nextToken(self: *Self) ?Token {
        self.skipWhitespace();

        if (self.index >= self.content.len)
            return null;

        const curr_char = self.content[self.index];

        const token = switch (curr_char) {
            '{' => {
                self.index = self.index + 1;
                return Token{ .symbol = Symbol.curly_left };
            },
            '}' => {
                self.index = self.index + 1;
                return Token{ .symbol = Symbol.curly_right };
            },
            '=' => {
                self.index = self.index + 1;
                return Token{ .symbol = Symbol.equal };
            },
            '\n' => {
                self.index = self.index + 1;
                return Token{ .symbol = Symbol.new_line };
            },
            ':' => {
                self.index = self.index + 1;
                return Token {.symbol = Symbol.colon};
            },
            ';' => {
                self.index = self.index + 1;
                return Token {.symbol = Symbol.semicolon};
            }
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

                // Checking if identifier is a keyword
                if (parseKeyword(ident)) |keyword| {
                    return Token{ .keyword = keyword };
                } else |_| {
                    //
                }
                return Token{ .identifier = ident };
            },
            else => {
                std.debug.panic("Unknown token encountered: {c}, int_code: {d}", .{ curr_char, @as(i32, curr_char) });
                return null;
            },
        };
        return token;
    }

    fn readString(self: *Self) error{UnterminatedString}![]const u8 {
        // Skipping Beggining of string (")

        self.index = self.index + 1;
        const start_pos = self.index 

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

    // Moves the index to the next non-whitespace character
    fn skipWhitespace(self: *Self) void {
        while (self.index < self.content.len and std.ascii.isWhitespace(self.content[self.index])
        // allow newlines for printing purposes
        and self.content[self.index] != '\n')
            self.index = self.index + 1;
    }
};

test "Separating symbols" {
    const t1 = "{";
    const t2 = "}";

    var l1 = try Lexer.init(t1, std.heap.page_allocator);
    var l2 = try Lexer.init(t2, std.heap.page_allocator);

    const a1 = try l1.nextToken();
    const a2 = try l2.nextToken();

    try std.testing.expectEqual(Symbol.curly_left, a1.symbol);
    try std.testing.expectEqual(Symbol.curly_right, a2.symbol);
}

test "Separating longer tokens" {
    const t3 = "token";

    var l3 = try Lexer.init(t3, std.heap.page_allocator);

    const a3 = try l3.nextToken();

    try std.testing.expectEqualSlices(u8, "token", a3.identifier);
}

test "Separating token chains tokens" {
    const sample_content = "{token} tokeninho";

    var lexer = try Lexer.init(sample_content, std.heap.page_allocator);

    const t1 = try lexer.nextToken();
    const t2 = try lexer.nextToken();
    const t3 = try lexer.nextToken();
    const t4 = try lexer.nextToken();

    try std.testing.expectEqual(Symbol.curly_left, t1.symbol);
    try std.testing.expectEqualSlices(u8, "token", t2.identifier);
    try std.testing.expectEqual(Symbol.curly_right, t3.symbol);
    try std.testing.expectEqualSlices(u8, "tokeninho", t4.identifier);
}
