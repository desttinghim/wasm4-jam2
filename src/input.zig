//! # Input
//! This is an input library for WASM4.
const w4 = @import("wasm4.zig");
const geom = @import("geom.zig");

/// Call at the end of the loop function. Updates previous input state to allow
/// press and release to be detected.
pub fn update() void {
    gamepadstates[0] = w4.GAMEPAD1.*;
    gamepadstates[1] = w4.GAMEPAD2.*;
    gamepadstates[2] = w4.GAMEPAD3.*;
    gamepadstates[3] = w4.GAMEPAD4.*;
    mousestate = w4.MOUSE_BUTTONS.*;
    mousepos_previous = mousepos_current;
    mousepos_current = geom.Vec2{ w4.MOUSE_X.*, w4.MOUSE_Y.* };
}

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Gamepad Input                                                             │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘
var gamepadstates: [4]u8 = .{ 0, 0, 0, 0 };

const Gamepad = enum(u8) {
    one = 0,
    two = 1,
    three = 2,
    four = 3,
};

const GamepadButton = enum(u8) {
    x = w4.BUTTON_1,
    z = w4.BUTTON_2,
    up = w4.BUTTON_UP,
    down = w4.BUTTON_DOWN,
    left = w4.BUTTON_LEFT,
    right = w4.BUTTON_RIGHT,
};

fn _pressed(state: u8, button: GamepadButton) bool {
    return (state & @enumToInt(button)) > 0;
}

/// Returns true if a button is pressed for the given gamepad.
pub fn btn(gp: Gamepad, button: GamepadButton) bool {
    return switch (gp) {
        .one => _pressed(w4.GAMEPAD1.*, button),
        .two => _pressed(w4.GAMEPAD2.*, button),
        .three => _pressed(w4.GAMEPAD3.*, button),
        .four => _pressed(w4.GAMEPAD4.*, button),
    };
}

/// Returns true if the button for a given gamepad was pressed this frame.
pub fn btnp(gp: Gamepad, button: GamepadButton) bool {
    return !_pressed(gamepadstates[@enumToInt(gp)], button) and btn(gp, button);
}

/// Returns true if the button for a given gamepad was released this frame.
pub fn btnr(gp: Gamepad, button: GamepadButton) bool {
    return _pressed(gamepadstates[@enumToInt(gp)], button) and !btn(gp, button);
}

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Mouse Input                                                               │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘
var mousestate: u8 = 0;
var mousepos_current: geom.Vec2 = geom.Vec2{ 0, 0 };
var mousepos_previous: geom.Vec2 = geom.Vec2{ 0, 0 };

const MouseButton = enum(u8) {
    left = w4.MOUSE_LEFT,
    right = w4.MOUSE_RIGHT,
    middle = w4.MOUSE_MIDDLE,
    any = w4.MOUSE_LEFT | w4.MOUSE_RIGHT | w4.MOUSE_MIDDLE,
};

/// Returns true if the given mouse button is down.
pub fn mouse(button: MouseButton) bool {
    return (w4.MOUSE_BUTTONS.* & @enumToInt(button)) > 0;
}

fn mouseprev(button: MouseButton) bool {
    return (mousestate & @enumToInt(button)) > 0;
}

/// Returns true if the given mouse button was pressed this frame.
pub fn mousep(button: MouseButton) bool {
    return mouse(button) and !mouseprev(button);
}

/// Returns true if the given mouse button was released this frame.
pub fn mouser(button: MouseButton) bool {
    return !mouse(button) and mouseprev(button);
}

/// Returns a vector with the mouse position
pub fn mousepos() geom.Vec2 {
    return mousepos_current;
}

/// Returns a vector with a diff of the mouse position
pub fn mousediff() geom.Vec2 {
    return mousepos_previous - mousepos();
}

test "usage" {
    // Import this file as a namespace
    const Input = @This();
    // In loop
    if (Input.btnp(.one, .left)) {
        // gamepad 1, left button just pressed
    }
    if (Input.btnr(.two, .right)) {
        // gampad 2, right button just released
    }
    if (Input.btn(.three, .up)) {
        // gamepad 3, up button pressed
    }

    if (Input.mouse(.left)) {
        // left mouse button pressed
    }
    if (Input.mousep(.right)) {
        // left mouse button just pressed
    }
    if (Input.mouser(.middle)) {
        // middle mouse button just released
    }
    _ = Input.mousepos();

    Input.update();
}
