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

const utils = @import("utils");
const format = utils.format;

const formatSize = format.formatSize;

const c = @cImport({
    @cInclude("nvml.h");
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

pub fn initialize() !c.nvmlDevice_t {
    if (c.nvmlInit() != c.NVML_SUCCESS)
        return error.NVMLInitFailed;

    var device_count: c_uint = 0;
    if (c.nvmlDeviceGetCount(&device_count) != c.NVML_SUCCESS or device_count == 0)
        return error.NoDevicesFound;

    var handle: c.nvmlDevice_t = undefined;
    if (c.nvmlDeviceGetHandleByIndex(0, &handle) != c.NVML_SUCCESS)
        return error.DeviceHandleFailed;

    return handle;
}

pub fn shutdown() void {
    _ = c.nvmlShutdown();
}

pub fn getGPUInfo(handle: c.nvmlDevice_t) !GPUInfo {
    var util: c.nvmlUtilization_t = undefined;
    _ = c.nvmlDeviceGetUtilizationRates(handle, &util);

    var temp: c_uint = 0;
    _ = c.nvmlDeviceGetTemperature(handle, c.NVML_TEMPERATURE_GPU, &temp);

    var mem_info: c.nvmlMemory_t = undefined;
    _ = c.nvmlDeviceGetMemoryInfo(handle, &mem_info);

    var fan_speed: c_uint = 0;
    const fan_result = c.nvmlDeviceGetFanSpeed(handle, &fan_speed);

    return GPUInfo{
        .gpu_busy = util.gpu,
        .temperature = @floatFromInt(temp),
        .pwm = if (fan_result == c.NVML_SUCCESS) fan_speed else 0,
        .mem_total = mem_info.total,
        .mem_used = mem_info.used,
        .mem_free = mem_info.free,
    };
}