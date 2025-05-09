const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const io = std.io;
const debug = std.debug;

const KILO: u64 = 1024;
const MEGA: u64 = KILO * KILO;
const GIGA: u64 = KILO * MEGA;

const GPUInfo = struct {
    memory_total: u64,
    memory_used: u64,
    memory_free: u64,
    temperature: f64,
    gpu_busy_percent: u64,
    memory_busy_percent: u64,
    pwm_percentage: u64,
};

fn readSysFile(path: []const u8) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    var buffer: [4096]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    return mem.trim(u8, buffer[0..bytes_read], " \n");
}

fn parseNumber(content: []const u8) u64 {
    return fmt.parseInt(u64, content, 10) catch |err| blk: {
        debug.print("Number parsing error: {}\n", .{err});
        break :blk 0;
    };
}

fn parseFloat(content: []const u8) f64 {
    return fmt.parseFloat(f64, content) catch |err| blk: {
        debug.print("Float parsing error: {}\n", .{err});
        break :blk 0.0;
    };
}

// TODO: Handle multiple GPUs if present
fn detectHwmonPath(allocator: mem.Allocator) ![]const u8 {
    const HwmonError = error{HwmonNotFound};

    var card0_hwmon_dir = fs.openDirAbsolute("/sys/class/drm/card0/device/hwmon", .{ .iterate = true }) catch |err| {
        debug.print("Fallback hwmon dir open failed: {}\n", .{err});
        return HwmonError.HwmonNotFound;
    };

    defer card0_hwmon_dir.close();

    var it = card0_hwmon_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const hwmon_path = try std.fmt.allocPrint(allocator, "/sys/class/drm/card0/device/hwmon/{s}/name", .{entry.name});
        defer allocator.free(hwmon_path);

        const name = readSysFile(hwmon_path) catch |err| {
            debug.print("Could not read {s}: {}\n", .{ hwmon_path, err });
            continue;
        };

        if (mem.eql(u8, name, "amdgpu")) return try std.fmt.allocPrint(allocator, "/sys/class/drm/card0/device/hwmon/{s}", .{entry.name});
    }

    return HwmonError.HwmonNotFound;
}

noinline fn getGPUInfo(allocator: mem.Allocator) !GPUInfo {
    const base_hwmon = try detectHwmonPath(allocator);
    defer allocator.free(base_hwmon);

    const paths: []const []const u8 = &.{
        "/device/mem_info_vram_total",
        "/device/mem_info_vram_used",
        "/temp1_input",
        "/device/gpu_busy_percent",
        "/device/mem_busy_percent",
        "/pwm1",
        "/pwm1_max",
    };

    var full_paths: [paths.len][]const u8 = undefined;

    for (paths, 0..) |suffix, i| full_paths[i] = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_hwmon, suffix });

    const memory_total = parseNumber(try readSysFile(full_paths[0]));
    const memory_used = parseNumber(try readSysFile(full_paths[1]));
    const temperature = parseFloat(try readSysFile(full_paths[2])) / 1000.0;
    const gpu_busy_percent = parseNumber(try readSysFile(full_paths[3]));
    const memory_busy_percent = parseNumber(try readSysFile(full_paths[4]));
    const pwm_value = parseNumber(try readSysFile(full_paths[5]));
    const pwm_max = parseNumber(try readSysFile(full_paths[6]));
    const pwm_percentage = @as(u64, @intFromFloat((@as(f32, @floatFromInt(pwm_value)) / @as(f32, @floatFromInt(pwm_max))) * 100.0));

    // Free all full_paths entries
    for (full_paths) |p| allocator.free(p);

    return GPUInfo{
        .memory_total = memory_total,
        .memory_used = memory_used,
        .memory_free = memory_total - memory_used,
        .temperature = temperature,
        .gpu_busy_percent = gpu_busy_percent,
        .memory_busy_percent = memory_busy_percent,
        .pwm_percentage = pwm_percentage,
    };
}

const FmtSize = struct {
    size: u64,
    pub inline fn format(self: FmtSize, comptime f: []const u8, o: fmt.FormatOptions, w: anytype) !void {
        return if (self.size >= GIGA) {
            try fmt.formatType(@as(f64, @floatFromInt(self.size)) / GIGA, f, o, w, 0);
            try w.writeByte('G');
        } else if (self.size >= MEGA) {
            try fmt.formatType(@as(f64, @floatFromInt(self.size)) / MEGA, f, o, w, 0);
            try w.writeByte('M');
        } else if (self.size >= KILO) {
            try fmt.formatType(@as(f64, @floatFromInt(self.size)) / KILO, f, o, w, 0);
            try w.writeByte('K');
        } else {
            try fmt.formatType(self.size, f, o, w, 0);
            try w.writeByte('B');
        };
    }
};

inline fn fmtSize(size: u64) FmtSize {
    return .{ .size = size };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const gpu_info = try getGPUInfo(allocator);

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    try out.writer().print(
        "{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"PWM · {d:.0}%\\n\\nMemory Total · {d:.2}\\nMemory Used · {d:.2}\\nMemory Free · {d:.2}\"}}",
        .{
            gpu_info.gpu_busy_percent,
            gpu_info.temperature,
            gpu_info.pwm_percentage,
            fmtSize(gpu_info.memory_total),
            fmtSize(gpu_info.memory_used),
            fmtSize(gpu_info.memory_free),
        },
    );

    try io.getStdOut().writer().writeAll(out.items);
}
