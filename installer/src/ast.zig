const std = @import("std");
const lxr = @import("lexer.zig");
const util = @import("util.zig");
const log = @import("logger.zig").getGlobalLogger;

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

        log().debug("Parsing object: {s}", .{object.name});

        while (self.lexer.peek()) |token| {
            if (token == .symbol and token.symbol == .curly_right)
                break;

            const entry = try self.parseAssignment();

            try self.expectSymbol(.semicolon);

            object.fields.putNoClobber(entry.key, entry.value) catch return ParseError.ObjectDuplicateField;
        }

        try self.expectSymbol(.curly_right);

        log().debug("Object successfully parsed", .{});

        return object;
    }
    // Parses just 3 tokenes (NAME, '=', VALUE), doesn't skip the semicolon.
    fn parseAssignment(self: *Self) (ParseError || std.mem.Allocator.Error)!Entry {
        log().debug("Parsing assigment", .{});

        // any identifier is ok
        self.lexer.assertIdentifier() catch return ParseError.AssignmentIdentifierMissing;

        const ident_token = self.lexer.nextToken() orelse return ParseError.AssignmentIdentifierMissing;
        try self.expectSymbol(.assign);

        const ident = try self.alloc.dupe(u8, ident_token.identifier);
        log().debug("Identifier: {s}", .{ident});

        errdefer self.alloc.free(ident);
        const value = try self.parseValue();

        log().debug("Value: {any}", .{value});

        log().debug("Successfully parsed", .{});

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
                } else |err| {
                    std.debug.print("Couldnt parse object: {any}\n", .{err});
                    std.debug.panic("Assignment to identifiers not implemented (encountered indentifier: {s})\n", .{ident});
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

        log().err("Line {d}:{d} (Error:{any})| Expected symbol {s} but got {any}", .{ self.lexer.current_line, self.lexer.current_line_char, self.lexer.getError(), symbol.toString(), token });
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

// copies strings.
// If a field is missing but it has a default value it will be copied.
// If all fields of T have default values or are optional no error will be raised if a field is missing from map
// Otherwise error.MissingField will be returned
pub fn initObjectFromFields(comptime T: type, map: *const std.StringHashMap(Value), alloc: std.mem.Allocator) (error{MissingField} || std.mem.Allocator.Error)!T {
    const fields = @typeInfo(T).@"struct".fields;

    const has_default_values = comptime hasDefaultConstructor(T);

    var out: T = if (comptime has_default_values) T{} else undefined;

    inline for (fields) |field| {
        const field_name = field.name;
        const field_type = switch (@typeInfo(field.type)) {
            .optional => |o| o.child,
            else => field.type,
        };

        if (map.get(field_name)) |v| {
            switch (field_type) {
                []const u8 => {
                    // TODO :: Field is technically not missing but I do not wanna do this now
                    @field(out, field_name) = v.copyString(alloc) catch return error.MissingField;
                },
                //[]T => { // TODO :: This limits creating packages from string
                //    if(v != .list) log().err("Invalid field for a list", .{});
                //    var new = try alloc.alloc(T,v.list.len);
                //    for(v.list,0..) |item,i| {
                //        if(item != .object) log().err("Invalid field for a list", .{});
                //        new[i] = initObjectFromFields(T, item.object, alloc: std.mem.Allocator)
                //    }
                //}
                else => {
                    log().warn("Field type {any}  for {any} not yet supported - Skipping", .{ field_type, T });
                },
            }
        } else {
            if (has_default_values) {
                const fmt = comptime if (field_type == []const u8) "{s}" else "{any}";
                log().warn("Field {s} not found in the provided fields for {any}. Using default value " ++ fmt, .{ field_name, T, field.defaultValue().? });

                // Default strings are copied
                if (comptime field_type == []const u8) {
                    @field(out, field_name) = try alloc.dupe(u8, field.defaultValue().?);
                }
            } else if (@typeInfo(field.type) == .optional) { // Optiona lfields do not need a value
                log().warn("Optional field {s} for {any} is missing - defaulting to null", .{ field_name, T });
                @field(out, field_name) = null;
            } else {
                log().warn("Field {s} not found in the provided field map.", .{field_name});
                return error.MissingField;
            }
        }
    }
    return out;
}
fn hasDefaultConstructor(comptime T: type) bool {
    const info = @typeInfo(T);
    switch (info) {
        .@"struct" => |structInfo| {
            // If any field has no default, return false
            inline for (structInfo.fields) |field| {
                if (field.defaultValue() == null) {
                    return false;
                }
            }

            return true;
        },
        else => return false,
    }
}
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

test "Creating object from fields" {
    const stype = struct {
        name: []const u8,
        description: []const u8,
    };

    var fields = std.StringHashMap(Value).init(std.testing.allocator);
    defer fields.deinit();

    try fields.put("name", .{ .string = "Name:)" });
    try fields.put("description", .{ .string = "Description!" });

    const out = try initObjectFromFields(stype, &fields, std.testing.allocator);

    try std.testing.expectEqualSlices(u8, "Name:)", out.name);
    try std.testing.expectEqualSlices(u8, "Description!", out.description);

    std.testing.allocator.free(out.name);
    std.testing.allocator.free(out.description);
}

test "Creating object with nullable fields" {
    const stype = struct {
        description: ?[]const u8,
        non_present: ?[]const u8,
    };

    var fields = std.StringHashMap(Value).init(std.testing.allocator);
    defer fields.deinit();

    try fields.put("description", .{ .string = "Description!" });

    const out = try initObjectFromFields(stype, &fields, std.testing.allocator);

    try std.testing.expectEqualSlices(u8, "Description!", out.description.?);
    try std.testing.expectEqual(null, out.non_present);

    std.testing.allocator.free(out.description.?);
}

test "Checking if struct has default consctructor" {
    const ok_type = struct {
        name: []const u8 = "ligma",
    };
    const ok_type2 = struct {
        name: []const u8 = "ligma",
        field: []const u8 = "bols",
    };

    const not_ok_type = struct {
        name: []const u8,
    };

    const t1 = hasDefaultConstructor(ok_type);
    const t2 = hasDefaultConstructor(ok_type2);
    const t3 = hasDefaultConstructor(not_ok_type);

    try std.testing.expect(t1 == true);
    try std.testing.expect(t2 == true);
    try std.testing.expect(t3 == false);
}
