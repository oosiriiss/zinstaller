const std = @import("std");

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
        Package.init("GRUB", "Bootloader"),
        Package.init("sddm", "Login manager"),
        Package.init("pulseaudio", "Sound server, middleware between applications and hardware"),
        Package.init("pavucontrol", "Sound mixer - Pulse audio volume control"),
        Package.initWithDependencies("hyprland-git", "Window manager", &[_]Package{
            Package.init("qt5-wayland", "Qt5 with wayland support"),
            Package.init("qt6-wayland", "Qt6 with wayland support"),
        }),
    };

    for (packages) |package| {
        package.print();
    }
}
