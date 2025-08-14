const std = @import("std");
const openFile = @import("util.zig").openFileWrite;

const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const MAGENTA = "\x1b[35m";
const CYAN = "\x1b[36m";
const RESET = "\x1b[0m";

const writer = if (@import("builtin").is_test) std.io.null_writer.any() else std.io.getStdOut().writer().any();
// for convenience
var global_logger: Logger = Logger.init(writer);

// Logger must be initialized with initGlobalLogger
pub fn getGlobalLogger() *Logger {
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
    stdout: std.io.AnyWriter,
    log_file: ?std.fs.File,
    next_file_only: bool,
    next_stdout_only: bool,

    const Self = @This();

    pub fn init(stdout_writer: std.io.AnyWriter) Self {
        return .{
            .stdout = stdout_writer,
            .log_file = null,
            .next_stdout_only = false,
            .next_file_only = false,
        };
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
        const stdout_fmt = comptime createStdOutFmt(level, fmt);
        const file_fmt = comptime createFileFmt(level, fmt);

        if (!self.next_file_only) {
            self.stdout.print(stdout_fmt, args) catch |e| {
                std.debug.print("Writing to stdout failed: (err: {any})", .{e});
            };
        }

        if (!self.next_stdout_only) {
            if (self.log_file) |f| {
                f.writer().print(file_fmt, args) catch |e| {
                    std.debug.print("Writing to file failed: (err: {any})", .{e});
                };
            }
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
