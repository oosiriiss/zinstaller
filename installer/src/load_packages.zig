const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");

pub const PackageLoadError = error{ FileNotFound, FileAccessDenied, UnkownError };

const PACKAGE_OBJECT_NAME = "package";
const PACKAGE_NAME_FIELD = "name";
const PACKAGE_DESCRIPTION_FIELD = "description";
const PACKAGE_DEPENDENCIES_FIELD = "dependencies";

const PackageError = error{InvalidFormat};

pub const PackageDescriptor = struct {
    name: []const u8,
    description: ?[]const u8,
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
    pub fn formatShort(self: Self, writer: std.io.AnyWriter) !void {
        const desc = if (self.description) |d| d else "???";

        try writer.print("{s:^10} - {s:<20} - Dependencies {d}", .{ self.name, desc, self.countDependencies() });
    }
    fn countDependencies(self: Self) u32 {
        if (self.dependencies == null) return 0;
        var sum: u32 = 0;
        for (self.dependencies.?) |dep| sum = sum + dep.countDependencies();
        return sum;
    }
};

pub fn loadPackages(filename: []const u8) ![]PackageDescriptor {
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

    const allocator = std.heap.page_allocator;

    const file_content = try allocator.alloc(u8, file_size);
    defer allocator.free(file_content);

    _ = try file.readAll(file_content);

    var lexer = lxr.Lexer.init(file_content);

    var parser = ast.Parser.init(&lexer, allocator);

    var ast_tree = try parser.build();
    defer ast_tree.deinit();

    const parsed = try createPackages(ast_tree.root.list);

    std.debug.print("====================== AST  ====================\n", .{});
    for (ast_tree.root.list) |node| {
        node.debugPrint();
    }
    std.debug.print("================================================\n", .{});

    std.debug.print("================ Parsed Packages ===============\n", .{});
    for (parsed) |package| {
        package.debugPrint();
        std.debug.print("\n", .{});
    }
    std.debug.print("================================================\n", .{});

    return parsed;
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

test "Creating package without dependencies from AST" {
    const content =
        \\package {
        \\   name = "hyprland";
        \\   description = "Window manager";
        \\   dependencies = [];
        \\}
    ;

    var l = lxr.Lexer.init(content);
    var builder = ast.Parser(void).init(&l, std.testing.allocator);

    var tree = try builder.build();
    defer tree.deinit();

    const package = try createPackage(tree.root);

    try std.testing.expectEqualSlices(u8, package.name, "hyprland");
    try std.testing.expectEqualSlices(u8, package.description.?, "Window manager");
    try std.testing.expect(package.dependencies.?.len == 0);
}

test "Creating package with single object dependency from AST" {
    const content =
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
    ;

    var l = lxr.Lexer.init(content);
    var builder = ast.Parser(void).init(&l, std.heap.page_allocator);

    var tree = try builder.build();
    defer tree.deinit();

    const package = try createPackage(tree.root);

    try std.testing.expectEqualSlices(u8, package.name, "hyprland");
    try std.testing.expectEqualSlices(u8, package.description.?, "Window manager");
    try std.testing.expectEqual(1, package.dependencies.?.len);
    try std.testing.expectEqualSlices(u8, package.dependencies.?[0].name, "name1");
    try std.testing.expectEqualSlices(u8, package.dependencies.?[0].description.?, "desc1");
    try std.testing.expectEqual(0, package.dependencies.?[0].dependencies.?.len);
}

test "Creating package with multiple object dependency from AST" {
    const content =
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
    ;

    var l = lxr.Lexer.init(content);
    var builder = ast.Parser(void).init(&l, std.heap.page_allocator);

    const tree = try builder.build();

    const package = try createPackage(tree.root);

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
