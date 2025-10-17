const std = @import("std");

const Sample = struct { idle: u64, total: u64 };

fn parseCpuLine(line: []const u8) !Sample {
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return error.UnexpectedFormat;
    var it = std.mem.tokenizeAny(u8, line[sp + 1 ..], " \t");

    var fields: [10]u64 = undefined;
    var idx: usize = 0;
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        if (idx >= fields.len) break;
        fields[idx] = try std.fmt.parseInt(u64, tok, 10);
        idx += 1;
    }
    if (idx < 4) return error.UnexpectedFormat;

    const user    = fields[0];
    const nice    = fields[1];
    const system  = fields[2];
    const idle    = fields[3];
    const iowait  = if (idx > 4) fields[4] else 0;
    const irq     = if (idx > 5) fields[5] else 0;
    const softirq = if (idx > 6) fields[6] else 0;
    const steal   = if (idx > 7) fields[7] else 0;

    const idle_all = idle + iowait;
    const non_idle = user + nice + system + irq + softirq + steal;
    const total = idle_all + non_idle;
    return Sample{ .idle = idle_all, .total = total };
}

fn readSnapshot(alloc: std.mem.Allocator) !struct {
    overall: Sample,
    cores: []Sample,
} {
    var file = try std.fs.openFileAbsolute("/proc/stat", .{});
    defer file.close();

    const buf = try file.readToEndAlloc(alloc, 128 * 1024);
    defer alloc.free(buf);

    var overall: Sample = undefined;
    var have_overall = false;
    var cores_count: usize = 0;

    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "cpu")) break;
        if (std.mem.startsWith(u8, line, "cpu ")) {
            overall = try parseCpuLine(line);
            have_overall = true;
        } else if (line.len >= 4 and std.ascii.isDigit(line[3])) {
            cores_count += 1;
        }
    }
    if (!have_overall) return error.UnexpectedFormat;

    var cores = try alloc.alloc(Sample, cores_count);
    errdefer alloc.free(cores);

    var idx: usize = 0;
    var lines2 = std.mem.splitScalar(u8, buf, '\n');
    while (lines2.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "cpu")) break;
        if (line.len >= 4 and std.ascii.isDigit(line[3])) {
            if (idx >= cores.len) break;
            cores[idx] = try parseCpuLine(line);
            idx += 1;
        }
    }

    return .{ .overall = overall, .cores = cores };
}

fn computeUsage(a: Sample, b: Sample) f64 {
    const totald: f64 = @floatFromInt(b.total - a.total);
    const idled:  f64 = @floatFromInt(b.idle  - a.idle);
    if (totald <= 0) return 0.0;
    return (totald - idled) / totald * 100.0;
}

fn readFrequencies(alloc: std.mem.Allocator) ![]u64 {
    var file = try std.fs.openFileAbsolute("/proc/cpuinfo", .{});
    defer file.close();

    const buf = try file.readToEndAlloc(alloc, 128 * 1024);
    defer alloc.free(buf);

    var count: usize = 0;
    var lines1 = std.mem.splitScalar(u8, buf, '\n');
    while (lines1.next()) |raw| {
        if (std.mem.startsWith(u8, raw, "cpu MHz")) count += 1;
    }

    var freqs = try alloc.alloc(u64, count);
    if (count == 0) return freqs;

    var idx: usize = 0;
    var lines2 = std.mem.splitScalar(u8, buf, '\n');
    while (lines2.next()) |raw| {
        if (std.mem.startsWith(u8, raw, "cpu MHz") and idx < count) {
            var parts = std.mem.splitSequence(u8, raw, ":");
            _ = parts.next(); // "cpu MHz"
            if (parts.next()) |val_str| {
                const val_trim = std.mem.trim(u8, val_str, " \t");
                const mhz_f = try std.fmt.parseFloat(f64, val_trim);
                freqs[idx] = @intFromFloat(mhz_f);
                idx += 1;
            }
        }
    }

    return freqs;
}


fn cpuUsageAllOnce(alloc: std.mem.Allocator, delay_ms: u64) !struct {
    overall: f64,
    avg: f64,
    cores: []f64,
    freqs: []u64,
} {
    const a = try readSnapshot(alloc);
    defer alloc.free(a.cores);
    std.Thread.sleep(delay_ms * std.time.ns_per_ms);
    const b = try readSnapshot(alloc);
    defer alloc.free(b.cores);

    if (a.cores.len != b.cores.len) return error.UnexpectedFormat;

    const per_core = try alloc.alloc(f64, a.cores.len);
    errdefer alloc.free(per_core);

    var sum: f64 = 0.0;
    for (per_core, 0..) |*val, i| {
        val.* = computeUsage(a.cores[i], b.cores[i]);
        sum += val.*;
    }

    const avg = if (per_core.len > 0) sum / @as(f64, @floatFromInt(per_core.len)) else 0.0;
    const freqs = try readFrequencies(alloc);

    return .{
        .overall = computeUsage(a.overall, b.overall),
        .avg = avg,
        .cores = per_core,
        .freqs = freqs,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var delay_ms: u64 = 200;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    for (args) |a| {
        if (std.mem.startsWith(u8, a, "--delay-ms=")) {
            delay_ms = try std.fmt.parseInt(u64, a["--delay-ms=".len..], 10);
        }
    }

    const res = try cpuUsageAllOnce(alloc, delay_ms);
    defer alloc.free(res.cores);
    defer alloc.free(res.freqs);

    const overall_i: i64 = @intFromFloat(@round(res.overall));
    const avg_i: i64 = @intFromFloat(@round(res.avg));
    const class = blk: {
        if (res.overall >= 90.0) break :blk "critical";
        if (res.overall >= 70.0) break :blk "warning";
        break :blk "good";
    };

    var out_buf: [2048]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const out = &out_writer.interface;

    // JSON
    try out.print("{{\"text\":\"CPU {d}%\",\"class\":\"{s}\",\"percentage\":{d},\"average\":{d},\"frequencies\":[", .{
        overall_i, class, overall_i, avg_i,
    });

    for (res.freqs, 0..) |f, i| {
        if (i != 0) try out.print(",", .{});
        try out.print("{d}", .{f});
    }
    try out.print("],\"cores\":[", .{});

    for (res.cores, 0..) |c, i| {
        if (i != 0) try out.print(",", .{});
        const ci: i64 = @intFromFloat(@round(c));
        try out.print("{d}", .{ci});
    }
    try out.print("]}}\n", .{});
    try out.flush();
}
