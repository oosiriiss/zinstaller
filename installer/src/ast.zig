const std = @import("std");
const lxr = @import("lexer.zig");
const Symbol = lxr.Symbol;
const Keyword = lxr.Keyword;
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
    bool: bool,

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
            .bool => {},
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
            .bool => |v| {
                printer.printSilent("{s}", .{if (v == true) "true" else "false"});
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

pub const ParseError = error{
    AssignmentIdentifierMissing,
    ObjectDuplicateField,
    UnexpectedSymbol,
    SyntaxError,
};
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

        log().debug("Parsing object: {s}", .{identifier});

        var object = Object{
            .name = try self.alloc.dupe(u8, identifier),
            .fields = std.StringHashMap(Value).init(self.alloc),
        };
        errdefer object.deinit(self.alloc);

        while (self.lexer.peek()) |token| {
            if (token == .symbol and token.symbol == .curly_right)
                break;

            const entry = try self.parseStatement();

            object.fields.putNoClobber(entry.key, entry.value) catch return ParseError.ObjectDuplicateField;
        }

        try self.expectSymbol(.curly_right);

        log().debug("Object successfully parsed", .{});

        return object;
    }
    // Parses just 3 tokenes (NAME, '=', VALUE) and expects a symbol ';' or end of line signaling end of statement
    fn parseStatement(self: *Self) (ParseError || std.mem.Allocator.Error)!Entry {
        log().debug("Parsing assigment", .{});

        // any identifier is ok
        const ident_token = self.expectIdentifier() catch return ParseError.AssignmentIdentifierMissing;
        try self.expectSymbol(.assign);

        const ident = try self.alloc.dupe(u8, ident_token);
        log().debug("Identifier: {s}", .{ident});
        errdefer self.alloc.free(ident);
        const value = try self.parseValue();

        log().debug("Value: {any} Successfully parsed", .{value});

        try self.expectStatementEnd();
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
                    log().err("Couldnt parse object: {any}\n", .{err});
                    std.debug.panic("Assignment to identifiers not implemented (encountered indentifier: {s})\n", .{ident});
                }
            },
            .symbol => |s| {
                if (s == .square_left)
                    return Value{ .list = try self.parseArray() };

                log().err("Unexpected symbol \"{s}\" encountered", .{s.toString()});
                return ParseError.UnexpectedSymbol;
            },
            .keyword => |kw| {
                self.lexer.skipToken();
                switch (kw) {
                    .true, .false => |v| {
                        log().debug("bool keyword: {any} isTrue: {any}", .{ v, v == .true });
                        return Value{ .bool = (v == .true) };
                    },
                }
            },
        }
    }
    fn expectSymbol(self: *Self, symbol: Symbol) ParseError!void {
        const token = self.lexer.nextToken();
        if (token != null and token.? == .symbol and token.?.symbol == symbol)
            return;

        log().err("Line {d}:{d} (lexer error:{any})| Expected symbol {s} but got {any}", .{ self.lexer.state.current_line, self.lexer.state.current_line_char, self.lexer.getError(), symbol.toString(), token });
        return ParseError.SyntaxError;
    }
    fn expectKeyword(self: *Self, keyword: Keyword) ParseError!void {
        const token = self.lexer.nextToken();
        if (token != null and token.? == .keyword and token.?.keyword == keyword)
            return;

        log().err("Line {d}:{d} (lexer error:{any})| Expected keyword {any} but got {any}", .{ self.lexer.state.current_line, self.lexer.state.current_line_char, self.lexer.getError(), keyword, token });
        return ParseError.SyntaxError;
    }

    fn expectIdentifier(self: *Self) ParseError![]const u8 {
        const token = self.lexer.nextToken();
        if (token != null and token.? == .identifier)
            return token.?.identifier;

        log().err("Line {d}:{d} (lexer error:{any})| Expected identifier but got {any}", .{ self.lexer.state.current_line, self.lexer.state.current_line_char, self.lexer.getError(), token });
        return ParseError.SyntaxError;
    }

    fn expectStatementEnd(self: *Self) ParseError!void {
        const token = self.lexer.peek();
        if (self.lexer.isEndOfLine()) {
            log().debug("Found statement end of line", .{});
            return;
        }

        if (token) |t| {
            if (t == .symbol and t.symbol == .semicolon) {
                log().debug("Found statement semicolon", .{});
                self.lexer.skipToken();
                return;
            }
        }

        log().err("Line {d}:{d} (lexer error:{any})| Expected ';' or newline but got {any}", .{ self.lexer.state.current_line, self.lexer.state.current_line_char, self.lexer.getError(), token });
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
pub fn initObjectFromFields(comptime T: type, map: *const std.StringHashMap(Value), alloc: std.mem.Allocator) (error{ MissingField, InvalidValueType } || std.mem.Allocator.Error)!T {
    const fields = @typeInfo(T).@"struct".fields;

    const has_default_values = comptime hasDefaultConstructor(T);

    var out: T = if (comptime has_default_values) T{} else undefined;

    inline for (fields) |field| {
        const field_name = field.name;
        const field_info = @typeInfo(field.type);
        const field_type = switch (field_info) {
            .optional => |o| o.child,
            else => field.type,
        };

        if (map.get(field_name)) |v| {
            if (field_info == .@"enum") {
                if (v != .string) return error.InvalidValueType;

                var ok = false;

                inline for (field_info.@"enum".fields) |f| {
                    if (std.mem.eql(u8, v.string, f.name)) {
                        @field(out, field_name) = @enumFromInt(f.value);
                        ok = true;
                    }
                }
                if (!ok) {
                    std.debug.panic("Enum str value {s} couldnt be converted to enum of type {any}", .{ v.string, field_type });
                    return error.InvalidValueType;
                }
            } else {
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
                    bool => {
                        if (v != .bool) return error.InvalidValueType;
                        @field(out, field_name) = v.bool;
                    },
                    else => {
                        log().err("Field type {any}  for {any} not yet supported", .{ field_type, T });
                    },
                }
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
                log().err("Field {s} not found in the provided field map.", .{field_name});
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

////////////////////////////////////////
////////////////////////////////////////
/////////////// TESTS //////////////////
////////////////////////////////////////
////////////////////////////////////////

const testing = std.testing;
const test_alloc = testing.allocator;

test "Parsing string assignment" {
    const content =
        \\ huj = "Hello"; 
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, testing.allocator);

    var e = try ast.parseStatement();
    defer e.deinit(ast.alloc);

    try testing.expectEqualSlices(u8, "huj", e.key);
    try testing.expectEqualSlices(u8, "Hello", e.value.string);
}

test "Parsing empty object assignment" {
    const content =
        \\ huj = testobject {};
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, testing.allocator);

    var e = try ast.parseStatement();
    defer e.deinit(testing.allocator);

    try testing.expectEqualSlices(u8, "huj", e.key);
    try testing.expect(e.value == .object);
    try testing.expectEqualSlices(u8, "testobject", e.value.object.name);
}

test "Parsing object with fields assignment" {
    const content =
        \\ huj = testobject { one = "one"; two = "two";};
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, testing.allocator);

    var e = try ast.parseStatement();
    defer e.deinit(testing.allocator);

    try testing.expectEqualSlices(u8, "huj", e.key);
    try testing.expect(e.value == .object);
    try testing.expectEqualSlices(u8, "testobject", e.value.object.name);
    try testing.expect(e.value.object.fields.count() == 2);
    try testing.expectEqualSlices(u8, "one", e.value.object.fields.get("one").?.string);
    try testing.expectEqualSlices(u8, "two", e.value.object.fields.get("two").?.string);
}

test "Parsing list of strings" {
    const content =
        \\ [ "first","second","third" ];
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, testing.allocator);

    const e = try ast.parseArray();
    defer {
        for (e) |*v| {
            v.deinit(testing.allocator);
        }
        testing.allocator.free(e);
    }

    try testing.expectEqual(3, e.len);
    try testing.expectEqualSlices(u8, "first", e[0].string);
    try testing.expectEqualSlices(u8, "second", e[1].string);
    try testing.expectEqualSlices(u8, "third", e[2].string);
}

test "Parsing list of strings assignment" {
    const content =
        \\ huj = [ "first","second","third" ];
    ;

    var lexer = lxr.Lexer.init(content);
    var ast = Parser.init(&lexer, testing.allocator);

    var e = try ast.parseStatement();
    defer e.deinit(testing.allocator);

    try testing.expectEqualSlices(u8, "huj", e.key);
    try testing.expect(e.value == .list);
    try testing.expectEqualSlices(u8, "first", e.value.list[0].string);
    try testing.expectEqualSlices(u8, "second", e.value.list[1].string);
    try testing.expectEqualSlices(u8, "third", e.value.list[2].string);
}

test "Parsing special characters in strings" {
    const content = "\\n\\\"\\r\\0";

    var str = try Parser.handleStringLiteral(content, testing.allocator);
    defer str.deinit(testing.allocator);

    try testing.expectEqual('\n', str.string[0]);
    try testing.expectEqual('"', str.string[1]);
    try testing.expectEqual('\r', str.string[2]);
    try testing.expectEqual(0, str.string[3]);
}

test "Creating object from fields" {
    const stype = struct {
        name: []const u8,
        description: []const u8,
    };

    var fields = std.StringHashMap(Value).init(testing.allocator);
    defer fields.deinit();

    try fields.put("name", .{ .string = "Name:)" });
    try fields.put("description", .{ .string = "Description!" });

    const out = try initObjectFromFields(stype, &fields, testing.allocator);

    try testing.expectEqualSlices(u8, "Name:)", out.name);
    try testing.expectEqualSlices(u8, "Description!", out.description);

    testing.allocator.free(out.name);
    testing.allocator.free(out.description);
}

test "Creating object with nullable fields" {
    const stype = struct {
        description: ?[]const u8,
        non_present: ?[]const u8,
    };

    var fields = std.StringHashMap(Value).init(testing.allocator);
    defer fields.deinit();

    try fields.put("description", .{ .string = "Description!" });

    const out = try initObjectFromFields(stype, &fields, testing.allocator);

    try testing.expectEqualSlices(u8, "Description!", out.description.?);
    try testing.expectEqual(null, out.non_present);

    testing.allocator.free(out.description.?);
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

    try testing.expect(t1 == true);
    try testing.expect(t2 == true);
    try testing.expect(t3 == false);
}

test "Parser expect functions work as expected" {
    const content =
        \\ package {};
        \\ true false {};
        \\ = [ ; ],
    ;
    var lexer = lxr.Lexer.init(content);
    var parser = Parser.init(&lexer, testing.allocator);

    try testing.expectEqualSlices(u8, "package", try parser.expectIdentifier());
    try parser.expectSymbol(.curly_left);
    try parser.expectSymbol(.curly_right);
    try parser.expectSymbol(.semicolon);
    try parser.expectKeyword(.true);
    try parser.expectKeyword(.false);
    try parser.expectSymbol(.curly_left);
    try parser.expectSymbol(.curly_right);
    try parser.expectSymbol(.semicolon);
    try parser.expectSymbol(.assign);
    try parser.expectSymbol(.square_left);
    try parser.expectSymbol(.semicolon);
    try parser.expectSymbol(.square_right);
    try parser.expectSymbol(.comma);
}

test "Statement can end with either end of line or ; " {
    const semicolon_stmt =
        \\ Something = "string";
    ;
    const eof_stmt = "Something = \"string\"";
    const newline_stmt =
        \\ Something = "string"
        \\ "Next token"
    ;

    var lexer = lxr.Lexer.init(semicolon_stmt);
    var a = Parser.init(&lexer, test_alloc);

    var e1 = try a.parseStatement();
    defer e1.deinit(test_alloc);
    try a.expectStatementEnd();

    lexer = lxr.Lexer.init(eof_stmt);
    a = Parser.init(&lexer, test_alloc);
    var e2 = try a.parseStatement();
    defer e2.deinit(test_alloc);
    try a.expectStatementEnd();

    lexer = lxr.Lexer.init(newline_stmt);
    a = Parser.init(&lexer, test_alloc);
    var e3 = try a.parseStatement();
    defer e3.deinit(test_alloc);
    try a.expectStatementEnd();
}
