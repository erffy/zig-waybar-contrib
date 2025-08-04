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
        const gpuInfo = try SMI.getGPUInfo(handle);

        try gpuInfo.toJson(stdout);
        try stdout.writeByte('\n');
        try waybar.signal(11);

        Thread.sleep(1 * time.ns_per_s);
    }
}
