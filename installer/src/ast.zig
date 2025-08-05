const std = @import("std");
const lxr = @import("lexer.zig");
const util = @import("util.zig");

// As of the current state basically just a pack of variables or essentially a named scope
pub const Object = struct {
    name: []const u8,
    // Array better for smaller scopes? idk
    fields: std.StringHashMap(Value),

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);

        // Freeing the keys and values
        var it = self.fields.iterator();
        while (it.next()) |field| {
            allocator.free(field.key_ptr.*);
            field.value_ptr.deinit(allocator);
        }

        // Freeing the array
        self.fields.deinit();
    }
};

// better name would be expression or statement idk its enough for now
//
// It should own the memory of the fields.
//
pub const Value = union(enum) {
    string: []const u8,
    list: []Value,
    object: Object,

    const Self = @This();

    // Frees this element and all of the subelements
    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .object => |*o| o.deinit(alloc),
            .list => |*l| {
                for (l.*) |*val| val.deinit(alloc);
                alloc.free(l.*);
                l.* = undefined;
            },
            .string => |str| alloc.free(str),
        }
    }

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
                    printer.printSilent("{s}\n", .{f.key_ptr.*});
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
    // asserts that it is instance of a string and returns it's copy.
    pub fn copyString(self: Self, alloc: std.mem.Allocator) ![]const u8 {
        if (self != .string) return error.NotAString;
        return try alloc.dupe(u8, self.string);
    }
};
pub const Entry = struct {
    key: []const u8,
    value: Value,

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        alloc.free(self.key);
        self.value.deinit(alloc);
    }
};

const AbstractSyntaxTree = struct {
    root: Value,
    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.root.deinit(self.alloc);
    }
};

pub const ParseError = error{ AssignmentIdentifierMissing, AssignmentInvalidValue, AssignmentValueMissing, ObjectDuplicateField, SyntaxError, InvalidValue };
pub const Parser = struct {
    lexer: *lxr.Lexer,
    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn init(lexer: *lxr.Lexer, allocator: std.mem.Allocator) Self {
        return .{ .lexer = lexer, .alloc = allocator };
    }

    pub fn build(self: *Self) !AbstractSyntaxTree {
        return .{ .root = try self.parseValue(), .alloc = self.alloc };
    }

    //  As of now array of different type values is acceptable
    fn parseArray(self: *Self) (ParseError || std.mem.Allocator.Error)![]Value {
        try self.expectSymbol(.square_left);

        var items = std.ArrayList(Value).init(self.alloc);
        errdefer items.deinit();

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
        try self.expectSymbol(.square_right);
        return try items.toOwnedSlice();
    }

    // Copies the identifier into the object name field
    fn parseObject(self: *Self, identifier: []const u8) (ParseError || std.mem.Allocator.Error)!Object {
        try self.expectSymbol(.curly_left);

        var object = Object{ .name = try self.alloc.dupe(u8, identifier), .fields = std.StringHashMap(Value).init(self.alloc) };
        errdefer object.deinit(self.alloc);

        while (self.lexer.peek()) |token| {
            if (token == .symbol and token.symbol == .curly_right)
                break;

            const entry = try self.parseAssignment();

            try self.expectSymbol(.semicolon);

            object.fields.putNoClobber(entry.key, entry.value) catch return ParseError.ObjectDuplicateField;
        }

        try self.expectSymbol(.curly_right);

        return object;
    }
    // Parses just 3 tokenes (NAME, '=', VALUE), doesn't skip the semicolon.
    fn parseAssignment(self: *Self) (ParseError || std.mem.Allocator.Error)!Entry {

        // any identifier is ok
        self.lexer.assertIdentifier() catch return ParseError.AssignmentIdentifierMissing;

        const ident_token = self.lexer.nextToken() orelse return ParseError.AssignmentIdentifierMissing;

        try self.expectSymbol(.assign);

        const ident = try self.alloc.dupe(u8, ident_token.identifier);
        errdefer self.alloc.free(ident);
        const value = try self.parseValue();

        return Entry{
            .key = ident,
            .value = value,
        };
    }
    fn parseValue(self: *Self) !Value {
        const value_token = self.lexer.peek() orelse return ParseError.SyntaxError;

        switch (value_token) {
            .string_literal => |str| {
                self.lexer.skipToken();
                return handleStringLiteral(str, self.alloc);
            },
            .identifier => |ident| {
                // Skipping identifier
                self.lexer.skipToken();

                if (self.parseObject(ident)) |object| {
                    return Value{ .object = object };
                } else |_| {
                    std.debug.panic("Assignment to identifiers not implemented\n", .{});
                }
            },
            .symbol => |s| {
                if (s == .square_left)
                    return Value{ .list = try self.parseArray() };
                return ParseError.SyntaxError;
            },
            else => {
                std.debug.print("Invalid value token when parsing: {any}\n", .{value_token});
                return ParseError.InvalidValue;
            },
        }
    }
    fn expectSymbol(self: *Self, symbol: lxr.Symbol) ParseError!void {
        const token = self.lexer.nextToken();
        if (token != null and token.? == .symbol and token.?.symbol == symbol) return;

        std.log.err("Line {d}:{d} (Error:{any})| Expected symbol {s} but got {any}", .{ self.lexer.current_line, self.lexer.current_line_char, self.lexer.getError(), symbol.toString(), token });
        return ParseError.SyntaxError;
    }

    // handles special characters in strings
    fn handleStringLiteral(str: []const u8, alloc: std.mem.Allocator) (std.mem.Allocator.Error)!Value {
        var parsed = std.ArrayList(u8).init(alloc);
        defer parsed.deinit();

        var i: usize = 0;
        while (i < str.len) : (i += 1) {
            const c = str[i];
            if (c == '\\' and i < str.len - 1) {
                const special = createSpecialChar(str[i + 1]);
                try parsed.append(special);
                // skipping the special char
                i = i + 1;
            } else {
                try parsed.append(c);
            }
        }

        return Value{
            .string = try parsed.toOwnedSlice(),
        };
    }

    // if the previouscharacter was a \ in
    // if the character is an unkown special character just the input character is returned.
    fn createSpecialChar(c: u8) u8 {
        return switch (c) {
            'n' => '\n',
            'r' => '\r',
            '0' => 0,
            else => c,
        };
    }
};

test "Parsing string assignment" {
    const content =
        \\ huj = "Hello"; 
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, std.testing.allocator);

    var e = try ast.parseAssignment();
    defer e.deinit(ast.alloc);

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expectEqualSlices(u8, "Hello", e.value.string);
}

test "Parsing empty object assignment" {
    const content =
        \\ huj = testobject {};
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, std.testing.allocator);

    var e = try ast.parseAssignment();
    defer e.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expect(e.value == .object);
    try std.testing.expectEqualSlices(u8, "testobject", e.value.object.name);
}

test "Parsing object with fields assignment" {
    const content =
        \\ huj = testobject { one = "one"; two = "two";};
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, std.testing.allocator);

    var e = try ast.parseAssignment();
    defer e.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expect(e.value == .object);
    try std.testing.expectEqualSlices(u8, "testobject", e.value.object.name);
    try std.testing.expect(e.value.object.fields.count() == 2);
    try std.testing.expectEqualSlices(u8, "one", e.value.object.fields.get("one").?.string);
    try std.testing.expectEqualSlices(u8, "two", e.value.object.fields.get("two").?.string);
}

test "Parsing list of strings" {
    const content =
        \\ [ "first","second","third" ];
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, std.testing.allocator);

    const e = try ast.parseArray();
    defer {
        for (e) |*v| {
            v.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(e);
    }

    try std.testing.expectEqual(3, e.len);
    try std.testing.expectEqualSlices(u8, "first", e[0].string);
    try std.testing.expectEqualSlices(u8, "second", e[1].string);
    try std.testing.expectEqualSlices(u8, "third", e[2].string);
}

test "Parsing list of strings assignment" {
    const content =
        \\ huj = [ "first","second","third" ];
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, std.testing.allocator);

    var e = try ast.parseAssignment();
    defer e.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, "huj", e.key);
    try std.testing.expect(e.value == .list);
    try std.testing.expectEqualSlices(u8, "first", e.value.list[0].string);
    try std.testing.expectEqualSlices(u8, "second", e.value.list[1].string);
    try std.testing.expectEqualSlices(u8, "third", e.value.list[2].string);
}

test "Parsing special characters in strings" {
    const content = "\\n\\\"\\r\\0";

    var str = try Parser.handleStringLiteral(content, std.testing.allocator);
    defer str.deinit(std.testing.allocator);

    try std.testing.expectEqual('\n', str.string[0]);
    try std.testing.expectEqual('"', str.string[1]);
    try std.testing.expectEqual('\r', str.string[2]);
    try std.testing.expectEqual(0, str.string[3]);
}
