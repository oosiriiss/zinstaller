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
    scripts_dir: []const u8 = DEFAULT_SCRIPTS_DIR_PATH,
    // Path where the dotfiles are
    dotfiles_dir: []const u8 = DEFAULT_DOTFILES_DIR_PATH,
    // Path to the .config directory
    config_dir: []const u8 = DEFAULT_CONFIG_DIR_PATH,
    packages_file: []const u8 = DEFAULT_PACKAGES_FILE_PATH,
    cache_file: []const u8 = DEFAULT_CACHE_FILE_PATH,
    log_file: []const u8 = DEFAULT_LOG_FILE_PATH,
    setup_script_stop_on_fail: bool = false,

    const Self = @This();

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.scripts_dir);
        alloc.free(self.dotfiles_dir);
        alloc.free(self.packages_file);
        alloc.free(self.cache_file);
        alloc.free(self.log_file);
        alloc.free(self.config_dir);
    }

    pub fn debugPrint(self: Self) void {
        if (comptime @import("builtin").mode == .Debug) {
            const fields = comptime @typeInfo(Self).@"struct".fields;

            std.debug.print("Config: \n", .{});
            inline for (fields) |field| {
                const field_modifier = switch (field.type) {
                    []const u8 => "s",
                    else => "any",
                };
                const fmt = "   {s} = {" ++ field_modifier ++ "}\n";
                std.debug.print(fmt, .{ field.name, @field(self, field.name) });
            }
        }
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

    const config = try createConfig(ast_tree.root.object, alloc);
    log().info("Configuration loaded successfully", .{});

    config.debugPrint();

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

    try std.testing.expectEqualSlices(u8, "./scripts", config.scripts_dir);
    try std.testing.expectEqualSlices(u8, "./packages", config.packages_file);
    try std.testing.expectEqualSlices(u8, "./dotfiles", config.dotfiles_dir);
    // field not set defualt value
    try std.testing.expectEqualSlices(u8, DEFAULT_CACHE_FILE_PATH, config.cache_file);
}
