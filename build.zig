const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("pymodule", "src/example_mod.zig", .unversioned);
    lib.setTarget(target);
    lib.linkSystemLibrary("c");
    // TODO: Build for multiple versions of Python
    lib.addIncludeDir("/usr/include/python3.9");
    lib.addSystemIncludeDir("/usr/include");
    lib.setBuildMode(mode);
    // TODO: Create properly-named shared library
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
