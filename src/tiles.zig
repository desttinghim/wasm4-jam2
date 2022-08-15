const draw = @import("draw.zig");
const geom = @import("geom.zig");

pub const assets = @import("assets");
pub const bitmap = draw.Bitmap{
    .data = &assets.tilemap_packed,
    .width = assets.tilemap_packed_width,
    .height = assets.tilemap_packed_height,
};
pub const tile_size = geom.Vec2{ 16, 16 };
pub const tilemap_size = @divFloor(geom.Vec2{ bitmap.width, bitmap.height }, tile_size);

/// Blits the given tile to the screen. w4.DRAW_COLORS must be set before calling function
pub fn blit(pos: geom.Vec2, tile: isize) void {
    const x = @mod(tile, tilemap_size[0]) * tile_size[0];
    const y = @divTrunc(tile, tilemap_size[0]) * tile_size[1];
    const rect = geom.AABB{ x, y, tile_size[0], tile_size[1] };
    bitmap.blit_sub(pos, rect, .{ .bpp = .b2 });
}

pub const grass = 0;
