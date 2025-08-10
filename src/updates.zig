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
const process = std.process;
const heap = std.heap;
const io = std.io;
const sort = std.sort;
const fs = std.fs;
const ascii = std.ascii;
const math = std.math;
const posix = std.posix;
const time = std.time;
const fmt = std.fmt;
const ArrayList = std.ArrayList;
const Thread = std.Thread;

const utils = @import("utils");
const waybar = utils.waybar;

const resolveIp = @import("ping.zig").resolveIP;

const BUFFER_SIZE = 4096;
const MAX_VERSION_LENGTH = 20;
const MAX_UPDATES = 75;

const UpdateInfo = struct {
    pkg_name: [BUFFER_SIZE]u8,
    local_version: [MAX_VERSION_LENGTH + 1]u8,
    new_version: [MAX_VERSION_LENGTH + 1]u8,
};

const CheckUpdatesError = error{
    CannotCreateTempDb,
    CannotFetchUpdates,
    CommandFailed,
};

const ESCAPE_MAP = init: {
    var map: [256]u8 = undefined;
    for (0..256) |i| map[i] = @as(u8, @truncate(i));

    map['"'] = '\\';
    map['\\'] = '\\';
    map['\n'] = 'n';
    map['\r'] = 'r';
    map['\t'] = 't';
    break :init map;
};

inline fn escapeJson(input: []const u8, output: []u8) void {
    var j: usize = 0;
    for (input) |char| {
        if (j >= output.len - 1) break;

        const escaped = ESCAPE_MAP[char];
        if (escaped != char) {
            if (j + 2 >= output.len) break;
            output[j] = '\\';
            j += 1;
            output[j] = escaped;
        } else output[j] = char;

        j += 1;
    }

    output[j] = 0;
}

fn compareUpdates(context: void, a: UpdateInfo, b: UpdateInfo) bool {
    _ = context;
    return mem.lessThan(u8, &a.pkg_name, &b.pkg_name);
}

inline fn parseLine(line: []const u8, info: *UpdateInfo) bool {
    const trimmed = mem.trim(u8, line, &ascii.whitespace);
    if (trimmed.len == 0) return false;

    const arrow_idx = mem.indexOf(u8, trimmed, "->") orelse return false;
    const left_part = mem.trim(u8, trimmed[0..arrow_idx], &ascii.whitespace);
    const new_version = mem.trim(u8, trimmed[arrow_idx + 2 ..], &ascii.whitespace);
    if (new_version.len == 0) return false;

    const last_space = mem.lastIndexOf(u8, left_part, " ") orelse return false;
    const pkg_name = left_part[0..last_space];
    const local_ver = left_part[last_space + 1 ..];

    if (pkg_name.len >= info.pkg_name.len or
        local_ver.len >= info.local_version.len or
        new_version.len >= info.new_version.len) return false;

    @memset(&info.pkg_name, 0);
    @memset(&info.local_version, 0);
    @memset(&info.new_version, 0);

    @memcpy(info.pkg_name[0..pkg_name.len], pkg_name);
    @memcpy(info.local_version[0..local_ver.len], local_ver);
    @memcpy(info.new_version[0..new_version.len], new_version);

    return true;
}

noinline fn checkupdates(allocator: mem.Allocator) ![]u8 {
    const tmp_base = posix.getenv("TMPDIR") orelse "/var/tmp";
    const uid = posix.getenv("EUID") orelse "1000";

    var db_path_buffer: [fs.max_path_bytes]u8 = undefined;
    var tmp_local_buffer: [fs.max_path_bytes]u8 = undefined;

    const db_path = try fmt.bufPrint(&db_path_buffer, "{s}/checkup-db-{s}", .{ tmp_base, uid });

    _ = fs.openDirAbsolute(db_path, .{}) catch |err| switch (err) {
        error.FileNotFound => try fs.makeDirAbsolute(db_path),
        else => |e| return e,
    };
    defer fs.deleteTreeAbsolute(db_path) catch {};

    const local_db = "/var/lib/pacman/local";
    const tmp_local = try fmt.bufPrint(&tmp_local_buffer, "{s}/local", .{db_path});

    fs.symLinkAbsolute(local_db, tmp_local, .{}) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const sync_result = try runCommand(allocator, &[_][]const u8{ "fakeroot", "pacman", "-Sy", "--dbpath", db_path, "--logfile", "/dev/null" });

    if (sync_result != 0) {
        fs.deleteTreeAbsolute(db_path) catch {};
        return CheckUpdatesError.CannotFetchUpdates;
    }

    const updates = try getUpdates(allocator, db_path);
    if (updates.len == 0) {
        fs.deleteTreeAbsolute(db_path) catch {};
        return &[_]u8{};
    }

    return updates;
}

noinline fn getUpdates(allocator: mem.Allocator, db_path: []const u8) ![]u8 {
    var child = process.Child.init(&[_][]const u8{ "pacman", "-Qu", "--dbpath", db_path }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, math.maxInt(usize));
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, math.maxInt(usize));
    defer allocator.free(stderr);

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0 or stderr.len > 0) allocator.free(stdout);

    var lines = ArrayList(u8).init(allocator);
    var iter = mem.splitAny(u8, stdout, "\n");
    while (iter.next()) |line| {
        if (line.len == 0) continue;
        if (!mem.containsAtLeast(u8, line, 1, "[")) {
            try lines.appendSlice(line);
            try lines.append('\n');
        }
    }

    allocator.free(stdout);
    return lines.toOwnedSlice();
}

inline fn runCommand(allocator: mem.Allocator, argv: []const []const u8) !u8 {
    var child = process.Child.init(argv, allocator);
    child.stderr_behavior = .Ignore;
    child.stdout_behavior = .Ignore;

    try child.spawn();
    const term = try child.wait();

    return switch (term) {
        .Exited => |code| code,
        else => return CheckUpdatesError.CommandFailed,
    };
}

pub fn main() !void {
    const stdout = io.getStdOut().writer();

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var err_buf: [512]u8 = undefined;

    while (true) {
        while (try resolveIp(allocator, "google.com", "80") == null) {
            Thread.sleep(500 * time.ns_per_ms);
        }

        _ = arena.reset(.free_all);

        const result = checkupdates(allocator);
        if (result) |updates_output| {
            if (updates_output.len == 0) {
                try stdout.print("{{}}", .{});
            } else {
                var updates = try allocator.alloc(UpdateInfo, MAX_UPDATES);
                var updates_count: usize = 0;

                var lines = mem.splitAny(u8, updates_output, "\n");
                while (lines.next()) |line| {
                    if (updates_count >= MAX_UPDATES) break;
                    if (line.len == 0) continue;
                    if (parseLine(line, &updates[updates_count])) updates_count += 1;
                }

                sort.insertion(UpdateInfo, updates[0..updates_count], {}, compareUpdates);

                var output_buffer: [BUFFER_SIZE * MAX_UPDATES]u8 = undefined;
                var output_stream = io.fixedBufferStream(&output_buffer);
                const writer = output_stream.writer();

                for (updates[0..updates_count], 0..) |update, i| {
                    try writer.print("{s:<25} {s:<15} -> {s}\n", .{
                        mem.sliceTo(&update.pkg_name, 0),
                        mem.sliceTo(&update.local_version, 0),
                        mem.sliceTo(&update.new_version, 0),
                    });

                    if (i == MAX_UPDATES - 1 and updates_count >= MAX_UPDATES) {
                        try writer.writeAll("...");
                        break;
                    }
                }

                const written = output_stream.pos;
                if (written > 0 and output_buffer[written - 1] == '\n')
                    output_stream.pos -= 1;

                var json_buffer: [BUFFER_SIZE * 2]u8 = undefined;
                escapeJson(output_buffer[0..output_stream.pos], &json_buffer);

                try stdout.print("{{\"text\":\"  {d}\",\"tooltip\":\"{s}\"}}", .{ updates_count, mem.sliceTo(&json_buffer, 0) });
            }
        } else |err| {
            const msg = fmt.bufPrint(&err_buf, "Error: {s}", .{@errorName(err)}) catch "Unknown";
            escapeJson(msg, &err_buf);
            try stdout.print("{{\"text\":\"  err\",\"tooltip\":\"{s}\"}}", .{mem.sliceTo(&err_buf, 0)});
        }

        try stdout.writeByte('\n');
        try waybar.signal(10);

        Thread.sleep(160 * time.ns_per_s);
    }
}
