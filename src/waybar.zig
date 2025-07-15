const std = @import("std");
const fs = std.fs;
const ascii = std.ascii;
const fmt = std.fmt;
const mem = std.mem;

pub fn getPid() !?u32 {
    var dir = try fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!ascii.isDigit(entry.name[0])) continue;

        var path_buf: [64]u8 = undefined;
        const path = try fmt.bufPrint(&path_buf, "/proc/{s}/comm", .{entry.name});

        const file = fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        var name_buf: [64]u8 = undefined;
        const n = try file.readAll(&name_buf);
        const proc_name = mem.trimRight(u8, name_buf[0..n], "\n");

        if (mem.eql(u8, proc_name, "waybar")) return try fmt.parseInt(u32, entry.name, 10);
    }

    return null;
}
