const std = @import("std");
const package = @import("loading_packages.zig");
const util = @import("util.zig");

const Range = struct {
    start: u32,
    end: u32,
};

const InputTokenType = enum {
    number,
    range,
};

const InputToken = union(InputTokenType) { number: u32, range: Range };

fn askForPackages() std.ArrayList(InputToken) {
    const stdin = std.io.getStdIn().reader();

    while (true) {
        util.print("Please numbers or ranges of desired packages (i.e \"1 2 3 5-8 19 72 420 13\")\n", .{});
        util.print(">>> ", .{});

        if (stdin.readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 4096)) |input| {
            defer std.heap.page_allocator.free(input);

            //
            parseSelectionInput(input);
            //

        } else |err| {
            switch (err) {
                error.StreamTooLong => {
                    std.debug.print("Input string is too long\n", .{});
                },
                std.mem.Allocator.Error => {
                    std.debug.print("Couldn't allocate memory, try again\n", .{});
                },
                error.NoEofError => {
                    std.debug.print("No EOF, please try again\n", .{});
                },
            }
        }
    }
}

fn parseSelectionInput(input: []const u8) !std.ArrayList(InputToken) {
    const tokens = std.ArrayList(InputToken);

    const tokenizer = std.mem.tokenizeScalar(u8, input, ' ');

    while (tokenizer.next()) |token| {
        if (parseToken(token)) |parsed_token|
            try tokens.append(parsed_token)
        else
            std.debug.print("Couldn't parse {s}. Skipping it...\n", .{token});
    }

    return tokens;
}

// Tries to parse the given strtoken
//
// On success returns a proper token
// On failure returns error.UnknownToken
fn parseToken(strtoken: []const u8) !InputToken {
    if (parseNumberToken(strtoken)) |n|
        return n;

    if (parseRangeToken(strtoken)) |r|
        return r;

    return error.UnknownToken;
}

fn parseNumberToken(str: []const u8) !InputToken {
    return std.fmt.parseInt(u32, str, 10);
}

fn parseRangeToken(str: []const u8) !InputToken {
    const splitIter = std.mem.splitScalar(str, '-');

    const bottom = splitIter.next() orelse return error.ParseError;
    const top = splitIter.next() orelse return error.ParseError;

    try std.fmt.parseInt(bottom);
    try std.fmt.parseInt(top);

    if (splitIter.next() != null)
        return false;

    return InputToken{ .range = Range{ .start = bottom, .top = top } };
}
