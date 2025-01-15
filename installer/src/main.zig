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
            std.debug.print("dependencies: {{\n", .{});
            for (deps) |dep| {
                std.debug.print("\t", .{});
                dep.print();
            }
            std.debug.print("}}\n", .{});
        }
        std.debug.print("}}\n", .{});
    }
};

pub fn main() !void {
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

    var file = try std.fs.Dir.createFile("packages.list",std.fs.File.CreateFlags {.read = true,}) catch return;
    file.

    for (packages) |package| {
        package.print();
    }
}
