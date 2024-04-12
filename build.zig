const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "openssl",
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
}
