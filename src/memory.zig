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
const mem = std.mem;
const io = std.io;
const fs = std.fs;
const math = std.math;
const time = std.time;
const posix = std.posix;
const Thread = std.Thread;

const utils = @import("utils");
const waybar = utils.waybar;
const format = utils.format;

const formatSize = format.formatSizeKilo;

const MemoryInfo = struct {
    mem_total: u64 = 0,
    mem_used: u64 = 0,
    mem_free: u64 = 0,
    mem_shared: u64 = 0,
    mem_buff_cache: u64 = 0,
    mem_available: u64 = 0,

    swap_total: u64 = 0,
    swap_used: u64 = 0,
    swap_free: u64 = 0,

    active: u64 = 0,
    inactive: u64 = 0,
    anon_pages: u64 = 0,
    mapped: u64 = 0,
    dirty: u64 = 0,
    writeback: u64 = 0,
    kernel_stack: u64 = 0,
    page_tables: u64 = 0,
    slab: u64 = 0,

    pub inline fn toJson(self: MemoryInfo, writer: anytype) !void {
        const total_usage = self.mem_used + self.swap_used;
        const total_percentage = @as(f64, @floatFromInt(total_usage)) / @as(f64, @floatFromInt(self.mem_total + self.swap_total)) * 100;

        try writer.print("{{\"text\":\"  {d:.2} · {d:.0}%\",\"tooltip\":\"Total · {d:.2}\\nUsed · {d:.2}\\nFree · {d:.2}\\nAvailable · {d:.2}\\nShared · {d:.2}\\nBuffer / Cache · {d:.2}\\n\\nActive · {d:.2}\\nInactive · {d:.2}\\nAnon Pages · {d:.2}\\nMapped · {d:.2}\\nDirty · {d:.2}\\nWriteback · {d:.2}\\nKernel Stack · {d:.2}\\nPage Tables · {d:.2}\\nSlab · {d:.2}\\n\\nSwap Total · {d:.2}\\nSwap Used · {d:.2}\\nSwap Free · {d:.2}\"}}", .{
            formatSize(total_usage),
            total_percentage,
            formatSize(self.mem_total),
            formatSize(self.mem_used),
            formatSize(self.mem_free),
            formatSize(self.mem_available),
            formatSize(self.mem_shared),
            formatSize(self.mem_buff_cache),
            formatSize(self.active),
            formatSize(self.inactive),
            formatSize(self.anon_pages),
            formatSize(self.mapped),
            formatSize(self.dirty),
            formatSize(self.writeback),
            formatSize(self.kernel_stack),
            formatSize(self.page_tables),
            formatSize(self.slab),
            formatSize(self.swap_total),
            formatSize(self.swap_used),
            formatSize(self.swap_free),
        });
    }
};

inline fn asInt(s: []const u8) u128 {
    var buf = [1]u8{0} ** 16;
    if (s.len <= buf.len) @memcpy(buf[0..s.len], s);
    return @bitCast(buf);
}

noinline fn parse() !MemoryInfo {
    var file_buf: [1024]u8 = undefined;
    var content = try fs.cwd().readFile("/proc/meminfo", &file_buf);

    var result = MemoryInfo{};
    var buffers: u64 = 0;
    var cached: u64 = 0;
    var pos: usize = 0;
    while (mem.indexOfScalarPos(u8, content, pos, ':')) |idx| {
        const label = content[pos..idx];
        var name_int: u128 = 0;
        const name_buf = mem.asBytes(&name_int);
        @memcpy(name_buf[0..label.len], label);
        const line_start = idx + 1;
        pos = (mem.indexOfScalarPos(u8, content, line_start, '\n') orelse break) + 1;

        const value_start = mem.trimLeft(u8, content[line_start..pos], " ");
        const end_index = mem.indexOfScalar(u8, value_start, ' ') orelse value_start.len;
        const value_str = value_start[0..end_index];
        switch (name_int) {
            asInt("MemTotal") => result.mem_total = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("MemFree") => result.mem_free = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("MemAvailable") => result.mem_available = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Buffers") => buffers = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Cached") => cached = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Shmem") => result.mem_shared = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("SwapTotal") => result.swap_total = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("SwapFree") => result.swap_free = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Active") => result.active = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Inactive") => result.inactive = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("AnonPages") => result.anon_pages = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Mapped") => result.mapped = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Dirty") => result.dirty = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Writeback") => result.writeback = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("KernelStack") => result.kernel_stack = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("PageTables") => result.page_tables = try fmt.parseUnsigned(u64, value_str, 10),
            asInt("Slab") => result.slab = try fmt.parseUnsigned(u64, value_str, 10),
            else => {},
        }
    }
    result.mem_buff_cache = buffers + cached;
    result.mem_used = result.mem_total - result.mem_available;
    result.swap_used = result.swap_total - result.swap_free;
    return result;
}

pub fn main() !void {
    var stdout = io.getStdOut().writer();

    while (true) {
        const memInfo = try parse();

        try memInfo.toJson(stdout);
        try stdout.writeByte('\n');
        try waybar.signal(12);

        Thread.sleep(1 * time.ns_per_s);
    }
}
