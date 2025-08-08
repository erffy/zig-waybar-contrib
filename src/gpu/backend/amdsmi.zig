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
const io = std.io;
const time = std.time;
const heap = std.heap;

const utils = @import("utils");
const format = utils.format;

const formatSize = format.formatSize;

const c = @cImport({
    @cInclude("amd_smi/amdsmi.h");
});

pub const GPUInfo = struct {
    gpu_busy: u64,
    temperature: f64,
    pwm: u64,
    mem_total: u64,
    mem_used: u64,
    mem_free: u64,

    pub inline fn json(self: GPUInfo, writer: anytype) !void {
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

pub fn initialize() !c.amdsmi_processor_handle {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (c.amdsmi_init(c.AMDSMI_INIT_AMD_GPUS) != c.AMDSMI_STATUS_SUCCESS) return error.AmdSmiInitFailed;

    var socket_count: u32 = 0;
    _ = c.amdsmi_get_socket_handles(&socket_count, null);
    if (socket_count == 0) return error.NoDevicesFound;

    const sockets = try allocator.alloc(c.amdsmi_socket_handle, socket_count);
    defer allocator.free(sockets);
    _ = c.amdsmi_get_socket_handles(&socket_count, sockets.ptr);

    var proc_count: u32 = 0;
    _ = c.amdsmi_get_processor_handles(sockets[0], &proc_count, null);
    if (proc_count == 0) return error.NoDevicesFound;

    const procs = try allocator.alloc(c.amdsmi_processor_handle, proc_count);
    defer allocator.free(procs);
    _ = c.amdsmi_get_processor_handles(sockets[0], &proc_count, procs.ptr);

    return procs[0];
}

pub fn shutdown() void {
    _ = c.amdsmi_shut_down();
}

pub fn getGPUInfo(handle: c.amdsmi_processor_handle) !GPUInfo {
    var temp: i64 = 0;
    var gpu_busy: u32 = 0;
    var mem_total: u64 = 0;
    var mem_used: u64 = 0;
    var fan_speed: i64 = 0;
    var fan_max: u64 = 0;

    // Temperature
    const temp_result = c.amdsmi_get_temp_metric(handle, c.AMDSMI_TEMPERATURE_TYPE_EDGE, c.AMDSMI_TEMP_CURRENT, &temp);
    const temperature: f64 = if (temp_result == c.AMDSMI_STATUS_SUCCESS)
        @as(f64, @floatFromInt(temp))
    else
        0.0;

    // Busy info
    const gpu_result = c.amdsmi_get_gpu_busy_percent(handle, &gpu_busy);
    const gpu_usage: u64 = if (gpu_result == c.AMDSMI_STATUS_SUCCESS)
        gpu_busy
    else
        0;

    // Memory info
    _ = c.amdsmi_get_gpu_memory_total(handle, c.AMDSMI_MEM_TYPE_VRAM, &mem_total);
    _ = c.amdsmi_get_gpu_memory_usage(handle, c.AMDSMI_MEM_TYPE_VRAM, &mem_used);
    const mem_free = if (mem_total > mem_used) mem_total - mem_used else 0;

    // PWM info
    const fan_result = c.amdsmi_get_gpu_fan_speed(handle, 0, &fan_speed);
    const fan_max_result = c.amdsmi_get_gpu_fan_speed_max(handle, 0, &fan_max);

    var fan_pwm: u64 = 0;
    if (fan_result == c.AMDSMI_STATUS_SUCCESS and fan_max_result == c.AMDSMI_STATUS_SUCCESS and fan_max > 0) fan_pwm = @min(@as(u64, @intCast(@divTrunc(@as(i128, fan_speed) * 100, @as(i128, fan_max)))), 100);

    return GPUInfo{
        .temperature = temperature,
        .gpu_busy = gpu_usage,
        .pwm = fan_pwm,
        .mem_total = mem_total,
        .mem_used = mem_used,
        .mem_free = mem_free,
    };
}