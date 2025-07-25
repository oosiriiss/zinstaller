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
    const pkg = try parsePackage(&lexer);
    lexer.allow_whitespace_tokens = allow_whitespace;

    std.debug.print("Parse pacakge: {any}\n", .{pkg});
}

pub const PackageParseError = error{ MissingPackageIdentifier, InvalidPackageIdentifier, InvalidSymbol, SyntaxError };

const PackageDescriptor = struct { name: []u8, description: ?[]u8, dependencies: ?[]PackageDescriptor };

fn parsePackage(lexer: *lxr.Lexer(PackageLoadKeywords)) (PackageParseError || std.mem.Allocator.Error)!PackageDescriptor {
    {
        const package_token = lexer.nextToken() orelse return PackageParseError.MissingPackageIdentifier;
        std.debug.print("Initial token: {any}\n", .{package_token});
        if (package_token != .keyword) return PackageParseError.MissingPackageIdentifier;
        if (package_token.keyword != PackageLoadKeywords.package) return PackageParseError.InvalidPackageIdentifier;
    }

    var name: ?[]u8 = null;
    var description: ?[]u8 = null;
    var dependencies = std.ArrayList(PackageDescriptor).init(std.heap.page_allocator);
    // Deinit not needed since we copy the data into owned slice at the end but ill keep it here in case in change something
    defer dependencies.deinit();

    _ = lexer.assertSymbol(lxr.Symbol.curly_left) orelse return PackageParseError.SyntaxError;
    while (lexer.nextToken()) |token| {
        std.debug.print("'identifier token': {any}\n", .{token});
        const identifier = if (token == .identifier) token.identifier else return PackageParseError.SyntaxError;
        _ = lexer.assertSymbol(lxr.Symbol.equal) orelse return PackageParseError.InvalidSymbol;
        const value_token = lexer.nextToken();
        if (value_token == null) {
            std.debug.print("Invalid value token encountered: {any}", .{value_token});
            return PackageParseError.SyntaxError;
        }

        if (value_token.? == .string_literal) {
            const str = value_token.?.string_literal;
            // TODO :: Add handling memory errors:)

            if (std.mem.eql(u8, PACKAGE_NAME_FIELD, identifier) and name == null) {
                name = std.heap.page_allocator.dupe(u8, str) catch null;
            } else if (std.mem.eql(u8, PACKAGE_DESCRIPTION_FIELD, identifier) and description == null) {
                description = std.heap.page_allocator.dupe(u8, str) catch null;
            }
        } else if (value_token.? == .symbol) {
            const symbol = value_token.?.symbol;
            if (symbol == lxr.Symbol.square_left and std.mem.eql(u8, PACKAGE_DEPENDENCIES_FIELD, identifier)) {
                std.debug.print("Dependencies field not supported yet\n", .{});
                _ = lexer.assertSymbol(lxr.Symbol.square_right);
            }
        }
        _ = lexer.assertSymbol(lxr.Symbol.semicolon);

        const symbol = lexer.peekSymbol();

        // TODO :: detect early invalid curly
        if (symbol == lxr.Symbol.curly_right)
            break;
    }

    return PackageDescriptor{ .name = name.?, .description = description, .dependencies = try dependencies.toOwnedSlice() };
}
