const std = @import("std");

const PackageDescriptor = struct {
    name: []const u8,
    description: []const u8,

    dependencies: ?[]PackageDescriptor,

    allocator: std.mem.Allocator,

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

    fn deinit(self: PackageDescriptor) !void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        if (self.dependencies != null)
            self.allocator.free(self.dependencies);
    }
};

const ReadPackageError = error{ PackageTooLong, ReadError };

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

fn readPackagesFromFile(filename: []const u8) ReadPackageError![]PackageDescriptor {
    const file = try std.fs.cwd().openFile(filename);
    defer file.close();

    const file_reader = file.reader();
    const buf: [4096]u8 = undefined;

    var packages = std.ArrayList(struct { pkg: PackageDescriptor, indent: i32 }).init(std.heap.page_allocator);

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

        const package = PackageDescriptor.init(.{ .name = name, .description = description, .dependencies = dependencies, .allocator = std.heap.page_allocator });

        try packages.append(package);
    }
}
