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
const fmt = std.fmt;

const KILO: comptime_int = 1024;
const MEGA: comptime_int = KILO * KILO;
const GIGA: comptime_int = KILO * MEGA;

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

pub inline fn formatSize(size: u64) FmtSize {
    return .{ .size = size };
}

pub inline fn formatSizeKilo(size_kib: u64) FmtSize {
    return formatSize(size_kib * 1024);
}