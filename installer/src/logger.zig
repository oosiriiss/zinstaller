const std = @import("std");
const openFile = @import("util.zig").openFileWrite;
const builtin = @import("builtin");

const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const MAGENTA = "\x1b[35m";
const CYAN = "\x1b[36m";
const RESET = "\x1b[0m";

// for convenience
var global_logger: Logger = undefined;

pub fn initializeGlobalLogger() void {
    global_logger.init();
}

// Logger must be initialized with initGlobalLogger
pub fn getGlobalLogger() *Logger {
    initializeGlobalLogger();
    return &global_logger;
}

pub fn shutdownGlobalLogger() void {
    global_logger.deinit();
}

const Level = enum {
    info,
    warn,
    err,
    debug,
};

pub const Logger = struct {
    stdout: *std.io.Writer,
    stdout_file_writer: std.fs.File.Writer,
    log_writer: std.io.Writer,
    log_file_writer: std.fs.File.Writer,
    log_file: ?std.fs.File,

    stdout_buffer: [512]u8,
    file_buffer: [512]u8,

    next_file_only: bool,
    next_stdout_only: bool,

    const Self = @This();

    pub fn init(self: *Self) void {
        self.log_file = null;
        self.next_file_only = false;
        self.next_stdout_only = false;

        self.stdout_buffer = undefined;
        self.file_buffer = undefined;

        self.stdout_file_writer = std.fs.File.stdout().writer(&.{});

        self.stdout = &self.stdout_file_writer.interface;
    }

    pub fn deinit(self: *Self) void {
        if (self.log_file) |file| {
            file.close();
        }
    }

    // Make sure to call deinit to close the file handle after.
    pub fn initLogFile(self: *Self, log_file_path: []const u8) !void {
        if (self.log_file) |file| {
            file.close();
        }

        const file = try openFile(log_file_path);
        self.log_file = file;

        self.log_file_writer = self.log_file.?.writer(&.{});
        self.log_writer = self.log_file_writer.interface;

        self.info("Logging file intialized {s}", .{log_file_path});
    }

    // Next logging will be only redirected to stdout
    pub fn nextStdoutOnly(self: *Self) void {
        self.next_stdout_only = true;
    }

    // Next logging will be only redirected to th elog file if it exists.
    pub fn nextFileOnly(self: *Self) void {
        self.next_file_only = true;
    }

    pub fn info(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub fn warn(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub fn err(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    // Only works in debug builds
    pub fn debug(self: *Self, comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            self.log(.debug, fmt, args);
        }
    }

    fn log(self: *Self, comptime level: Level, comptime fmt: []const u8, args: anytype) void {
        if (comptime builtin.is_test) {
            return;
        }

        const stdout_fmt = comptime createStdOutFmt(level, fmt);
        const file_fmt = comptime createFileFmt(level, fmt);

        if (!self.next_file_only) {
            self.stdout.print(stdout_fmt, args) catch |e| {
                std.debug.print("Writing to stdout failed: (err: {any})", .{e});
            };
        }

        if (!self.next_stdout_only and self.log_file != null) {
            self.log_writer.print(file_fmt, args) catch |e| {
                std.debug.print("Writing to file failed: (err: {any})", .{e});
            };
        }

        self.resetExclusiveLog();
    }

    fn resetExclusiveLog(self: *Self) void {
        self.next_file_only = false;
        self.next_stdout_only = false;
    }
    fn createStdOutFmt(comptime level: Level, comptime fmt: []const u8) []const u8 {
        return switch (level) {
            .info => "[" ++ CYAN ++ "INFO" ++ RESET ++ "]: " ++ fmt ++ "\n",
            .warn => "[" ++ YELLOW ++ "WARN" ++ RESET ++ "]: " ++ fmt ++ "\n",
            .err => "[" ++ RED ++ "ERROR" ++ RESET ++ "]: " ++ fmt ++ "\n",
            .debug => "[" ++ MAGENTA ++ "DEBUG" ++ RESET ++ "]: " ++ fmt ++ "\n",
        };
    }
    fn createFileFmt(comptime level: Level, comptime fmt: []const u8) []const u8 {
        return switch (level) {
            .info => "[INFO]: " ++ fmt ++ "\n",
            .warn => "[WARN]: " ++ fmt ++ "\n",
            .err => "[ERROR]: " ++ fmt ++ "\n",
            .debug => "[DEBUG]: " ++ fmt ++ "\n",
        };
    }
};
