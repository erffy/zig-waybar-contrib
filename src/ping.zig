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
const c = std.c;
const fmt = std.fmt;
const Thread = std.Thread;
const Allocator = mem.Allocator;

const utils = @import("utils");
const waybar = utils.waybar;
const readConfig = utils.config.readConfig;

const PingError = error{
    Timeout,
    NetworkError,
};

const BUFFER_SIZE = 64;
var target_last_update_ms: i64 = 0;

const Data = struct {
    TARGET_DOMAIN: []const u8,
    TARGET_IP: []const u8,
    TARGET_PORT: []const u8,
    TARGET_UPDATE_MS: i64,
    TIMEOUT_MS: i64,
};

const PingResult = struct {
    icon: []const u8 = "",
    latency: i64,
    quality: []const u8,
    data: Data,

    pub inline fn format(self: PingResult, writer: anytype) !void {
        const now = time.milliTimestamp();
        const next_update_sec = @max(0, self.data.TARGET_UPDATE_MS - (@divTrunc(now - target_last_update_ms, 1000)));

        try writer.print(
            "{{\"text\":\"  {d}ms\", \"tooltip\":\"Quality · {s}\\nDomain · {s}\\nDomain IP · {s}\\nDomain IP Update · {d}s\"}}",
            .{ self.latency, self.quality, self.data.TARGET_DOMAIN, self.data.TARGET_IP, next_update_sec },
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

noinline fn ping(buffer: []u8, data: Data) !i64 {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.ICMP);
    defer posix.close(socket);

    const timeout = posix.timeval{
        .sec = @intCast(@divExact(data.TIMEOUT_MS, 1000)),
        .usec = @intCast((@mod(data.TIMEOUT_MS, 1000)) * 1000),
    };

    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, mem.asBytes(&timeout));

    const addr = try net.Address.parseIp4(data.TARGET_IP, 0);

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

pub fn resolveIP(allocator: Allocator, domain: []const u8, port: []const u8) !?[]const u8 {
    const domain_cstr = try allocator.dupeZ(u8, domain);
    const port_cstr = try allocator.dupeZ(u8, port);

    const hints = c.addrinfo{
        .family = posix.AF.UNSPEC,
        .socktype = posix.SOCK.STREAM,
        .protocol = 0,
        .flags = c.AI{},
        .addrlen = 0,
        .canonname = null,
        .addr = null,
        .next = null,
    };

    var result: ?*c.addrinfo = null;
    _ = c.getaddrinfo(domain_cstr.ptr, port_cstr.ptr, &hints, &result);
    defer if (result) |res| c.freeaddrinfo(res);

    const ai = result;
    if (ai) |node| {
        const sockaddr = node.addr.?;

        switch (sockaddr.family) {
            posix.AF.INET => {
                const ipv4_sockaddr = @as(*const posix.sockaddr.in, @ptrCast(@alignCast(node.addr)));
                const addr_bytes = mem.asBytes(&ipv4_sockaddr.addr);
                return try fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ addr_bytes[0], addr_bytes[1], addr_bytes[2], addr_bytes[3] });
            },
            else => return null,
        }
    }

    return null;
}

const UpdateIPArguments = struct {
    allocator: Allocator,
    data: *Data,
};

fn updateIP(args: UpdateIPArguments) !void {
    while (true) {
        if (try resolveIP(args.allocator, args.data.TARGET_DOMAIN, args.data.TARGET_PORT)) |ip| {
            args.data.TARGET_IP = ip;
            target_last_update_ms = time.milliTimestamp();
        }

        Thread.sleep(@intCast(args.data.TARGET_UPDATE_MS * time.ns_per_s));
    }
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

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var data = Data{
        .TARGET_DOMAIN = try allocator.dupeZ(u8, "google.com"),
        .TARGET_IP = "",
        .TARGET_PORT = try allocator.dupeZ(u8, "80"),
        .TARGET_UPDATE_MS = 30,
        .TIMEOUT_MS = 10000,
    };

    const configData = try readConfig(allocator, "ping.json");
    if (configData) |config| {
        defer config.deinit();

        const config_obj = config.value.object;
        if (config_obj.get("TARGET_DOMAIN")) |target_domain_value| {
            const target_domain_str = target_domain_value.string;
            if (target_domain_str.len >= 4) data.TARGET_DOMAIN = try allocator.dupeZ(u8, target_domain_str);
        }

        if (config_obj.get("TARGET_PORT")) |target_port_value| {
            const target_port_str = target_port_value.string;
            data.TARGET_PORT = try allocator.dupeZ(u8, target_port_str);
        }

        if (config_obj.get("TARGET_UPDATE_MS")) |target_update_ms_value| {
            const target_update_ms_int = target_update_ms_value.integer;
            if (target_update_ms_int > 0) data.TARGET_UPDATE_MS = target_update_ms_int;
        }

        if (config_obj.get("TIMEOUT_MS")) |target_timeout_ms_value| {
            const target_timeout_ms_int = target_timeout_ms_value.integer;
            if (target_timeout_ms_int > 0) data.TIMEOUT_MS = target_timeout_ms_int;
        }
    }

    _ = try Thread.spawn(.{}, updateIP, .{UpdateIPArguments{ .allocator = allocator, .data = &data }});

    while (true) {
        if (data.TARGET_IP.len == 0) {
            Thread.sleep(100 * time.ns_per_ms);
            continue;
        }

        var buffer: [BUFFER_SIZE]u8 = undefined;
        createIcmpPacket(&buffer);

        const latency = ping(&buffer, data) catch |err| switch (err) {
            PingError.Timeout => -1,
            PingError.NetworkError => -2,
            else => -3,
        };

        const result = PingResult{
            .data = data,
            .latency = latency,
            .quality = quality(latency),
        };

        try result.format(stdout);
        try stdout.writeByte('\n');
        try waybar.signal(14);

        Thread.sleep(1 * time.ns_per_s);
    }
}
