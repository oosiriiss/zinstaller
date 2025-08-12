const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");
const log = @import("logger.zig").getGlobalLogger;

pub const PackageLoadError = error{ FileNotFound, FileAccessDenied, UnkownError };

const PackageError = error{InvalidFormat};

pub const PackageDescriptor = struct {
    name: []const u8,
    description: ?[]const u8,
    dependencies: ?[]PackageDescriptor = null,
    setup_command: ?[]const u8,

    const Self = @This();

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.name);

        if (self.description) |desc| {
            alloc.free(desc);
        }
        if (self.dependencies) |dps| {
            for (dps) |d| {
                d.deinit(alloc);
            }
            alloc.free(dps);
        }
    }

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
    pub fn countDependencies(self: Self) usize {
        if (self.dependencies == null) return 0;
        var sum: usize = self.dependencies.?.len;
        for (self.dependencies.?) |dep| sum = sum + dep.countDependencies();
        return sum;
    }
};

// Package Context for usage in hashmaps or other stuff
// Package hash and comparisons are based on the package.name
pub const PackageContext = struct {
    const Self = @This();

    pub fn hash(self: Self, p: PackageDescriptor) u32 {
        _ = self;
        return std.array_hash_map.hashString(p.name);
    }

    pub fn eql(self: @This(), f: PackageDescriptor, s: PackageDescriptor, s_index: usize) bool {
        _ = self;
        _ = s_index;
        return std.mem.eql(u8, f.name, s.name);
    }
};

pub fn loadPackages(packages_file_path: []const u8, alloc: std.mem.Allocator) ![]PackageDescriptor {
    const file = try util.openFileReadonly(packages_file_path);
    defer file.close();

    const file_size = try file.getEndPos();
    try file.seekTo(0);

    const file_content = try alloc.alloc(u8, file_size);
    defer alloc.free(file_content);

    _ = try file.readAll(file_content);

    var lexer = lxr.Lexer.init(file_content);
    var parser = ast.Parser.init(&lexer, alloc);

    var ast_tree = try parser.build();
    defer ast_tree.deinit();

    const parsed = try createPackages(ast_tree.root.list, alloc);

    if (comptime @import("builtin").mode == .Debug) {
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
    }

    return parsed;
}

fn createPackages(ast_tree: []ast.Value, alloc: std.mem.Allocator) (PackageError || std.mem.Allocator.Error)![]PackageDescriptor {
    var arr = std.ArrayList(PackageDescriptor).init(alloc);
    errdefer arr.deinit();

    for (ast_tree) |object| {
        try arr.append(try createPackage(object, alloc));
    }

    return arr.toOwnedSlice();
}

fn createPackageFromString(v: ast.Value, alloc: std.mem.Allocator) (PackageError || std.mem.Allocator.Error)!PackageDescriptor {
    if (v != .string) return PackageError.InvalidFormat;

    return PackageDescriptor{
        .name = try alloc.dupe(u8, v.string),
        .description = null,
        .setup_command = null,
        .dependencies = null,
    };
}

fn createPackage(val: ast.Value, alloc: std.mem.Allocator) (PackageError || std.mem.Allocator.Error)!PackageDescriptor {
    if (val != .object) return createPackageFromString(val, alloc);
    const PACKAGE_OBJECT_NAME = "package";
    if (!std.mem.eql(u8, val.object.name, PACKAGE_OBJECT_NAME)) return PackageError.InvalidFormat;
    const obj = val.object;

    // // TODO :: This limits creating packages from string
    // Maybe add some custom context or something
    // For now just setting the default value of packages to null works
    var package = ast.initObjectFromFields(PackageDescriptor, &obj.fields, alloc) catch return PackageError.InvalidFormat;

    if (obj.fields.get("dependencies")) |deps| {
        if (deps != .list) log().err("Dependencies must be list", .{});
        package.dependencies = try createPackages(deps.list, alloc);
    }

    return package;
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
    var builder = ast.Parser.init(&l, std.testing.allocator);

    var tree = try builder.build();
    defer tree.deinit();

    const package = try createPackage(tree.root, std.testing.allocator);
    defer package.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, package.name, "hyprland");
    try std.testing.expectEqualSlices(u8, package.description.?, "Window manager");
    try std.testing.expect(package.dependencies.?.len == 0);
}

test "Creating package from string" {
    const content =
        \\ "Package_name"
    ;
    var l = lxr.Lexer.init(content);

    var builder = ast.Parser.init(&l, std.testing.allocator);

    var tree = try builder.build();
    defer tree.deinit();

    var package = try createPackageFromString(tree.root, std.testing.allocator);
    defer package.deinit(std.testing.allocator);
    var package2 = try createPackage(tree.root, std.testing.allocator);
    defer package2.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, "Package_name", package.name);
    try std.testing.expectEqualSlices(u8, "Package_name", package2.name);
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

    var builder = ast.Parser.init(&l, std.testing.allocator);

    var tree = try builder.build();
    defer tree.deinit();

    const package = try createPackage(tree.root, std.testing.allocator);
    defer package.deinit(std.testing.allocator);

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

    var lexer = lxr.Lexer.init(content);

    var builder = ast.Parser.init(&lexer, std.testing.allocator);

    var tree = try builder.build();
    defer tree.deinit();

    const package = try createPackage(tree.root, std.testing.allocator);
    defer package.deinit(std.testing.allocator);

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
