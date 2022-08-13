// WASM-4: https://wasm4.org/docs

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Platform Constants                                                        │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘

pub const CANVAS_SIZE: u32 = 160;

pub const BUTTON_1: u8 = 1;
pub const BUTTON_2: u8 = 2;
pub const BUTTON_LEFT: u8 = 16;
pub const BUTTON_RIGHT: u8 = 32;
pub const BUTTON_UP: u8 = 64;
pub const BUTTON_DOWN: u8 = 128;

pub const MOUSE_LEFT: u8 = 1;
pub const MOUSE_RIGHT: u8 = 2;
pub const MOUSE_MIDDLE: u8 = 4;

pub const SYSTEM_PRESERVE_FRAMEBUFFER: u8 = 1;
pub const SYSTEM_HIDE_GAMEPAD_OVERLAY: u8 = 2;

pub const TONE_PULSE1: u32 = 0;
pub const TONE_PULSE2: u32 = 1;
pub const TONE_TRIANGLE: u32 = 2;
pub const TONE_NOISE: u32 = 3;
pub const TONE_MODE1: u32 = 0;
pub const TONE_MODE2: u32 = 4;
pub const TONE_MODE3: u32 = 8;
pub const TONE_MODE4: u32 = 12;

pub const BLIT_2BPP: u32 = 1;
pub const BLIT_1BPP: u32 = 0;
pub const BLIT_FLIP_X: u32 = 2;
pub const BLIT_FLIP_Y: u32 = 4;
pub const BLIT_ROTATE: u32 = 8;

usingnamespace if (@import("builtin").is_test) stubWasm4 else externWasm4;

const externWasm4 = struct {
    // ┌───────────────────────────────────────────────────────────────────────────┐
    // │                                                                           │
    // │ Memory Addresses                                                          │
    // │                                                                           │
    // └───────────────────────────────────────────────────────────────────────────┘

    pub const PALETTE: *[4]u32 = @intToPtr(*[4]u32, 0x04);
    pub const DRAW_COLORS: *u16 = @intToPtr(*u16, 0x14);
    pub const GAMEPAD1: *const u8 = @intToPtr(*const u8, 0x16);
    pub const GAMEPAD2: *const u8 = @intToPtr(*const u8, 0x17);
    pub const GAMEPAD3: *const u8 = @intToPtr(*const u8, 0x18);
    pub const GAMEPAD4: *const u8 = @intToPtr(*const u8, 0x19);
    pub const MOUSE_X: *const i16 = @intToPtr(*const i16, 0x1a);
    pub const MOUSE_Y: *const i16 = @intToPtr(*const i16, 0x1c);
    pub const MOUSE_BUTTONS: *const u8 = @intToPtr(*const u8, 0x1e);
    pub const SYSTEM_FLAGS: *u8 = @intToPtr(*u8, 0x1f);
    pub const FRAMEBUFFER: *[6400]u8 = @intToPtr(*[6400]u8, 0xA0);
    /// INCLUDES STACK! A slice pointing to all available program memory
    pub const PROGRAM_MEMORY: *[58975]u8 = @intToPtr(*[58975]u8, 0x19A0);

    // ┌───────────────────────────────────────────────────────────────────────────┐
    // │                                                                           │
    // │ Drawing Functions                                                         │
    // │                                                                           │
    // └───────────────────────────────────────────────────────────────────────────┘

    /// Copies pixels to the framebuffer.
    pub extern fn blit(sprite: [*]const u8, x: i32, y: i32, width: i32, height: i32, flags: u32) void;

    /// Copies a subregion within a larger sprite atlas to the framebuffer.
    pub extern fn blitSub(sprite: [*]const u8, x: i32, y: i32, width: i32, height: i32, src_x: u32, src_y: u32, stride: i32, flags: u32) void;

    /// Draws a line between two points.
    pub extern fn line(x1: i32, y1: i32, x2: i32, y2: i32) void;

    /// Draws an oval (or circle).
    pub extern fn oval(x: i32, y: i32, width: i32, height: i32) void;

    /// Draws a rectangle.
    pub extern fn rect(x: i32, y: i32, width: u32, height: u32) void;

    /// Draws text using the built-in system font.
    pub extern fn text(str: [*]const u8, x: i32, y: i32) void;

    pub extern fn textUtf8(strPtr: [*]const u8, strLen: usize, x: i32, y: i32) void;

    /// Draws a vertical line
    pub extern fn vline(x: i32, y: i32, len: u32) void;

    /// Draws a horizontal line
    pub extern fn hline(x: i32, y: i32, len: u32) void;

    // ┌───────────────────────────────────────────────────────────────────────────┐
    // │                                                                           │
    // │ Sound Functions                                                           │
    // │                                                                           │
    // └───────────────────────────────────────────────────────────────────────────┘

    /// Plays a sound tone.
    pub extern fn tone(frequency: u32, duration: u32, volume: u32, flags: u32) void;

    // ┌───────────────────────────────────────────────────────────────────────────┐
    // │                                                                           │
    // │ Storage Functions                                                         │
    // │                                                                           │
    // └───────────────────────────────────────────────────────────────────────────┘

    /// Reads up to `size` bytes from persistent storage into the pointer `dest`.
    pub extern fn diskr(dest: [*]u8, size: u32) u32;

    /// Writes up to `size` bytes from the pointer `src` into persistent storage.
    pub extern fn diskw(src: [*]const u8, size: u32) u32;

    // ┌───────────────────────────────────────────────────────────────────────────┐
    // │                                                                           │
    // │ Other Functions                                                           │
    // │                                                                           │
    // └───────────────────────────────────────────────────────────────────────────┘

    /// Prints a message to the debug console.
    pub extern fn trace(x: [*]const u8) void;
    pub extern fn traceUtf8(x: [*]const u8, len: usize) void;

    /// Use with caution, as there's no compile-time type checking.
    ///
    /// * %c, %d, and %x expect 32-bit integers.
    /// * %f expects 64-bit floats.
    /// * %s expects a *zero-terminated* string pointer.
    ///
    /// See https://github.com/aduros/wasm4/issues/244 for discussion and type-safe
    /// alternatives.
    pub extern fn tracef(x: [*:0]const u8, ...) void;
};

const stubWasm4 = struct {

    // ┌───────────────────────────────────────────────────────────────────────────┐
    // │                                                                           │
    // │ Memory Addresses                                                          │
    // │                                                                           │
    // └───────────────────────────────────────────────────────────────────────────┘

    /// Simulated memory for testing
    var buffer = [_]u8{0} ** 64000;
    pub const PALETTE: *[4]u32 = @ptrCast(*[4]u32, &buffer[0x04]);
    pub const DRAW_COLORS: *u16 = @ptrCast(*u16, &buffer[0x14]);
    pub const GAMEPAD1: *const u8 = @ptrCast(*const u8, &buffer[0x16]);
    pub const GAMEPAD2: *const u8 = @ptrCast(*const u8, &buffer[0x17]);
    pub const GAMEPAD3: *const u8 = @ptrCast(*const u8, &buffer[0x18]);
    pub const GAMEPAD4: *const u8 = @ptrCast(*const u8, &buffer[0x19]);
    pub const MOUSE_X: *const i16 = @ptrCast(*const i16, &buffer[0x1a]);
    pub const MOUSE_Y: *const i16 = @ptrCast(*const i16, &buffer[0x1c]);
    pub const MOUSE_BUTTONS: *const u8 = @ptrCast(*const u8, &buffer[0x1e]);
    pub const SYSTEM_FLAGS: *u8 = @ptrCast(*u8, &buffer[0x1f]);
    pub const FRAMEBUFFER: *[6400]u8 = @ptrCast(*[6400]u8, &buffer[0xA0]);
    pub const PROGRAM_MEMORY: *[58975]u8 = @ptrCast(*[58975]u8, &buffer[0x19A0]);

    pub fn blit(_: [*]const u8, _: i32, _: i32, _: i32, _: i32, _: u32) void {}
    pub fn blitSub(_: [*]const u8, _: i32, _: i32, _: i32, _: i32, _: u32, _: u32, _: i32, _: u32) void {}
    pub fn line(_: i32, _: i32, _: i32, _: i32) void {}
    pub fn oval(_: i32, _: i32, _: i32, _: i32) void {}
    pub fn rect(_: i32, _: i32, _: u32, _: u32) void {}
    pub fn text(_: [*]const u8, _: i32, _: i32) void {}
    pub fn vline(_: i32, _: i32, _: u32) void {}
    pub fn hline(_: i32, _: i32, _: u32) void {}
    pub fn tone(_: u32, _: u32, _: u32, _: u32) void {}
    pub fn diskr(_: [*]u8, _: u32) u32 {
        return 0;
    }
    pub fn diskw(_: [*]const u8, _: u32) u32 {
        return 0;
    }
    pub fn trace(_: [*]const u8) void {}
    pub fn traceUtf8(_: [*]const u8, _: usize) void {}
    // pub fn tracef(_: [*:0]const u8, ...) void {}
};
