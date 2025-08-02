const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");

const SCRIPTS_DIR_FIELD = "scripts_dir";
const PACKAGES_PATH_FIELD = "packages_file";
const DOTFILES_DIR_FIELD = "dotfiles_dir";

const Config = struct {
    scripts_dir: []const u8,
    dotfiles_dir: []const u8,
    packages_path: []const u8,

    const Self = @This();

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.scripts_dir);
        alloc.free(self.dotfiles_dir);
        alloc.free(self.packages_path);
    }
};

const ConfigError = error{InvalidFormat};

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
        .scripts_dir = undefined,
        .dotfiles_dir = undefined,
        .packages_path = undefined,
    };

    while (field_iter.next()) |field| {
        const name = field.key_ptr.*;
        const value = field.value_ptr.*;

        if (std.mem.eql(u8, name, SCRIPTS_DIR_FIELD)) {
            if (value != .string) return ConfigError.InvalidFormat;
            config.scripts_dir = try alloc.dupe(u8, value.string);
        } else if (std.mem.eql(u8, name, DOTFILES_DIR_FIELD)) {
            if (value != .string) return ConfigError.InvalidFormat;
            config.dotfiles_dir = try alloc.dupe(u8, value.string);
        } else if (std.mem.eql(u8, name, PACKAGES_PATH_FIELD)) {
            if (value != .string) return ConfigError.InvalidFormat;
            config.packages_path = try alloc.dupe(u8, value.string);
        } else {
            return ConfigError.InvalidFormat;
        }
    }

    return config;
}
