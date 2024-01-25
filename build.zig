const std = @import("std");

pub fn linkPCRE(
    exe_compile: *std.Build.Step.Compile,
    jstring_dep: *std.Build.Dependency,
) void {
    exe_compile.addCSourceFile(.{
        .file = .{
            .path = jstring_dep.builder.pathFromRoot(
                jstring_dep.module("pcre_binding.c").source_file.path,
            ),
        },
        .flags = &.{"-std=c17"},
    });
    exe_compile.linkSystemLibrary2(
        "libpcre2-8",
        .{ .use_pkg_config = .yes },
    );
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule(
        "jstring",
        .{
            .source_file = .{ .path = "src/jstring.zig" },
        },
    );

    _ = b.addModule(
        "pcre_binding.c",
        .{
            .source_file = .{
                .path = b.pathFromRoot("src/pcre/pcre_binding.c"),
            },
        },
    );

    const obj_pcre_binding = b.addObject(.{
        .name = "pcre_binding",
        .target = target,
        .optimize = optimize,
    });
    obj_pcre_binding.addCSourceFile(
        .{
            .file = .{ .path = "src/pcre/pcre_binding.c" },
            .flags = &.{"-std=c17"},
        },
    );
    obj_pcre_binding.linkSystemLibrary2(
        "libpcre2-8",
        .{ .use_pkg_config = .yes },
    );

    const jstring_lib = b.addStaticLibrary(.{
        .name = "jstring",
        .root_source_file = .{ .path = "src/jstring.zig" },
        .target = target,
        .optimize = optimize,
    });

    jstring_lib.addObject(obj_pcre_binding);
    jstring_lib.linkSystemLibrary2("libpcre2-8", .{ .use_pkg_config = .yes });

    b.installArtifact(jstring_lib);
}
