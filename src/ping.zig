const std = @import("std");
const net = std.net;
const mem = std.mem;
const posix = std.posix;
const io = std.io;
const time = std.time;
const heap = std.heap;

const PingResult = struct {
    latency: ?i64,
    error_message: ?[]const u8,
};

const TARGET = "8.8.8.8";
const PACKET_SIZE = 64;
const TIMEOUT_MS: i64 = 5000;

inline fn calculateChecksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;

    while (i + 1 < data.len) : (i += 2) sum += @as(u16, data[i]) << 8 | data[i + 1];

    if (i < data.len) sum += @as(u16, data[i]) << 8;

    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);

    return ~@as(u16, @truncate(sum));
}

inline fn createIcmpPacket(allocator: mem.Allocator) ![]u8 {
    var packet = try allocator.alloc(u8, PACKET_SIZE);
    @memset(packet, 0);

    packet[0] = 8;
    packet[1] = 0;

    const cs = calculateChecksum(packet);
    packet[2] = @as(u8, @truncate(cs >> 8));
    packet[3] = @as(u8, @truncate(cs & 0xFF));

    return packet;
}

noinline fn ping(allocator: mem.Allocator, ip_address: []const u8) !PingResult {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.ICMP);
    defer posix.close(socket);

    const timeout = posix.timeval{
        .tv_sec = @intCast(TIMEOUT_MS / 1000),
        .tv_usec = @intCast((TIMEOUT_MS % 1000) * 1000),
    };

    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, mem.asBytes(&timeout));

    const addr = try net.Address.parseIp4(ip_address, 0);

    const packet = try createIcmpPacket(allocator);
    defer allocator.free(packet);

    const start_time = time.milliTimestamp();

    _ = try posix.sendto(socket, packet, 0, &addr.any, addr.getOsSockLen());

    var recv_buffer = [_]u8{0} ** PACKET_SIZE;
    _ = try posix.recvfrom(socket, &recv_buffer, 0, null, null);

    const latency = time.milliTimestamp() - start_time;

    return PingResult{ .latency = if (latency >= 0 and latency <= TIMEOUT_MS) latency else null, .error_message = null };
}

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var bw = io.bufferedWriter(io.getStdOut().writer());

    const result = try ping(allocator, TARGET);

    if (result.latency) |latency| {
        try bw.writer().print("{{\"text\":\"   {d}ms\", \"tooltip\":\"Target: {s}\"}}", .{ latency, TARGET });
    } else {
        try bw.writer().print("{{\"text\":\"\", \"tooltip\":\"\", \"class\":\"hidden\"}}", .{});
    }

    try bw.flush();
}