const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize, .shared = true });
    exe_mod.addImport("raylib", raylib_dep.module("raylib"));
    exe_mod.addImport("raygui", raylib_dep.module("raygui"));
    exe_mod.linkLibrary(raylib_dep.artifact("raylib"));
    const ecs_dependency = b.dependency("ecs", .{ .target = target, .optimize = optimize });
    exe_mod.addImport("ecs", ecs_dependency.module("zig-ecs"));

    const exe = b.addExecutable(.{
        .name = "brackeys-2025",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
