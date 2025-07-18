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
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const io = std.io;
const time = std.time;
const posix = std.posix;
const heap = std.heap;
const Allocator = mem.Allocator;

const utils = @import("utils");
const waybar = utils.waybar;
const format = utils.format;

const formatSize = format.formatSize;

const c = @cImport({
    @cInclude("amd_smi/amdsmi.h");
});

const GPUInfo = struct {
    gpu_busy: u64,
    temperature: f64,
    pwm: u64,
    mem_total: u64,
    mem_used: u64,
    mem_free: u64,

    pub inline fn toJson(self: GPUInfo, writer: anytype) !void {
        try writer.print(
            "{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"PWM · {d}%\\nVRAM Total · {d:.2}\\nVRAM Used · {d:.2}\\nVRAM Free · {d:.2}\"}}\n",
            .{
                self.gpu_busy,
                @as(i64, @intFromFloat(self.temperature)),
                self.pwm,
                formatSize(self.mem_total),
                formatSize(self.mem_used),
                formatSize(self.mem_free),
            },
        );
    }
};

fn initializeAMDSMI() !u32 {
    if (c.amdsmi_init(0) != c.AMDSMI_STATUS_SUCCESS) return error.AmdSmiInitFailed;

    var num_devices: u32 = 0;
    if (c.amdsmi_get_processor_handles(&num_devices, null) != c.AMDSMI_STATUS_SUCCESS or num_devices == 0) {
        _ = c.amdsmi_shut_down();
        return error.NoDevicesFound;
    }

    return num_devices;
}

fn shutdownAMDSMI() void {
    _ = c.amdsmi_shut_down();
}

fn getGPUInfoAMDSMI(device_index: u32) !GPUInfo {
    var handles: [8]c.amdsmi_processor_handle = undefined;
    var count: u32 = handles.len;
    if (c.amdsmi_get_processor_handles(&count, &handles) != c.AMDSMI_STATUS_SUCCESS or device_index >= count)
        return error.DeviceHandleError;

    const handle = handles[device_index];
    var temp: i64 = 0;
    var gpu_busy: u32 = 0;
    var mem_total: u64 = 0;
    var mem_used: u64 = 0;
    var fan_speed: i64 = 0;
    var fan_max: u64 = 0;

    // Temperature
    const temp_result = c.amdsmi_get_temp_metric(handle, c.AMDSMI_TEMP_TYPE_EDGE, c.AMDSMI_TEMP_CURR, &temp);
    const temperature: f64 = if (temp_result == c.AMDSMI_STATUS_SUCCESS) @as(f64, @floatFromInt(temp)) / 1000.0 else 0.0;

    // GPU usage
    const busy_result = c.amdsmi_get_gpu_busy_percent(handle, &gpu_busy);
    const gpu_usage: u64 = if (busy_result == c.AMDSMI_STATUS_SUCCESS) gpu_busy else 0;

    // VRAM info
    var usage: u64 = 0;
    var total: u64 = 0;
    const mem_used_result = c.amdsmi_get_gpu_memory_usage(handle, c.AMDSMI_MEM_TYPE_VRAM, &usage);
    const mem_total_result = c.amdsmi_get_gpu_memory_total(handle, c.AMDSMI_MEM_TYPE_VRAM, &total);

    if (mem_used_result == c.AMDSMI_STATUS_SUCCESS) mem_used = usage;
    if (mem_total_result == c.AMDSMI_STATUS_SUCCESS) mem_total = total;
    const mem_free = if (mem_total > mem_used) mem_total - mem_used else 0;

    const fan_result = c.amdsmi_get_gpu_fan_speed(handle, 0, &fan_speed);
    const fan_max_result = c.amdsmi_get_gpu_fan_speed_max(handle, 0, &fan_max);

    var fan_pwm: u64 = 0;
    if (fan_result == c.AMDSMI_STATUS_SUCCESS and fan_max_result == c.AMDSMI_STATUS_SUCCESS and fan_max > 0) {
        const scaled = @as(i128, fan_speed) * 100;
        fan_pwm = @as(u64, @intCast(@divTrunc(scaled, @as(i128, fan_max))));
        fan_pwm = @min(fan_pwm, 100);
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
    const stdout = io.getStdOut().writer();

    _ = try initializeAMDSMI();
    defer shutdownAMDSMI();

    while (true) {
        try (try getGPUInfoAMDSMI(0)).toJson(stdout);
        try stdout.writeByte('\n');
        try waybar.signal(11);

        time.sleep(1 * time.ns_per_s);
    }
}
