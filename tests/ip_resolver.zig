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
const posix = std.posix;

pub fn resolveIP(allocator: std.mem.Allocator, domain: []const u8, port: []const u8) !?[]const u8 {
    // Convert to null-terminated strings
    const domain_cstr = try allocator.dupeZ(u8, domain);
    defer allocator.free(domain_cstr);
    const port_cstr = try allocator.dupeZ(u8, port);
    defer allocator.free(port_cstr);
    
    const hints = std.c.addrinfo{
        .family = posix.AF.UNSPEC, // IPv4 or IPv6
        .socktype = posix.SOCK.STREAM, // TCP
        .protocol = 0,
        .flags = std.c.AI{},
        .addrlen = 0,
        .canonname = null,
        .addr = null,
        .next = null,
    };

    var result: ?*std.c.addrinfo = null;
    _ = std.c.getaddrinfo(domain_cstr.ptr, port_cstr.ptr, &hints, &result);
    defer if (result) |res| std.c.freeaddrinfo(res);
    
    const ai = result;
    if (ai) |node| {
        const sockaddr = node.addr.?;

        // Handle different address families
        switch (sockaddr.family) {
            posix.AF.INET => {
                const ipv4_sockaddr = @as(*const posix.sockaddr.in, @ptrCast(@alignCast(node.addr)));
                
                // Extract IP address bytes (in network byte order)
                const addr_bytes = std.mem.asBytes(&ipv4_sockaddr.addr);
                return try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{
                    addr_bytes[0], addr_bytes[1], addr_bytes[2], addr_bytes[3]
                });
            },
            posix.AF.INET6 => {
                const ipv6_sockaddr = @as(*const posix.sockaddr.in6, @ptrCast(@alignCast(node.addr)));
                const addr_bytes = std.mem.asBytes(&ipv6_sockaddr.addr);
                
                var ip_buffer: [39]u8 = undefined; // Max IPv6 string length
                var ip_len: usize = 0;
                
                for (0..16) |i| {
                    if (i > 0 and i % 2 == 0) {
                        ip_buffer[ip_len] = ':';
                        ip_len += 1;
                    }
                    const hex_chars = std.fmt.bufPrint(ip_buffer[ip_len..], "{x:0>2}", .{addr_bytes[i]}) catch unreachable;
                    ip_len += hex_chars.len;
                }
                
                return try allocator.dupe(u8, ip_buffer[0..ip_len]);
            },
            else => {
                return null;
            },
        }
    }
    
    return null;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const domain = "example.com";
    const port = "80";
    
    if (try resolveIP(allocator, domain, port)) |ip| {
        defer allocator.free(ip);
        std.debug.print("Resolved IP: {s}\n", .{ip});
    } else {
        std.debug.print("Failed to resolve domain\n", .{});
    }
}