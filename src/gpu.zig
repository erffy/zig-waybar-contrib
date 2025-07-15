const std = @import("std");
const waybar = @import("waybar.zig");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const io = std.io;
const time = std.time;
const posix = std.posix;
const Allocator = mem.Allocator;

const KILO = 1024;
const MEGA = 1024 * KILO;
const GIGA = 1024 * MEGA;

const GPUInfo = struct {
    temperature: f64,
    gpu_busy: u64,
    pwm: u64,
    mem_total: u64,
    mem_used: u64,
    mem_free: u64,
};

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

fn readFile(allocator: Allocator, path: []const u8) ![]u8 {
    const file = fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 4096);
    errdefer allocator.free(content);
    
    const trimmed = mem.trim(u8, content, " \n\t\r");
    if (trimmed.len == content.len) return content;
    
    const result = try allocator.dupe(u8, trimmed);
    allocator.free(content);
    return result;
}

fn readU64(allocator: Allocator, path: []const u8) u64 {
    const content = readFile(allocator, path) catch return 0;
    defer allocator.free(content);
    return fmt.parseInt(u64, content, 10) catch 0;
}

fn readF64(allocator: Allocator, path: []const u8) f64 {
    const content = readFile(allocator, path) catch return 0.0;
    defer allocator.free(content);
    return fmt.parseFloat(f64, content) catch 0.0;
}

fn getHwmonPath(allocator: Allocator) ![]const u8 {
    var drm_dir = try fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true });
    defer drm_dir.close();

    var drm_it = drm_dir.iterate();
    while (try drm_it.next()) |entry| {
        if (!mem.startsWith(u8, entry.name, "card")) continue;

        const hwmon_glob_path = try fmt.allocPrint(allocator, "/sys/class/drm/{s}/device/hwmon", .{entry.name});
        defer allocator.free(hwmon_glob_path);

        var hwmon_dir = fs.openDirAbsolute(hwmon_glob_path, .{ .iterate = true }) catch continue;
        defer hwmon_dir.close();

        var hwmon_it = hwmon_dir.iterate();
        while (try hwmon_it.next()) |hw_entry| {
            if (hw_entry.kind != .directory) continue;

            const name_path = try fmt.allocPrint(allocator, "{s}/{s}/name", .{ hwmon_glob_path, hw_entry.name });
            defer allocator.free(name_path);

            const name = readFile(allocator, name_path) catch continue;

            if (mem.eql(u8, name, "amdgpu")) {
                return try fmt.allocPrint(allocator, "{s}/{s}", .{ hwmon_glob_path, hw_entry.name });
            }
        }
    }

    return error.HwmonNotFound;
}

fn getGPUInfo(allocator: Allocator, base: []const u8) !GPUInfo {
    const temp_path = try fmt.allocPrint(allocator, "{s}/temp1_input", .{base});
    defer allocator.free(temp_path);
    const temp = readF64(allocator, temp_path) / 1000.0;

    const gpu_path = try fmt.allocPrint(allocator, "{s}/device/gpu_busy_percent", .{base});
    defer allocator.free(gpu_path);
    const gpu = readU64(allocator, gpu_path);

    const pwm_path = try fmt.allocPrint(allocator, "{s}/pwm1", .{base});
    defer allocator.free(pwm_path);
    const pwm = readU64(allocator, pwm_path);

    const pwm_max_path = try fmt.allocPrint(allocator, "{s}/pwm1_max", .{base});
    defer allocator.free(pwm_max_path);
    const pwm_max = readU64(allocator, pwm_max_path);

    const mem_total_path = try fmt.allocPrint(allocator, "{s}/device/mem_info_vram_total", .{base});
    defer allocator.free(mem_total_path);
    const mem_total = readU64(allocator, mem_total_path);

    const mem_used_path = try fmt.allocPrint(allocator, "{s}/device/mem_info_vram_used", .{base});
    defer allocator.free(mem_used_path);
    const mem_used = readU64(allocator, mem_used_path);

    const mem_free = if (mem_total > mem_used) mem_total - mem_used else 0;

    return GPUInfo{
        .temperature = temp,
        .gpu_busy = gpu,
        .pwm = if (pwm_max > 0) pwm * 100 / pwm_max else 0,
        .mem_total = mem_total,
        .mem_used = mem_used,
        .mem_free = mem_free,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = io.getStdOut().writer();

    const base = try getHwmonPath(allocator);
    defer allocator.free(base);

    while (true) {
        const waybarPid = try waybar.getPid();
        
        const info = try getGPUInfo(allocator, base);
        
        try stdout.print(
            "{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"PWM · {d}%\\n\\nVRAM Total · {d:.2}\\nVRAM Used · {d:.2}\\nVRAM Free · {d:.2}\"}}\n",
            .{
                info.gpu_busy,
                @as(i64, @intFromFloat(info.temperature)),
                info.pwm,
                fmtSize(info.mem_total),
                fmtSize(info.mem_used),
                fmtSize(info.mem_free),
            },
        );

        if (waybarPid) |pid| try posix.kill(@intCast(pid), 32 + 11);

        time.sleep(1 * time.ns_per_s);
    }
}