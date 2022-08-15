const std = @import("std");

const pkgs = struct {
    const zmath = std.build.Pkg{
        .name = "zmath",
        .source = .{ .path = "deps/zmath/src/zmath.zig" },
    };
    const assets = std.build.Pkg{
        .name = "assets",
        .source = .{ .path = "assets/tiles.zig" },
    };
};

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary("cart", "src/main.zig", .unversioned);

    // lib.addPackage(pkgs.zmath);
    lib.addPackage(pkgs.assets);

    lib.setBuildMode(mode);
    lib.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    lib.import_memory = true;
    lib.initial_memory = 65536;
    lib.max_memory = 65536;
    lib.stack_size = 14752;

    // Export WASM-4 symbols
    lib.export_symbol_names = &[_][]const u8{ "start", "update" };

    lib.install();

    const prefix = b.getInstallPath(.lib, "");
    const opt = b.addSystemCommand(&[_][]const u8{
        "wasm-opt",
        "-Oz",
        "--strip-debug",
        "--strip-producers",
        "--zero-filled-memory",
    });

    opt.addArtifactArg(lib);
    const optout = try std.fs.path.join(b.allocator, &.{ prefix, "opt.wasm" });
    defer b.allocator.free(optout);
    opt.addArgs(&.{ "--output", optout });

    const opt_step = b.step("opt", "Run wasm-opt on cart.wasm, producing opt.wasm");
    opt_step.dependOn(&lib.step);
    opt_step.dependOn(&opt.step);
}
