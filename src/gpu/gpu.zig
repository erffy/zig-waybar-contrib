const std = @import("std");
const io = std.io;
const time = std.time;
const Thread = std.Thread;

const utils = @import("utils");
const waybar = utils.waybar;

const bo = @import("build_options");

pub fn main() !void {
    const stdout = io.getStdOut().writer();

    const SMI = blk: {
        if (bo.has_amdsmi) {
            break :blk @import("backend/amdsmi.zig");
        } else if (bo.has_rocm) {
            break :blk @import("backend/rocmsmi.zig");
        } else if (bo.has_nvml) {
            break :blk @import("backend/nvml.zig");
        } else {
            @compileError("No supported GPU backend found.");
        }
    };

    const handle = try SMI.initialize();
    defer SMI.shutdown();

    while (true) {
        try (try SMI.getGPUInfo(handle)).toJson(stdout);
        try stdout.writeByte('\n');
        try waybar.signal(11);

        Thread.sleep(1 * time.ns_per_s);
    }
}
