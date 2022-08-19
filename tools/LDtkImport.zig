//! Uses zig-ldtk to convert a ldtk file into a binary format for wired
const std = @import("std");
const LDtk = @import("../deps/zig-ldtk/src/LDtk.zig");
const world = @import("../src/world.zig");
const geom = @import("../src/geom.zig");

const KB = 1024;
const MB = 1024 * KB;

const LDtkImport = @This();

step: std.build.Step,
builder: *std.build.Builder,
source_path: std.build.FileSource,
output_name: []const u8,
world_data: std.build.GeneratedFile,

pub fn create(b: *std.build.Builder, opt: struct {
    source_path: std.build.FileSource,
    output_name: []const u8,
}) *@This() {
    var result = b.allocator.create(LDtkImport) catch @panic("memory");
    result.* = LDtkImport{
        .step = std.build.Step.init(.custom, "convert and embed a ldtk map file", b.allocator, make),
        .builder = b,
        .source_path = opt.source_path,
        .output_name = opt.output_name,
        .world_data = undefined,
    };
    result.*.world_data = std.build.GeneratedFile{ .step = &result.*.step };
    return result;
}

fn make(step: *std.build.Step) !void {
    const this = @fieldParentPtr(LDtkImport, "step", step);

    const allocator = this.builder.allocator;
    const cwd = std.fs.cwd();

    // Get path to source and output
    const source_src = this.source_path.getPath(this.builder);
    const output = this.builder.getInstallPath(.lib, this.output_name);

    // Open ldtk file and read all of it into `source`
    const source_file = try cwd.openFile(source_src, .{});
    defer source_file.close();
    const source = try source_file.readToEndAlloc(allocator, 10 * MB);
    defer allocator.free(source);

    var ldtk_parser = try LDtk.parse(allocator, source);
    defer ldtk_parser.deinit();

    const ldtk = ldtk_parser.root;

    // Store levels
    var rooms = std.ArrayList(world.Room).init(allocator);
    defer rooms.deinit();

    var entities = std.ArrayList(world.Entity).init(allocator);
    defer entities.deinit();

    for (ldtk.levels) |level| {
        std.log.warn("Level: {}", .{rooms.items.len});
        const parsed_level = try parseLevel(.{
            .allocator = allocator,
            .ldtk = ldtk,
            .level = level,
            .entities = &entities,
        });

        try rooms.append(parsed_level);
    }
    defer for (rooms.items) |level| {
        allocator.free(level.tiles);
    };

    // Create array to write data to
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    const writer = data.writer();

    var player_count: usize = 0;
    try writer.writeInt(u16, @intCast(u16, entities.items.len), .Little);
    for (entities.items) |entity| {
        if (entity.kind == .Player) player_count += 1;
        try entity.write(writer);
    }

    if (player_count > 1) std.log.warn("Too many players!", .{});

    try writer.writeInt(u8, @intCast(u8, rooms.items.len), .Little);
    for (rooms.items) |room, i| {
        try room.write(writer);
        std.log.warn("Room {}: ({},{}) [{},{}]", .{i, room.coord[0], room.coord[1], room.size[0], room.size[1]});
    }

    // Open output file and write data into it
    cwd.makePath(this.builder.getInstallPath(.lib, "")) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    try cwd.writeFile(output, data.items);

    this.world_data.path = output;
}

/// Returns parsed level. User owns level.tiles
fn parseLevel(opt: struct {
    allocator: std.mem.Allocator,
    ldtk: LDtk.Root,
    level: LDtk.Level,
    entities: *std.ArrayList(world.Entity),
}) !world.Room {
    const ldtk = opt.ldtk;
    const level = opt.level;
    const entities = opt.entities;
    const allocator = opt.allocator;

    const layers = level.layerInstances orelse return error.NoLayers;

    const world_x: i8 = @intCast(i8, @divFloor(level.worldX, (ldtk.worldGridWidth orelse 160)));
    const world_y: i8 = @intCast(i8, @divFloor(level.worldY, (ldtk.worldGridHeight orelse 160)));

    const size_x_usize = @intCast(usize, @divFloor(level.pxWid, (world.tile_size[0])));
    const size_y_usize = @intCast(usize, @divFloor(level.pxHei, (world.tile_size[1])));

    const size_x: u8 = @intCast(u8, size_x_usize);
    const size_y: u8 = @intCast(u8, size_y_usize);

    var tiles = try allocator.alloc(u8, size_x_usize * size_y_usize);
    const room = world.Room{
        .coord = .{ world_x, world_y },
        .size = .{ size_x, size_y },
        .tiles = tiles,
    };

    var cliff_layer: ?LDtk.LayerInstance = null;
    var environment_layer: ?LDtk.LayerInstance = null;

    for (layers) |layer| {
        if (std.mem.eql(u8, layer.__identifier, "Entities")) {
            // Entities
            std.debug.assert(layer.__type == .Entities);

            for (layer.entityInstances) |entity| {
                var kind_opt: ?world.EntityKind = null;
                if (std.mem.eql(u8, entity.__identifier, "Player")) {
                    kind_opt = .Player;
                } else if (std.mem.eql(u8, entity.__identifier, "Pot")) {
                    kind_opt = .Pot;
                } else if (std.mem.eql(u8, entity.__identifier, "Skeleton")) {
                    kind_opt = .Skeleton;
                }

                if (kind_opt) |kind| {
                    const world_entity = world.Entity.init(kind, entity.__grid[0], entity.__grid[1]);
                    try entities.append(world_entity.addRoomPos(room));
                }
            }

            std.log.warn("Entities: {}", .{entities.items.len});
        } else if (std.mem.eql(u8, layer.__identifier, "Cliffs")) {
            // cliff
            std.debug.assert(layer.__type == .IntGrid);

            cliff_layer = layer;
        } else if (std.mem.eql(u8, layer.__identifier, "Environment")) {
            // environment
            std.debug.assert(layer.__type == .IntGrid);

            environment_layer = layer;
        } else {
            // Unknown
            std.log.warn("{s}: {}", .{ layer.__identifier, layer.__type });
        }
    }

    if (cliff_layer == null) return error.MissingCliffLayer;
    if (environment_layer == null) return error.MissingEnvironmentLayer;

    const cliff = cliff_layer.?;
    const environment = environment_layer.?;

    std.debug.assert(cliff.__cWid == environment.__cWid);
    std.debug.assert(cliff.__cHei == environment.__cHei);

    const width = @intCast(u16, cliff.__cWid);
    std.debug.assert(width == room.size[0]);

    for (tiles) |_, i| {
        tiles[i] = 0;
    }

    // Add unchanged tile data
    for (environment.autoLayerTiles) |autotile| {
        const x = @divExact(autotile.px[0], environment.__gridSize);
        const y = @divExact(autotile.px[1], environment.__gridSize);
        const i = @intCast(usize, x + y * width);
        const t = @intCast(u8, autotile.t);
        tiles[i] = t;
    }

    // Add cliff tiles
    for (cliff.autoLayerTiles) |autotile| {
        const x = @divExact(autotile.px[0], cliff.__gridSize);
        const y = @divExact(autotile.px[1], cliff.__gridSize);
        const i = @intCast(usize, x + y * width);
        const t = @intCast(u8, autotile.t);
        tiles[i] = t;
    }

    return room;
}
