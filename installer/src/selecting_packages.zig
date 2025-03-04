const std = @import("std");
const package = @import("loading_packages.zig");
const util = @import("util.zig");

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

pub fn selectPackages(packages: []package.PackageDescriptor) ![]package.PackageDescriptor {
    try printRecursive(selectPackages);

    while (true) {
        util.print("Please numbers or ranges of desired packages (i.e \"1 2 3 5-8 19 72 420 13\")\n", .{});
        util.print(">>> ", .{});
        if (askForPackageNumbers()) |numbers| {
            return filterSelectedPackages(packages, numbers);
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
    //
}

fn printRecursive(packages: []const package.PackageDescriptor, writer: anytype) !void {
    const PkgIndent = struct { indent: u8, pkg: package.PackageDescriptor };

    var stack = try std.ArrayList(PkgIndent).initCapacity(std.heap.page_allocator, packages.len + 10);

    // Reverse to maintain the correct printing order of packages
    for (0..packages.len) |i| {
        try stack.append(.{ .indent = 0, .pkg = packages[packages.len - 1 - i] });
    }

    var current_index: usize = 0;

    while (stack.items.len > 0) {
        const item = stack.pop();
        const current_package = item.pkg;
        const current_indent = item.indent;

        try util.printCharN('\t', current_indent, writer);

        if (current_indent == 0) {
            try writer.print("{d}. ", .{current_index});
            current_index = current_index + 1;
        }

        try writer.print("{s} - {s}\n", .{ current_package.name, current_package.description });

        if (current_package.dependencies) |deps| {
            for (0..deps.len) |i| {
                // Reverse to maintain the correct printing order of packages
                try stack.append(.{ .indent = current_indent + 1, .pkg = deps[deps.len - 1 - i] });
            }
        }
    }
}

///
/// Modifies the slice
/// Puts selected packages at the beginning of the slice
///
/// Returns a slice with selected packages
///
fn filterSelectedPackages(packages: []package.PackageDescriptor, tokens: []const InputToken) ![]package.PackageDescriptor {
    var current_index: usize = 0;

    for (0..packages.len) |i| {
        if (isSelected(i, tokens)) {
            std.mem.swap(package.PackageDescriptor, &packages[current_index], &packages[i]);
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

fn askForPackageNumbers() std.mem.Allocator.Error!std.ArrayList(InputToken) {
    const stdin = std.io.getStdIn().reader();

    const input = stdin.readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 4096);
    defer std.heap.page_allocator.free(input);

    const tokens = try parseSelectionInput(input);
    if (tokens.items.len <= 0) {
        tokens.deinit();
        std.debug.print("Please insert valid numbers\n", .{});
    }

    return tokens;
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

/// Tries to parse the given strtoken
///
/// On success returns a proper token
/// On failure returns error.UnknownToken
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

test "Filtering packages" {
    const PackageDescriptor = package.PackageDescriptor;

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

test "Recursive enumrated print" {
    const PackageDescriptor = package.PackageDescriptor;

    var deps1_deps = [_]PackageDescriptor{ //
    PackageDescriptor{ .name = "P1_DEP1_DEP1_NAME", .description = "P1_DEP1_DEP1_DESC", .dependencies = null }};

    var deps1 = [_]PackageDescriptor{ //
    PackageDescriptor{
        .name = "P1_DEP1_NAME",
        .description = "P1_DEP1_DESC",
        //
        .dependencies = &deps1_deps,
    }};

    var deps2_deps2_deps = [_]PackageDescriptor{PackageDescriptor{ .name = "P2_DEP2_DEP1_NAME", .description = "P2_DEP2_DEP1_DESC", .dependencies = null }};

    var deps2_deps = [_]PackageDescriptor{ //
        PackageDescriptor{ .name = "P2_DEP1_DEP1_NAME", .description = "P2_DEP1_DEP1_DESC", .dependencies = null },
        PackageDescriptor{
            .name = "P2_DEP2_NAME",
            .description = "P2_DEP2_DESC",
            //
            .dependencies = &deps2_deps2_deps,
        },
    };

    var deps2 = [_]PackageDescriptor{ //
    PackageDescriptor{
        .name = "P2_DEP1_NAME",
        .description = "P2_DEP1_DESC",
        //
        .dependencies = &deps2_deps,
    }};

    var packages = [_]PackageDescriptor{
        PackageDescriptor{
            .name = "P1",
            .description = "D1",
            //
            .dependencies = &deps1,
        },

        PackageDescriptor{
            .name = "P2",
            .description = "D2",
            .dependencies = &deps2,
        },
        PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null },
        PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null },
        PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null },
        PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null },
        PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null },
    };

    try printRecursive(&packages, std.io.null_writer);
}
