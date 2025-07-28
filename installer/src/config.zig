const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");

pub const PackageLoadError = error{ FileNotFound, FileAccessDenied, UnkownError };

const PackageLoadKeywords = enum {
    if_keyword,
};

const package_load_kw_map = std.StaticStringMap(PackageLoadKeywords).initComptime([_]struct { []const u8, PackageLoadKeywords }{});

const PACKAGE_OBJECT_NAME = "package";
const PACKAGE_NAME_FIELD = "name";
const PACKAGE_DESCRIPTION_FIELD = "description";
const PACKAGE_DEPENDENCIES_FIELD = "dependencies";

const PackageError = error{InvalidFormat};

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

    std.debug.print("====================== AST  ====================\n", .{});
    for (ast_tree) |node| {
        node.debugPrint();
    }
    std.debug.print("================================================\n", .{});

    const parsed = try createPackages(ast_tree);

    std.debug.print("================ Parsed Packages ===============\n", .{});
    for (parsed) |package| {
        package.debugPrint();
        std.debug.print("\n", .{});
    }
    std.debug.print("================================================\n", .{});
}

fn createPackages(ast_tree: []ast.Value) (PackageError || std.mem.Allocator.Error)![]PackageDescriptor {
    var arr = std.ArrayList(PackageDescriptor).init(std.heap.page_allocator);
    defer arr.deinit();

    for (ast_tree) |object| {
        try arr.append(try createPackage(object));
    }

    return arr.toOwnedSlice();
}

fn createPackage(val: ast.Value) (PackageError || std.mem.Allocator.Error)!PackageDescriptor {
    if (val != .object) return PackageError.InvalidFormat;
    if (!std.mem.eql(u8, val.object.name, PACKAGE_OBJECT_NAME)) return PackageError.InvalidFormat;
    const obj = val.object;

    var field_iter = obj.fields.iterator();

    var pkg = PackageDescriptor{ .name = undefined, .description = null, .dependencies = null };

    const alloc = std.heap.page_allocator;

    while (field_iter.next()) |field| {
        const name = field.key_ptr.*;
        const value = field.value_ptr.*;

        if (std.mem.eql(u8, name, PACKAGE_NAME_FIELD)) {
            if (value != .string) return PackageError.InvalidFormat;
            pkg.name = try alloc.dupe(u8, value.string);
        } else if (std.mem.eql(u8, name, PACKAGE_DESCRIPTION_FIELD)) {
            if (value != .string) return PackageError.InvalidFormat;
            pkg.description = try alloc.dupe(u8, value.string);
        } else if (std.mem.eql(u8, name, PACKAGE_DEPENDENCIES_FIELD)) {
            if (value != .list) return PackageError.InvalidFormat;
            pkg.dependencies = try createPackages(value.list);
        } else {
            return PackageError.InvalidFormat;
        }
    }

    return pkg;
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

test "Creating package without dependencies from AST" {
    const content =
        \\ [
        \\package {
        \\   name = "hyprland";
        \\   description = "Window manager";
        \\   dependencies = [];
        \\}
        \\]
    ;

    var l = lxr.Lexer(TestKeywords).init(content, std.heap.page_allocator, test_keyword_map);
    var builder = ast.AST(TestKeywords).init(&l, std.heap.page_allocator);

    const tree = try builder.build();

    const package = try createPackage(tree[0]);

    try std.testing.expectEqualSlices(u8, package.name, "hyprland");
    try std.testing.expectEqualSlices(u8, package.description.?, "Window manager");
    try std.testing.expect(package.dependencies.?.len == 0);
}

test "Creating package with single object dependency from AST" {
    const content =
        \\ [
        \\package {
        \\   name = "hyprland";
        \\   description = "Window manager";
        \\   dependencies = [
        \\      package {
        \\            name = "name1";
        \\            description = "desc1";
        \\            dependencies = [];
        \\      }
        \\   ];
        \\}
        \\]
    ;

    var l = lxr.Lexer(TestKeywords).init(content, std.heap.page_allocator, test_keyword_map);
    var builder = ast.AST(TestKeywords).init(&l, std.heap.page_allocator);

    const tree = try builder.build();

    const package = try createPackage(tree[0]);

    try std.testing.expectEqualSlices(u8, package.name, "hyprland");
    try std.testing.expectEqualSlices(u8, package.description.?, "Window manager");
    try std.testing.expectEqual(1, package.dependencies.?.len);
    try std.testing.expectEqualSlices(u8, package.dependencies.?[0].name, "name1");
    try std.testing.expectEqualSlices(u8, package.dependencies.?[0].description.?, "desc1");
    try std.testing.expectEqual(0, package.dependencies.?[0].dependencies.?.len);
}

test "Creating package with multiple object dependency from AST" {
    const content =
        \\ [
        \\package {
        \\   name = "hyprland";
        \\   description = "Window manager";
        \\   dependencies = [
        \\      package {
        \\            name = "name1";
        \\            description = "desc1";
        \\            dependencies = [];
        \\      },
        \\      package {
        \\            name = "name2";
        \\            description = "desc2";
        \\            dependencies = [];
        \\      }
        \\   ];
        \\}
        \\]
    ;

    var l = lxr.Lexer(TestKeywords).init(content, std.heap.page_allocator, test_keyword_map);
    var builder = ast.AST(TestKeywords).init(&l, std.heap.page_allocator);

    const tree = try builder.build();

    const package = try createPackage(tree[0]);

    try std.testing.expectEqualSlices(u8, package.name, "hyprland");
    try std.testing.expectEqualSlices(u8, package.description.?, "Window manager");
    try std.testing.expectEqual(2, package.dependencies.?.len);
    try std.testing.expectEqualSlices(u8, package.dependencies.?[0].name, "name1");
    try std.testing.expectEqualSlices(u8, package.dependencies.?[0].description.?, "desc1");
    try std.testing.expectEqual(0, package.dependencies.?[0].dependencies.?.len);
    try std.testing.expectEqualSlices(u8, package.dependencies.?[1].name, "name2");
    try std.testing.expectEqualSlices(u8, package.dependencies.?[1].description.?, "desc2");
    try std.testing.expectEqual(0, package.dependencies.?[1].dependencies.?.len);
}
