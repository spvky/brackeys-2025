const std = @import("std");
const rl = @import("raylib");

pub const Character = struct {
    position: rl.Vector2,
    speed: f32 = 150,
    radius: f32 = 16,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    color: rl.Color = rl.Color.sky_blue,

    const Self = @This();

    pub fn init(position: rl.Vector2) Self {
        return .{ .position = position };
    }

    pub fn update(self: *Self) void {
        var x_vel: f32 = 0;
        var y_vel: f32 = 0;

        if (rl.isKeyDown(.a)) {
            x_vel -= 1;
        }
        if (rl.isKeyDown(.d)) {
            x_vel += 1;
        }
        if (rl.isKeyDown(.w)) {
            y_vel -= 1;
        }
        if (rl.isKeyDown(.s)) {
            y_vel += 1;
        }

        var velo_normalized = rl.math.vector2Normalize(.{ .x = x_vel, .y = y_vel });
        velo_normalized.x *= (self.speed * rl.getFrameTime());
        velo_normalized.y *= (self.speed * rl.getFrameTime());
        self.velocity = velo_normalized;
        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;
    }

    pub fn draw(self: Self) void {
        rl.drawCircleV(self.position, self.radius, self.color);
    }
};
