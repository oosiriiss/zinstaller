const std = @import("std");
const main = @import("main.zig");
const testing = std.testing;

const ConfigurationError = error{};

fn getConfigurations() std.StringHashMap(fn () std.mem.Allocator.Error!void) {
    const cfgs = std.StringHashMap(comptime fn () ConfigurationError!void).init();

    cfgs.put("nvidia-dkms", configureGrub);
}

// "runConfiguration"
// For every package in the file runs the configuration
fn resumeConfigurations(selectedPackagesFileName: []const u8) !void {
    _ = selectedPackagesFileName;
}

fn runConfigurations(selected: *const std.ArrayList(main.Package)) !void {
    _ = selected;
}

fn configureGrub() ConfigurationError!void {}
