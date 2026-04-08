const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;
const SetupStatus = @import("package_status.zig").SetupStatus;
const util = @import("util.zig");
const cli = @import("cli.zig");
const log = @import("logger.zig").getGlobalLogger;

const Range = struct {
    start_number: u32,
    end_number: u32,
};

const InputTokenType = enum {
    number,
    range,
};

const InputToken = union(InputTokenType) { number: u32, range: Range };

/// Modifies the slice
/// Puts selected packages at the beginning of the slice
/// Returns a slice with selected packages
pub fn selectPackagesFromCache(packages: []PackageDescriptor, map: *const std.StringHashMap(SetupStatus)) []PackageDescriptor {
    var current_index: usize = 0;

    for (0..packages.len) |index| {
        if (map.contains(packages[index].name)) {
            std.mem.swap(PackageDescriptor, &packages[current_index], &packages[index]);
            current_index = current_index + 1;
        }
    }
    return packages[0..current_index];
}
// Modifies the origina slice and puts the selected packages at the beginning (and returns the new slice)
pub fn selectPackages(packages: []PackageDescriptor, alloc: std.mem.Allocator, writer: *std.io.Writer) ![]PackageDescriptor {
    for (packages, 1..) |p, i| {
        try writer.print("{d}. ", .{i});
        try p.formatShort(writer);
        _ = try writer.write("\n");
    }

    while (true) {
        try writer.print("All packages are included by default.", .{});
        try writer.print("Please enter numbers or inclusive ranges of the packages to exclude (i.e \"1 2 3 5-8 19 72 420 78_000 13 \")\n", .{});
        try writer.print(">>> ", .{});
        try writer.flush();

        const numbers = askForPackageNumbers(alloc, writer) catch continue;

        validateSelectedPackages(numbers.items, packages.len) catch {
            if (cli.askConfirmation("Validation failed, do you want to redo selection? (All invalid choices will be ignored)", .{}))
                continue;
        };

        return filterExcludedPackages(packages, numbers.items);
    }
}

fn validateSelectedPackages(tokens: []const InputToken, package_count: usize) !void {
    var failed = false;

    for (tokens) |token| {
        switch (token) {
            .range => |r| {
                if (r.start_number > package_count or r.end_number > package_count) {
                    // Writer failing here doesn't matter
                    log().warn("Range {d}-{d} goes over allowed package number equal to {d}", .{ r.start_number, r.end_number, package_count });
                    failed = true;
                }
            },
            .number => |v| {
                if (v > package_count) {
                    log().warn("Package number {d} goes over allowed package number equal to {d}", .{ v, package_count });
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
fn filterExcludedPackages(packages: []PackageDescriptor, tokens: []const InputToken) []PackageDescriptor {
    var current_index: usize = 0;

    for (0..packages.len) |index| {

        // packages numbered from 1
        const package_number = index + 1;

        // Selected packages are excluded
        if (!isSelected(package_number, tokens)) {
            std.mem.swap(PackageDescriptor, &packages[current_index], &packages[index]);
            current_index = current_index + 1;
        }
    }
    return packages[0..current_index];
}

fn isSelected(package_number: usize, tokens: []const InputToken) bool {
    for (tokens) |token| {
        switch (token) {
            InputToken.number => |num| {
                if (num == package_number)
                    return true;
            },
            InputToken.range => |range| {
                if ((range.start_number <= package_number and package_number <= range.end_number))
                    return true;
            },
        }
    }

    return false;
}

fn askForPackageNumbers(alloc: std.mem.Allocator, stdout: *std.io.Writer) !std.ArrayList(InputToken) {
    var buf: [256]u8 = undefined;

    const line_raw = util.readLine(&buf) catch |err| {
        log().err("Couldn't read input", .{});
        return err;
    };

    const input = util.clipWhitespace(line_raw);

    if (input.len == 0) {
        return try std.ArrayList(InputToken).initCapacity(alloc, 0);
    }

    var tokens = parseSelectionInput(input, alloc) catch |err| {
        log().err("There was an error when parsing input (err:{})", .{err});
        return err;
    };

    if (tokens.items.len <= 0) {
        tokens.deinit(alloc);
        try stdout.print("Please try again and insert valid package numbers.\n", .{});
        try stdout.flush();
        return error.InvalidInput;
    }

    return tokens;
}

fn parseSelectionInput(input: []const u8, alloc: std.mem.Allocator) (std.mem.Allocator.Error)!std.ArrayList(InputToken) {
    var tokens = try std.ArrayList(InputToken).initCapacity(alloc, input.len / 10);
    errdefer tokens.deinit(alloc);

    var tokenizer = std.mem.tokenizeScalar(u8, input, ' ');

    while (tokenizer.next()) |token| {
        const parsed = parseToken(token) catch |err| {
            log().err("Couldn't parse \"{s}\" (err: {any}). Skipping it...", .{ token, err });
            continue;
        };

        try tokens.append(alloc, parsed);
    }

    return tokens;
}

/// Tries to parse the given strtoken
///
/// On success returns a proper token
/// On failure returns error.UnknownToken
fn parseToken(strtoken: []const u8) (error{InvalidToken})!InputToken {
    return parseNumberToken(strtoken) catch parseRangeToken(strtoken) catch error.InvalidToken;
}

fn parseNumberToken(str: []const u8) std.fmt.ParseIntError!InputToken {
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

    return InputToken{ .range = Range{ .start_number = start, .end_number = end } };
}

//////////////////////////////////////////////////
//////////////////////////////////////////////////
///////////////////  TESTS  //////////////////////
//////////////////////////////////////////////////
//////////////////////////////////////////////////

const testing = std.testing;
const testalloc = testing.allocator;

test "Filtering packages by package number" {
    const tokens = [_]InputToken{
        InputToken{ .number = 1 },
        InputToken{ .number = 3 },
        InputToken{ .number = 5 },
    };

    var packages = [_]PackageDescriptor{
        PackageDescriptor{ .name = "P1", .description = "D1", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P2", .description = "D2", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null, .setup_command = null },
    };

    const filtered = filterExcludedPackages(&packages, &tokens);

    try testing.expectEqual(packages.len - tokens.len, filtered.len);

    try testing.expectEqualSlices(u8, "P2", filtered[0].name);
    try testing.expectEqualSlices(u8, "P4", filtered[1].name);
    try testing.expectEqualSlices(u8, "P6", filtered[2].name);
    try testing.expectEqualSlices(u8, "P7", filtered[3].name);
}

test "Filtering packages by package range" {
    const tokens = [_]InputToken{
        InputToken{ .range = .{ .start_number = 1, .end_number = 2 } },
        InputToken{ .range = .{ .start_number = 5, .end_number = 8 } },
        InputToken{ .range = .{ .start_number = 10, .end_number = 11 } },
    };

    var packages = [_]PackageDescriptor{
        PackageDescriptor{ .name = "P1", .description = "D1", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P2", .description = "D2", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P8", .description = "D8", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P9", .description = "D9", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P10", .description = "D10", .dependencies = null, .setup_command = null },
        PackageDescriptor{ .name = "P11", .description = "D11", .dependencies = null, .setup_command = null },
    };

    const filtered = filterExcludedPackages(&packages, &tokens);

    try testing.expectEqual(3, filtered.len);

    try testing.expectEqualSlices(u8, "P3", filtered[0].name);
    try testing.expectEqualSlices(u8, "P4", filtered[1].name);
    try testing.expectEqualSlices(u8, "P9", filtered[2].name);
}

test "Selected package with valid number returns true" {
    const tokens = [_]InputToken{InputToken{ .number = 15 }};
    const x = isSelected(15, &tokens);
    try testing.expectEqual(true, x);
}

test "Selected package with invalid number returns false" {
    const tokens = [_]InputToken{InputToken{ .number = 14 }};
    const x = isSelected(15, &tokens);
    try testing.expectEqual(false, x);
}

test "Selected package within specified range return true" {
    const tokens = [_]InputToken{InputToken{ .range = .{ .start_number = 10, .end_number = 20 } }};
    const x = isSelected(15, &tokens);
    try testing.expectEqual(true, x);
}

test "Selected package outside of specified range returns false" {
    const tokens = [_]InputToken{InputToken{ .range = .{ .start_number = 10, .end_number = 20 } }};
    const x = isSelected(9, &tokens);
    const y = isSelected(21, &tokens);
    try testing.expectEqual(false, x);
    try testing.expectEqual(false, y);
}

test "Selected package on the edge of range returns true" {
    const tokens = [_]InputToken{InputToken{ .range = .{ .start_number = 10, .end_number = 20 } }};
    const x = isSelected(10, &tokens);
    const y = isSelected(20, &tokens);
    try testing.expectEqual(true, x);
    try testing.expectEqual(true, y);
}

test "Parsing number token" {
    try testing.expectError(std.fmt.ParseIntError.InvalidCharacter, parseNumberToken("194bx"));
    try testing.expectError(std.fmt.ParseIntError.InvalidCharacter, parseNumberToken("19;4"));
    try testing.expectError(std.fmt.ParseIntError.InvalidCharacter, parseNumberToken("m10"));
    try testing.expectError(std.fmt.ParseIntError.InvalidCharacter, parseNumberToken("-10"));
    try testing.expectEqual(10, (try parseNumberToken("10")).number);
    try testing.expectEqual(69420, (try parseNumberToken("69420")).number);
    try testing.expectEqual(69420, (try parseNumberToken("69_420")).number);
}

test "Parsing valid range" {
    const res = try parseRangeToken("5-12");
    try testing.expect(res.range.start_number == 5 and res.range.end_number == 12);

    const res2 = try parseRangeToken("0-15");
    try testing.expect(res2.range.start_number == 0 and res2.range.end_number == 15);

    const res3 = try parseRangeToken("8-122");
    try testing.expect(res3.range.start_number == 8 and res3.range.end_number == 122);
}

test "range start higher than top should throw" {
    const res = parseRangeToken("12-9");
    try testing.expectError(error.InvalidRange, res);
}

test "Too much components of range OR negative numbers in range" {
    const res = parseRangeToken("12-125-99");
    try testing.expectError(error.InvalidRange, res);
}

test "Non numerical value in a range" {
    const res = parseRangeToken("15-asdasdeleven");
    try testing.expectError(error.InvalidRange, res);

    const res2 = parseRangeToken("dasda-15");
    try testing.expectError(error.InvalidRange, res2);

    const res3 = parseRangeToken("asd-asdasdeleven");
    try testing.expectError(error.InvalidRange, res3);
}

test "Not enough components in range" {
    const res = parseRangeToken("-xd");
    try testing.expectError(error.InvalidRange, res);

    const res2 = parseRangeToken("asd-");
    try testing.expectError(error.InvalidRange, res2);

    const res3 = parseRangeToken("5-");
    try testing.expectError(error.InvalidRange, res3);

    const res4 = parseRangeToken("-10");
    try testing.expectError(error.InvalidRange, res4);
}

test "Selecting packages from cache" {
    var cache_map = std.StringHashMap(SetupStatus).init(testing.allocator);
    defer cache_map.deinit();
    try cache_map.put("t1", SetupStatus.download);
    try cache_map.put("t2", SetupStatus.download);
    try cache_map.put("t3", SetupStatus.download);
    try cache_map.put("t4", SetupStatus.download);

    var packages = [_]PackageDescriptor{
        .{ .name = "t1", .description = null, .dependencies = null, .setup_command = null },
        .{ .name = "t69", .description = null, .dependencies = null, .setup_command = null },
        .{ .name = "t3", .description = null, .dependencies = null, .setup_command = null },
        .{ .name = "t4", .description = null, .dependencies = null, .setup_command = null },
        .{ .name = "t2", .description = null, .dependencies = null, .setup_command = null },
        .{ .name = "t5", .description = null, .dependencies = null, .setup_command = null },
    };

    const loaded = selectPackagesFromCache(&packages, &cache_map);

    try testing.expectEqual(loaded.len, 4);
    try testing.expectEqualSlices(u8, "t1", loaded[0].name);
    try testing.expectEqualSlices(u8, "t3", loaded[1].name);
    try testing.expectEqualSlices(u8, "t4", loaded[2].name);
    try testing.expectEqualSlices(u8, "t2", loaded[3].name);
}
