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
};

pub const MarchInfo = struct {
    iterations: usize,
    distance: f32,
    point: ?Vec3f,
    floor: bool,
};

/// Given a SDF scene, marches from rayOrigin in rayDirection until it the max number of iterations is hit,
/// the max distance is hit, or a point was hit.
pub fn raymarch(scene: fn (Vec3f) f32, rayOrigin: Vec3f, rayDirection: Vec3f, maxDistance: f32, opt: MarchOpt) MarchInfo {
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
        if (t > maxDistance) break;
    }
    return .{
        .iterations = i,
        .distance = t,
        .point = null,
        .floor = false,
    };
}

pub const CoverageInfo = struct {
    point: Vec3f,
    hit: bool,
};

const Coverage = struct {
    low: f32,
    high: f32,
    sign: i4,

    fn contains(this: Coverage, other: Coverage) bool {
        // If the bottom of this span overlaps with the top of the next span
        return this.low <= other.high;
    }
};

fn coverage(pivot: f32, radius: f32) Coverage {
    return .{
        .low = pivot - @fabs(radius),
        .high = pivot + @fabs(radius),
        .sign = @floatToInt(i4, std.math.sign(radius)),
    };
}

fn abs(val: i4) i4 {
    return if (val < 0) -val else val;
}

fn printFloat(str: [*:0]const u8, f: f32) void {
    var fstr = [_]u8{' '} ** 8;
    fstr[0] = if (f < 0) '-' else ' ';
    fstr[1] = '0' + @floatToInt(u8, @minimum(9, @mod(f / 100, 10)));
    fstr[2] = '0' + @floatToInt(u8, @minimum(9, @mod(f / 10, 10)));
    fstr[3] = '0' + @floatToInt(u8, @minimum(9, @mod(f, 10)));
    fstr[4] = '.';
    fstr[5] = '0' + @floatToInt(u8, @minimum(9, @mod(f * 10, 10)));
    fstr[6] = '0' + @floatToInt(u8, @minimum(9, @mod(f * 100, 10)));
    fstr[7] = 0;
    w4.tracef("%s %s", str, fstr);
}

fn rayPoint(ro: Vec3f, rd: Vec3f, dist: f32) Vec3f {
    return ro + rd * @splat(3, dist);
}

/// A variation on the raymarch algorithm that starts at th emiddle of the bounds
/// - http://zone.dog/braindump/sdf_marching/
pub fn coverageSearch(scene: fn (Vec3f) f32, rayOrigin: Vec3f, rayDirection: Vec3f, travelStart: f32, travelEnd: f32, opt: MarchOpt) CoverageInfo {
    var pivotTravel = (travelStart + travelEnd) * 0.5;
    var pivotRadius = scene(rayPoint(rayOrigin, rayDirection, pivotTravel));
    // w4.tracef("\n---- start");
    // printFloat("travelStart", travelStart);
    // printFloat("travelEnd", travelEnd);
    // printFloat("pivotRadius", pivotRadius);
    // printFloat("pivotTravel", pivotTravel);

    var stack: [20]Coverage = undefined;
    var len: usize = 2;

    stack[0] = coverage(travelEnd, 0);
    stack[1] = coverage(pivotTravel, pivotRadius);

    var cursor = coverage(travelStart, 0);

    const epsilon = opt.epsilon;

    var iter: usize = 0;
    while (iter < opt.maxSteps) : (iter += 1) {
        const i = len - 1;
        // w4.tracef("---- %d", i);
        // printFloat("stack[i].low", stack[i].low);
        // printFloat("stack[i].high", stack[i].high);
        // printFloat("cursor.low", cursor.low);
        // printFloat("cursor.high", cursor.high);
        if (stack[i].low - epsilon <= cursor.high) {
            // w4.tracef("popping top of stack");
            // If the top of the stack contains the end of the cursor, it becomes the cursor
            cursor = stack[i];
            len -= 1;
            if (len == 0 or cursor.sign < 0) break;
        } else {
            pivotTravel = (stack[i].low + cursor.high) * 0.5;
            // printFloat("pivotTravel", pivotTravel);
            pivotRadius = scene(rayPoint(rayOrigin, rayDirection, pivotTravel));
            // printFloat("pivotRadius", pivotRadius);
            const next = coverage(pivotTravel, pivotRadius);
            // printFloat("next.low", next.low);
            // printFloat("next.high", next.high);
            if (stack[i].sign == next.sign and stack[i].low - epsilon <= next.high) {
                // w4.tracef("changing low");
                stack[i].low = next.low;
            } else {
                // w4.tracef("pushing to stack");
                stack[len] = next;
                len += 1;
            }
        }
    }

    if (cursor.sign == -1) {
        // If the cursor is inside a sdf
        return .{
            .point = rayOrigin + rayDirection * @splat(3, @maximum(travelStart, cursor.low)),
            .hit = true,
        };
    } else {
        return .{
            .point = rayOrigin + rayDirection * @splat(3, travelEnd),
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
