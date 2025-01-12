const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const heap = std.heap;
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

inline fn findPath(base_paths: []const []const u8) ![]const u8 {
    for (base_paths) |path| {
        const file = fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();
        return try heap.page_allocator.dupe(u8, path);
    }
    return error.PathNotFound;
}

noinline fn getGPUInfo(allocator: mem.Allocator) !GPUInfo {
    const base_device = "/sys/class/hwmon/hwmon2/device";
    const base_hwmon = "/sys/class/hwmon/hwmon2";

    const mem_total_path = try fmt.allocPrint(allocator, "{s}/mem_info_vram_total", .{base_device});
    defer allocator.free(mem_total_path);
    const memory_total_raw = try readSysFile(mem_total_path);
    const memory_total = parseNumber(memory_total_raw);

    const mem_used_path = try fmt.allocPrint(allocator, "{s}/mem_info_vram_used", .{base_device});
    defer allocator.free(mem_used_path);
    const memory_used_raw = try readSysFile(mem_used_path);
    const memory_used = parseNumber(memory_used_raw);

    const temperature_path = try fmt.allocPrint(allocator, "{s}/temp1_input", .{base_hwmon});
    defer allocator.free(temperature_path);
    const temperature_raw = try readSysFile(temperature_path);
    const temperature = parseFloat(temperature_raw) / 1000.0;

    const gpu_busy_path = try fmt.allocPrint(allocator, "{s}/gpu_busy_percent", .{base_device});
    defer allocator.free(gpu_busy_path);

    const gpu_busy_raw = try readSysFile(gpu_busy_path);
    const gpu_busy_percent = parseNumber(gpu_busy_raw);

    const mem_busy_path = try fmt.allocPrint(allocator, "{s}/mem_busy_percent", .{base_device});
    defer allocator.free(mem_busy_path);

    const mem_busy_raw = try readSysFile(mem_busy_path);
    const memory_busy_percent = parseNumber(mem_busy_raw);

    return GPUInfo{
        .memory_total = memory_total,
        .memory_used = memory_used,
        .memory_free = memory_total - memory_used,
        .temperature = temperature,
        .gpu_busy_percent = gpu_busy_percent,
        .memory_busy_percent = memory_busy_percent,
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
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var bw = io.bufferedWriter(io.getStdOut().writer());

    const gpu_info = try getGPUInfo(allocator);

    try bw.writer().print("{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"Memory Total · {d:.2}\\nMemory Used · {d:.2}\\nMemory Free · {d:.2}\"}}", .{
        gpu_info.gpu_busy_percent,
        gpu_info.temperature,
        fmtSize(gpu_info.memory_total),
        fmtSize(gpu_info.memory_used),
        fmtSize(gpu_info.memory_free),
    });

    try bw.flush();
}
