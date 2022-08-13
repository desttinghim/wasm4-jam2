//! Raymarched SDF rendering
//! Referencess:
//! - https://9bitscience.blogspot.com/2013/07/raymarching-distance-fields_14.html
//! - https://iquilezles.org/articles/distfunctions/
const geom = @import("geom.zig");
const std = @import("std");

pub const MarchOpt = struct {
    maxSteps: usize = 20,
    epsilon: f32 = 0.1,
};

pub fn raymarch(scene: fn (geom.Vec3f) f32, rayOrigin: geom.Vec3f, rayDirection: geom.Vec3f, opt: MarchOpt) bool {
    var t: f32 = 0;
    var i: usize = 0;
    while (i < opt.maxSteps) : (i += 1) {
        const d = scene(rayOrigin + rayDirection * @splat(3, t));
        if (d < opt.epsilon) return true;
        t += d;
    }
    return false;
}

pub fn sphere(p: geom.Vec3f, radius: f32) f32 {
    return geom.vec3.lengthf(p) - radius;
}
