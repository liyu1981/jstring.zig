const std = @import("std");
const jstring_build = @import("jstring");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const jstring_dep = b.dependency("jstring", .{});

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("jstring", jstring_dep.module("jstring"));

    jstring_build.linkPCRE(exe, jstring_dep);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
