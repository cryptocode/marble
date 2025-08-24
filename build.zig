const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const marble_mod = b.addModule("marble", .{
        .root_source_file = b.path("src/main.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "marble",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .name = "example_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("marble", marble_mod);

    const example_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&example_tests.step);
}
