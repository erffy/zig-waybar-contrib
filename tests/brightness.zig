const std = @import("std");

// Import the C API from libddcutil
const c = @cImport({
    @cInclude("ddcutil_c_api.h");
});

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var display_idx: i32 = 0;
    const step: i64 = 10;
    var change: ?i64 = null;
    var set_val: ?i64 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--up")) {
            change = step;
        } else if (std.mem.eql(u8, a, "--down")) {
            change = -step;
        } else if (std.mem.eql(u8, a, "--set")) {
            if (i + 1 >= args.len) {
                try stdout.print("Error: --set requires a value\n", .{});
                return;
            }
            set_val = try std.fmt.parseInt(i64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, a, "--display")) {
            if (i + 1 >= args.len) {
                try stdout.print("Error: --display requires a value\n", .{});
                return;
            }
            display_idx = try std.fmt.parseInt(i32, args[i + 1], 10);
            i += 1;
        }
    }

    var disp_handle: c.DDCA_Display_Handle = null;
    const display_idx_ptr = @as(?*anyopaque, &display_idx);

    const status_open = c.ddca_open_display2(display_idx_ptr, true, &disp_handle);
    if (status_open != 0) {
        try stdout.print("Error opening display {d}: status {d}\n", .{display_idx, status_open});
        return;
    }
    _ = c.ddca_close_display(disp_handle);

    // Use c.DDCA_Table_Vcp_Value, not your own struct
    var vcp_value: [*c]c.DDCA_Table_Vcp_Value = undefined;

    const status_get = c.ddca_get_table_vcp_value(disp_handle, 0x10, &vcp_value);
    if (status_get != 0) {
        try stdout.print("Error reading brightness: status {d}\n", .{status_get});
        return;
    }

    const current = @as(i64, vcp_value.*.bytect);
    const maximum = @as(i64, vcp_value.*.bytes.*);

    const new_val: i64 = if (set_val) |val| val else if (change) |ch| current + ch else current;

    var nv = new_val;
    if (nv < 0) nv = 0;
    if (nv > maximum) nv = maximum;

    const status_set = c.ddca_set_table_vcp_value(disp_handle, 0x10, vcp_value);
    if (status_set != 0) {
        try stdout.print("Error setting brightness: status {d}\n", .{status_set});
        return;
    }

    try stdout.print("Display {d}: brightness {d}/{d}\n", .{display_idx, nv, maximum});
}
