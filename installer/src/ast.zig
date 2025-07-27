const std = @import("std");
const lxr = @import("lexer.zig");

// As of the current state basically just a pack of variables
pub const Object = struct {
    name: []const u8,
    // Array better for smaller scopes? idk
    fields: std.StringHashMap(Value),
};

pub const Value = union(enum) {
    string: []const u8,
    list: []Value,
    object: Object,
};
pub const Entry = struct {
    key: []const u8,
    value: Value,
};

pub const ParseError = error{ AssignmentIdentifierMissing, AssignmentInvalidValue, AssignmentValueMissing, ObjectDuplicateField, SyntaxError };

pub fn AST(comptime KEYWORDS: type) type {
    return comptime struct {
        lexer: *lxr.Lexer(KEYWORDS),
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(lexer: *lxr.Lexer(KEYWORDS), allocator: std.mem.Allocator) Self {
            return .{ .lexer = lexer, .allocator = allocator };
        }
        pub fn build(self: *Self) ![]Object {
            // root object may be only a list
            self.lexer.assertSymbol(.square_left) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            self.lexer.assertSymbol(.square_right) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            return error.EOF;
        }

        // Copies the identifier into the object name field
        fn parseObject(self: *Self, identifier: []const u8) (ParseError || std.mem.Allocator.Error)!Object {
            self.lexer.assertSymbol(.curly_left) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            var object = Object{ .name = try self.allocator.dupe(u8, identifier), .fields = std.StringHashMap(Value).init(self.allocator) };

            while (self.lexer.peek()) |token| {
                if (token == .symbol and token.symbol == .curly_right)
                    break;

                const entry = try self.parseAssignment();
                self.lexer.assertSymbol(.semicolon) catch return ParseError.SyntaxError;
                self.lexer.skipToken();

                object.fields.putNoClobber(entry.key, entry.value) catch return ParseError.ObjectDuplicateField;
            }

            self.lexer.assertSymbol(.curly_right) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            return object;
        }
        // Parses just 3 tokenes (NAME, '=', VALUE), doesn't skip the semicolon.
        fn parseAssignment(self: *Self) (ParseError || std.mem.Allocator.Error)!Entry {

            // any identifier is ok
            self.lexer.assertIdentifier() catch return ParseError.AssignmentIdentifierMissing;

            const ident_token = self.lexer.nextToken() orelse return ParseError.AssignmentIdentifierMissing;
            const identifier = ident_token.identifier;

            self.lexer.assertSymbol(.equal) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            const value_token = self.lexer.nextToken() orelse return ParseError.AssignmentValueMissing;
            const value = try self.parseValue(value_token);
            return Entry{ .key = try self.allocator.dupe(u8, identifier), .value = value };
        }
        fn parseValue(self: *Self, value_token: lxr.Token(KEYWORDS)) !Value {
            switch (value_token) {
                .string_literal => |str| return Value{ .string = try self.allocator.dupe(u8, str) },
                .identifier => |ident| {
                    if (self.lexer.assertSymbol(.curly_left)) {
                        // Object
                        return Value{ .object = try self.parseObject(ident) };
                    } else |_| {
                        // Variable assignemnt
                        std.debug.panic("Assignment to identifiers not implemented\n", .{});
                    }
                },
                else => {
                    return ParseError.AssignmentInvalidValue;
                },
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

test "Parsing string assignment" {
    const t1 =
        \\ huj = "Hello"; 
    ;

    var l1 = lxr.Lexer(TestKeywords).init(t1, std.heap.page_allocator, test_keyword_map);
    var ast = AST(TestKeywords).init(&l1, std.heap.page_allocator);
    const e = try ast.parseAssignment();

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expectEqualSlices(u8, "Hello", e.value.string);

    std.debug.print("Parsed assignemnt name={s} value={any}\n", .{ e.key, e.value });
}

test "Parsing empty object assignment" {
    const t1 =
        \\ huj = testobject {};
    ;

    var l1 = lxr.Lexer(TestKeywords).init(t1, std.heap.page_allocator, test_keyword_map);
    var ast = AST(TestKeywords).init(&l1, std.heap.page_allocator);
    const e = try ast.parseAssignment();

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expect(e.value == .object);
    try std.testing.expectEqualSlices(u8, "testobject", e.value.object.name);

    std.debug.print("Parsed object name={s} value={any}\n", .{ e.key, e.value });
}

test "Parsing object with fields assignment" {
    const t1 =
        \\ huj = testobject { one = "one"; two = "two";};
    ;

    var l1 = lxr.Lexer(TestKeywords).init(t1, std.heap.page_allocator, test_keyword_map);
    var ast = AST(TestKeywords).init(&l1, std.heap.page_allocator);
    const e = try ast.parseAssignment();

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expect(e.value == .object);
    try std.testing.expectEqualSlices(u8, "testobject", e.value.object.name);
    try std.testing.expect(e.value.object.fields.count() == 2);
    try std.testing.expectEqualSlices(u8, "one", e.value.object.fields.get("one").?.string);
    try std.testing.expectEqualSlices(u8, "two", e.value.object.fields.get("two").?.string);

    std.debug.print("Parsed object name={s} value={any}\n", .{ e.key, e.value });
}
