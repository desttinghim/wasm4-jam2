//! Raymarched SDF rendering
//! Referencess:
//! - https://9bitscience.blogspot.com/2013/07/raymarching-distance-fields_14.html
//! - https://iquilezles.org/articles/distfunctions/
const std = @import("std");
const zm = @import("zmath");

pub const MarchOpt = struct {
    maxSteps: usize = 20,
    epsilon: f32 = 0.1,
    maxDistance: f32 = 100,
};

pub const MarchInfo = struct {
    iterations: usize,
    distance: f32,
    point: ?zm.Vec,
};

/// Given a SDF scene, marches from rayOrigin in rayDirection until it the max number of iterations is hit,
/// the max distance is hit, or a point was hit.
pub fn raymarch(scene: fn (zm.Vec) f32, rayOrigin: zm.Vec, rayDirection: zm.Vec, opt: MarchOpt) MarchInfo {
    var t: f32 = 0;
    var i: usize = 0;
    while (i < opt.maxSteps) : (i += 1) {
        const p = rayOrigin + rayDirection * @splat(4, t);
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

pub fn getNormal(scene: fn (zm.Vec) f32, point: zm.Vec, opt: struct {h: f32 = 0.01}) zm.Vec {
    const h = @splat(4, opt.h);
    const right = zm.f32x4(1, 0, 0, 0);
    const up = zm.f32x4(0, 1, 0, 0);
    const forward  = zm.f32x4(0, 0, 1, 0);
    return zm.normalize3(.{
        scene(point + right * h) - scene(point - right * h),
        scene(point + up * h) - scene(point - up * h),
        scene(point + forward * h) - scene(point - forward * h),
    });
}

// pub fn shade(scene: fn(zm.Vec) f32, p: geom.Vec3) f32 {
//     const normal = geom.vec3.normalize
// }

pub fn sphere(p: zm.Vec, radius: f32) f32 {
    return zm.length3(p)[0] - radius;
}
