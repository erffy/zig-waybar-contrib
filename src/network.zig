const std = @import("std");
const waybar = @import("waybar.zig");
const os = std.os;
const mem = std.mem;
const fmt = std.fmt;
const fs = std.fs;
const time = std.time;
const heap = std.heap;
const io = std.io;
const net = std.net;
const posix = std.posix;

const NetStats = struct {
    rx_bytes: u64,
    tx_bytes: u64,
    iface: []const u8,
};

// Constants
const INTERVAL_NS = time.ns_per_s;
const BUFFER_SIZE = 4096;
const SLEEP_INTERVAL_NS = 5_000_000; // 5ms

// Global state
var force_update: bool = false;
var last_rx: u64 = 0;
var last_tx: u64 = 0;
var current_iface: [32]u8 = undefined;
var current_iface_len: usize = 0;

// Pre-allocated buffers
var read_buffer: [BUFFER_SIZE]u8 = undefined;
var format_buffer: [64]u8 = undefined;

// Optimized human readable speed formatting
fn formatSpeed(bytes_per_sec: u64) []const u8 {
    return switch (bytes_per_sec) {
        0...999 => fmt.bufPrint(&format_buffer, "{d} B/s", .{bytes_per_sec}) catch "0 B/s",
        1000...999_999 => fmt.bufPrint(&format_buffer, "{d:.1} KB/s", .{@as(f32, @floatFromInt(bytes_per_sec)) / 1000.0}) catch "0 KB/s",
        1_000_000...999_999_999 => fmt.bufPrint(&format_buffer, "{d:.1} MB/s", .{@as(f32, @floatFromInt(bytes_per_sec)) / 1_000_000.0}) catch "0 MB/s",
        else => fmt.bufPrint(&format_buffer, "{d:.1} GB/s", .{@as(f32, @floatFromInt(bytes_per_sec)) / 1_000_000_000.0}) catch "0 GB/s",
    };
}

// Optimized integer parsing (no allocation)
fn parseU64Fast(str: []const u8) !u64 {
    if (str.len == 0) return error.InvalidNumber;

    var result: u64 = 0;
    for (str) |code| {
        if (code < '0' or code > '9') return error.InvalidNumber;

        const digit = code - '0';
        result = result * 10 + digit;
    }

    return result;
}

// Skip whitespace without allocation
fn skipWhitespace(str: []const u8) []const u8 {
    var start: usize = 0;
    while (start < str.len and (str[start] == ' ' or str[start] == '\t')) start += 1;
    return str[start..];
}

// Trim whitespace from end
fn trimEnd(str: []const u8) []const u8 {
    var end = str.len;
    while (end > 0 and (str[end - 1] == ' ' or str[end - 1] == '\t' or str[end - 1] == '\n' or str[end - 1] == '\r')) end -= 1;
    return str[0..end];
}

// Check if interface is likely the primary network interface
fn isPreferredInterface(iface: []const u8) u8 {
    // Priority scoring: higher = more preferred
    if (mem.startsWith(u8, iface, "eth")) return 90; // Ethernet
    if (mem.startsWith(u8, iface, "en")) return 85; // Ethernet (systemd naming)
    if (mem.startsWith(u8, iface, "wl")) return 80; // WiFi (systemd naming)
    if (mem.startsWith(u8, iface, "wlan")) return 75; // WiFi (traditional)
    if (mem.startsWith(u8, iface, "wifi")) return 70; // WiFi (alternative)
    if (mem.startsWith(u8, iface, "usb")) return 60; // USB networking
    if (mem.startsWith(u8, iface, "ppp")) return 50; // PPP connections
    if (mem.startsWith(u8, iface, "tun")) return 40; // VPN tunnels
    if (mem.startsWith(u8, iface, "tap")) return 35; // TAP interfaces
    if (mem.startsWith(u8, iface, "br")) return 30; // Bridges
    if (mem.startsWith(u8, iface, "docker")) return 20; // Docker interfaces
    if (mem.startsWith(u8, iface, "veth")) return 15; // Virtual ethernet
    if (mem.startsWith(u8, iface, "virbr")) return 10; // libvirt bridges
    return 5; // Unknown interface types get low priority
}

// Get the default route interface from /proc/net/route
fn getDefaultInterface() ![]const u8 {
    const file = fs.openFileAbsolute("/proc/net/route", .{}) catch return error.NoRoute;
    defer file.close();

    var route_buffer: [2048]u8 = undefined;
    const bytes_read = file.readAll(&route_buffer) catch return error.NoRoute;
    const content = route_buffer[0..bytes_read];

    var line_start: usize = 0;
    var line_count: u8 = 0;

    for (content, 0..) |byte, i| {
        if (byte == '\n') {
            line_count += 1;
            if (line_count == 1) { // Skip header
                line_start = i + 1;
                continue;
            }

            const line = content[line_start..i];
            line_start = i + 1;

            // Parse route line: Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT
            var field_start: usize = 0;
            var field_count: u8 = 0;
            var iface_name: []const u8 = "";
            var destination: []const u8 = "";

            for (line, 0..) |line_byte, j| {
                if (line_byte == '\t' or j == line.len - 1) {
                    const field_end = if (j == line.len - 1) j + 1 else j;
                    const field = line[field_start..field_end];

                    field_count += 1;
                    switch (field_count) {
                        1 => iface_name = field,
                        2 => {
                            destination = field;
                            // Check if this is default route (destination = 00000000)
                            if (mem.eql(u8, destination, "00000000")) {
                                // Store in global buffer
                                const copy_len = @min(iface_name.len, current_iface.len - 1);
                                @memcpy(current_iface[0..copy_len], iface_name[0..copy_len]);
                                current_iface_len = copy_len;
                                return current_iface[0..current_iface_len];
                            }
                            break;
                        },
                        else => {},
                    }

                    field_start = j + 1;
                }
            }
        }
    }

    return error.NoRoute;
}

// Optimized network stats reading with smart interface selection
fn readNetStats() !NetStats {
    const file = fs.openFileAbsolute("/proc/net/dev", .{}) catch return error.NoActiveInterface;
    defer file.close();

    const bytes_read = file.readAll(&read_buffer) catch return error.NoActiveInterface;
    const content = read_buffer[0..bytes_read];

    // Try to get the default route interface first
    const default_iface = getDefaultInterface() catch "";

    var line_start: usize = 0;
    var line_count: u8 = 0;
    var best_iface: []const u8 = "";
    var best_stats: NetStats = undefined;
    var best_priority: u8 = 0;
    var found_any = false;

    // Parse line by line without tokenizer allocation
    for (content, 0..) |byte, i| {
        if (byte == '\n') {
            line_count += 1;
            if (line_count <= 2) { // Skip headers
                line_start = i + 1;
                continue;
            }

            const line = content[line_start..i];
            line_start = i + 1;

            // Find colon
            const colon_pos = mem.indexOf(u8, line, ":") orelse continue;

            // Extract interface name
            const iface = trimEnd(line[0..colon_pos]);

            // Skip loopback
            if (mem.eql(u8, iface, "lo")) continue;

            // Parse data after colon
            const data = skipWhitespace(line[colon_pos + 1 ..]);

            // Manual field parsing (faster than tokenizer)
            var field_start: usize = 0;
            var field_count: u8 = 0;
            var rx_bytes: u64 = 0;
            var tx_bytes: u64 = 0;

            for (data, 0..) |data_byte, j| {
                if (data_byte == ' ' or data_byte == '\t' or j == data.len - 1) {
                    if (field_start < j or (j == data.len - 1 and data_byte != ' ' and data_byte != '\t')) {
                        const field_end = if (j == data.len - 1 and data_byte != ' ' and data_byte != '\t') j + 1 else j;
                        const field = data[field_start..field_end];

                        if (field.len > 0) {
                            field_count += 1;
                            switch (field_count) {
                                1 => rx_bytes = parseU64Fast(field) catch continue,
                                9 => {
                                    tx_bytes = parseU64Fast(field) catch continue;
                                    break;
                                },
                                else => {},
                            }
                        }
                    }

                    // Skip consecutive spaces
                    var next_start = j + 1;
                    while (next_start < data.len and (data[next_start] == ' ' or data[next_start] == '\t')) next_start += 1;
                    field_start = next_start;
                }
            }

            // Only consider interfaces with traffic
            if (rx_bytes + tx_bytes > 0) {
                // If this is the default route interface, use it immediately
                if (default_iface.len > 0 and mem.eql(u8, iface, default_iface)) {
                    const copy_len = @min(iface.len, current_iface.len - 1);
                    @memcpy(current_iface[0..copy_len], iface[0..copy_len]);
                    current_iface_len = copy_len;

                    return NetStats{
                        .rx_bytes = rx_bytes,
                        .tx_bytes = tx_bytes,
                        .iface = current_iface[0..current_iface_len],
                    };
                }

                // Otherwise, score interfaces by preference
                const priority = isPreferredInterface(iface);
                if (!found_any or priority > best_priority) {
                    best_priority = priority;
                    best_iface = iface;
                    best_stats = NetStats{
                        .rx_bytes = rx_bytes,
                        .tx_bytes = tx_bytes,
                        .iface = iface,
                    };
                    found_any = true;
                }
            }
        }
    }

    if (found_any) {
        // Store best interface name in global buffer
        const copy_len = @min(best_iface.len, current_iface.len - 1);
        @memcpy(current_iface[0..copy_len], best_iface[0..copy_len]);
        current_iface_len = copy_len;

        return NetStats{
            .rx_bytes = best_stats.rx_bytes,
            .tx_bytes = best_stats.tx_bytes,
            .iface = current_iface[0..current_iface_len],
        };
    }

    return error.NoActiveInterface;
}

// Format upload speed in separate buffer
fn formatUploadSpeed(bytes_per_sec: u64, buffer: []u8) []const u8 {
    return switch (bytes_per_sec) {
        0...999 => fmt.bufPrint(buffer, "{d} B/s", .{bytes_per_sec}) catch "0 B/s",
        1000...999_999 => fmt.bufPrint(buffer, "{d:.1} KB/s", .{@as(f32, @floatFromInt(bytes_per_sec)) / 1000.0}) catch "0 KB/s",
        1_000_000...999_999_999 => fmt.bufPrint(buffer, "{d:.1} MB/s", .{@as(f32, @floatFromInt(bytes_per_sec)) / 1_000_000.0}) catch "0 MB/s",
        else => fmt.bufPrint(buffer, "{d:.1} GB/s", .{@as(f32, @floatFromInt(bytes_per_sec)) / 1_000_000_000.0}) catch "0 GB/s",
    };
}

// Signal handler (kept simple)
fn handleSig(_: c_int) callconv(.C) void {
    force_update = true;
}

fn getLocalIPv4Address(buf: *[net.Address.formatBufLen]u8, iface_name: []const u8) ![]const u8 {
    var addrs = try net.getInterfaceAddresses(heap.page_allocator); // internals need allocator, but we don't allocate from it
    defer addrs.deinit();

    for (addrs.addrs) |addr| {
        if (addr.iface_name) |name| {
            if (mem.eql(u8, name, iface_name)) {
                if (addr.addr) |ip_addr| {
                    if (ip_addr.any.family == net.AddressFamily.ipv4) return ip_addr.format(buf);
                }
            }
        }
    }

    return "unknown";
}

pub fn main() !void {
    const stdout = io.getStdOut().writer();

    while (true) {
        const waybarPid = try waybar.getPid();

        const stats = readNetStats() catch {
            try stdout.writeAll("{{}}\n");
            time.sleep(INTERVAL_NS);
            continue;
        };

        const rx = stats.rx_bytes;
        const tx = stats.tx_bytes;

        if (last_rx != 0 and last_tx != 0) {
            const rx_speed = if (rx >= last_rx) rx - last_rx else 0;
            const tx_speed = if (tx >= last_tx) tx - last_tx else 0;

            const download_and_upload = formatSpeed(rx_speed + tx_speed);

            const download = formatSpeed(rx_speed);
            var upload_buffer: [64]u8 = undefined;
            const upload = formatUploadSpeed(tx_speed, &upload_buffer);

            try stdout.print("{{\"text\":\"{s}\",\"tooltip\":\"Gateway · {s}\\nLocal IP · {s}\\nInterface · {s}\\n  {s} ・   {s}\"}}\n", .{ download_and_upload, "0.0.0.0", "0.0.0.0", stats.iface, download, upload });

            if (waybarPid) |pid| try posix.kill(@intCast(pid), 32 + 14);
        }

        last_rx = rx;
        last_tx = tx;

        // High-precision timing loop
        const start = time.nanoTimestamp();
        while (true) {
            const elapsed = time.nanoTimestamp() - start;
            if (elapsed >= INTERVAL_NS or force_update) {
                force_update = false;
                break;
            }

            time.sleep(SLEEP_INTERVAL_NS);
        }
    }
}
