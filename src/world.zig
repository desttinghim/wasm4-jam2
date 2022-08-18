const std = @import("std");
const draw = @import("draw.zig");
const geom = @import("geom.zig");
const Anim = @import("Anim.zig");

pub const assets = @import("assets");
pub const bitmap = draw.Bitmap{
    .data = &assets.tilemap_packed,
    .width = assets.tilemap_packed_width,
    .height = assets.tilemap_packed_height,
};
pub const tile_size = geom.Vec2{ 16, 16 };
pub const tilemap_size = @divFloor(geom.Vec2{ bitmap.width, bitmap.height }, tile_size);
pub const room_grid_size = geom.Vec2{ 10, 10 };

/// Blits the given tile to the screen. w4.DRAW_COLORS must be set before calling function
pub fn blit(pos: geom.Vec2, tile: isize) void {
    const x = @mod(tile, tilemap_size[0]) * tile_size[0];
    const y = @divTrunc(tile, tilemap_size[0]) * tile_size[1];
    const rect = geom.AABB{ x, y, tile_size[0], tile_size[1] };
    bitmap.blit_sub(pos, rect, .{ .bpp = .b2 });
}

pub const grass = 0;
pub const pot = 135;

pub const player_style = 0x4300;
pub const player_bmp = draw.Bitmap{ .data = &assets.mc, .width = assets.mc_width, .height = assets.mc_height };
pub const player_punch_bmp = draw.Bitmap{ .data = &assets.mc_punch, .width = assets.mc_punch_width, .height = assets.mc_punch_height };
pub const player_anim_stand_down = [_]Anim.Ops{ .{ .Index = 0 }, .Stop };
pub const player_anim_walk_down = [_]Anim.Ops{
    .{ .Index = 1 }, .{ .Wait = 8 },
    .{ .Index = 2 }, .{ .Wait = 8 },
    .{ .Index = 3 }, .{ .Wait = 8 },
    .FlipX,
};
pub const player_anim_stand_up = [_]Anim.Ops{ .{ .Index = 4 }, .Stop };
pub const player_anim_walk_up = [_]Anim.Ops{
    .{ .Index = 5 }, .{ .Wait = 8 },
    .{ .Index = 6 }, .{ .Wait = 8 },
    .{ .Index = 7 }, .{ .Wait = 8 },
    .FlipX,
};
pub const player_anim_stand_side = [_]Anim.Ops{ .{ .Index = 8 }, .Stop };
pub const player_anim_walk_side = [_]Anim.Ops{
    .{ .Index = 9 },  .{ .Wait = 8 },
    .{ .Index = 10 }, .{ .Wait = 8 },
    .{ .Index = 11 }, .{ .Wait = 8 },
    .{ .Index = 12 }, .{ .Wait = 8 },
    .{ .Index = 13 }, .{ .Wait = 8 },
    .{ .Index = 14 }, .{ .Wait = 8 },
};
pub const player_anim_punch_down = [_]Anim.Ops{
    .NoInterrupt,
    .{ .SetFlipX = false },
    .{ .Index = 0 },
    .{ .Wait = 5 },
    .{ .Index = 1 },
    .{ .Wait = 5 },
    .AllowInterrupt,
    .{ .Index = 2 },
    .{ .Wait = 5 },
    .Stop,
};
pub const player_anim_punch_down2 = [_]Anim.Ops{
    .NoInterrupt,
    .{ .SetFlipX = true },
    .{ .Index = 0 },
    .{ .Wait = 5 },
    .{ .Index = 1 },
    .{ .Wait = 5 },
    .AllowInterrupt,
    .{ .Index = 2 },
    .{ .Wait = 5 },
    .Stop,
};
pub const player_anim_punch_up = [_]Anim.Ops{
    .NoInterrupt,
    .{ .SetFlipX = false },
    .{ .Index = 3 },
    .{ .Wait = 5 },
    .{ .Index = 4 },
    .{ .Wait = 5 },
    .AllowInterrupt,
    .{ .Index = 5 },
    .{ .Wait = 5 },
    .Stop,
};
pub const player_anim_punch_up2 = [_]Anim.Ops{
    .NoInterrupt,
    .{ .SetFlipX = true },
    .{ .Index = 3 },
    .{ .Wait = 5 },
    .{ .Index = 4 },
    .{ .Wait = 5 },
    .AllowInterrupt,
    .{ .Index = 5 },
    .{ .Wait = 5 },
    .Stop,
};
pub const player_anim_punch_side = [_]Anim.Ops{
    .NoInterrupt,
    .{ .Index = 6 },
    .{ .Wait = 5 },
    .{ .Index = 7 },
    .{ .Wait = 5 },
    .AllowInterrupt,
    .{ .Index = 8 },
    .{ .Wait = 5 },
    .Stop,
};
pub const player_anim_punch_side2 = [_]Anim.Ops{
    .NoInterrupt,
    .{ .Index = 9 },
    .{ .Wait = 5 },
    .{ .Index = 10 },
    .{ .Wait = 5 },
    .AllowInterrupt,
    .{ .Index = 11 },
    .{ .Wait = 5 },
    .Stop,
};

pub const EntityKind = enum {
    Player,
    Pot,
};

pub const Entity = struct {
    /// Location measured in tiles
    vec: [2]i16,
    kind: EntityKind,

    pub fn init(kind: EntityKind, x: i64, y: i64) Entity {
        return .{
            .kind = kind,
            .vec = .{ @intCast(i16, x), @intCast(i16, y) },
        };
    }

    pub fn toPos(entity: Entity) geom.Vec2f {
        return geom.vec2.itof(entity.toVec2());
    }

    pub fn toVec2(entity: Entity) geom.Vec2 {
        return geom.Vec2{ entity.vec[0], entity.vec[1] } * tile_size;
    }

    /// Convert vec directly to geom.Vec2 for doing math
    pub fn toVec(entity: Entity) geom.Vec2 {
        return geom.Vec2{ entity.vec[0], entity.vec[1] };
    }

    pub fn addRoomPos(entity: Entity, room: Room) Entity {
        const vec = entity.toVec() + room.toVec2();
        return .{ .vec = .{ @intCast(i16, vec[0]), @intCast(i16, vec[1]) }, .kind = entity.kind };
    }

    pub fn subRoomPos(entity: Entity, room: Room) Entity {
        const vec = entity.toVec() - room.toVec2();
        return .{ .vec = .{ @intCast(i16, vec[0]), @intCast(i16, vec[1]) }, .kind = entity.kind };
    }

    pub fn write(entity: Entity, writer: anytype) !void {
        try writer.writeInt(u8, @enumToInt(entity.kind), .Little);
        try writer.writeInt(i16, entity.vec[0], .Little);
        try writer.writeInt(i16, entity.vec[1], .Little);
    }

    pub fn read(reader: anytype) !Entity {
        return Entity{
            .kind = @intToEnum(EntityKind, try reader.readInt(u8, .Little)),
            .vec = .{
                try reader.readInt(i16, .Little),
                try reader.readInt(i16, .Little),
            },
        };
    }
};

pub const Room = struct {
    /// Location measured in rooms
    coord: [2]i8,
    size: [2]u8,
    tiles: []const u8,
    num: usize = 0,

    pub fn toArr(room: Room) geom.Vec2 {
        return .{ room.coord[0], room.coord[1] };
    }

    pub fn toVec2(room: Room) geom.Vec2 {
        return geom.Vec2{ room.coord[0], room.coord[1] } * room_grid_size;
    }

    pub fn toAABB(room: Room) geom.AABB {
        const pos = room.toVec2();
        return .{ pos[0], pos[1], room.size[0], room.size[1] };
    }

    pub fn toID(room: Room) u16 {
        return @intCast(u16, @bitCast(u8, room.coord[0])) | @intCast(u16, @bitCast(u8, room.coord[1])) << 8;
    }

    pub fn coordFromID(id: u16) [2]i8 {
        const x = @bitCast(i8, @intCast(u8, 0x00_FF & id));
        const y = @bitCast(i8, @intCast(u8, 0xFF_00 & id >> 8));
        return .{x, y};
    }

    pub fn compare(ctx: void, a:  Room, b:  Room) bool {
        _ = ctx;
        return a.toID() > b.toID();
    }

    pub fn contains(room: Room, coord: geom.Vec2) bool {
        const rect = geom.aabb.as_rect(geom.aabb.initv(geom.Vec2{ room.coord[0], room.coord[1] } * room_grid_size, geom.Vec2{ room.size[0], room.size[1] }));
        return (geom.rect.contains(rect, coord));
    }

    pub fn write(room: Room, writer: anytype) !void {
        try writer.writeInt(i8, room.coord[0], .Little);
        try writer.writeInt(i8, room.coord[1], .Little);
        try writer.writeInt(u8, room.size[0], .Little);
        try writer.writeInt(u8, room.size[1], .Little);
        for (room.tiles) |tile| {
            try writer.writeByte(tile);
        }
    }

    pub fn readHeader(reader: anytype) !Room {
        const x = try reader.readInt(i8, .Little);
        const y = try reader.readInt(i8, .Little);
        const size_x = try reader.readInt(u8, .Little);
        const size_y = try reader.readInt(u8, .Little);
        return Room{
            .coord = .{ x, y },
            .size = .{ size_x, size_y },
            .tiles = &[0]u8{},
        };
    }

    pub fn findAndRead(alloc: std.mem.Allocator, reader: anytype, coord2Find: geom.Vec2) !Room {
        var count: usize = 0;
        while (count < 255) : (count += 1) {
            // If we don't find the room, we crash
            var room = readHeader(reader);
            if (room.contains(coord2Find)) {
                const tile_slice = try alloc.alloc(u8, @intCast(usize, room.size[0]) * @intCast(usize, room.size[1]));
                for (tile_slice) |*tile| {
                    tile.* = try reader.readByte();
                }
                room.tiles = tile_slice;
                return room;
            } else {
                var i: usize = 0;
                while (i < @intCast(usize, room.size[0]) * @intCast(usize, room.size[1])) : (i += 1) {
                    _ = try reader.readByte();
                }
            }
        }
        return error.NoSuchRoom;
    }

    pub fn read(alloc: std.mem.Allocator, reader: anytype) !Room {
        var room = readHeader(reader);
        const tile_slice = try alloc.alloc(u8, @intCast(usize, room.size[0]) * @intCast(usize, room.size[1]));
        for (tile_slice) |*tile| {
            tile.* = try reader.readByte();
        }
        room.tiles = tile_slice;
        return room;
    }
};
