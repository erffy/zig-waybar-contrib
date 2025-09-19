const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get $HOME from environment
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    // Construct full path: $HOME/.config/zwc/config.json
    const config_path = try std.fs.path.join(allocator, &.{ home_dir, ".config", "zwc", "config.json" });
    defer allocator.free(config_path);

    // Try opening file
    var file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();

    // Read all file contents
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    _ = try file.readAll(buffer);

    // Parse JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Example access
    if (root.object.get("username")) |username_val| {
        std.debug.print("Username: {s}\n", .{username_val.string});
    } else {
        std.debug.print("username not set in config\n", .{});
    }
}
