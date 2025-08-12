const std = @import("std");
const lxr = @import("lexer.zig");
const ast = @import("ast.zig");
const util = @import("util.zig");
const log = @import("logger.zig").getGlobalLogger;

const DEFAULT_SCRIPTS_DIR_PATH = "./scripts";
const DEFAULT_DOTFILES_DIR_PATH = "./dotfiles";
const DEFAULT_CONFIG_DIR_PATH = "~/.config";
const DEFAULT_PACKAGES_FILE_PATH = "./packages.list";
const DEFAULT_CACHE_FILE_PATH = "./packages.cache";
const DEFAULT_LOG_FILE_PATH = "./out.log";

pub const Config = struct {
    scripts_dir_path: []const u8 = DEFAULT_SCRIPTS_DIR_PATH,
    // Path where the dotfiles are
    dotfiles_dir_path: []const u8 = DEFAULT_DOTFILES_DIR_PATH,
    // Path to the .config directory
    config_dir_path: []const u8 = DEFAULT_CONFIG_DIR_PATH,
    packages_file_path: []const u8 = DEFAULT_PACKAGES_FILE_PATH,
    cache_file_path: []const u8 = DEFAULT_CACHE_FILE_PATH,
    log_file_path: []const u8 = DEFAULT_LOG_FILE_PATH,

    const Self = @This();

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.scripts_dir_path);
        alloc.free(self.dotfiles_dir_path);
        alloc.free(self.packages_file_path);
        alloc.free(self.cache_file_path);
        alloc.free(self.log_file_path);
        alloc.free(self.config_dir_path);
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
    log().info("Loading configuration from {s}", .{filename});

    const file = try util.openFileReadonly(filename);
    defer file.close();

    const file_content = try util.readAllAlloc(file, alloc);
    defer alloc.free(file_content);

    var lexer = lxr.Lexer.init(file_content);
    var parser = ast.Parser.init(&lexer, alloc);

    var ast_tree = try parser.build();
    defer ast_tree.deinit();

    if (ast_tree.root != .object) {
        log().err("Invalid format of config file", .{});
    }

    var i = ast_tree.root.object.fields.keyIterator();

    while (i.next()) |k| {
        std.debug.print("Key: {s}\n", .{k.*});
    }

    const config = try createConfig(ast_tree.root.object, alloc);
    log().info("Configuration loaded successfully", .{});
    return config;
}

pub fn createConfig(obj: ast.Object, alloc: std.mem.Allocator) !Config {
    // I'll leave this function just in case I wanna add something here.
    return try ast.initObjectFromFields(Config, &obj.fields, alloc);
}

test "Loading config from file" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var file = try dir.dir.createFile("test_config", .{ .read = true });

    try file.writer().print(
        \\  config {{
        \\      scripts_dir_path = "./scripts";
        \\      packages_file_path = "./packages";
        \\      dotfiles_dir_path = "./dotfiles";
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
    try std.testing.expectEqualSlices(u8, DEFAULT_CACHE_FILE_PATH, config.cache_file_path);
}
