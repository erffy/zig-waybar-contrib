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
// along with this program. If not, see <https://gnu.org/licenses>.

const std = @import("std");
const mem = std.mem;
const c = std.c;
const posix = std.posix;
const fmt = std.fmt;

const Allocator = mem.Allocator;

pub fn resolveIP(allocator: Allocator, domain: []const u8, port: []const u8) !?[]const u8 {
    const domain_cstr = try allocator.dupeZ(u8, domain);
    const port_cstr = try allocator.dupeZ(u8, port);

    const hints = c.addrinfo{
        .family = posix.AF.INET,
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
    defer c.freeaddrinfo(result.?);

    const node = result.?;

    const ipv4 = @as(*const posix.sockaddr.in, @ptrCast(@alignCast(node.addr.?)));
    const bytes = mem.asBytes(&ipv4.addr);

    return try fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ bytes[0], bytes[1], bytes[2], bytes[3] });
}