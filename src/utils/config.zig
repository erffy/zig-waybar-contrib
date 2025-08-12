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
const heap = std.heap;
const process = std.process;
const fs = std.fs;
const json = std.json;
const mem = std.mem;
const Allocator = mem.Allocator;

pub fn readConfig(allocator: Allocator, config_name: []const u8) !json.Parsed(json.Value) {
    const home_dir = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    const config_path = try fs.path.join(allocator, &.{ home_dir, ".config", "zwc", config_name });
    defer allocator.free(config_path);

    var file = fs.openFileAbsolute(config_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => return err,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    _ = try file.readAll(buffer);

    return try json.parseFromSlice(json.Value, allocator, buffer, .{});
}