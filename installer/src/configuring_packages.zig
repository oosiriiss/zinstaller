const std = @import("std");

const ConfigurationStatus = enum {
    /// Nothing has been done yes
    none,
    /// Downloaded, waiting for configuration
    downloaded,
    /// All the setup and configurations are finished
    done,
};

const PackageStatus = struct {
    name: []const u8,
    status: ConfigurationStatus,

    /// Doesn't copy the name
    pub fn init(name: []const u8, status: ConfigurationStatus) PackageStatus {
        return .{ .name = name, .status = status };
    }

    /// Copies the name
    pub fn initWithCopy(p_name: []const u8, status: ConfigurationStatus, alloc: std.mem.Allocator) !PackageStatus {
        const name = try alloc.dupe(u8, p_name);

        return .{ .name = name, .status = status };
    }
};


pub fn configurationResumePossible

