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
const Build = std.Build;

const Executable = struct {
    name: []const u8,
    source: []const u8,
    link_rocm: bool = false,
    run_args: ?[]const []const u8 = null,
};

const executables = [_]Executable{
    .{ .name = "memory", .source = "src/memory.zig" },
    .{ .name = "ping", .source = "src/ping.zig" },
    .{ .name = "updates", .source = "src/updates.zig" },
    .{ .name = "network", .source = "src/network.zig" },
    .{ .name = "gpu", .source = "src/gpu-smi.zig", .link_rocm = true },
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
            .use_llvm = true
        });

        exe_obj.want_lto = true;

        if (exe.link_rocm) {
            exe_obj.use_lld = true;
            exe_obj.linkLibC();
            exe_obj.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "/opt/rocm/include" } });
            exe_obj.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "/opt/rocm/lib" } });
            exe_obj.linkSystemLibrary("rocm_smi64");
        }

        const install_step = b.addInstallArtifact(exe_obj, .{});
        b.getInstallStep().dependOn(&install_step.step);

        const run_cmd = b.addRunArtifact(exe_obj);
        if (b.args) |args| run_cmd.addArgs(args);
        if (exe.run_args) |args| run_cmd.addArgs(args);

        const run_step = b.step(
            b.fmt("run-{s}", .{exe.name}),
            b.fmt("Run the {s} executable", .{exe.name}),
        );
        run_step.dependOn(&run_cmd.step);
    }
}