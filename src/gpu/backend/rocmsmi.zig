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

// Reduced support will not receive feature or quality updates.
// Use amdsmi if possible.

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
const format = utils.format;

const formatSize = format.formatSize;

const c = @cImport({
    @cInclude("rocm_smi/rocm_smi.h");
});

pub const MAX_DEVICES = 32;
var device_ids: [MAX_DEVICES]u32 = undefined;
var device_count: usize = 0;

const GPUInfo = struct {
    gpu_busy: u64,
    temperature: f64,
    pwm: u64,
    mem_total: u64,
    mem_used: u64,
    mem_free: u64,

    pub inline fn toJson(self: GPUInfo, writer: anytype) !void {
        try writer.print(
            "{{\"text\":\"  {d}% · {d}°C\",\"tooltip\":\"PWM · {d}%\\nVRAM Total · {d:.2}\\nVRAM Used · {d:.2}\\nVRAM Free · {d:.2}\"}}",
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

pub fn initialize() !usize {
    if (c.rsmi_init(0) != c.RSMI_STATUS_SUCCESS)
        return error.ROCmSMIInitFailed;

    var num_devices: u32 = 0;
    if (c.rsmi_num_monitor_devices(&num_devices) != c.RSMI_STATUS_SUCCESS) {
        _ = shutdown();
        return error.DeviceCountFailed;
    }

    if (num_devices == 0) {
        _ = shutdown();
        return error.NoDevicesFound;
    }

    var i: u32 = 0;
    device_count = 0;

    while (i < num_devices and device_count < MAX_DEVICES) : (i += 1) {
        var temp: c.uint64_t = 0;
        const status = c.rsmi_dev_temp_metric_get(i, c.RSMI_TEMP_TYPE_EDGE, c.RSMI_TEMP_CURRENT, &temp);

        if (status == c.RSMI_STATUS_SUCCESS) {
            device_ids[device_count] = i;
            device_count += 1;
        }
    }

    if (device_count == 0) {
        _ = shutdown();
        return error.NoUsableDevices;
    }

    return device_count;
}

pub fn shutdown() void {
    _ = c.rsmi_shut_down();
}

pub fn getGPUInfo(device_id: u32) !GPUInfo {
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
