const std = @import("std");
const package = @import("loading_packages.zig");

const Range = struct {
    start: u32,
    end: u32,
};

const InputTokenType = enum {
    number,
    range,
};

const InputToken = union(InputTokenType) { number: u32, range: Range };

fn askForPackages() []InputToken {
    const stdin = std.io.getStdIn().reader();

    while (true) {
        if (stdin.readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 4096)) |input| {
            defer std.heap.page_allocator.free(input);

            parseSelectionInput(input):

        } else |err| {
            switch (err) {
                error.StreamTooLong => {
                    std.log.err("Input string is too long\n", .{});
                },
                std.mem.Allocator.Error => {
                    std.log.err("Couldn't allocate memory, try again\n", .{});
                },
                error.NoEofError => {
                    std.log.err("No EOF, please try again\n", .{});
                }
            }
        }
    }
}

fn parseSelectionInput(input:[]const u8) []InputToken
