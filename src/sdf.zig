//! Raymarched SDF rendering
//! Referencess:
//! - https://9bitscience.blogspot.com/2013/07/raymarching-distance-fields_14.html
//! - https://iquilezles.org/articles/distfunctions/
const std = @import("std");
const zm = @import("zmath");
const geom = @import("geom.zig");
const Vec3f = geom.Vec3f;

pub const MarchOpt = struct {
    maxSteps: usize = 20,
    epsilon: f32 = 0.1,
    maxDistance: f32 = 100,
};

pub const MarchInfo = struct {
    iterations: usize,
    distance: f32,
    point: ?Vec3f,
    floor: bool,
};

/// Given a SDF scene, marches from rayOrigin in rayDirection until it the max number of iterations is hit,
/// the max distance is hit, or a point was hit.
pub fn raymarch(scene: fn (Vec3f) f32, rayOrigin: Vec3f, rayDirection: Vec3f, opt: MarchOpt) MarchInfo {
    var t: f32 = 0;
    var i: usize = 0;
    while (i < opt.maxSteps) : (i += 1) {
        const p = rayOrigin + rayDirection * @splat(3, t);
        const d = scene(p);
        if (d < opt.epsilon) return .{
            .iterations = i,
            .distance = t,
            .point = p,
            .floor = false,
        };
        if (t > 1.0 and p[1] + 10 <= opt.epsilon) return .{
            .iterations = i,
            .distance = t,
            .point = null,
            .floor = true,
        };
        t += d;
        if (t > opt.maxDistance) break;
    }
    return .{
        .iterations = i,
        .distance = t,
        .point = null,
        .floor = false,
    };
}

pub fn getNormal(scene: fn (geom.Vec3f) f32, point: geom.Vec3f, opt: struct { h: f32 = 0.01 }) geom.Vec3f {
    const h = @splat(3, opt.h);
    return geom.vec3.normalizef(.{
        scene(point + geom.vec3.rightf * h) - scene(point - geom.vec3.rightf * h),
        scene(point + geom.vec3.upf * h) - scene(point - geom.vec3.upf * h),
        scene(point + geom.vec3.forwardf * h) - scene(point - geom.vec3.forwardf * h),
    });
}

pub fn sphere(p: Vec3f, radius: f32) f32 {
    return geom.vec3.lengthf(p) - radius;
}

pub fn plane(p: Vec3f, n: Vec3f, h: f32) f32 {
    return geom.vec3.lengthf(p, n)[0] + h;
}

pub fn box(p: Vec3f, b: Vec3f) f32 {
    const q = @fabs(p) - b;
    const zero = @splat(3, @as(f32, 0.0));
    return geom.vec3.lengthf(@maximum(q, zero)) + @minimum(@maximum(q[0], @maximum(q[1], q[2])), 0.0);
}
