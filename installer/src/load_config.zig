const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");

const SCRIPTS_PATH_FIELD = "scripts_path";

const Config = struct {
    scripts_path: []const u8,
    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.alloc.free(self.scripts_path);
    }
};

const ConfigError = error{InvalidFormat};

pub fn loadConfig(filename: []const u8) !Config {
    std.log.info("Loading configuration from {s}", .{filename});

    const file = try util.openFileReadonly(filename);
    defer file.close();

    const alloc = std.heap.page_allocator;

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
        .scripts_path = undefined,
        .alloc = alloc,
    };

    while (field_iter.next()) |field| {
        const name = field.key_ptr.*;
        const value = field.value_ptr.*;

        if (std.mem.eql(u8, name, SCRIPTS_PATH_FIELD)) {
            if (value != .string) return ConfigError.InvalidFormat;
            config.scripts_path = try alloc.dupe(u8, value.string);
        } else {
            return ConfigError.InvalidFormat;
        }
    }

    return config;
}
