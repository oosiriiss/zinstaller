const std = @import("std");

const PackageDescriptor = struct {
    name: []const u8,
    description: []const u8,
    dependencies: ?[]PackageDescriptor,
    allocator: std.mem.Allocator,

    const Self = @This();

    fn init(params: struct { name: []const u8, description: []const u8, dependencies: ?[]PackageDescriptor, allocator: std.mem.Allocator }) PackageDescriptor {
        allocator = params.allocator;

        var name = try params.allocator.alloc(u8, params.name.len);
        errdefer params.allocator.free(name);

        var description = try params.allocator.alloc(u8, params.description.len);
        errdefer params.allocator.free(description);

        var dependencies = null;

        std.mem.copyForwards(u8, name, params.name);
        std.mem.copyForwards(u8, description, params.description);

        if (params.dependencies) |deps| {
            dependencies = params.allocator.alloc(PackageDescriptor, deps.len);
            errdefer params.allocator.free(dependencies);
        }

        return .{ name, description, dependencies };
    }

    fn deinit(self: Self) !void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        if (self.dependencies != null)
            self.allocator.free(self.dependencies);
    }
};

const RawPackageDescriptor = struct {
    pkg: PackageDescriptor,
    indent: u8,
};

const ReadPackageError = error{ PackageTooLong, ReadError };

// Actual function that does all the loading
pub fn loadPackages(filename: []const u8) ![]PackageDescriptor {
    const raw = try loadRawPackagesFromFile(filename);
    defer raw.deinit();
    return try setDependencies(raw);
}

// Counts numer of tabs or sequences of 4*space from the left of the slice
fn countIndent(s: []const u8) u32 {
    const INDENT_SPACE_COUNT = 4;

    var i = 0;
    var indents: u32 = 0;
    while (i < s.len) {
        if (s[i] == '\t') {
            i = i + 1;
            indents = indents + 1;
        } else if (i + INDENT_SPACE_COUNT - 1 < s.len) {
            i = i + INDENT_SPACE_COUNT;
            indents = indents + 1;
        } else break;
    }
    return indents;
}

// Loads packages without set dependencies yet
// just parses the file and extracts the name and description along with indent of the package to help with package dependencies
fn loadRawPackagesFromFile(filename: []const u8) !std.ArrayList(RawPackageDescriptor) {
    const file = try std.fs.cwd().openFile(filename);
    defer file.close();

    const file_reader = file.reader();
    const buf: [4096]u8 = undefined;

    var packages = std.ArrayList(RawPackageDescriptor).init(std.heap.page_allocator);

    while (true) {
        const slice = file_reader.readUntilDelimiterOrEof(buf, " ") catch |err| {
            if (err == error.StreamTooLong)
                return ReadPackageError.PackageTooLong
            else
                return ReadPackageError.ReadError;
        };
        // EOF
        if (slice == null)
            break;

        const tokenizer = std.mem.tokenizeScalar(slice, " ");
        const name = tokenizer.next();
        const description = tokenizer.next();
        const indent = countIndent(slice);

        if (name == null or description == null) {
            std.debug.print("Couldn't parse Package. LINE: {s}", .{buf});
            continue;
        }
        const package = try PackageDescriptor.init(.{ .name = name, .description = description, .dependencies = null, .allocator = std.heap.page_allocator });

        try packages.append(.{ .pkg = package, .indent = indent });
    }

    return packages;
}

fn countDependeciesOfPackage(pkgs: []const RawPackageDescriptor, packageIndex: u32) u32 {
    std.debug.assert(packageIndex < pkgs.len and packageIndex >= 0);

    var i = packageIndex + 1;
    var count: u32 = 0;
    var min_indent = std.math.maxInt(u32);

    while (i < pkgs.len and pkgs[i].indent != pkgs[packageIndex]) {
        const curr_pkg = pkgs[i];

        if (curr_pkg.indent <= min_indent) {
            count = count + 1;
            min_indent = curr_pkg.indent;
        }

        i = i + 1;
    }

    return count;
}

// Allcates all resources and returns a slice of the Packages
fn setDependencies(pkgs: []const RawPackageDescriptor) ![]PackageDescriptor {
    std.debug.assert(pkgs.len > 0);

    // Calcualting Min indent
    var min_indent = std.math.maxInt(u32);
    for (pkgs) |package| {
        if (package.indent < min_indent)
            min_indent = package.indent;
    }

    // Counting root packages
    var root_count = 0;
    for (pkgs) |package| {
        if (package.indent == min_indent)
            root_count = root_count + 1;
    }

    // Setting dependencies from the end
    //

    const allocator = std.heap.page_allocator;

    // Output packages
    var root_packages = try allocator.alloc(PackageDescriptor, root_count);
    // Index to help insert packages
    var root_index = 0;

    errdefer allocator.free(root_packages);
    var helperStack = try std.ArrayList(PackageDescriptor).init(allocator);
    defer helperStack.deinit();

    var i = pkgs.len - 1;
    var last_indent = pkgs[i].indent;
    var dependency_counter = 0;

    while (i >= 0) {
        const current_pkg = pkgs[i];

        // These are valid indents of depdendenceis of x
        // X
        //                   Y
        //          Z
        //  W
        if (current_pkg.indent >= last_indent)
            helperStack.append(current_pkg.pkg)
        else {
            // Adding all dependencies
            current_pkg.pkg.dependencies = try allocator.alloc(PackageDescriptor, helperStack.items.len);

            std.mem.copyForwards(PackageDescriptor, current_pkg.pkg.dependencies, helperStack.items);
            try helperStack.clearRetainingCapacity();

            if (current_pkg.indent == min_indent) {
                root_packages[root_index] = current_pkg.pkg;
                root_index = root_index + 1;
            } else helperStack.append(current_pkg.pkg);
        }

        last_indent = current_pkg.indent;
        i = i - 1;
    }
}
