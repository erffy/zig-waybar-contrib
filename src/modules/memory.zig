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
const mem = std.mem;
const io = std.io;
const fs = std.fs;
const time = std.time;
const fmt = std.fmt;
const StaticStringMap = std.StaticStringMap;
const Thread = std.Thread;

const pid = @import("pid");

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
    swap_cached: u64 = 0,

    active: u64 = 0,
    inactive: u64 = 0,
    anon_pages: u64 = 0,
    mapped: u64 = 0,
    dirty: u64 = 0,
    writeback: u64 = 0,
    kernel_stack: u64 = 0,
    page_tables: u64 = 0,
    slab: u64 = 0,

    pub inline fn json(this: @This(), writer: *io.Writer) !void {
        const total_usage = this.mem_used + this.swap_used;
        const denom = this.mem_total + this.swap_total;
        const pct: f64 = if (denom == 0) 0 else @as(f64, @floatFromInt(total_usage)) / @as(f64, @floatFromInt(denom)) * 100.0;

        try writer.print(
            "{{\"text\":\"  {d:.0}% · {Bi:.2}\",\"tooltip\":\"Total · {Bi:.2}\\nUsed · {Bi:.2}\\nFree · {Bi:.2}\\nAvailable · {Bi:.2}\\nShared · {Bi:.2}\\nBuffer / Cache · {Bi:.2}\\n\\nActive · {Bi:.2}\\nInactive · {Bi:.2}\\nAnon Pages · {Bi:.2}\\nMapped · {Bi:.2}\\nDirty · {Bi:.2}\\nWriteback · {Bi:.2}\\nKernel Stack · {Bi:.2}\\nPage Tables · {Bi:.2}\\nSlab · {Bi:.2}\\n\\nSwap Total · {Bi:.2}\\nSwap Used · {Bi:.2}\\nSwap Free · {Bi:.2}\\nSwap Cached · {Bi:.2}\"}}",
            .{
                pct,
                total_usage,
                this.mem_total,
                this.mem_used,
                this.mem_free,
                this.mem_available,
                this.mem_shared,
                this.mem_buff_cache,
                this.active,
                this.inactive,
                this.anon_pages,
                this.mapped,
                this.dirty,
                this.writeback,
                this.kernel_stack,
                this.page_tables,
                this.slab,
                this.swap_total,
                this.swap_used,
                this.swap_free,
                this.swap_cached,
            },
        );
    }
};

const Key = enum {
    MemTotal,
    MemFree,
    MemAvailable,
    Buffers,
    Cached,
    Shmem,
    SwapTotal,
    SwapFree,
    SwapCached,
    Active,
    Inactive,
    AnonPages,
    Mapped,
    Dirty,
    Writeback,
    KernelStack,
    PageTables,
    Slab,
};

const key_map = StaticStringMap(Key).initComptime(.{
    .{ "MemTotal", .MemTotal },
    .{ "MemFree", .MemFree },
    .{ "MemAvailable", .MemAvailable },
    .{ "Buffers", .Buffers },
    .{ "Cached", .Cached },
    .{ "Shmem", .Shmem },
    .{ "SwapTotal", .SwapTotal },
    .{ "SwapFree", .SwapFree },
    .{ "SwapCached", .SwapCached },
    .{ "Active", .Active },
    .{ "Inactive", .Inactive },
    .{ "AnonPages", .AnonPages },
    .{ "Mapped", .Mapped },
    .{ "Dirty", .Dirty },
    .{ "Writeback", .Writeback },
    .{ "KernelStack", .KernelStack },
    .{ "PageTables", .PageTables },
    .{ "Slab", .Slab },
});

fn parseValueU64(s: []const u8) !u64 {
    var it = mem.tokenizeAny(u8, s, " \t");
    if (it.next()) |num| return fmt.parseUnsigned(u64, num, 10);
    return error.Invalid;
}

fn parse(buf: []const u8) !MemoryInfo {
    var info = MemoryInfo{};
    var buffers: u64 = 0;
    var cached: u64 = 0;
    var swap_cached: u64 = 0;

    var it = mem.splitScalar(u8, buf, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const colon = mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = line[0..colon];
        const rest = line[colon + 1 ..];

        if (key_map.get(key)) |which| {
            var v = parseValueU64(rest) catch continue;
            v *= 1024;

            switch (which) {
                .MemTotal => info.mem_total = v,
                .MemFree => info.mem_free = v,
                .MemAvailable => info.mem_available = v,
                .Buffers => buffers = v,
                .Cached => cached = v,
                .Shmem => info.mem_shared = v,
                .SwapTotal => info.swap_total = v,
                .SwapFree => info.swap_free = v,
                .SwapCached => swap_cached = v,
                .Active => info.active = v,
                .Inactive => info.inactive = v,
                .AnonPages => info.anon_pages = v,
                .Mapped => info.mapped = v,
                .Dirty => info.dirty = v,
                .Writeback => info.writeback = v,
                .KernelStack => info.kernel_stack = v,
                .PageTables => info.page_tables = v,
                .Slab => info.slab = v,
            }
        }
    }

    info.mem_buff_cache = buffers + cached + swap_cached;
    info.swap_cached = swap_cached;

    if (info.mem_available == 0 and info.mem_total != 0) {
        const freeish = info.mem_free + info.mem_buff_cache;
        info.mem_available = if (freeish > info.mem_total) 0 else info.mem_total - (info.mem_total - freeish);
    }

    if (info.mem_total >= info.mem_available) {
        info.mem_used = info.mem_total - info.mem_available;
    } else info.mem_used = 0;

    if (info.swap_total >= info.swap_free) {
        info.swap_used = info.swap_total - info.swap_free;
    } else info.swap_used = 0;

    return info;
}

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var buf: [8 * 1024]u8 = undefined;

    while (true) {
        var f = try fs.openFileAbsolute("/proc/meminfo", .{ .mode = .read_only });
        var f_reader = f.reader(&.{});
        const n = try f_reader.interface.readSliceShort(&buf);
        f.close();

        const mem_info = try parse(buf[0..n]);

        try mem_info.json(stdout);
        try stdout.writeByte('\n');
        try pid.signal("waybar", 12);

        try stdout.flush();

        Thread.sleep(1 * time.ns_per_s);
    }
}
