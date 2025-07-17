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
const ascii = std.ascii;
const fmt = std.fmt;
const mem = std.mem;

pub fn getPid() !?u32 {
    var dir = try fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!ascii.isDigit(entry.name[0])) continue;

        var path_buf: [64]u8 = undefined;
        const path = try fmt.bufPrint(&path_buf, "/proc/{s}/comm", .{entry.name});

        const file = fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        var name_buf: [64]u8 = undefined;
        const n = try file.readAll(&name_buf);
        const proc_name = mem.trimRight(u8, name_buf[0..n], "\n");

        if (mem.eql(u8, proc_name, "waybar")) return try fmt.parseInt(u32, entry.name, 10);
    }

    return null;
}
