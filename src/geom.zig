const std = @import("std");

/// Represents a 2D floating point Vector as .{ x, y }
pub const Vec2f = @Vector(2, f32);
/// Represents a 2D signed Vector as .{ x, y }
pub const Vec2 = @Vector(2, i32);

/// Contains convenience functions for working with vectors.
pub const vec2 = struct {
    /// Vector index representing x
    pub const x = 0;
    /// Vector index representing y
    pub const y = 1;

    /// 2D up vector (i32)
    pub const up = Vec2{ 0, -1 };
    /// 2D down vector (i32)
    pub const down = Vec2{ 0, 1 };
    /// 2D left vector (i32)
    pub const left = Vec2{ -1, 0 };
    /// 2D right vector (i32)
    pub const right = Vec2{ 1, 0 };

    /// 2D up vector
    pub const upf = Vec2f{ 0, -1 };
    /// 2D down vector
    pub const downf = Vec2f{ 0, 1 };
    /// 2D left vector
    pub const leftf = Vec2f{ -1, 0 };
    /// 2D right vector
    pub const rightf = Vec2f{ 1, 0 };

    /////////////////////////////////////////
    // i32 integer backed vector functions //
    /////////////////////////////////////////

    /// Returns true x = x and y = y
    pub fn equals(v1: Vec2, v2: Vec2) bool {
        return @reduce(.And, v1 == v2);
    }

    /// Returns true if the vector is zero
    pub fn isZero(v: Vec2) bool {
        return equals(v, Vec2{ 0, 0 });
    }

    /// Copies the vectors x and y to make a rect
    pub fn double(v: Vec2) Rect {
        return Rect{ v[0], v[1], v[0], v[1] };
    }

    /// Returns the length of the vector, squared
    pub fn length_sqr(a: Vec2) i32 {
        return @reduce(.Add, a * a);
    }

    /// Returns the distance squared
    pub fn dist_sqr(a: Vec2, b: Vec2) i32 {
        return length_sqr(a - b);
    }

    /// Returns the length of the vector.
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn length(a: Vec2) i32 {
        return @floatToInt(i32, @sqrt(@intToFloat(f32, length_sqr(a))));
    }

    /// Returns the distance between two vectors (assuming they are points).
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn dist(a: Vec2, b: Vec2) i32 {
        return length(a - b);
    }

    ///////////////////////////////////////
    // f32 float backed vector functions //
    ///////////////////////////////////////

    /// Returns the distance between two vectors
    pub fn distf(a: Vec2f, b: Vec2f) f32 {
        var subbed = @fabs(a - b);
        return lengthf(subbed);
    }

    /// Returns the length between two vectors
    pub fn lengthf(vector: Vec2f) f32 {
        var squared = vector * vector;
        return @sqrt(@reduce(.Add, squared));
    }

    /// Returns the normalized vector
    pub fn normalizef(vector: Vec2f) Vec2f {
        return vector / @splat(2, lengthf(vector));
    }

    /// Converts an i32 backed vector to a f32 backed one.
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn itof(v2: Vec2) Vec2f {
        return Vec2f{ @intToFloat(f32, v2[0]), @intToFloat(f32, v2[1]) };
    }

    /// Converts a f32 backed vector to an i32 backed one.
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn ftoi(vec2f: Vec2f) Vec2 {
        return Vec2{ @floatToInt(i32, @floor(vec2f[0])), @floatToInt(i32, @floor(vec2f[1])) };
    }

    /// Returns dot product of a and b
    pub fn dot(a: Vec2f, b: Vec2f) f32 {
        return a[0] * b[0] + a[1] * b[1];
    }

    /// Returns dot product of vector with self
    pub fn dot2(v: Vec2f) f32 {
        return dot(v, v);
    }

    /// Returns the negative dot product
    pub fn ndot(a: Vec2f, b: Vec2f) f32 {
        return a[0] * b[0] - a[1] * b[1];
    }
};

/// Represents a 3D floating point Vector as .{ x, y, z }
pub const Vec3 = @Vector(3, i32);
/// Represents a 3D floating point Vector as .{ x, y, z }
pub const Vec3f = @Vector(3, f32);

/// Contains convenience functions for working with vectors.
pub const vec3 = struct {
    /// Vector index representing x
    pub const x = 0;
    /// Vector index representing y
    pub const y = 1;
    /// Vector index representing y
    pub const z = 2;

    /////////////////////////////////////////
    // i32 integer backed vector functions //
    /////////////////////////////////////////

    /// Returns true x = x and y = y
    pub fn equals(v1: Vec3, v2: Vec3) bool {
        return @reduce(.And, v1 == v2);
    }

    /// Returns true if the vector is zero
    pub fn isZero(v: Vec3) bool {
        return equals(v, Vec3{ 0, 0, 0 });
    }

    // /// Copies the vectors x and y to make a rect
    // pub fn double(v: Vec3) Rect {
    //     return Rect{ v[0], v[1], v[0], v[1] };
    // }

    /// Returns the length of the vector, squared
    pub fn length_sqr(a: Vec3) i32 {
        return @reduce(.Add, a * a);
    }

    /// Returns the distance squared
    pub fn dist_sqr(a: Vec3, b: Vec3) i32 {
        return length_sqr(a - b);
    }

    /// Returns the length of the vector.
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn length(a: Vec3) i32 {
        return @floatToInt(i32, @sqrt(@intToFloat(f32, length_sqr(a))));
    }

    /// Returns the distance between two vectors (assuming they are points).
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn dist(a: Vec3, b: Vec3) i32 {
        return length(a - b);
    }

    ///////////////////////////////////////
    // f32 float backed vector functions //
    ///////////////////////////////////////

    /// Returns the distance between two vectors
    pub fn distf(a: Vec3f, b: Vec3f) f32 {
        var subbed = @fabs(a - b);
        return lengthf(subbed);
    }

    /// Returns the length between two vectors
    pub fn lengthf(vector: Vec3f) f32 {
        var squared = vector * vector;
        return @sqrt(@reduce(.Add, squared));
    }

    /// Returns the normalized vector
    pub fn normalizef(vector: Vec3f) Vec3f {
        return vector / @splat(3, lengthf(vector));
    }

    /// Converts an i32 backed vector to a f32 backed one.
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn itof(v3: Vec3) Vec3f {
        return Vec3f{ @intToFloat(f32, v3[0]), @intToFloat(f32, v3[1]), @intToFloat(f32, v3[2]) };
    }

    /// Converts a f32 backed vector to an i32 backed one.
    /// NOTE: Conversion between floats and ints on WASM appears
    /// to be broken, so this may not return the correct results.
    pub fn ftoi(vec3f: Vec3f) Vec3 {
        return Vec3{ @floatToInt(i32, @floor(vec3f[0])), @floatToInt(i32, @floor(vec3f[1])), @floatToInt(i32, @floor(vec3f[2])) };
    }

    /// Returns cross product of a and b
    /// Referenced https://www.tutorialspoint.com/cplusplus-program-to-compute-cross-product-of-two-vectors
    pub fn cross(a: Vec3f, b: Vec3f) Vec3f {
        return .{
            a[1] * b[2] - a[2] * b[1],
            -(a[0] * b[2] - a[2] * b[0]),
            a[0] * b[1] - a[1] * b[0],
        };
    }

    /// Returns dot product of a and b
    pub fn dot(a: Vec3f, b: Vec3f) f32 {
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    }

    /// Returns dot product of vector with self
    pub fn dot2(v: Vec3f) f32 {
        return dot(v, v);
    }
};

/// Represents a rectangle as .{ left, top, right, bottom } with integers
pub const Rect = @Vector(4, i32);
/// Represents a rectangle as .{ left, top, right, bottom } with floats
pub const Rectf = @Vector(4, f32);

/// Contains convenience functions for working with Rects
pub const rect = struct {
    ///////////////////////////////////////
    // i32 integer backed rect functions //
    ///////////////////////////////////////
    pub fn as_aabb(rectangle: Rect) AABB {
        return AABB{
            rectangle[0],
            rectangle[1],
            rectangle[2] - rectangle[0],
            rectangle[3] - rectangle[1],
        };
    }

    pub fn top(rectangle: Rect) i32 {
        return rectangle[1];
    }

    pub fn left(rectangle: Rect) i32 {
        return rectangle[0];
    }

    pub fn top_left(rectangle: Rect) Vec2 {
        return .{ rectangle[0], rectangle[1] };
    }

    pub fn right(rectangle: Rect) i32 {
        return rectangle[2];
    }

    pub fn bottom(rectangle: Rect) i32 {
        return rectangle[3];
    }

    pub fn bottom_right(rectangle: Rect) Vec2 {
        return .{ rectangle[2], rectangle[3] };
    }

    pub fn size(rectangle: Rect) Vec2 {
        return .{ rectangle[2] - rectangle[0], rectangle[3] - rectangle[1] };
    }

    pub fn contains(rectangle: Rect, vector: Vec2) bool {
        return @reduce(.And, top_left(rectangle) < vector) and
            @reduce(.And, bottom_right(rectangle) >= vector);
    }

    // TODO: Verify that this does what I want
    pub fn overlaps(rect1: Rect, rect2: Rect) bool {
        return @reduce(
            .And,
            @select(
                bool,
                rect1 > rect2,
                rect1 <= rect2,
                .{ true, true, false, false },
            ),
        );
    }

    pub fn shift(rectangle: Rect, vector: Vec2) Rect {
        return rectangle + vec2.double(vector);
    }

    /////////////////////////////////////
    // f32 float backed rect functions //
    /////////////////////////////////////

    pub fn topf(rectangle: Rectf) f32 {
        return rectangle[1];
    }

    pub fn leftf(rectangle: Rectf) f32 {
        return rectangle[0];
    }

    pub fn top_leftf(rectangle: Rectf) Vec2f {
        return .{ rectangle[0], rectangle[1] };
    }

    pub fn rightf(rectangle: Rectf) f32 {
        return rectangle[2];
    }

    pub fn bottomf(rectangle: Rectf) f32 {
        return rectangle[3];
    }

    pub fn bottom_rightf(rectangle: Rectf) Vec2f {
        return .{ rectangle[2], rectangle[3] };
    }

    pub fn sizef(rectangle: Rectf) Vec2f {
        return .{ rectangle[2] - rectangle[0], rectangle[3] - rectangle[1] };
    }

    pub fn containsf(rectangle: Rectf, vector: Vec2f) bool {
        return @reduce(.And, top_left(rectangle) < vector) and @reduce(.And, bottom_right(rectangle) > vector);
    }

    pub fn shiftf(rectangle: Rectf, vector: Vec2f) Rectf {
        return rectangle + vec2.double(vector);
    }
};

/// Represents a rectangle as .{ x, y, width, height } with integers.
/// This type is similar to Rect, but the key difference is is in how the last 2
/// elements are represented. For example, AABBs would be a better format for
/// storing information about a character's collision box, but Rects are better
/// for bounds checking.
pub const AABB = @Vector(4, i32);
/// Represents a rectangle as .{ x, y, width, height } with floats
pub const AABBf = @Vector(4, f32);

/// Contains convience functions for working with AABBs
pub const aabb = struct {
    /// Converts the AABB into a Rect
    pub fn as_rect(box: AABB) Rect {
        return Rect{ box[0], box[1], box[0] + box[2], box[0] + box[3] };
    }

    pub fn pos(box: AABB) Vec2 {
        return Vec2{ box[0], box[1] };
    }

    pub fn size(box: AABB) Vec2 {
        return Vec2{ box[2], box[3] };
    }

    pub fn x(box: AABB) i32 {
        return box[0];
    }

    pub fn y(box: AABB) i32 {
        return box[1];
    }

    pub fn width(box: AABB) i32 {
        return box[2];
    }

    pub fn height(box: AABB) i32 {
        return box[3];
    }

    pub fn initv(posv: Vec2, sizev: Vec2) AABB {
        return AABB{ posv[0], posv[1], sizev[0], sizev[1] };
    }

    pub fn addv(box: AABB, v2: Vec2) AABB {
        return initv(pos(box) + v2, size(box));
    }

    pub fn subv(box: AABB, v2: Vec2) AABB {
        return initv(pos(box) - v2, size(box));
    }

    /// Converts the AABBf into a Rectf
    pub fn as_rectf(box: AABBf) Rectf {
        return Rectf{ box[0], box[1], box[0] + box[2], box[0] + box[3] };
    }

    pub fn posf(box: AABBf) Vec2f {
        return Vec2f{ box[0], box[1] };
    }

    pub fn sizef(box: AABBf) Vec2f {
        return Vec2f{ box[2], box[3] };
    }

    pub fn initvf(posv: Vec2f, sizev: Vec2f) AABBf {
        return AABBf{ posv[0], posv[1], sizev[0], sizev[1] };
    }

    pub fn addvf(box: AABBf, v2: Vec2f) AABBf {
        return initv(pos(box) + v2, size(box));
    }

    pub fn subvf(box: AABBf, v2: Vec2f) AABBf {
        return initv(pos(box) - v2, size(box));
    }
};
