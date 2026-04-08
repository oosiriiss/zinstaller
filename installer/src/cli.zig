const std = @import("std");
const util = @import("util.zig");

pub fn askConfirmation(comptime msg: []const u8, args: anytype) bool {
    // TODO :: Should this return an error?

    var buf: [64]u8 = undefined;

    var stdoutBuffer: [128]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdoutBuffer).interface;

    while (true) {
        stdout.print(msg, args) catch continue;
        stdout.print("(y/n)", .{}) catch continue;
        stdout.flush() catch continue;

        if (util.readLine(&buf)) |lineRaw| {
            const lowered_line = std.ascii.lowerString(&buf, lineRaw);
            const line = util.clipWhitespace(lowered_line);

            // Defaults to confirmation
            if (line.len == 0)
                return true;

            if (std.mem.eql(u8, line, "y"))
                return true;

            if (line.len >= 3 and std.mem.eql(u8, line[0..3], "yes"))
                return true;

            return false;
        } else |err| {
            std.debug.print("Error encountered when reading input. Try Again. (error: {any})\n", .{err});
        }
    }
}
