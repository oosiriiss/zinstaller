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
        try writer.print("Package {{ name: \"{s}\",\n description: \"{s}\",\n", .{ self.name, self.description });
        if (self.dependencies) |deps| {
            try writer.print("dependencies: {d}", .{deps.len});
        }
    }
};

fn printEnumeratedPackages(packages: []const Package, writer: *const std.fs.File.Writer) !void {
    for (packages.len, packages) |i, package| {
        try writer.write("{d}", .{i});
        try package.print(writer);
        try writer.writer("\n");
    }
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
    var syncResult = std.process.Child.init(&.{ "pacman", "-Syu", "--noconfirm" }, std.heap.page_allocator);

    const r = try syncResult.spawnAndWait();

    if (r.Exited != 0)
        return error.PacmanError;
}

fn downloadSelectedPackages(packages: *const std.ArrayList(Package), ostream: *const std.fs.File.Writer) !void {
    const packagesStr = try extractPackageNames(packages);
    errdefer std.heap.page_allocator.free(packagesStr);

    try ostream.print("\n\nDownloading packages: {s}\n\n", .{packagesStr});

    const command = [_][]const u8{ "pacman", "-S", packagesStr };

    var installResult = std.process.Child.init(&command, std.heap.page_allocator);

    const r = try installResult.spawnAndWait();

    if (r.Exited != 0)
        return error.PacmanError;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // List of packages
    const packages = comptime [_]Package{
        Package.init("GRUB", "Bootloader"),                                                       Package.init("sddm", "Login manager"),
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

    // Flatteing packages list (adding dependencies to the main list)
    const flattened = flattenPackagesArray(&packages) catch |err| {
        std.debug.print("Couldn't flatten packages array: {any}\n", .{err});
        return;
    };
    defer flattened.deinit();

    dumpPackagesToFile(&flattened) catch |err| {
        std.debug.print("Dumping packages to file failed! {any}", .{err});
        return;
    };

    runPacmanSync(&stdout) catch |err| {
        std.debug.print("Couldn't run pacman sync: {any}", .{err});
        return;
    };
    downloadSelectedPackages(&flattened, &stdout) catch |err| {
        std.debug.print("Downllading selected packages failed {any}", .{err});
        return;
    };
}
