const std = @import("std");
const assert = std.debug.assert;
const log = @import("logger.zig").getGlobalLogger;

pub const Keyword = enum {
    true,
    false,
};

const keyword_map = std.StaticStringMap(Keyword).initComptime([_]struct { []const u8, Keyword }{
    .{ "true", Keyword.true },
    .{ "false", Keyword.false },
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

const State = struct {
    /// Current position inside content
    index: usize,
    // Line number of current content
    current_line: usize,
    // Column of the
    current_line_char: usize,
};

pub const LexerError = error{ UnknownToken, UnterminatedString, EOF };

// The lexer doesn't allocate anything all the slices come directly from the source text.
pub const Lexer = struct {
    /// The content that is parsed
    content: []const u8,
    state: State,
    last_state: State,
    // Current error or null if everyting is ok
    current_error: ?LexerError,

    const Self = @This();
    pub fn init(content: []const u8) Self {
        return .{
            .content = content,
            .state = .{
                .index = 0,
                .current_line = 1,
                .current_line_char = 1,
            },
            .last_state = .{
                .index = 0,
                .current_line = 1,
                .current_line_char = 1,
            },
            .current_error = null,
        };
    }

    pub fn debugPrint(self: *Self) void {
        const saved_index = self.state.index;
        self.state.index = 0;

        while (self.nextToken()) |token| {
            token.debugPrint();
            std.debug.print(" ", .{});
        }

        self.state.index = saved_index;
    }

    // Returns last encountered error or void if no error was encountered
    // Line number and column can be retrieved with self.current_line and self.current_line_char fields
    pub fn getError(self: Self) LexerError!void {
        if (self.current_error) |err| return err;
    }

    // Tries to parse the token from give content
    // if self.content is finished returns null and self.current_error is LexerError.EOF
    // if an error is encountered self.current_error is set and the function returns null
    // If the token is a string it is only valid until the next time you call Lexer.nextToken()
    pub fn nextToken(self: *Self) ?Token {
        if (self.current_error != null) return null;

        self.skipIgnorable();

        // Saving state to last valid
        self.saveState();

        if (!self.canReadChar()) {
            self.current_error = LexerError.EOF;
            return null;
        }

        if (self.matchSymbol()) |symbol| {
            return Token{ .symbol = symbol };
        } else |_| {}

        const curr_char = self.peekChar();

        const token = switch (curr_char) {
            '"' => {
                if (self.readString()) |str| {
                    return Token{ .string_literal = str };
                } else |err| {
                    self.restoreState();
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
                self.restoreState();
                return null;
            },
        };
        return token;
    }

    pub fn peek(self: *Self) ?Token {
        // self.nextToken() also saves state, but after skipping whitespaces and we dont want that here
        const state = self.state;
        const last_state = self.last_state;

        const token = self.nextToken();

        self.state = state;
        self.last_state = last_state;

        return token;
    }

    pub fn skipToken(self: *Self) void {
        _ = self.nextToken();
    }

    // Returns true if next token is on the new line or EOF
    pub fn isEndOfLine(self: *Self) bool {
        self.saveState();
        self.skipIgnorable();
        const next_line = self.state.current_line;
        const next_index = self.state.index;
        self.restoreState();

        log().debug("current_line: {d} next_line:{d}", .{ self.state.current_line, next_line });

        return self.state.current_line != next_line or (next_index >= self.content.len);
    }

    fn saveState(self: *Self) void {
        log().debug("Saving state index:{d}, line:{d} line_col:{d}", .{ self.state.index, self.state.current_line, self.state.current_line_char });
        self.last_state = self.state;
        log().debug("Saved: index:{d}, line:{d} line_col:{d}", .{ self.last_state.index, self.last_state.current_line, self.last_state.current_line_char });
    }
    fn restoreState(self: *Self) void {
        self.state = self.last_state;
    }

    fn matchSymbol(self: *Self) !Symbol {

        // Matching from longset to shortest
        var current_length: usize = LONGEST_SYMBOL_LENGTH;

        while (current_length > 0) {
            if (self.state.index + current_length - 1 >= self.content.len) {
                current_length = current_length - 1;
                continue;
            }

            const key = self.content[self.state.index..(self.state.index + current_length)];

            if (symbol_map.get(key)) |s| {
                for (0..current_length) |_| _ = self.readChar();
                return s;
            }

            current_length = current_length - 1;
        }

        return error.InvalidSymbol;
    }

    // It reads the content of the string until the next " character
    // '\' is encounterd the next character will be treated as a string content,
    // so for example " will be skipped. No substitution is done for special characters
    // e.g. '\n' is still outputted as 2 separate characters.
    // for '\' use '\\'
    fn readString(self: *Self) error{UnterminatedString}![]const u8 {
        // Skipping Beggining of string (")
        _ = self.readChar();
        const content_start = self.state.index;

        while (self.canReadChar() and self.peekChar() != '"') {
            if (self.readChar() == '\\')
                _ = self.readChar();
        }

        if (!self.canReadChar()) {
            return error.UnterminatedString;
        }

        // Skipping end of string (")
        _ = self.readChar();

        return self.content[content_start..(self.state.index - 1)];
    }

    fn readIdentifier(self: *Self) []const u8 {
        const start_pos = self.state.index;

        while (self.canReadChar() and (std.ascii.isAlphanumeric(self.peekChar()) or self.peekChar() == '_'))
            _ = self.readChar();

        return self.content[start_pos..self.state.index];
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
        return self.state.index < self.content.len;
    }

    fn readChar(self: *Self) u8 {
        const char = self.content[self.state.index];
        self.state.index = self.state.index + 1;

        self.state.current_line_char = self.state.current_line_char + 1;
        if (char == '\n') {
            self.state.current_line = self.state.current_line + 1;
            self.state.current_line_char = 1;
        }

        return char;
    }

    fn peekChar(self: *Self) u8 {
        return self.content[self.state.index];
    }

    fn skipWhitespace(self: *Self) void {
        while (self.canReadChar() and std.ascii.isWhitespace(self.peekChar())) {
            _ = self.readChar();
        }
    }

    fn isComment(self: Self) bool {
        // This symbol doesn't get matched with other symbols and the rest of the line after it is ignored by the lexer
        const COMMENT_SYMBOL = "//";
        return self.state.index + COMMENT_SYMBOL.len - 1 < self.content.len and
            std.mem.eql(u8, COMMENT_SYMBOL, self.content[self.state.index..(self.state.index + COMMENT_SYMBOL.len)]);
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

////////////////////////////////////////////
////////////////////////////////////////////
///////////////// TESTS ////////////////////
////////////////////////////////////////////
////////////////////////////////////////////

const testing = std.testing;

test "Separating single-char symbols" {
    const sample_content = "{}";

    var lexer = Lexer.init(sample_content);

    try testing.expectEqual(Symbol.curly_left, lexer.nextToken().?.symbol);
    try testing.expectEqual(Symbol.curly_right, lexer.nextToken().?.symbol);
}

test "Skipping comments" {
    const sample_content =
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

    var lexer = Lexer.init(sample_content);

    try testing.expectEqualSlices(u8, "huj", lexer.nextToken().?.identifier);
    try testing.expectEqual(Symbol.assign, lexer.nextToken().?.symbol);
    try testing.expectEqualSlices(u8, "123", lexer.nextToken().?.string_literal);
    try testing.expectEqual(Symbol.semicolon, lexer.nextToken().?.symbol);
    try testing.expectEqualSlices(u8, "lala", lexer.nextToken().?.identifier);
    try testing.expectEqual(Symbol.assign, lexer.nextToken().?.symbol);
    try testing.expectEqualSlices(u8, "234", lexer.nextToken().?.string_literal);
    try testing.expectEqual(Symbol.semicolon, lexer.nextToken().?.symbol);
}

test "Separating longer tokens" {
    const sample_content = "token";

    var lexer = Lexer.init(sample_content);

    try testing.expectEqualSlices(u8, "token", lexer.nextToken().?.identifier);
}

test "Separating token chains tokens" {
    const sample_content = "{token} tokeninho";

    var lexer = Lexer.init(sample_content);

    try testing.expectEqual(Symbol.curly_left, lexer.nextToken().?.symbol);
    try testing.expectEqualSlices(u8, "token", lexer.nextToken().?.identifier);
    try testing.expectEqual(Symbol.curly_right, lexer.nextToken().?.symbol);
    try testing.expectEqualSlices(u8, "tokeninho", lexer.nextToken().?.identifier);
}

test "Parsing keywords" {
    const sample_content = "true false";

    var lexer = Lexer.init(sample_content);

    const t1 = lexer.nextToken().?;
    const t2 = lexer.nextToken().?;

    try testing.expectEqual(Keyword.true, t1.keyword);
    try testing.expectEqual(Keyword.false, t2.keyword);
}

test "Unterminated string should set lexer error" {
    const sample_content = "\"Some string content that is not terminated";
    var lexer = Lexer.init(sample_content);

    try testing.expectEqual(null, lexer.nextToken());
    try testing.expectEqual(LexerError.UnterminatedString, lexer.getError());
}

test "Unknown symbol should set lexer error" {
    const sample_content = "%";
    var lexer = Lexer.init(sample_content);

    try testing.expectEqual(null, lexer.nextToken());
    try testing.expectEqual(LexerError.UnknownToken, lexer.getError());
}

test "Backslash allows to treat next character as normal char" {
    const sample_content = " \" String\\\" \" ";
    var lexer = Lexer.init(sample_content);

    try testing.expectEqualSlices(u8, " String\\\" ", lexer.nextToken().?.string_literal);
}

test "Skipping ending \" should return unterminated error " {
    const sample_content = " \" String \\\"  ";
    var lexer = Lexer.init(sample_content);

    try testing.expectEqual(null, lexer.nextToken());
    try testing.expectEqual(LexerError.UnterminatedString, lexer.getError());
}

test "Saving and restoring state works" {
    const content =
        \\a
        \\"Line 1"
        \\"Line 2"
        \\ assign = "Hello";;; 
        \\"Line 3"
    ;

    var lexer = Lexer.init(content);
    try testing.expectEqual(0, lexer.state.index);
    try testing.expectEqual(1, lexer.state.current_line);
    try testing.expectEqual(1, lexer.state.current_line_char);
    lexer.skipToken();
    lexer.skipWhitespace();
    try testing.expectEqual(2, lexer.state.index);
    try testing.expectEqual(2, lexer.state.current_line);
    try testing.expectEqual(1, lexer.state.current_line_char);
    lexer.restoreState();
    try testing.expectEqual(0, lexer.state.index);
    try testing.expectEqual(1, lexer.state.current_line);
    try testing.expectEqual(1, lexer.state.current_line_char);
}

test "Lexer returns to previous valid state after encountering error " {
    const unterminated_string = " \" some string \\\" ";
    const unknown_tokens = "identifier = \"ValidString\" : ` ";

    var lexer = Lexer.init(unterminated_string);

    try testing.expectEqual(null, lexer.nextToken());
    try testing.expectEqual(LexerError.UnterminatedString, lexer.getError());
    try testing.expectEqual(1, lexer.state.index);

    lexer = Lexer.init(unknown_tokens);

    try testing.expectEqualSlices(u8, "identifier", lexer.nextToken().?.identifier);
    try testing.expectEqual(Symbol.assign, lexer.nextToken().?.symbol);
    try testing.expectEqualSlices(u8, "ValidString", lexer.nextToken().?.string_literal);
    try testing.expectEqual(null, lexer.nextToken());
    try testing.expectEqual(LexerError.UnknownToken, lexer.getError());
    try testing.expectEqual(27, lexer.state.index);
}

test "Lexer correctly detects end of line" {
    const multiline =
        \\
        \\ "this is line first"
        \\ "Next" "Not end of line"
    ;
    const eof = " ident ";

    var lexer = Lexer.init(multiline);

    try testing.expectEqual(0, lexer.state.index);
    try testing.expectEqual(1, lexer.state.current_line);
    try testing.expectEqual(1, lexer.state.current_line_char);
    try testing.expect(lexer.isEndOfLine());
    try testing.expectEqualSlices(u8, "this is line first", lexer.nextToken().?.string_literal);
    try testing.expect(lexer.isEndOfLine());
    try testing.expectEqualSlices(u8, "Next", lexer.nextToken().?.string_literal);
    try testing.expect(!lexer.isEndOfLine());

    lexer = Lexer.init(eof);

    try testing.expectEqualSlices(u8, "ident", lexer.nextToken().?.identifier);
    try testing.expect(lexer.isEndOfLine());
}
