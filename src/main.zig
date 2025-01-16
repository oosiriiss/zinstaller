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
    pub fn print(self: Package) void {
        std.debug.print("Package {{\n name: \"{s}\",\n description: \"{s}\",\n", .{ self.name, self.description });
        if (self.dependencies) |deps| {
            std.debug.print("dependencies: {d}", .{deps.len});
        }
    }
};

fn dumpPackagesToFile(packages: *const std.ArrayList(Package)) !void {
    var file = try std.fs.cwd().createFile("packages.list", .{});
    defer file.close();

    var fileWriter = std.io.bufferedWriter(file.writer());
    var out = fileWriter.writer();

    for (packages.items) |package| {
        try out.print("{s}\n", .{package.name});
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

    // Selecting packages

    // Flatteing packages list (adding dependencies to the main list)
    const flattened = flattenPackagesArray(&packages) catch |err| {
        std.debug.print("Couldn't flatten packages array: {any}\n", .{err});
        return;
    };
    defer flattened.deinit();

    try dumpPackagesToFile(&flattened);

    try stdout.print("Synchronizing pacman\n", .{});
    var syncResult = std.process.Child.init(&.{ "pacman", "-Syu", "--noconfirm" }, std.heap.page_allocator);

    _ = syncResult.spawnAndWait() catch |err| {
        std.debug.print("Couldn't pacman -Syu: {any}", .{err});
        return;
    };

    syncResult.stdout_behavior = std.process.Child.StdIo.Pipe;
    syncResult.stdin_behavior = std.process.Child.StdIo.Pipe;

    //std.debug.print("Synchronization Result: {d}\nSynchronization stdout: {s}\nSynchronization stderr: {s}", .{ syncResult.term.Exited, syncResult.stdout, syncResult.stderr });

    const packagesStr = extractPackageNames(&flattened) catch |err| {
        std.debug.print("There was an error when extracting Packagae names: {any}", .{err});
        return;
    };

    defer std.heap.page_allocator.free(packagesStr);

    const command = [_][]const u8{ "pacman", "-S", packagesStr };

    std.debug.print("Downloading packages: {s}", .{packagesStr});
    const installResult = std.process.Child.run(.{ .allocator = std.heap.page_allocator, .argv = &command }) catch |err| {
        std.debug.print("Couldn't pacman -Syu: {any}", .{err});
        return;
    };
    std.debug.print("Installation stdout: {s}\nInstallation stderr: {s}", .{ installResult.stdout, installResult.stderr });
}
