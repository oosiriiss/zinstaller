const std = @import("std");
const PackageDescriptor = @import("load_packages.zig").PackageDescriptor;

fn calculateDownloadStringLength(packages: []const PackageDescriptor) usize {
    var length: usize = 0;

    for (packages) |pkg| {
        length = length + pkg.name.len;
    }

    // Spaces between package names
    length = length + (packages.len - 1);

    return length;
}

// Allocates the memory - the caller is responsibel for freeing it
fn prepareDownloadString(packages: []const PackageDescriptor, alloc: std.mem.Allocator) ![]u8 {
    const length = calculateDownloadStringLength(packages);
    var buf = try alloc.alloc(u8, length);

    var current_offset: usize = 0;

    for (packages, 0..) |pkg, i| {
        std.mem.copyForwards(u8, buf[current_offset..], pkg.name);

        current_offset = current_offset + pkg.name.len;

        // Spaces between names
        if (i < packages.len - 1) {
            buf[current_offset] = ' ';
            current_offset = current_offset + 1;
        }
    }

    return buf;
}

pub fn downloadPackages(packages: []const PackageDescriptor) !void {
    const alloc = std.heap.page_allocator;

    const download_string = prepareDownloadString(packages, alloc);
    defer alloc.free(download_string);
}

test "Calculating length for download string" {
    const test_packages: [2]PackageDescriptor = .{ .{ .name = "package_first", .description = null, .dependencies = null }, .{ .name = "package_second", .description = null, .dependencies = null } };

    const length = calculateDownloadStringLength(&test_packages);

    try std.testing.expectEqual(28, length);
}

test "Creating download string" {
    const test_packages: [2]PackageDescriptor = .{ .{ .name = "package_first", .description = null, .dependencies = null }, .{ .name = "package_second", .description = null, .dependencies = null } };

    const str = try prepareDownloadString(&test_packages, std.testing.allocator);
    defer std.testing.allocator.free(str);

    try std.testing.expectEqual(28, str.len);
    // try std.testing.expectEqualSlices(u8, "package_first package_second", str);
}
