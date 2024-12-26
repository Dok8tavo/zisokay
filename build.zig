const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root = b.path("src/root.zig");

    _ = b.addModule("zisokay", .{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });

    const object = b.addObject(.{
        .name = "zisokay",
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });

    const documentation = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "doc",
        .source_dir = object.getEmittedDocs(),
    });

    const build_tests = b.addTest(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(build_tests);
    if (b.args) |args|
        run_tests.addArgs(args);

    const doc_step = b.step("doc", "Generate documentation");
    const test_step = b.step("test", "Build & run tests");
    const zls_step = b.step("zls", "A step for zls to use");

    doc_step.dependOn(&documentation.step);
    test_step.dependOn(&run_tests.step);
    zls_step.dependOn(&object.step);

    b.getInstallStep().dependOn(&object.step);
}
