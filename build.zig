const std = @import("std");
const Build = std.Build;

const Executable = struct {
    name: []const u8,
    source: []const u8,
    run_args: ?[]const []const u8 = null,
};

const executables = [_]Executable{
    .{ .name = "memory", .source = "src/memory.zig" },
    .{ .name = "gpu", .source = "src/gpu.zig" },
    .{ .name = "ping", .source = "src/ping.zig" },
    .{ .name = "updates", .source = "src/updates.zig" },
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    for (executables) |exe| {
        const exe_obj = b.addExecutable(.{
            .name = exe.name,
            .root_source_file = b.path(exe.source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .use_llvm = true
        });

        exe_obj.want_lto = true;

        const install_exe = b.addInstallArtifact(exe_obj, .{});
        b.getInstallStep().dependOn(&install_exe.step);

        const run_cmd = b.addRunArtifact(exe_obj);
        if (b.args) |args| run_cmd.addArgs(args);
        if (exe.run_args) |args| run_cmd.addArgs(args);

        const run_step = b.step(b.fmt("run-{s}", .{exe.name}), b.fmt("Run the {s} executable", .{exe.name}));
        run_step.dependOn(&run_cmd.step);
    }
}
