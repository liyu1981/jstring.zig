const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const jstring_module = b.createModule(.{
        .root_source_file = .{ .path = "../../src/jstring.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "translate_c_extract",
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("jstring", jstring_module);
    exe.addObjectFile(.{ .path = "../../zig-out/lib/libpcre_binding.a" });
    exe.linkSystemLibrary2("libpcre2-8", .{ .use_pkg_config = .yes });
    exe.linkLibC();

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
