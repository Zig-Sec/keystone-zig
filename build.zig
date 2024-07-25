const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.Build);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const upstream = b.dependency("keystone", .{});
    const build_path = upstream.path("build");
    const module_path = try build_path.getPath3(upstream.builder, null).joinString(alloc, "");
    log.info("Keystone location: {s}", .{module_path});

    std.fs.makeDirAbsolute(module_path) catch |err| {
        log.warn("make dir failed: {}", .{err});
    };

    const translate = b.addTranslateC(.{
        .root_source_file = upstream.path("include/keystone/keystone.h"),
        .target = target,
        .optimize = optimize,
    });
    translate.addIncludeDir(try upstream.path("include").getPath3(upstream.builder, &translate.step).joinString(alloc, ""));

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

    translate.step.dependOn(&cmake_step.step);
    b.getInstallStep().dependOn(&cmake_step.step);

    const mod = b.addModule("keystone-c", .{
        .root_source_file = translate.getOutput(),
        .link_libc = true,
        .link_libcpp = true,
        .target = target,
        .optimize = optimize,
    });

    mod.addIncludePath(upstream.path("include/keystone"));
    mod.addLibraryPath(build_path.path(upstream.builder, "llvm/lib64"));

    // TODO: Eventually make the link mode configurable.
    mod.linkSystemLibrary("keystone", .{
        .needed = true,
        .preferred_link_mode = .static,
    });
}
