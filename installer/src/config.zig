const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");

pub const PackageLoadError = error{ FileNotFound, FileAccessDenied, UnkownError };

const PackageLoadKeywords = enum {
    if_keyword,
};

const package_load_kw_map = std.StaticStringMap(PackageLoadKeywords).initComptime([_]struct { []const u8, PackageLoadKeywords }{
    .{ "if", PackageLoadKeywords.if_keyword },
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
    lexer.allow_whitespace_tokens = false;

    var parser = ast.AST(PackageLoadKeywords).init(&lexer, allocator);

    const ast_tree = try parser.build();

    for (ast_tree) |node| {
        node.debugPrint();
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
