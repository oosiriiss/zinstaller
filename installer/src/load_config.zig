const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");

const BASE_SCRIPTS_DIR_PATH = "./scripts";
const BASE_DOTFILES_DIR_PATH = "./doftiles";
const BASE_PACKAGES_FILE_PATH = "./packages.list";

pub const Config = struct {
    scripts_dir_path: []const u8,
    dotfiles_dir_path: []const u8,
    packages_file_path: []const u8,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        alloc.free(self.scripts_dir_path);
        alloc.free(self.dotfiles_dir_path);
        alloc.free(self.packages_file_path);
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

    var config = Config{
        .scripts_dir_path = BASE_SCRIPTS_DIR_PATH,
        .dotfiles_dir_path = BASE_DOTFILES_DIR_PATH,
        .packages_file_path = BASE_PACKAGES_FILE_PATH,
    };

    var str_field_map = std.StringHashMap(*[]const u8).init(alloc);
    try str_field_map.put("scripts_dir", &config.scripts_dir_path);
    try str_field_map.put("dotfiles_dir", &config.dotfiles_dir_path);
    try str_field_map.put("packages_file", &config.packages_file_path);

    while (field_iter.next()) |field| {
        const name = field.key_ptr.*;
        const value = field.value_ptr.*;

        if (str_field_map.get(name)) |config_field_ptr| {
            config_field_ptr.* = value.copyString(alloc) catch return ConfigError.FieldHandleFail;
        } else {
            std.log.err("Unknown field {s} in config", .{name});
            return ConfigError.InvalidFormat;
        }
    }

    return config;
}
