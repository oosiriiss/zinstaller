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




pub fn selectPackages() {

//
        util.print("Please numbers or ranges of desired packages (i.e \"1 2 3 5-8 19 72 420 13\")\n", .{});
        util.print(">>> ", .{});
}






fn askForPackages() std.mem.Allocator.Error!std.ArrayList(InputToken) {
    const stdin = std.io.getStdIn().reader();

    while (true) {

        if (stdin.readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 4096)) |input| {
            defer std.heap.page_allocator.free(input);

            const tokens = try parseSelectionInput(input);
            if (tokens.items.len <= 0) {
                tokens.deinit();
                std.debug.print("Please insert valid numbers\n", .{});
            }

            return tokens;
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

fn parseSelectionInput(input: []const u8) std.mem.Allocator.Error!std.ArrayList(InputToken) {
    const tokens = std.ArrayList(InputToken).init(std.heap.page_allocator);

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

fn parseRangeToken(str: []const u8) error{InvalidRange}!InputToken {
    var splitIter = std.mem.splitScalar(u8, str, '-');

    const startToken = splitIter.next() orelse return error.InvalidRange;
    const endToken = splitIter.next() orelse return error.InvalidRange;

    const start = std.fmt.parseInt(u32, startToken, 10) catch return error.InvalidRange;
    const end = std.fmt.parseInt(u32, endToken, 10) catch return error.InvalidRange;

    if (splitIter.next() != null)
        return error.InvalidRange;

    if (start > end)
        return error.InvalidRange;

    return InputToken{ .range = Range{ .start = start, .end = end } };
}

test "Parsing valid range" {
    const res = try parseRangeToken("5-12");
    try std.testing.expect(res.range.start == 5 and res.range.end == 12);

    const res2 = try parseRangeToken("0-15");
    try std.testing.expect(res2.range.start == 0 and res2.range.end == 15);

    const res3 = try parseRangeToken("8-122");
    try std.testing.expect(res3.range.start == 8 and res3.range.end == 122);
}

test "range start higher than top should throw" {
    const res = parseRangeToken("12-9");
    try std.testing.expectError(error.InvalidRange, res);
}

test "Too much components of range OR negative numbers in range" {
    const res3 = parseRangeToken("12-125-99");
    try std.testing.expectError(error.InvalidRange, res3);
}

test "Non numerical value in a range" {
    const res = parseRangeToken("15-asdasdeleven");
    try std.testing.expectError(error.InvalidRange, res);

    const res2 = parseRangeToken("dasda-15");
    try std.testing.expectError(error.InvalidRange, res2);

    const res3 = parseRangeToken("asd-asdasdeleven");
    try std.testing.expectError(error.InvalidRange, res3);
}

test "Not enough components in range" {
    const res = parseRangeToken("-xd");
    try std.testing.expectError(error.InvalidRange, res);

    const res2 = parseRangeToken("asd-");
    try std.testing.expectError(error.InvalidRange, res2);
}
