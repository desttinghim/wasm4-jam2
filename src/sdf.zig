//! Raymarched SDF rendering
//! Referencess:
//! - https://9bitscience.blogspot.com/2013/07/raymarching-distance-fields_14.html
//! - https://iquilezles.org/articles/distfunctions/
const std = @import("std");
const zm = @import("zmath");
const geom = @import("geom.zig");
const Vec3f = geom.Vec3f;
const w4 = @import("wasm4.zig");

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

const Coverage = struct {
    low: f32,
    high: f32,
    sign: f32,
};

fn coverage(low: f32, high: f32, sign: f32) Coverage {
    return .{ .low = low, .high = high, .sign =  sign };
}

const CoverageInfo = struct {
    pos: Vec3f,
    hit: bool,
};

/// A variation on the raymarch algorithm that starts at th emiddle of the bounds
/// - http://zone.dog/braindump/sdf_marching/
pub fn coverageSearch(scene: fn (Vec3f) f32, rayOrigin: Vec3f, rayDirection: Vec3f, travelStart: f32, travelEnd: f32) CoverageInfo {
    var pivotTravel = (travelStart + travelEnd) * 0.5;
    const pivotPoint = rayOrigin + rayDirection * @splat(3, pivotTravel);
    var pivotRadius = scene(pivotPoint);
    const abs_pivotRadius = @fabs(pivotRadius);

    var stack: [10]Coverage = undefined;
    var len: usize = 2;

    stack[0] = coverage(travelEnd, travelEnd, 0);
    stack[1] = coverage(pivotTravel - abs_pivotRadius, pivotTravel + abs_pivotRadius, std.math.sign(pivotRadius));

    var cursor = coverage(travelStart, travelStart, 0);

    // var count: usize = 0;
    while (len > 0) {
        const i = len - 1;
        if (stack[i].low <= cursor.high) {
            cursor = stack[i];
            len -= 1;
            continue;
        }
        pivotTravel = (stack[i].low + cursor.high) * 0.5;
        pivotRadius = scene(rayOrigin + rayDirection * @splat(3, pivotTravel));
        const next = coverage(pivotTravel - @fabs(pivotRadius), pivotTravel + @fabs(pivotRadius), std.math.sign(pivotRadius));
        if (@fabs(stack[i].sign + next.sign) > 0 and stack[i].low <= next.high) {
            stack[i].low = next.low;
        } else {
            stack[len] = next;
            len += 1;
        }
    }

    if (cursor.sign < 0) {
        return .{
            .pos = rayOrigin + rayDirection * @splat(3, @maximum(travelStart, cursor.low)),
            .hit = true,
        };
    } else {
        return .{
            .pos = rayOrigin + rayDirection * @splat(3, travelEnd),
            .hit = false,
        };
    }
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
