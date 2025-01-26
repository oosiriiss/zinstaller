const std = @import("std");
const linux = std.os.linux;

inline fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}
inline fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

inline fn isWhitespace(c: u8) bool {
    return (c == ' ' or c == '\t' or c == '\n' or c == '\r');
}
// Returns a slice without the whitespaces before and after
fn removeWhitespace(s: []const u8) []const u8 {
    var i: usize = 0;
    var j: usize = s.len;

    while (i < s.len and isWhitespace(s[i]))
        i = i + 1;

    while (j > i and isWhitespace(s[j - 1]))
        j = j - 1;

    return s[i..j];
}

// Represents a package that will be downloaded all with all its dependencies
// Must call deinit
const Package = struct {

    // Name of the package
    // Owns the memory
    name: []u8,
    // description of the package
    // Owns the memory
    description: []u8,
    // a list of other packages that this package depends on
    dependencies: ?[]const Package,
    allocator: *const std.mem.Allocator,

    pub fn init(params: struct { name: []const u8, description: []const u8, dependencies: ?[]const Package = null, allocator: *const std.mem.Allocator = &std.heap.page_allocator }) !Package {
        const allocator = params.allocator;

        const name = try allocator.alloc(u8, params.name.len);
        const description = try allocator.alloc(u8, params.description.len);
        var packages: ?[]Package = null;

        std.mem.copyForwards(u8, name, params.name);
        std.mem.copyForwards(u8, description, params.description);

        if (params.dependencies) |deps| {
            packages = try allocator.alloc(Package, deps.len);
            std.mem.copyForwards(Package, packages.?, deps);
        }

        return .{ .name = name, .description = description, .dependencies = packages, .allocator = allocator };
    }
    pub fn print(self: *const Package, writer: *const std.fs.File.Writer) !void {
        try writer.print("{s} - {s}\n", .{ self.name, self.description });
    }

    pub fn setDependencies(self: *Package, packages: []const Package) !void {
        if (self.dependencies != null)
            self.allocator.free(self.dependencies.?);

        const dependencies = try self.allocator.alloc(Package, packages.len);
        std.mem.copyForwards(Package, dependencies, packages);

        self.dependencies = dependencies;
    }

    pub fn deinit(self: *Package) void {
        const a = self.allocator;
        a.free(self.name);
        a.free(self.description);
        a.free(self.dependencies);
    }
};

fn printEnumeratedPackages(packages: []const Package, writer: *const std.fs.File.Writer) !void {
    if (packages.len == 0)
        return;

    var stack = std.ArrayList(struct { package: Package, depth: u8 }).init(std.heap.page_allocator);
    for (packages) |package| {
        try stack.append(.{ .package = package, .depth = 0 });
    }

    var packageNumber: usize = 1;
    const maxPackageNumberDigits = std.math.log10(packages.len) + 1;

    while (stack.items.len > 0) {
        const tmp = stack.pop();
        const currentPackage = tmp.package;
        const currentDepth = tmp.depth;

        // Adding its dependecies to be printed with a slight indent next
        if (currentPackage.dependencies) |deps| {
            for (deps) |dependency| {
                try stack.append(.{ .package = dependency, .depth = currentDepth + 1 });
            }
        }

        if (currentDepth > 0) {
            // Skipping first column
            for (maxPackageNumberDigits + 2) |_| {
                _ = try writer.write(" ");
            }

            // Indent dependencies
            for (currentDepth) |_| {
                _ = try writer.write("\t");
            }
        }
        // Enumerate not dependencies
        if (currentDepth == 0) {
            try writer.print("{d}.", .{packageNumber});

            const currentDigits = std.math.log10(packageNumber);
            // Filling spaces so The column has equal width
            for (maxPackageNumberDigits - currentDigits) |_| {
                _ = try writer.write(" ");
            }
            // Spacing
            _ = try writer.write(" ");
            packageNumber = packageNumber + 1;
        }
        // Printing the actual name of the package
        try currentPackage.print(writer);
    }
}

const RangeError = error{
    // Invalid number of elements in the range like 12-15-3 or range contains invalid characters (not just digits) like 12k-15.
    NotRangeError,
};

const RangeResult = struct { bottom: usize, top: usize };

// Parses a range specfied in rangeToken
// rangeToken should be of format "X-Y" where X and Y are integers.
//
// If X < Y
// range from X -> Y is returned
// or else
// Y -> X
//
fn parseRange(rangeToken: []const u8) RangeError!RangeResult {
    var rangeIterator = std.mem.tokenizeScalar(u8, rangeToken, '-');

    // first, second, null
    if (rangeIterator.buffer.len != 3)
        return RangeError.NotRangeError;

    const first = rangeIterator.next().?;
    const second = rangeIterator.next().?;

    const x = std.fmt.parseInt(usize, first, 10) catch null;
    const y = std.fmt.parseInt(usize, second, 10) catch null;

    if (x == null or y == null)
        return RangeError.NotRangeError;

    return .{ .bottom = min(usize, x.?, y.?), .top = max(usize, x.?, y.?) };
}

// Modifies the input package slice by putting the selected packages at the front and the rest at the end
// returns the slice of selected packages
fn parsePackageInput(input: []const u8, packages: []Package) ![]Package {
    var tokens = std.mem.tokenizeScalar(u8, input, ' ');

    const selectedPackages = try std.heap.page_allocator.alloc(bool, packages.len);
    defer std.heap.page_allocator.free(selectedPackages);
    @memset(selectedPackages, false);

    while (tokens.next()) |token| {
        if (std.fmt.parseInt(usize, token, 10)) |num| {
            // Package numbers begin at 1
            if (num > 0 and num <= selectedPackages.len) {
                selectedPackages[num] = true;
            } else std.debug.print("Specified number: {d} is out of rangea ({d}-{d})\n", .{ num, 0, selectedPackages.len });

            // Token parsed continuing to the next one
            continue;
        } else |_| {}

        if (parseRange(token)) |range| {
            // Indices capping the range at maximum available ranges
            const bottom = max(usize, 0, range.bottom - 1);
            const top = min(usize, selectedPackages.len, range.top + 1);

            for (bottom..top) |i|
                selectedPackages[i] = true;

            // Token parsed continuing to the next one
            continue;
        } else |_| {}
    }

    var selectedPackagesCount: usize = 0;
    for (selectedPackages) |isSelected| {
        if (isSelected)
            selectedPackagesCount = selectedPackagesCount + 1;
    }

    var i: usize = 0;
    var j: usize = 0;
    while (true) {

        // Selected package
        while (i < selectedPackages.len and selectedPackages[i] == false)
            i = i + 1;

        // Package empty spot
        while (j < selectedPackages.len and selectedPackages[j] == true)
            j = j + 1;

        if (i < packages.len and j < packages.len) {
            std.mem.swap(Package, &packages[i], &packages[j]);
            std.mem.swap(bool, &selectedPackages[i], &selectedPackages[j]);

            i = i + 1;
            j = j + 1;
        } else break;
    }

    return packages[0..selectedPackagesCount];
}

fn askForPackages(packages: []const Package, writer: *const std.fs.File.Writer) ![]Package {
    const stdin = std.io.getStdIn().reader();

    try writer.print("\n\nChoose the numbers of packages you with to install like (example: 1-3 5, 1-2 4-5 8, 1 2 3 4 5) or press enter for all\n", .{});

    while (true) {
        try writer.print(">> ", .{});
        var buffer: [1024]u8 = undefined;

        const bytes = try stdin.readAll(&buffer);

        if (parsePackageInput(buffer[0..bytes], packages)) |selectedPackagesCount| {
            return packages[0..selectedPackagesCount];
        } else |err| {
            std.debug.print("Couldn't parse the input: {}\n", .{err});
        }

        try writer.print("Read: {s}", .{buffer[0..bytes]});
        break;
    }
}

// Modifies the input slice
// Returns a slice with the filtered packages
fn filterPickedPackages(packages: []Package, writer: *const std.fs.File.Writer) ![]Package {
    try printEnumeratedPackages(packages, writer);

    const selected = try askForPackages(packages, writer);
    defer selected.deinit();

    return packages[1..2];
}

fn dumpPackagesToFile(packages: *const std.ArrayList(Package)) !void {
    var file = try std.fs.cwd().createFile("packages.list", .{ .truncate = true });
    defer file.close();

    var fileWriter = std.io.bufferedWriter(file.writer());
    var out = fileWriter.writer();

    for (packages.items) |package| {
        try package.print(&out);
    }
    try fileWriter.flush();
}
fn exists(arr: *const std.ArrayList(Package), searched: Package) bool {
    for (arr.items) |package| {
        if (std.mem.eql(u8, package.name, searched.name))
            return true;
    }
    return false;
}

fn flattenPackagesArray(packages: []const Package) !std.ArrayList(Package) {
    var flattenedArr = std.ArrayList(Package).init(std.heap.page_allocator);

    for (packages) |package| {
        if (package.dependencies) |deps| {
            for (deps) |dependency| {
                // Dependency is not added
                if (!exists(&flattenedArr, dependency)) {
                    try flattenedArr.append(dependency);
                }
            }
        }
        if (!exists(&flattenedArr, package))
            try flattenedArr.append(package);
    }
    return flattenedArr;
}

// Loads packages from file
//
// Packages file format:
//
// NAME = DESCRIPTION
// NAME2 = DESCRIPTION2
// NAME3 = DESCRIPTION3
//
fn loadPackages(fileName: []const u8) !std.ArrayList(Package) {
    const flags = std.fs.File.OpenFlags{ .mode = .read_only };

    const file = try std.fs.cwd().openFile(fileName, flags);
    defer file.close();

    var reader = file.reader();
    var buf: [512:0]u8 = undefined;

    const allocator = std.heap.page_allocator;

    var packages = std.ArrayList(Package).init(allocator);
    var dependenciesHelper = std.ArrayList(Package).init(allocator);
    defer dependenciesHelper.deinit();

    const countIndent = struct {
        fn cnt(s: []const u8) usize {
            var i: usize = 0;
            while (i < s.len and s[i] == '\t')
                i = i + 1;
            return i;
        }
    }.cnt;

    while (true) {
        const read = reader.readUntilDelimiterOrEof(&buf, '\n') catch |err| {
            std.debug.print("Failed to read from file: {}\n", .{err});
            break;
        };

        if (read == null)
            break;

        var tokens = std.mem.tokenizeScalar(u8, read.?, '=');

        const nameToken = tokens.next();
        const descriptionToken = tokens.next();
        const currentIndent = countIndent(read.?);

        if (nameToken == null or descriptionToken == null) {
            std.debug.print("encountered a line with bad format in {s}: line: {s}\n", .{ fileName, read.? });
            break;
        }

        const name = nameToken.?;
        const description = descriptionToken.?;
        const package = try Package.init(.{ .name = name, .description = description, .dependencies = null, .allocator = &allocator });

        // Dependency
        if (currentIndent > 0)
            try dependenciesHelper.append(package)
        else {
            // Flushing all previous dependencies to its corresponding package
            if (packages.items.len > 0 and dependenciesHelper.items.len > 0) {
                try packages.items[packages.items.len - 1].setDependencies(dependenciesHelper.items);

                dependenciesHelper.clearRetainingCapacity();
            }
            // Adding current package
            try packages.append(package);
        }
    }

    // Flushing remaining dependencies
    if (packages.items.len > 0 and dependenciesHelper.items.len > 0) {
        try packages.items[packages.items.len - 1].setDependencies(dependenciesHelper.items);
        dependenciesHelper.clearRetainingCapacity();
    }

    return packages;
}

fn extractPackageNames(packages: *const std.ArrayList(Package)) ![]const u8 {
    var len = packages.items.len; // space for spaces
    for (packages.items) |package| {
        len += package.name.len;
    }

    var str = try std.heap.page_allocator.alloc(u8, len);

    var i: usize = 0;
    for (packages.items) |package| {
        for (package.name) |c| {
            str[i] = c;
            i = i + 1;
        }
        str[i] = ' ';
        i = i + 1;
    }
    return str;
}

fn runPacmanSync(ostream: *const std.fs.File.Writer) !void {
    try ostream.print("Synchronizing pacman\n", .{});
    var syncResult = std.process.Child.init(&.{ "yay", "-Syu", "--noconfirm" }, std.heap.page_allocator);

    const r = try syncResult.spawnAndWait();

    if (r.Exited != 0)
        return error.PacmanError;
}

fn downloadSelectedPackages(packages: *const std.ArrayList(Package), ostream: *const std.fs.File.Writer) !void {
    const packagesStr = try extractPackageNames(packages);
    errdefer std.heap.page_allocator.free(packagesStr);

    try ostream.print("\n\nDownloading packages: {s}\n\n", .{packagesStr});

    const command = [_][]const u8{ "yay", "-S", packagesStr };

    var installResult = std.process.Child.init(&command, std.heap.page_allocator);

    const r = try installResult.spawnAndWait();

    if (r.Exited != 0)
        return error.PacmanError;
}

pub fn main() !void {
    const DEBUG = true;

    const stdout = std.io.getStdOut().writer();

    // List of packages
    const packages = comptime [_]Package{
        Package.init("grub", "Bootloader"),                                                       Package.init("sddm", "Login manager"),
        Package.init("pulseaudio", "Sound server, middleware between applications and hardware"), Package.init("pavucontrol", "Sound mixer - Pulse audio volume control"),
        Package.init("waybar", "Wyland top bar"),                                                 Package.init("hyprpaper", "Hyprland wallpapers"),
        Package.init("rofi-lbonn-wayland-git", "Rofi wayland support"),                           Package.init("wlr-randr", "randr for wayland"),
        Package.init("swaync", "Notifications"),                                                  Package.init("brightnessctl", "Changing screen brightness"),
        Package.init("nautilus", "File manager/explorer"),                                        Package.initWithDependencies("nvidia-dkms", "Nvidia graphics drivers", &[_]Package{Package.init("egl-wayland", "Idk some opengl nvidia support shit")}),
        Package.initWithDependencies("hyprland-git", "Window manager", &[_]Package{
            Package.init("qt5-wayland", "Qt5 with wayland support"),
            Package.init("qt6-wayland", "Qt6 with wayland support"),
        }),
    };

    const pickedPackages = filterPickedPackages(&packages, &stdout) catch |err| {
        std.debug.print("Couldn't filter picked packages: {any}\n", .{err});
        return;
    };
    // Flatteing packages list (adding dependencies to the main list)
    const flattened = flattenPackagesArray(&packages) catch |err| {
        std.debug.print("Couldn't flatten packages array: {any}\n", .{err});
        return;
    };
    defer flattened.deinit();
    pickedPackages.deinit();

    if (comptime DEBUG) {
        std.debug.print("Simulating Printing packages...\n", .{});
        std.debug.print("Simulating pacman sync...\n", .{});
        std.debug.print("Simulating upgradingpackages...\n", .{});
    } else {
        dumpPackagesToFile(&flattened) catch |err| {
            std.debug.print("Dumping packages to file failed! {any}\n", .{err});
            return;
        };
        runPacmanSync(&stdout) catch |err| {
            std.debug.print("Couldn't run pacman sync: {any}\n", .{err});
            return;
        };
        downloadSelectedPackages(&flattened, &stdout) catch |err| {
            std.debug.print("Downllading selected packages failed: {any}\n", .{err});
            return;
        };
    }
}

test "Parsing range" {
    const range = "1-5";
    const res = try parseRange(range);
    try std.testing.expectEqual(res, RangeResult{ .bottom = 1, .top = 5 });
}

test "Reading Packages" {
    var packages: [25]Package = undefined;

    var titleBuf: [32:0]u8 = undefined;
    var descriptionBuf: [32:0]u8 = undefined;

    for (0..packages.len) |i| {
        const title = try std.fmt.bufPrint(&titleBuf, "Package {d}", .{i});
        const description = try std.fmt.bufPrint(&descriptionBuf, "Description {d}", .{i});

        packages[i] = try Package.init(.{ .name = title, .description = description });
    }

    const selected = try parsePackageInput("2-5 1 8", &packages);

    try std.testing.expectEqualSlices(Package, packages[0..6], selected);
}

test "reading packages from file" {
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();

    var tmpFile = try tmpDir.dir.createFile("testfile.list", std.fs.File.CreateFlags{ .read = true, .truncate = true });
    const fileContent = "Package 1 = This is Package 1\n" ++
        "\tDependency 1 = This is some dependency\n" ++
        "\tDependency 2 = This is some dependency 2\n" ++
        "Package 2 = This is Package 2\n" ++
        "\tDependency 3 = This is some dependency\n" ++
        "\tDependency 4 = This is some dependency 2\n" ++
        "Package 3 = This is package3\n" ++
        "\tDependency 5 = This is some dependency\n" ++
        "\tDependency 6 = This is some dependency 2\n";
    _ = try tmpFile.write(fileContent);
    tmpFile.close();

    // changing the cwd for the test
    var buf: [512]u8 = undefined;
    const cwdPath = try std.fs.cwd().realpath(".", &buf);
    var buf2: [512]u8 = undefined;
    const tmpPath = try tmpDir.dir.realpath(".", &buf2);
    try std.posix.chdir(tmpPath);

    const res = try loadPackages("testfile.list");

    try printEnumeratedPackages(res.items, &std.io.getStdOut().writer());

    // Reverting the cwd to the original
    try std.posix.chdir(cwdPath);

    try std.testing.expect(res.items.len == 3);
}

test "removing whitespace from string with only whitespace" {
    const str = " \t \r \n    ";
    const res = removeWhitespace(str);
    try std.testing.expectEqualSlices(u8, res, "");
}
test "removing whitespace from nonempty string" {
    const str = " \t\n\r\r\r\n   Some test string! \r\t\n\n\n  ";
    const res = removeWhitespace(str);
    try std.testing.expectEqualSlices(u8, res, "Some test string!");
}
