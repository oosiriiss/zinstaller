const std = @import("std");
const util = @import("util.zig");

const PackageDescriptor = struct {
    name: []const u8,
    description: []const u8,
    dependencies: ?[]PackageDescriptor,
    allocator: std.mem.Allocator,

    const Self = @This();

    fn init(params: struct { name: []const u8, description: []const u8, allocator: std.mem.Allocator }) !PackageDescriptor {
        const name = try params.allocator.dupe(u8, params.name);
        errdefer params.allocator.free(name);

        const description = try params.allocator.dupe(u8, params.description);
        errdefer params.allocator.free(description);

        return Self{ .name = name, .description = description, .dependencies = null, .allocator = params.allocator };
    }

    //
    // Returns updated PackageDescriptor with specified dependencies
    //
    // Dependencies names,descriptions etc. must remain valid!
    //
    fn setDependencies(self: Self, deps: []RawPackageDescriptor) !Self {
        var dependencies = try self.allocator.alloc(PackageDescriptor, deps.len);

        var i: usize = 0;

        for (deps) |d| {
            dependencies[i] = d.pkg;
            i = i + 1;
        }

        return Self{ .name = self.name, .description = self.description, .dependencies = dependencies, .allocator = self.allocator };
    }

    fn deinit(self: Self) !void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        if (self.dependencies != null)
            self.allocator.free(self.dependencies);
    }
};

const RawPackageDescriptor = struct { pkg: PackageDescriptor, indent: u32 };

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
        const indent = util.countIndent(slice.?);

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
fn createPackageTree(pkgs: []const RawPackageDescriptor) ![]PackageDescriptor {
    std.debug.assert(pkgs.len > 0);

    // Calcualting Min indent
    var min_indent: u32 = std.math.maxInt(u32);
    for (pkgs) |package| {
        if (package.indent < min_indent)
            min_indent = package.indent;
    }

    // Counting root packages
    var root_count: u32 = 0;
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
    var root_index = root_packages.len - 1;
    var packagesStack = std.ArrayList(RawPackageDescriptor).init(std.heap.page_allocator);
    defer packagesStack.deinit();

    var i = pkgs.len;

    // Iteraing packages from the end
    while (i > 0) {
        i = i - 1;
        std.debug.assert(root_index >= 0);

        const current_package = pkgs[i];

        if (packagesStack.getLastOrNull()) |previous_package| {
            // Previous packages were a children of current package
            // Setting its children
            if (previous_package.indent > current_package.indent) {
                const updated_pkg = try current_package.pkg.setDependencies(packagesStack.items);
                packagesStack.clearRetainingCapacity();

                // Adding root package to the final slice
                if (current_package.indent == 0) {
                    root_packages[root_index] = updated_pkg;
                    root_index = root_index - 1;
                } else try packagesStack.append(.{ .indent = current_package.indent, .pkg = updated_pkg });
            } else // Package is a sibling of previous package
            try packagesStack.append(current_package);
        }
    }

    return root_packages;
}
