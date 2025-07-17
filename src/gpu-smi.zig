// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of zig-waybar-contrib.
//
// Copyright (c) 2025 erffy
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.


const std = @import("std");
const waybar = @import("waybar.zig");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const io = std.io;
const time = std.time;
const posix = std.posix;
const heap = std.heap;
const Allocator = mem.Allocator;

const c = @cImport({
    @cInclude("rocm_smi/rocm_smi.h");
});

const KILO: comptime_int = 1024;
const MEGA: comptime_int = KILO * KILO;
const GIGA: comptime_int = KILO * MEGA;

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

fn initializeROCmSMI() !u32 {
    if (c.rsmi_init(0) != c.RSMI_STATUS_SUCCESS) {
        return error.ROCmSMIInitFailed;
    }

    var num_devices: u32 = 0;
    if (c.rsmi_num_monitor_devices(&num_devices) != c.RSMI_STATUS_SUCCESS) {
        _ = c.rsmi_shut_down();
        return error.DeviceCountFailed;
    }

    if (num_devices == 0) {
        _ = c.rsmi_shut_down();
        return error.NoDevicesFound;
    }

    return num_devices;
}

fn shutdownROCmSMI() void {
    _ = c.rsmi_shut_down();
}

fn getGPUInfoROCm(device_id: u32) !GPUInfo {
    var temp: i64 = 0;
    var gpu_busy: u32 = 0;
    var mem_total: u64 = 0;
    var mem_used: u64 = 0;
    var fan_speed: i64 = 0;
    var fan_max: u64 = 0;

    // Temperature
    const temp_result = c.rsmi_dev_temp_metric_get(device_id, c.RSMI_TEMP_TYPE_EDGE, c.RSMI_TEMP_CURRENT, &temp);
    const temperature: f64 = if (temp_result == c.RSMI_STATUS_SUCCESS) @as(f64, @floatFromInt(temp)) / 1000.0 else 0.0;

    // GPU busy %
    const gpu_result = c.rsmi_dev_busy_percent_get(device_id, &gpu_busy);
    const gpu_usage: u64 = if (gpu_result == c.RSMI_STATUS_SUCCESS) gpu_busy else 0;

    // VRAM memory info
    var usage: u64 = 0;
    var total: u64 = 0;
    const mem_used_result = c.rsmi_dev_memory_usage_get(device_id, c.RSMI_MEM_TYPE_VRAM, &usage);
    const mem_total_result = c.rsmi_dev_memory_total_get(device_id, c.RSMI_MEM_TYPE_VRAM, &total);

    if (mem_used_result == c.RSMI_STATUS_SUCCESS) mem_used = usage;
    if (mem_total_result == c.RSMI_STATUS_SUCCESS) mem_total = total;

    const mem_free = if (mem_total > mem_used) mem_total - mem_used else 0;

    const fan_result = c.rsmi_dev_fan_speed_get(device_id, 0, &fan_speed);
    const fan_max_result = c.rsmi_dev_fan_speed_max_get(device_id, 0, &fan_max);

    var fan_pwm: u64 = 0;

    if (fan_result == c.RSMI_STATUS_SUCCESS and fan_max_result == c.RSMI_STATUS_SUCCESS) {
        if (fan_max > 0) {
            const scaled = @as(i128, fan_speed) * 100;
            fan_pwm = @as(u64, @intCast(@divTrunc(scaled, @as(i128, fan_max))));
            fan_pwm = @min(fan_pwm, 100);
        }
    }

    return GPUInfo{
        .temperature = temperature,
        .gpu_busy = gpu_usage,
        .pwm = fan_pwm,
        .mem_total = mem_total,
        .mem_used = mem_used,
        .mem_free = mem_free,
    };
}

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const stdout = io.getStdOut().writer();

    _ = try initializeROCmSMI();
    defer shutdownROCmSMI();

    while (true) {
        const waybarPid = try waybar.getPid();
        const info = try getGPUInfoROCm(0);

        try stdout.print(
            "{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"PWM · {d}%\\nVRAM Total · {d:.2}\\nVRAM Used · {d:.2}\\nVRAM Free · {d:.2}\"}}\n",
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
