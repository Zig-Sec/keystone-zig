const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.Build);

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("keystone", .{});
    const build_path = upstream.path("build");
    const module_path = try build_path.getPath3(upstream.builder, null).joinString(alloc, "");
    log.info("Keystone location: {s}", .{module_path});

    std.fs.makeDirAbsolute(module_path) catch |err| {
        log.warn("make dir failed: {}", .{err});
    };

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("zig-out/include/keystone/keystone.h"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "keystone",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cmake_step = b.addSystemCommand(&.{
        if (builtin.os.tag == .linux)
            "../make-lib.sh"
        else if (builtin.os.tag == .windows)
            "..\\nmake-lib.bat"
        else
            @compileError("Base system not supported."),
        "lib_only",
    });
    cmake_step.setCwd(upstream.path("build"));
    lib.step.dependOn(&cmake_step.step);

    lib.installHeadersDirectory(upstream.path("include/keystone"), "keystone", .{});

    const lib_copy = b.addObjCopy(build_path.path(upstream.builder, "llvm/lib64/"), .{ .basename = "keystone" });
    lib_copy.step.dependOn(&cmake_step.step);
    translate.step.dependOn(&lib_copy.step);

    _ = b.addModule("keystone-c", .{
        .root_source_file = translate.getOutput(),
        .link_libc = true,
        .link_libcpp = true,
    });

    b.installArtifact(lib);
}
