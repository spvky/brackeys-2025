const std = @import("std");
const math = std.math;
const rl = @import("raylib");

pub fn ease_in_out_back(x: f32) f32 {
    const c1: f32 = 1.70158;
    const c2: f32 = c1 * 1.525;

    if (x < 0.5) {
        return 0.5 * (x * 2 * x * 2 * ((c2 + 1) * x * 2 - c2));
    } else {
        const adjusted_x = (x * 2) - 2;
        return 0.5 * (adjusted_x * adjusted_x * ((c2 + 1) * adjusted_x + c2) + 2);
    }
}

pub fn ease_in_out(x: f32) f32 {
    return -(math.cos(math.pi * x) - 1) / 2;
}
