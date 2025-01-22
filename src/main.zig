const std = @import("std");
const linux = std.os.linux;

const Package = struct {
    name: []const u8,
    description: []const u8,
    dependencies: ?[]const Package,

    pub fn init(name: []const u8, description: []const u8) Package {
        return .{ .name = name, .description = description, .dependencies = null };
    }

    pub fn initWithDependencies(name: []const u8, description: []const u8, dependencies: []const Package) Package {
        return .{ .name = name, .description = description, .dependencies = dependencies };
    }
    pub fn print(self: Package, writer: *const std.fs.File.Writer) !void {
        try writer.print("{s} - {s}\n", .{ self.name, self.description });
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
    const maxPackageNumberDigits = std.math.log10(packages.len);

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

fn parsePackageInput(packageNumbers:[]i32,input:[]u8) !void {


    var index = 0;


    while(index < input.len) {
        // Todo implement this shit

    }

    var buffer:[22]u8 = undefined;

}

fn askForPackages(maxNumber: usize, writer: *const std.fs.File.Writer) !std.ArrayList(i32) {
    var selected = try std.ArrayList(i32).initCapacity(std.heap.page_allocator, maxNumber);
    errdefer selected.deinit();

    const stdin = std.io.getStdIn().reader();

    try writer.print("\n\nChoose the numbers of packages you with to install like (example: 1-3 5, 1-2 4-5 8, 1 2 3 4 5) or press enter for all\n", .{});
    while (true) {
        try writer.print(">> ", .{});
        var buffer: [1024]u8 = undefined;

        _ = try stdin.readAll(&buffer);

        try writer.print("Read: {s}", .{buffer});
        break;
    }

    return selected;
}

fn filterPickedPackages(packages: []const Package, writer: *const std.fs.File.Writer) !std.ArrayList(Package) {
    var filteredPackages = std.ArrayList(Package).init(std.heap.page_allocator);
    errdefer filteredPackages.deinit();

    try printEnumeratedPackages(packages, writer);

    const selected = try ask_for_packages(packages.len, writer);
    defer selected.deinit();

    return filteredPackages;
}

fn dumpPackagesToFile(packages: *const std.ArrayList(Package)) !void {
    var file = try std.fs.cwd().createFile("packages.list", .{ .truncate = true });
    defer file.close();

    var fileWriter = std.io.bufferedWriter(file.writer());
    var out = fileWriter.writer();

    for (packages.items) |package| {
        try out.print("{s}\n", .{package.name});
        try fileWriter.flush();
    }
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

test "Reading Packages" {
    _ = try ask_for_packages(120, &std.io.getStdOut().writer());

    try std.testing.expectEqual(1, 1);
}
