const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const io = std.io;
const debug = std.debug;
const math = std.math;

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

inline fn readSysFile(path: []const u8) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [4096]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    const content = buffer[0..bytes_read];

    return mem.trim(u8, content, " \n");
}

inline fn parseNumber(content: []const u8) u64 {
    return fmt.parseInt(u64, content, 10) catch |err| blk: {
        debug.print("Number parsing error: {}\n", .{err});
        break :blk 0;
    };
}

inline fn parseFloat(content: []const u8) f64 {
    return fmt.parseFloat(f64, content) catch |err| blk: {
        debug.print("Float parsing error: {}\n", .{err});
        break :blk 0.0;
    };
}

noinline fn getGPUInfo() !GPUInfo {
    const base_hwmon = "/sys/class/hwmon/hwmon2"; // TODO: Implement autodetection of the correct hwmon path by scanning /sys/class/hwmon/ and selecting the relevant sensor files based on available hardware.

    const paths = comptime blk: {
        const base_paths = .{
            "/device/mem_info_vram_total",
            "/device/mem_info_vram_used",
            "/temp1_input",
            "/device/gpu_busy_percent",
            "/device/mem_busy_percent",
            "/pwm1",
            "/pwm1_max",
        };

        var full_paths: [base_paths.len][]const u8 = undefined;
        for (base_paths, 0..) |path, i| full_paths[i] = base_hwmon ++ path;

        break :blk full_paths;
    };

    const memory_total = parseNumber(try readSysFile(paths[0]));
    const memory_used = parseNumber(try readSysFile(paths[1]));
    const temperature = parseFloat(try readSysFile(paths[2])) / 1000.0;
    const gpu_busy_percent = parseNumber(try readSysFile(paths[3]));
    const memory_busy_percent = parseNumber(try readSysFile(paths[4]));

    const pwm_value = parseNumber(try readSysFile(paths[5]));
    const max_pwm_value = parseNumber(try readSysFile(paths[6]));
    const pwm_percentage = @as(u64, @intFromFloat((@as(f32, @floatFromInt(pwm_value)) / @as(f32, @floatFromInt(max_pwm_value))) * 100.0));

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

    pub inline fn format(self: FmtSize, comptime frmt: []const u8, options: fmt.FormatOptions, writer: anytype) !void {
        return if (self.size >= GIGA) {
            try fmt.formatType(@as(f64, @floatFromInt(self.size)) / GIGA, frmt, options, writer, 0);
            try writer.writeByte('G');
        } else if (self.size >= MEGA) {
            try fmt.formatType(@as(f64, @floatFromInt(self.size)) / MEGA, frmt, options, writer, 0);
            try writer.writeByte('M');
        } else if (self.size >= KILO) {
            try fmt.formatType(@as(f64, @floatFromInt(self.size)) / KILO, frmt, options, writer, 0);
            try writer.writeByte('K');
        } else {
            try fmt.formatType(self.size, frmt, options, writer, 0);
            try writer.writeByte('B');
        };
    }
};

inline fn fmtSize(size: u64) FmtSize {
    return .{ .size = size };
}

pub fn main() !void {
    const gpu_info = try getGPUInfo();

    var bw = io.bufferedWriter(io.getStdOut().writer());

    try bw.writer().print("{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"PWM · {d:.0}%\\n\\nMemory Total · {d:.2}\\nMemory Used · {d:.2}\\nMemory Free · {d:.2}\"}}", .{
        gpu_info.gpu_busy_percent,
        gpu_info.temperature,
        gpu_info.pwm_percentage,
        fmtSize(gpu_info.memory_total),
        fmtSize(gpu_info.memory_used),
        fmtSize(gpu_info.memory_free),
    });

    try bw.flush();
}
