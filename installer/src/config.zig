const std = @import("std");
const lxr = @import("lexer.zig");

pub const PackageLoadError = error{ FileNotFound, FileAccessDenied, UnkownError };

const PackageLoadKeywords = enum {
    package,
};

const package_load_kw_map = std.StaticStringMap(PackageLoadKeywords).initComptime([_]struct { []const u8, PackageLoadKeywords }{
    .{ "package", PackageLoadKeywords.package },
});

const PACKAGE_NAME_FIELD = "name";
const PACKAGE_DESCRIPTION_FIELD = "description";
const PACKAGE_DEPENDENCIES_FIELD = "dependencies";

pub fn loadConfig(filename: []const u8) !void {
    const flags: std.fs.File.OpenFlags = .{ .mode = .read_only };

    const file = std.fs.cwd().openFile(filename, flags) catch |err| {
        const oerr = std.fs.File.OpenError;
        switch (err) {
            oerr.AccessDenied => {
                std.log.err("Access to packages file: '{s}' denied", .{filename});
                return PackageLoadError.FileAccessDenied;
            },
            oerr.FileNotFound => {
                std.log.err("packages file '{s}' not found\n", .{filename});
                return PackageLoadError.FileNotFound;
            },
            else => {
                std.log.err("An unknown error occurred when trying to open file {s}", .{filename});
                return PackageLoadError.UnkownError;
            },
        }
    };

    defer file.close();

    const file_size = try file.getEndPos();
    try file.seekTo(0);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const file_content = try allocator.alloc(u8, file_size);
    defer allocator.free(file_content);

    _ = try file.readAll(file_content);

    var lexer = lxr.Lexer(PackageLoadKeywords).init(file_content, allocator, package_load_kw_map);

    //while (lexer.nextToken()) |token| {
    //    std.debug.print(" ", .{});
    //    try token.debugPrint();
    //}

    const allow_whitespace = lexer.allow_whitespace_tokens;
    lexer.allow_whitespace_tokens = false;

    var root_packages = std.ArrayList(PackageDescriptor).init(allocator);

    while (lexer.peek() != null) {
        const pkg = try parsePackage(&lexer);
        try root_packages.append(pkg);
    }

    lexer.allow_whitespace_tokens = allow_whitespace;

    for (root_packages.items) |pkg| {
        pkg.debugPrint();
        std.debug.print("\n", .{});
    }
}

pub const PackageParseError = error{ MissingPackageIdentifier, InvalidPackageIdentifier, InvalidSymbol, SyntaxError, MissingSemicolon };

const PackageDescriptor = struct {
    name: []u8,
    description: ?[]u8,
    dependencies: ?[]PackageDescriptor,

    const Self = @This();
    pub fn debugPrint(self: Self) void {
        const desc = if (self.description) |d| d else "";

        std.debug.print("Package(name='{s}', description='{s}', dependencies=[", .{ self.name, desc });

        if (self.dependencies) |deps| {
            for (0..deps.len) |i| {
                deps[i].debugPrint();
                if (i < deps.len - 1)
                    std.debug.print(", ", .{});
            }
        }
        std.debug.print("])", .{});
    }
};

// Parses Array of packages. This function expects the initial '[' to be already used and not present in lexer.
fn parsePackageArray(lexer: *lxr.Lexer(PackageLoadKeywords)) (PackageParseError || std.mem.Allocator.Error)!?[]PackageDescriptor {
    const initial_token = lexer.peek() orelse return null;

    // Empty array check
    if (initial_token == .symbol and initial_token.symbol == lxr.Symbol.square_right) {
        lexer.skipToken();
        return null;
    }

    var packages = std.ArrayList(PackageDescriptor).init(std.heap.page_allocator);
    // for the null return case. Should matter for toOwnedSlice().
    defer packages.deinit();

    while (lexer.peek()) |token| {
        if (token == .symbol) {
            if (token.symbol == lxr.Symbol.square_right) {
                lexer.skipToken();
                break;
            }

            if (token.symbol == lxr.Symbol.comma) {
                lexer.skipToken();
                // Continue allows for trailing commas in a list
                continue;
            }
        }

        const pkg = try parsePackage(lexer);
        try packages.append(pkg);
    }

    return if (packages.items.len > 0) packages.toOwnedSlice() catch null else null;
}

fn parsePackage(lexer: *lxr.Lexer(PackageLoadKeywords)) (PackageParseError || std.mem.Allocator.Error)!PackageDescriptor {
    std.debug.print("Package parsing started\n", .{});
    // TODO :: Add syntax/error checking

    lexer.assertKeyword(PackageLoadKeywords.package) catch return PackageParseError.MissingPackageIdentifier;
    lexer.skipToken();

    var name: ?[]u8 = null;
    var description: ?[]u8 = null;
    var dependencies: ?[]PackageDescriptor = null;

    lexer.assertSymbol(lxr.Symbol.curly_left) catch return PackageParseError.SyntaxError;
    lexer.skipToken();

    while (lexer.nextToken()) |token| {
        std.debug.print("'identifier token': {any}\n", .{token});
        const identifier = if (token == .identifier) token.identifier else return PackageParseError.SyntaxError;
        // Skipping '=' sign;
        lexer.assertSymbol(lxr.Symbol.equal) catch return PackageParseError.InvalidSymbol;
        lexer.skipToken();

        const value_token = lexer.nextToken() orelse {
            std.debug.print("Null token encountered where it wasn't expected.\n", .{});
            return PackageParseError.SyntaxError;
        };

        switch (value_token) {
            .symbol => |s| {
                if (s != lxr.Symbol.square_left or !std.mem.eql(u8, PACKAGE_DEPENDENCIES_FIELD, identifier)) {
                    std.debug.panic("Invalid symbol:)", .{});
                }
                dependencies = parsePackageArray(lexer) catch {
                    std.debug.panic("Couldn't parse package array\n", .{});
                };
            },
            .string_literal => |str| {
                // TODO :: Add handling memory errors:)

                if (std.mem.eql(u8, PACKAGE_NAME_FIELD, identifier) and name == null) {
                    name = std.heap.page_allocator.dupe(u8, str) catch null;
                } else if (std.mem.eql(u8, PACKAGE_DESCRIPTION_FIELD, identifier) and description == null) {
                    description = std.heap.page_allocator.dupe(u8, str) catch null;
                }
            },
            else => {
                std.debug.panic("Invalid token encountered when parsing package.\n", .{});
            },
        }

        // Expression final semicolon
        lexer.assertSymbol(lxr.Symbol.semicolon) catch return PackageParseError.MissingSemicolon;
        lexer.skipToken();

        // If '}' is encountered the package parsing should be finished.
        const s = lexer.peek();
        if (s != null and s.? == .symbol and s.?.symbol == lxr.Symbol.curly_right) {
            lexer.skipToken();
            break;
        }
    }

    std.debug.print("Package parsing finished successfully.\n", .{});
    return PackageDescriptor{ .name = name.?, .description = description, .dependencies = dependencies };
}

test "Parsing package without dependencies" {
    const test_content =
        \\package {
        \\ name = "test_name";
        \\ description = "test_description";
        \\ dependencies = [];
        \\}
    ;

    var lexer = lxr.Lexer(PackageLoadKeywords).init(test_content, std.heap.page_allocator, package_load_kw_map);

    const pkg = try parsePackage(&lexer);

    try std.testing.expectEqualSlices(u8, "test_name", pkg.name);
    try std.testing.expectEqualSlices(u8, "test_description", pkg.description.?);
    try std.testing.expectEqual(null, pkg.dependencies);
}

test "Parsing a package with dependency" {
    const test_content =
        \\package {
        \\      name = "test_name";
        \\      description = "test_description";
        \\      dependencies = [
        \\           package {   
        \\               name = "test_name";
        \\               description = "test_description";
        \\               dependencies = [];
        \\           }
        \\      ];
        \\}
    ;

    var lexer = lxr.Lexer(PackageLoadKeywords).init(test_content, std.heap.page_allocator, package_load_kw_map);
    const pkg = try parsePackage(&lexer);

    try std.testing.expectEqualSlices(u8, "test_name", pkg.name);
    try std.testing.expectEqualSlices(u8, "test_description", pkg.description.?);
    try std.testing.expectEqual(1, pkg.dependencies.?.len);
}

test "Parsing a package with multiple dependencies" {
    const test_content =
        \\package {
        \\      name = "test_name";
        \\      description = "test_description";
        \\      dependencies = [
        \\           package {   
        \\               name = "test_name";
        \\               description = "test_description";
        \\               dependencies = [];
        \\           },
        \\           package {   
        \\               name = "test_name";
        \\               description = "test_description";
        \\               dependencies = [];
        \\           }
        \\      ];
        \\}
    ;

    var lexer = lxr.Lexer(PackageLoadKeywords).init(test_content, std.heap.page_allocator, package_load_kw_map);
    const pkg = try parsePackage(&lexer);

    try std.testing.expectEqualSlices(u8, "test_name", pkg.name);
    try std.testing.expectEqualSlices(u8, "test_description", pkg.description.?);
    try std.testing.expectEqual(2, pkg.dependencies.?.len);
}

test "Parsing package with a trailing comma in dependencies" {
    const test_content =
        \\package {
        \\      name = "test_name";
        \\      description = "test_description";
        \\      dependencies = [
        \\           package {   
        \\               name = "test_name";
        \\               description = "test_description";
        \\               dependencies = [];
        \\           },
        \\      ];
        \\}
    ;

    var lexer = lxr.Lexer(PackageLoadKeywords).init(test_content, std.heap.page_allocator, package_load_kw_map);
    const pkg = try parsePackage(&lexer);

    try std.testing.expectEqualSlices(u8, "test_name", pkg.name);
    try std.testing.expectEqualSlices(u8, "test_description", pkg.description.?);
    try std.testing.expectEqual(1, pkg.dependencies.?.len);
}
