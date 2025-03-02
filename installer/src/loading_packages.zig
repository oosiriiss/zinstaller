const std = @import("std");
const util = @import("util.zig");

const PackageDescriptor = struct {
    name: []const u8,
    description: []const u8,
    dependencies: ?[]PackageDescriptor,

    const Self = @This();

    fn init(params: struct { name: []const u8, description: []const u8, allocator: std.mem.Allocator }) !PackageDescriptor {
        const name = try params.allocator.dupe(u8, params.name);
        errdefer params.allocator.free(name);

        const description = try params.allocator.dupe(u8, params.description);
        errdefer params.allocator.free(description);

        return Self{ .name = name, .description = description, .dependencies = null };
    }

    //
    // Returns updated PackageDescriptor with specified dependencies
    //
    // Dependencies names,descriptions etc. must remain valid!
    // Sets the dependencies in reverse order last = first
    //
    fn setDependencies(self: Self, deps: []RawPackageDescriptor, allocator: std.mem.Allocator) !Self {
        if (deps.len == 0) {
            return self;
        }

        var dependencies = try allocator.alloc(PackageDescriptor, deps.len);
        var i: usize = dependencies.len;
        for (deps) |d| {
            i = i - 1;
            dependencies[i] = d.pkg;
        }

        return Self{ .name = self.name, .description = self.description, .dependencies = dependencies };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);

        if (self.dependencies) |deps| {
            for (0..deps.len) |i| {
                deps[i].deinit(allocator);
            }
            allocator.free(deps);
        }
    }

    // Prints the package
    pub fn print(self: Self, writer: std.fs.File.Writer) !void {
        try self.printWithIndent(0, writer);
    }

    // Print helper to tree-like printing with indents
    fn printWithIndent(self: Self, indent: u8, writer: std.fs.File.Writer) !void {
        try util.printCharN('\t', indent, writer);
        _ = try writer.write("Package {\n");
        try util.printCharN('\t', indent + 1, writer);
        _ = try writer.print("name: \"{s}\"\n", .{self.name});
        try util.printCharN('\t', indent + 1, writer);
        _ = try writer.print("description: \"{s}\"\n", .{self.description});
        try util.printCharN('\t', indent + 1, writer);
        if (self.dependencies) |ds| {
            _ = try writer.write("dependencies: [\n");
            for (ds) |d|
                try d.printWithIndent(indent + 2, writer);

            try util.printCharN('\t', indent + 1, writer);
            _ = try writer.write("]\n");
        } else {
            _ = try writer.write("dependencies: []");
        }

        try util.printCharN('\t', indent, writer);
        _ = try writer.write("}\n");
    }
};

const RawPackageDescriptor = struct { pkg: PackageDescriptor, indent: u8 };

const ReadPackageError = error{ PackageTooLong, ReadError };

// Actual function that does all the loading
pub fn loadPackages(filename: []const u8) ![]PackageDescriptor {
    const raw = try loadRawPackagesFromFile(filename);
    defer raw.deinit();
    return try createPackageTree(raw.items);
}

// Loads packages without set dependencies yet
// just parses the file and extracts the name and description along with indent of the package to help with package dependencies
fn loadRawPackagesFromFile(filename: []const u8) !std.ArrayList(RawPackageDescriptor) {
    const flags: std.fs.File.OpenFlags = .{ .mode = .read_only };
    const file = try std.fs.cwd().openFile(filename, flags);
    defer file.close();

    const file_reader = file.reader();
    var buf: [4096]u8 = undefined;

    var packages = std.ArrayList(RawPackageDescriptor).init(std.heap.page_allocator);

    while (true) {
        const slice = file_reader.readUntilDelimiterOrEof(&buf, ' ') catch |err| {
            if (err == error.StreamTooLong)
                return ReadPackageError.PackageTooLong
            else
                return ReadPackageError.ReadError;
        };
        // EOF
        if (slice == null)
            break;

        var tokenizer = std.mem.tokenizeScalar(u8, slice.?, '=');
        const nameToken = tokenizer.next();
        const descriptionToken = tokenizer.next();
        const indent = try util.countIndent(slice.?);

        if (nameToken == null or descriptionToken == null) {
            std.debug.print("Couldn't parse Package. LINE: {s}", .{buf});
            continue;
        }

        const name = util.clipWhitespace(nameToken.?);
        const description = util.clipWhitespace(descriptionToken.?);
        const package = try PackageDescriptor.init(.{ .name = name, .description = description, .allocator = std.heap.page_allocator });

        try packages.append(.{ .pkg = package, .indent = indent });
    }

    return packages;
}

fn countChildren(items: []const RawPackageDescriptor) usize {
    if (items.len == 0)
        return 0;

    var j: usize = items.len;
    const siblingIndent = items[items.len - 1].indent;
    var count: usize = 0;

    while (j > 0 and items[j - 1].indent == siblingIndent) {
        j = j - 1;
        count = count + 1;
    }

    return count;
}

// Allcates all resources and returns a slice of the Packages
fn createPackageTree(pkgs: []const RawPackageDescriptor) ![]PackageDescriptor {
    std.debug.assert(pkgs.len > 0);

    // Setting dependencies from the end
    //

    // Output packages
    var packagesStack = std.ArrayList(RawPackageDescriptor).init(std.heap.page_allocator);
    defer packagesStack.deinit();

    var i: usize = pkgs.len;

    while (i > 0) {
        i = i - 1;
        const curr = pkgs[i];

        //
        const prev_indent = if (packagesStack.getLastOrNull()) |last|
            last.indent
        else
            curr.indent;

        if (curr.indent < prev_indent) {
            const children_count = if (curr.indent == prev_indent) 0 else countChildren(packagesStack.items);

            const start = (packagesStack.items.len - children_count);
            const end = packagesStack.items.len;

            const updated = try curr.pkg.setDependencies(packagesStack.items[start..end], std.heap.page_allocator);
            // Deleting the children
            for (0..children_count) |_|
                _ = packagesStack.pop();

            try packagesStack.append(RawPackageDescriptor{ .indent = curr.indent, .pkg = updated });
        } else try packagesStack.append(curr);
    }

    // Counting root packages
    var root_count: u32 = 0;
    for (pkgs) |package| {
        if (package.indent == 0)
            root_count = root_count + 1;
    }

    // Copying the packages to the final array
    var root_packages = try std.heap.page_allocator.alloc(PackageDescriptor, root_count);

    for (0..root_packages.len) |j| {
        const pkg = packagesStack.pop();
        std.debug.assert(pkg.indent == 0);
        root_packages[j] = pkg.pkg;
    }

    return root_packages;
}

/////////////////////////////////
////////////  TESTS   ///////////
/////////////////////////////////

test "Creatin Package tree with only 2 levels" {
    const pkgs = [_]RawPackageDescriptor{
        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P1", .description = "D1", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P2", .description = "D2", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null } },
        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null } },
        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null } },
    };

    const res = try createPackageTree(&pkgs);

    try std.testing.expectEqual(3, res.len);
    try std.testing.expectEqualStrings(res[0].name, "P1");
    try std.testing.expectEqualStrings(res[0].dependencies.?[0].name, "P2");
    try std.testing.expectEqualStrings(res[0].dependencies.?[1].name, "P3");
    try std.testing.expectEqualStrings(res[1].name, "P4");
    try std.testing.expectEqualStrings(res[1].dependencies.?[0].name, "P5");
    try std.testing.expectEqualStrings(res[1].dependencies.?[1].name, "P6");
    try std.testing.expectEqualStrings(res[2].name, "P7");
    try std.testing.expectEqual(2, res[0].dependencies.?.len);
    try std.testing.expectEqual(2, res[1].dependencies.?.len);
    try std.testing.expectEqual(null, res[2].dependencies);
}

test "Creatin Package tree with only many levels" {
    const pkgs = [_]RawPackageDescriptor{
        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P1", .description = "D1", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P2", .description = "D2", .dependencies = null } },
        .{ .indent = 2, .pkg = PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null } },

        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null } },

        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null } },
        .{ .indent = 2, .pkg = PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P8", .description = "D8", .dependencies = null } },

        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P9", .description = "D9", .dependencies = null } },
    };

    const res = try createPackageTree(&pkgs);

    try std.testing.expectEqual(3, res.len);

    try std.testing.expectEqualStrings(res[0].name, "P1");
    try std.testing.expectEqualStrings(res[0].dependencies.?[0].name, "P2");
    try std.testing.expectEqualStrings(res[0].dependencies.?[0].dependencies.?[0].name, "P3");

    try std.testing.expectEqualStrings(res[1].name, "P4");
    try std.testing.expectEqualStrings(res[1].dependencies.?[0].name, "P5");
    try std.testing.expectEqualStrings(res[1].dependencies.?[1].name, "P6");
    try std.testing.expectEqualStrings(res[1].dependencies.?[2].name, "P8");
    try std.testing.expectEqualStrings(res[1].dependencies.?[1].dependencies.?[0].name, "P7");

    try std.testing.expectEqualStrings(res[2].name, "P9");

    try std.testing.expectEqual(1, res[0].dependencies.?.len);
    try std.testing.expectEqual(3, res[1].dependencies.?.len);
    try std.testing.expectEqual(null, res[2].dependencies);
}

test "Printing test" {
    const pkgs = [_]RawPackageDescriptor{
        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P1", .description = "D1", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P2", .description = "D2", .dependencies = null } },
        .{ .indent = 2, .pkg = PackageDescriptor{ .name = "P3", .description = "D3", .dependencies = null } },

        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P4", .description = "D4", .dependencies = null } },

        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P5", .description = "D5", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P6", .description = "D6", .dependencies = null } },
        .{ .indent = 2, .pkg = PackageDescriptor{ .name = "P7", .description = "D7", .dependencies = null } },
        .{ .indent = 1, .pkg = PackageDescriptor{ .name = "P8", .description = "D8", .dependencies = null } },

        .{ .indent = 0, .pkg = PackageDescriptor{ .name = "P9", .description = "D9", .dependencies = null } },
    };

    const res = try createPackageTree(&pkgs);

    try res[0].print(std.io.getStdOut().writer());
}
