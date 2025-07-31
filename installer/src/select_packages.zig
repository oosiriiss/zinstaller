const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const util = @import("util.zig");
const cli = @import("cli.zig");

const Range = struct {
    /// Inclusive
    start: u32,
    /// Inclusive
    end: u32,
};

const InputTokenType = enum {
    number,
    range,
};

const InputToken = union(InputTokenType) { number: u32, range: Range };

// Modifies the origina slice and puts the selected packages at the beginning (and returns the new slice)
pub fn selectPackages(packages: []PackageDescriptor, writer: std.io.AnyWriter) ![]PackageDescriptor {
    for (packages, 1..) |p, i| {
        try writer.print("{d}. ", .{i});
        try p.formatShort(writer);
        _ = try writer.write("\n");
    }

    while (true) {
        try util.print("Please enter numbers or ranges of desired packages (i.e \"1 2 3 5-8 19 72 420 13\")\n", .{});
        try util.print(">>> ", .{});

        const numbers = askForPackageNumbers() catch continue;

        validateSelectedPackages(numbers.items, packages.len) catch {
            if (cli.askConfirmation("Validation failed, do you want to redo selection? (All invalid choices will be ignored) (y/n) ", .{}))
                continue;
        };

        return filterSelectedPackages(packages, numbers.items);
    }
}

fn validateSelectedPackages(tokens: []const InputToken, package_count: usize) !void {
    var failed = false;

    for (tokens) |token| {
        switch (token) {
            .range => |r| {
                if (r.end > package_count or r.start > package_count) {
                    // Writer failing here doesn't matter
                    std.log.warn("Range {d}-{d} goes over allowed package number equal to {d}", .{ r.start, r.end, package_count });
                    failed = true;
                }
            },
            .number => |v| {
                if (v > package_count) {
                    std.log.warn("Package number {d} goes over allowed package number equal to {d}", .{ v, package_count });
                    failed = true;
                }
            },
        }
    }

    if (failed)
        return error.ValidationFailed;
}

///
/// Modifies the slice
/// Puts selected packages at the beginning of the slice
///
/// Returns a slice with selected packages
///
fn filterSelectedPackages(packages: []PackageDescriptor, tokens: []const InputToken) ![]PackageDescriptor {
    var current_index: usize = 0;

    for (0..packages.len) |i| {
        if (isSelected(i, tokens)) {
            std.mem.swap(PackageDescriptor, &packages[current_index], &packages[i]);
            current_index = current_index + 1;
        }
    }
    return packages[0..current_index];
}

fn isSelected(index: usize, tokens: []const InputToken) bool {
    for (tokens) |token| {
        switch (token) {
            InputToken.number => |num| {
                if (num == index)
                    return true;
            },
            InputToken.range => |range| {
                if ((range.start <= index and index <= range.end))
                    return true;
            },
        }
    }

    return false;
}

fn askForPackageNumbers() !std.ArrayList(InputToken) {
    var buf: [256]u8 = undefined;

    const line_raw = util.readLine(&buf) catch |err| {
        std.log.err("Couldn't read input", .{});
        return err;
    };

    const input = util.clipWhitespace(line_raw);

    const tokens = parseSelectionInput(input) catch |err| {
        std.log.err("There was an error when parsing input (err:{})", .{err});
        return err;
    };

    if (tokens.items.len <= 0) {
        tokens.deinit();
        util.print("Please try again anda insert valid package numbers.\n", .{}) catch {};
        return error.InvalidInput;
    }

    return tokens;
}

fn parseSelectionInput(input: []const u8) (std.mem.Allocator.Error)!std.ArrayList(InputToken) {
    var tokens = std.ArrayList(InputToken).init(std.heap.page_allocator);
    errdefer tokens.deinit();

    var tokenizer = std.mem.tokenizeScalar(u8, input, ' ');

    while (tokenizer.next()) |token| {
        const parsed = parseToken(token) catch |err| {
            std.log.err("Couldn't parse \"{s}\" (err: {any}). Skipping it...", .{ token, err });
            continue;
        };

        try tokens.append(parsed);
    }

    return tokens;
}

/// Tries to parse the given strtoken
///
/// On success returns a proper token
/// On failure returns error.UnknownToken
fn parseToken(strtoken: []const u8) (error{InvalidToken})!InputToken {
    if (parseNumberToken(strtoken)) |n|
        return n
    else |_| {}

    if (parseRangeToken(strtoken)) |r|
        return r
    else |_| {}

    return error.InvalidToken;
}

fn parseNumberToken(str: []const u8) !InputToken {
    const number = try std.fmt.parseUnsigned(u32, str, 10);
    return InputToken{ .number = number };
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

test "Filtering packages" {
    const tokens = [_]InputToken{
        InputToken{ .number = 0 },
        InputToken{ .number = 1 },
        InputToken{ .range = .{ .start = 1, .end = 3 } },
        InputToken{ .range = .{ .start = 5, .end = 6 } },
    };

    var packages = [_]PackageDescriptor{
        PackageDescriptor{ .name = "P1", .description = "D1", .dependencies = null },
        PackageDescriptor{ .name = "P2", .description = "D2", .dependencies = null },
        PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null },
        PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null },
        PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null },
        PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null },
        PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null },
    };

    const filtered = try filterSelectedPackages(&packages, &tokens);

    try std.testing.expectEqual(6, filtered.len);

    try std.testing.expectEqualSlices(u8, filtered[0].name, "P1");
    try std.testing.expectEqualSlices(u8, filtered[1].name, "P2");
    try std.testing.expectEqualSlices(u8, filtered[2].name, "P3");
    try std.testing.expectEqualSlices(u8, filtered[3].name, "P4");
    try std.testing.expectEqualSlices(u8, filtered[4].name, "P6");
    try std.testing.expectEqualSlices(u8, filtered[5].name, "P7");
}

test "Selected package with number return true" {
    const tokens = [_]InputToken{InputToken{ .number = 15 }};
    const x = isSelected(15, &tokens);
    try std.testing.expectEqual(true, x);
}

test "Selected package number return false" {
    const tokens = [_]InputToken{InputToken{ .number = 14 }};
    const x = isSelected(15, &tokens);
    try std.testing.expectEqual(false, x);
}

test "Selected package with range return true" {
    const tokens = [_]InputToken{InputToken{ .range = .{ .start = 10, .end = 20 } }};
    const x = isSelected(15, &tokens);
    try std.testing.expectEqual(true, x);
}

test "Selected package number range false" {
    const tokens = [_]InputToken{InputToken{ .range = .{ .start = 10, .end = 20 } }};
    const x = isSelected(9, &tokens);
    try std.testing.expectEqual(false, x);
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
