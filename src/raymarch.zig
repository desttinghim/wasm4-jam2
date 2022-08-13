//! Raymarched SDF rendering
//! Referencess:
//! - https://9bitscience.blogspot.com/2013/07/raymarching-distance-fields_14.html
//! - https://iquilezles.org/articles/distfunctions/
const geom = @import("geom.zig");
const std = @import("std");

pub const MarchOpt = struct {
    maxSteps: usize = 20,
    epsilon: f32 = 0.1,
    maxDistance: f32 = 100,
};

pub const MarchInfo = struct {
    iterations: usize,
    distance: f32,
    point: ?geom.Vec3f,
};

/// Given a SDF scene, marches from rayOrigin in rayDirection until it the max number of iterations is hit,
/// the max distance is hit, or a point was hit.
pub fn raymarch(scene: fn (geom.Vec3f) f32, rayOrigin: geom.Vec3f, rayDirection: geom.Vec3f, opt: MarchOpt) MarchInfo {
    var t: f32 = 0;
    var i: usize = 0;
    while (i < opt.maxSteps) : (i += 1) {
        const p = rayOrigin + rayDirection * @splat(3, t);
        const d = scene(p);
        if (d < opt.epsilon) return .{
            .iterations = i,
            .distance = t,
            .point = p,
        };
        t += d;
        if (t > opt.maxDistance) break;
    }
    return .{
        .iterations = i,
        .distance = t,
        .point = null,
    };
}

pub fn getNormal(scene: fn (geom.Vec3f) f32, point: geom.Vec3f, opt: struct {h: f32 = 0.01}) geom.Vec3f {
    const h = @splat(3, opt.h);
    return geom.vec3.normalizef(.{
        scene(point + geom.vec3.rightf * h) - scene(point - geom.vec3.rightf * h),
        scene(point + geom.vec3.upf * h) - scene(point - geom.vec3.upf * h),
        scene(point + geom.vec3.forwardf * h) - scene(point - geom.vec3.forwardf * h),
    });
}

// pub fn shade(scene: fn(geom.Vec3f) f32, p: geom.Vec3) f32 {
//     const normal = geom.vec3.normalize
// }

pub fn sphere(p: geom.Vec3f, radius: f32) f32 {
    return geom.vec3.lengthf(p) - radius;
}
