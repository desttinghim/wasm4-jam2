const std = @import("std");
const LDtkImport = @import("tools/LDtkImport.zig");
const WAEL = @import("tools/WAEL.zig");

const pkgs = struct {
    const zmath = std.build.Pkg{
        .name = "zmath",
        .source = .{ .path = "deps/zmath/src/zmath.zig" },
    };
    const assets = std.build.Pkg{
        .name = "assets",
        .source = .{ .path = "assets/assets.zig" },
    };
};

pub fn build(b: *std.build.Builder) !void {
    // Build assets
    const ldtk = LDtkImport.create(b, .{
        .source_path = .{ .path = "assets/map.ldtk" },
        .output_name = "mapldtk",
    });
    const music = WAEL.create(b, .{
        .source_path = .{ .path = "assets/music.wael" },
        .output_name = "music",
    });
    const data_step = b.addOptions();
    data_step.addOptionFileSource("path", .{.generated = &ldtk.world_data });
    data_step.addOptionFileSource("music", .{.generated = &music.music_data });

    // Build cart
    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary("cart", "src/main.zig", .unversioned);

    // Add dependencies
    lib.step.dependOn(&data_step.step);
    lib.addPackage(data_step.getPackage("world_data"));
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
