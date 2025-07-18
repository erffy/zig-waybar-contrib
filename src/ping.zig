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
const net = std.net;
const mem = std.mem;
const posix = std.posix;
const io = std.io;
const time = std.time;
const heap = std.heap;
const Thread = std.Thread;

const utils = @import("utils");
const waybar = utils.waybar;

const PingError = error{
    Timeout,
    NetworkError,
};

const TARGET = "94.140.14.14";
const PACKET_SIZE = 64;
const TIMEOUT_MS: i64 = 10000;

const PingResult = struct {
    icon: []const u8 = "",
    target: []const u8,
    latency: i64,
    quality: []const u8,

    pub inline fn format(self: PingResult, writer: anytype) !void {
        try writer.print(
            "{{\"text\":\"  {d}ms\", \"tooltip\":\"Quality: {s}\\nTarget: {s}\"}}",
            .{ self.latency, self.quality, self.target },
        );
    }
};

inline fn calculateChecksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;

    while (i + 3 < data.len) : (i += 4) sum += @as(u32, data[i]) << 24 |
        @as(u32, data[i + 1]) << 16 |
        @as(u32, data[i + 2]) << 8 |
        data[i + 3];

    while (i < data.len) : (i += 1) sum += @as(u32, data[i]) << @as(u5, @intCast((data.len - i - 1) * 8));
    while (sum >> 16 != 0) sum = (sum & 0xFFFF) + (sum >> 16);

    return ~@as(u16, @truncate(sum));
}

inline fn createIcmpPacket(buffer: []u8) void {
    @memset(buffer, 0);
    buffer[0] = 8;
    buffer[1] = 0;

    const cs = calculateChecksum(buffer);
    buffer[2] = @as(u8, @truncate(cs >> 8));
    buffer[3] = @as(u8, @truncate(cs & 0xFF));
}

noinline fn ping(buffer: []u8, ip_address: []const u8) !i64 {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.ICMP);
    defer posix.close(socket);

    const timeout = posix.timeval{
        .sec = @intCast(TIMEOUT_MS / 1000),
        .usec = @intCast((TIMEOUT_MS % 1000) * 1000),
    };

    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, mem.asBytes(&timeout));

    const addr = try net.Address.parseIp4(ip_address, 0);

    const start_time = time.milliTimestamp();

    _ = try posix.sendto(socket, buffer, 0, &addr.any, addr.getOsSockLen());

    const recv_result = posix.recvfrom(socket, buffer, 0, null, null) catch |err| {
        if (err == error.WouldBlock) return PingError.Timeout;
        return PingError.NetworkError;
    };
    _ = recv_result;

    const latency = time.milliTimestamp() - start_time;
    return latency;
}

fn quality(latency: i64) []const u8 {
    return switch (latency) {
        -999_999_999...-1 => "Down",
        0...5 => "Lightning Fast",
        6...15 => "Ultra Fast",
        16...30 => "Excellent",
        31...50 => "Very Good",
        51...75 => "Good",
        76...100 => "Fair",
        101...150 => "Average",
        151...200 => "Subpar",
        201...300 => "Poor",
        301...500 => "Laggy",
        501...1000 => "Unusable",
        else => "Dead",
    };
}

pub fn main() !void {
    const stdout = io.getStdOut().writer();

    while (true) {
        var buffer: [PACKET_SIZE]u8 = undefined;
        createIcmpPacket(&buffer);

        const latency = ping(&buffer, TARGET) catch |err| switch (err) {
            PingError.Timeout => -1,
            PingError.NetworkError => -2,
            else => -3,
        };

        const result = PingResult{
            .target = TARGET,
            .latency = latency,
            .quality = quality(latency),
        };

        try result.format(stdout);
        try stdout.writeByte('\n');
        try waybar.signal(14);

        Thread.sleep(1 * time.ns_per_s);
    }
}
