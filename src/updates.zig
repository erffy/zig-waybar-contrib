const std = @import("std");
const mem = std.mem;
const process = std.process;
const heap = std.heap;
const io = std.io;
const sort = std.sort;
const fs = std.fs;
const ascii = std.ascii;
const allocator = heap.page_allocator;

const BUFFER_SIZE = 4096;
const MAX_VERSION_LENGTH = 20;
const MAX_UPDATES = 75;

const UpdateInfo = struct {
    pkg_name: [BUFFER_SIZE]u8,
    local_version: [MAX_VERSION_LENGTH + 1]u8,
    new_version: [MAX_VERSION_LENGTH + 1]u8,
};

noinline fn escapeJson(input: []const u8, output: []u8) void {
    const escape_chars = &[_]u8{ '"', '\\', '\n', '\r', '\t' };
    const escape_replacements = &[_]u8{ '"', '\\', 'n', 'r', 't' };
    var j: usize = 0;

    for (input) |char| {
        if (j >= output.len - 1) break;

        if (mem.indexOfScalar(u8, escape_chars, char)) |esc_index| {
            if (j + 2 >= output.len) break;
            output[j] = '\\';
            j += 1;
            output[j] = escape_replacements[esc_index];
        } else {
            output[j] = char;
        }
        j += 1;
    }
    output[j] = 0;
}

fn compareUpdates(context: void, a: UpdateInfo, b: UpdateInfo) bool {
    _ = context;
    return mem.lessThan(u8, &a.pkg_name, &b.pkg_name);
}

noinline fn parseLine(line: []const u8, info: *UpdateInfo) bool {
    const trimmed = mem.trim(u8, line, &ascii.whitespace);
    if (trimmed.len == 0) return false;

    var parts = mem.split(u8, trimmed, "->");
    const left_part = mem.trim(u8, parts.first(), &ascii.whitespace);
    const new_version = mem.trim(u8, parts.rest(), &ascii.whitespace);
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

pub fn main() !void {
    const updates_output = try checkupdates();
    defer if (updates_output.len > 0) allocator.free(updates_output);

    var updates = [_]UpdateInfo{mem.zeroes(UpdateInfo)} ** MAX_UPDATES;
    var updates_count: usize = 0;

    var lines = mem.split(u8, updates_output, "\n");
    while (lines.next()) |line| {
        if (updates_count >= MAX_UPDATES) break;
        if (line.len == 0) continue;

        if (parseLine(line, &updates[updates_count])) updates_count += 1;
    }

    sort.insertion(UpdateInfo, updates[0..updates_count], {}, compareUpdates);

    var updates_str = std.ArrayList(u8).init(allocator);
    defer updates_str.deinit();

    for (updates[0..updates_count], 0..) |update, i| {
        try updates_str.writer().print("{s:<25} {s} -> {s}\n", .{
            mem.sliceTo(&update.pkg_name, 0),
            mem.sliceTo(&update.local_version, 0),
            mem.sliceTo(&update.new_version, 0),
        });

        if (i == MAX_UPDATES - 1 and updates_count >= MAX_UPDATES) {
            try updates_str.writer().writeAll("...");
            break;
        }
    }

    if (updates_str.items.len > 0 and updates_str.items[updates_str.items.len - 1] == '\n') _ = updates_str.pop();

    var pkg_list_escaped = [_]u8{0} ** (BUFFER_SIZE * 10);
    escapeJson(updates_str.items, &pkg_list_escaped);

    var bw = io.bufferedWriter(io.getStdOut().writer());
    const writer = bw.writer();

    if (updates_count > 0) {
        try writer.print("{{\"text\":\"\",\"tooltip\":\"{d} updates available.\\n\\n{s}\"}}", .{
            updates_count,
            mem.sliceTo(&pkg_list_escaped, 0)
        });
    } else {
        try writer.print("{{\"text\":\"\",\"tooltip\":\"You're up to date!\"}}", .{});
    }

    try bw.flush();
}

const CheckUpdatesError = error{
    CannotCreateTempDb,
    CannotFetchUpdates,
    CommandFailed,
};

noinline fn checkupdates() ![]u8 {
    const tmp_base = std.posix.getenv("TMPDIR") orelse "/var/tmp";
    const uid = std.posix.getenv("EUID") orelse "1000";

    var db_path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var tmp_local_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    const db_path = try std.fmt.bufPrint(&db_path_buffer, "{s}/checkup-db-{s}", .{ tmp_base, uid });

    _ = fs.openDirAbsolute(db_path, .{}) catch |err| switch (err) {
        error.FileNotFound => try fs.makeDirAbsolute(db_path),
        else => |e| return e,
    };
    defer fs.deleteTreeAbsolute(db_path) catch {};

    const local_db = "/var/lib/pacman/local";
    const tmp_local = try std.fmt.bufPrint(&tmp_local_buffer, "{s}/local", .{db_path});

    fs.symLinkAbsolute(local_db, tmp_local, .{}) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const sync_result = try runCommand(&[_][]const u8{
        "fakeroot",
        "pacman",
        "-Sy",
        "--dbpath",
        db_path,
        "--logfile",
        "/dev/null",
    });

    if (sync_result != 0) {
        fs.deleteTreeAbsolute(db_path) catch {};
        return CheckUpdatesError.CannotFetchUpdates;
    }

    const updates = try getUpdates(db_path);
    if (updates.len == 0) {
        fs.deleteTreeAbsolute(db_path) catch {};
        return &[_]u8{};
    }

    return updates;
}

noinline fn getUpdates(db_path: []const u8) ![]u8 {
    var child = process.Child.init(&[_][]const u8{
        "pacman",
        "-Qu",
        "--dbpath",
        db_path,
    }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(stderr);

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0 or stderr.len > 0) allocator.free(stdout);

    var lines = std.ArrayList(u8).init(allocator);
    var iter = mem.split(u8, stdout, "\n");
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

inline fn runCommand(argv: []const []const u8) !u8 {
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
