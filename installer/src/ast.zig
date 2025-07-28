const std = @import("std");
const lxr = @import("lexer.zig");
const util = @import("util.zig");

// As of the current state basically just a pack of variables or essentially a named scope
pub const Object = struct {
    name: []const u8,
    // Array better for smaller scopes? idk
    fields: std.StringHashMap(Value),
};

// better name would be expression or statement idk its enough for now
pub const Value = union(enum) {
    string: []const u8,
    list: []Value,
    object: Object,

    const Self = @This();

    pub fn debugPrint(self: Self) void {
        var printer = util.IndentPrinter{ .indent = 0, .writer = std.io.getStdErr().writer().any() };
        self.debugPrintHelper(&printer);
    }
    fn debugPrintHelper(self: Self, printer: *util.IndentPrinter) void {

        // TODO :: fix this :)
        switch (self) {
            .object => |o| {
                printer.printSilent("Object: {s}\n", .{o.name});
                var it = o.fields.iterator();

                printer.increase();
                while (it.next()) |f| {
                    printer.printSilent("{s} = \n", .{f.key_ptr.*});
                    printer.increase();
                    f.value_ptr.debugPrintHelper(printer);
                    printer.decrease();
                }
                printer.decrease();
            },
            .list => |l| {
                printer.printSilent("List: [\n", .{});
                printer.increase();
                for (l) |val| {
                    val.debugPrintHelper(printer);
                }
                printer.decrease();
                printer.printSilent("]\n", .{});
            },
            .string => |str| {
                printer.printSilent("\"{s}\"\n", .{str});
            },
        }
    }
};
pub const Entry = struct {
    key: []const u8,
    value: Value,
};

pub const ParseError = error{ AssignmentIdentifierMissing, AssignmentInvalidValue, AssignmentValueMissing, ObjectDuplicateField, SyntaxError, InvalidValue };

pub fn AST(comptime KEYWORDS: type) type {
    return comptime struct {
        lexer: *lxr.Lexer(KEYWORDS),
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(lexer: *lxr.Lexer(KEYWORDS), allocator: std.mem.Allocator) Self {
            return .{ .lexer = lexer, .allocator = allocator };
        }
        pub fn build(self: *Self) ![]Value {
            // root object may be only a list
            self.lexer.assertSymbol(.square_left) catch return ParseError.SyntaxError;

            return (try self.parseValue()).list;
        }

        //  As of now array of different type values is acceptable
        fn parseArray(self: *Self) (ParseError || std.mem.Allocator.Error)![]Value {
            self.lexer.assertSymbol(.square_left) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            var items = std.ArrayList(Value).init(self.allocator);
            // Deinit isn't needed since we turn the arraylist to owned slice at the end but it doesn't do anything wrong :)
            defer items.deinit();

            while (self.lexer.peek()) |token| {
                if (token == .symbol) {
                    if (token.symbol == .square_right)
                        break
                    else if (token.symbol == .comma) {
                        self.lexer.skipToken();
                        continue;
                    }
                }

                const value = try self.parseValue();

                try items.append(value);
            }

            self.lexer.assertSymbol(.square_right) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            return try items.toOwnedSlice();
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

            self.lexer.assertSymbol(.assign) catch return ParseError.SyntaxError;
            self.lexer.skipToken();

            const value = try self.parseValue();
            return Entry{ .key = try self.allocator.dupe(u8, identifier), .value = value };
        }
        fn parseValue(self: *Self) !Value {
            const value_token = self.lexer.peek() orelse return ParseError.SyntaxError;

            switch (value_token) {
                .string_literal => |str| {
                    self.lexer.skipToken();
                    return Value{ .string = try self.allocator.dupe(u8, str) };
                },
                .identifier => |ident| {
                    self.lexer.skipToken();

                    if (self.lexer.assertSymbol(.curly_left)) {
                        // Object
                        return Value{ .object = try self.parseObject(ident) };
                    } else |_| {
                        // Variable assignemnt
                        std.debug.panic("Assignment to identifiers not implemented\n", .{});
                    }
                },
                .symbol => |s| {
                    if (s == .square_left) return Value{ .list = try self.parseArray() };

                    return ParseError.SyntaxError;
                },
                else => {
                    std.debug.print("Invalid value token when parsing: {any}\n", .{value_token});
                    return ParseError.InvalidValue;
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
}

test "Parsing list of strings" {
    const t1 =
        \\ [ "first","second","third" ];
    ;

    var l1 = lxr.Lexer(TestKeywords).init(t1, std.heap.page_allocator, test_keyword_map);
    var ast = AST(TestKeywords).init(&l1, std.heap.page_allocator);
    const e = try ast.parseArray();

    try std.testing.expectEqual(3, e.len);
    try std.testing.expectEqualSlices(u8, "first", e[0].string);
    try std.testing.expectEqualSlices(u8, "second", e[1].string);
    try std.testing.expectEqualSlices(u8, "third", e[2].string);
}

test "Parsing list of strings assignment" {
    const t1 =
        \\ huj = [ "first","second","third" ];
    ;

    var l1 = lxr.Lexer(TestKeywords).init(t1, std.heap.page_allocator, test_keyword_map);
    var ast = AST(TestKeywords).init(&l1, std.heap.page_allocator);
    const e = try ast.parseAssignment();

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expect(e.value == .list);
    try std.testing.expectEqualSlices(u8, "first", e.value.list[0].string);
    try std.testing.expectEqualSlices(u8, "second", e.value.list[1].string);
    try std.testing.expectEqualSlices(u8, "third", e.value.list[2].string);
}
