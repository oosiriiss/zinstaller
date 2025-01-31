const std = @import("std");
const main = @import("main.zig");
const testing = std.testing;

const PackageConfigurationStatus = struct {
    name: []u8,
    done: bool,

    fn init(name: []const u8, done: bool) !@This() {
        var allocator = std.heap.page_allocator;

        const nameCpy = try allocator.alloc(u8, name.len);

        std.mem.copyForwards(u8, nameCpy, name);

        return .{ .name = nameCpy, .done = done };
    }
};

const ConfigurationError = error{ConfigurationNotFound};

fn configure(packageName: []const u8) ConfigurationError!void {
    const is = struct {
        fn cmp(b: []const u8) bool {
            return std.mem.eql(u8, packageName, b);
        }
    }.cmp;

    if (is("nvidia-dkms"))
        configureNvidiaDKMS()
    else if (is("sddm"))
        configureSDDM()
    else {
        return ConfigurationError.ConfigurationNotFound;
    }
}

fn loadConfigurePackages(fileName: []const u8) !std.ArrayList(PackageConfigurationStatus) {
    const file = try std.fs.cwd().openFile(fileName, std.fs.File.OpenFlags{ .mode = .read_only });

    const reader = file.reader();

    var buf: [128]u8 = undefined;

    var arr = std.ArrayList(PackageConfigurationStatus).init(std.heap.page_allocator);

    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        std.debug.print("Line: {s}\n", .{line});

        var tokenizer = std.mem.tokenizeScalar(u8, line, ' ');

        const name = tokenizer.next();
        const isDone = if (tokenizer.next()) |value| std.mem.eql(u8, value, "Done") else false;
        //const isDone = std.mem.eql(u8, tokenizer.next(), "Done");

        if (name != null) {
            const package = try PackageConfigurationStatus.init(name.?, isDone);

            try arr.append(package);
        } else {
            std.debug.print("Invalid package name at line: {s}", .{line});
        }
    }

    return arr;
}

// Saves packages
fn saveConfigurePackages(fileName: []const u8, packages: []const main.Package) !void {
    var file = try std.fs.cwd().createFile(fileName, .{ .truncate = true });
    defer file.close();

    var fileWriter = std.io.bufferedWriter(file.writer());
    var out = fileWriter.writer();

    for (packages.items) |package| {
        try package.print(&out);
    }
    try fileWriter.flush();
}

// Runs the configurations
fn runConfigurations(selected: *const std.ArrayList(main.Package)) !void {
    _ = selected;
}

fn configureNvidiaDKMS() !void {}

fn configureSDDM() !void {}

test "Loading packages" {
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();

    var tmpFile = try tmpDir.dir.createFile("testfile.list", std.fs.File.CreateFlags{ .read = true, .truncate = true });
    const fileContent = "Pkg1 Done\n" ++ "PKG2\n" ++ "PKG3 Done\n" ++ "PKG4 Done\n";
    _ = try tmpFile.write(fileContent);
    tmpFile.close();

    // changing the cwd for the test
    var buf: [512]u8 = undefined;
    const cwdPath = try std.fs.cwd().realpath(".", &buf);
    var buf2: [512]u8 = undefined;
    const tmpPath = try tmpDir.dir.realpath(".", &buf2);
    try std.posix.chdir(tmpPath);

    const res = try loadConfigurePackages("testfile.list");

    // Reverting the cwd to the original
    try std.posix.chdir(cwdPath);

    try std.testing.expect(res.items.len == 4);
}
