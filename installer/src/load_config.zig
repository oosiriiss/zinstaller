const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");

const BASE_SCRIPTS_DIR_PATH = "./scripts";
const BASE_DOTFILES_DIR_PATH = "./dotfiles";
const BASE_PACKAGES_FILE_PATH = "./packages.list";
const BASE_CACHE_FILE_PATH = "./packages.cache";

pub const Config = struct {
    scripts_dir_path: []const u8,
    dotfiles_dir_path: []const u8,
    packages_file_path: []const u8,
    cache_file_path: []const u8,

    const Self = @This();

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.scripts_dir_path);
        alloc.free(self.dotfiles_dir_path);
        alloc.free(self.packages_file_path);
        alloc.free(self.cache_file_path);
    }
};

const ConfigError = error{
    InvalidFormat,
    UnknownField,
    MissingFields,
    FieldHandleFail,
    MemoryError,
};

pub fn loadConfig(filename: []const u8, alloc: std.mem.Allocator) !Config {
    std.log.info("Loading configuration from {s}", .{filename});

    const file = try util.openFileReadonly(filename);
    defer file.close();

    const file_content = try util.readAllAlloc(file, alloc);
    defer alloc.free(file_content);

    var lexer = lxr.Lexer.init(file_content);
    var parser = ast.Parser.init(&lexer, alloc);

    var ast_tree = try parser.build();
    defer ast_tree.deinit();

    if (ast_tree.root != .object) {
        std.log.err("Invalid format of config file", .{});
    }

    const config = try createConfig(ast_tree.root.object, alloc);

    std.log.info("Configuration loaded successfully", .{});
    return config;
}

fn createConfig(obj: ast.Object, alloc: std.mem.Allocator) (ConfigError || std.mem.Allocator.Error)!Config {
    var field_iter = obj.fields.iterator();

    var scripts_dir: ?[]const u8 = null;
    var dotfiles_dir: ?[]const u8 = null;
    var packages_file: ?[]const u8 = null;
    var cache_file: ?[]const u8 = null;

    const field_creator = struct {
        pub fn creator(comptime T: type) type {
            return struct {
                field: *?T,
                default: T,
            };
        }
    }.creator;

    const StringField = field_creator([]const u8);

    var str_field_map = std.StringHashMap(StringField).init(alloc);
    defer str_field_map.deinit();
    try str_field_map.put("scripts_dir", .{
        .field = &scripts_dir,
        .default = BASE_SCRIPTS_DIR_PATH,
    });
    try str_field_map.put("dotfiles_dir", .{
        .field = &dotfiles_dir,
        .default = BASE_DOTFILES_DIR_PATH,
    });
    try str_field_map.put("packages_file", .{
        .field = &packages_file,
        .default = BASE_PACKAGES_FILE_PATH,
    });
    try str_field_map.put("cache_file", .{
        .field = &cache_file,
        .default = BASE_CACHE_FILE_PATH,
    });

    while (field_iter.next()) |field| {
        const name = field.key_ptr.*;
        const value = field.value_ptr.*;

        if (str_field_map.get(name)) |config_field_ptr| {
            config_field_ptr.field.* = value.copyString(alloc) catch return ConfigError.FieldHandleFail;
        } else {
            std.log.err("Unknown field {s} in config", .{name});
            return ConfigError.InvalidFormat;
        }
    }

    var val_iter = str_field_map.iterator();

    while (val_iter.next()) |entry| {
        const key_ptr = entry.key_ptr;
        const val_ptr = entry.value_ptr;

        if (val_ptr.field.* == null) {
            std.log.warn("{s} not found in config. Defaulted to value: {s}", .{ key_ptr.*, val_ptr.default });
            val_ptr.field.* = try alloc.dupe(u8, val_ptr.default);
        }
    }

    return Config{
        .scripts_dir_path = scripts_dir.?,
        .dotfiles_dir_path = dotfiles_dir.?,
        .packages_file_path = packages_file.?,
        .cache_file_path = cache_file.?,
    };
}

test "Loading config from file" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var file = try dir.dir.createFile("test_config", .{ .read = true });

    try file.writer().print(
        \\  config {{
        \\      scripts_dir = "./scripts";
        \\      packages_file = "./packages";
        \\      dotfiles_dir = "./dotfiles";
        \\  }}
    , .{});
    file.close();

    try dir.dir.setAsCwd();

    const orig = std.fs.cwd();

    const config = try loadConfig("test_config", std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try orig.setAsCwd();

    try std.testing.expectEqualSlices(u8, "./scripts", config.scripts_dir_path);
    try std.testing.expectEqualSlices(u8, "./packages", config.packages_file_path);
    try std.testing.expectEqualSlices(u8, "./dotfiles", config.dotfiles_dir_path);
    // field not set defualt value
    try std.testing.expectEqualSlices(u8, BASE_CACHE_FILE_PATH, config.cache_file_path);
}
