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
const fs = std.fs;
const Build = std.Build;

const Executable = struct {
    name: []const u8,
    source: []const u8,
    link_rocm: bool = false,
    link_amdsmi: bool = false,
    run_args: ?[]const []const u8 = null,
};

const static_executables = [_]Executable{
    .{ .name = "memory", .source = "src/memory.zig" },
    .{ .name = "ping", .source = "src/ping.zig" },
    .{ .name = "updates", .source = "src/updates.zig" },
};

fn fileExists(path: []const u8) bool {
    const file = fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();
    return true;
}

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const have_amdsmi = fileExists("/opt/rocm/lib/libamd_smi.so");
    const have_rocm = fileExists("/opt/rocm/lib/librocm_smi64.so");

    inline for (static_executables) |exe| {
        buildExecutable(b, exe, target, optimize);
    }

    if (have_amdsmi) {
        buildExecutable(b, .{
            .name = "gpu",
            .source = "src/gpu/amdsmi.zig",
            .link_amdsmi = true,
        }, target, optimize);
    } else if (have_rocm) {
        buildExecutable(b, .{
            .name = "gpu",
            .source = "src/gpu/rocmsmi.zig",
            .link_rocm = true,
        }, target, optimize);
    }
}

fn buildExecutable(b: *Build, exe: Executable, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const mod = b.createModule(.{
        .root_source_file = b.path(exe.source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const obj = b.addExecutable(.{
        .name = exe.name,
        .root_module = mod,
        .use_llvm = true,
        .use_lld = true,
    });

    const utils_mod = b.createModule(.{
        .root_source_file = b.path("src/utils/mod.zig"),
    });

    mod.addImport("utils", utils_mod);

    obj.want_lto = true;

    if (exe.link_amdsmi or exe.link_rocm) {
        obj.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "/opt/rocm/include" } });
        obj.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "/opt/rocm/lib" } });
    }

    if (exe.link_amdsmi) obj.linkSystemLibrary("amd_smi");
    if (exe.link_rocm) obj.linkSystemLibrary("rocm_smi64");

    const install = b.addInstallArtifact(obj, .{});
    b.getInstallStep().dependOn(&install.step);

    const run = b.addRunArtifact(obj);
    if (b.args) |args| run.addArgs(args);
    if (exe.run_args) |args| run.addArgs(args);

    const run_step = b.step(b.fmt("run-{s}", .{exe.name}), b.fmt("Run the {s} executable", .{exe.name}));
    run_step.dependOn(&run.step);
}
