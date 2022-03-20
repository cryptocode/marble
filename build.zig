const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("marble", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const example_tests = b.addTest("src/example_tests.zig");
    example_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&example_tests.step);
}
