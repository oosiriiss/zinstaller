const std = @import("std");
const util = @import("util.zig");

test "countIndent:: No indent in string" {
    const str = "Some String!";

    const indents = util.countIndent(str);
    try std.testing.expectEqual(0, indents);
}

test "countIndent:: proper coutning of indenting with tabs " {
    const t1 = "        x";
    const t2 = "\t\tx";
    const t3 = "\t\t\tx";

    const a1 = util.countIndent(t1);
    const a2 = util.countIndent(t2);
    const a3 = util.countIndent(t3);

    try std.testing.expectEqual(2, a1);
    try std.testing.expectEqual(2, a2);
    try std.testing.expectEqual(3, a3);
}

test "countIndent:: proper counting of indenting with spaces" {
    const t1 = "    x";
    const t2 = "        x";
    const t3 = "            x";

    const a1 = util.countIndent(t1);
    const a2 = util.countIndent(t2);
    const a3 = util.countIndent(t3);

    try std.testing.expectEqual(1, a1);
    try std.testing.expectEqual(2, a2);
    try std.testing.expectEqual(3, a3);
}

test "countIndent:: Error on ill-formated space indent" {
    const t1 = "  x";
    const t2 = "     x";
    const t3 = "           x";

    const a1 = util.countIndent(t1);
    const a2 = util.countIndent(t2);
    const a3 = util.countIndent(t3);

    std.debug.print("ERROR: {any}\n", .{a1});
    std.debug.print("ERROR: {any}\n", .{a2});
    std.debug.print("ERROR: {any}\n", .{a3});

    try std.testing.expectError(util.IndentError.InvalidSpaceIndent, a1);
    try std.testing.expectError(util.IndentError.InvalidSpaceIndent, a2);
    try std.testing.expectError(util.IndentError.InvalidSpaceIndent, a3);
}
