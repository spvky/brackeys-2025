const std = @import("std");
const rl = @import("raylib");

pub const Character = struct {
    position: rl.Vector2,
    speed: f32 = 150,
    radius: f32 = 4,
    collision_detected: bool = false,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    color: rl.Color = rl.Color.sky_blue,

    const Self = @This();

    pub fn init(position: rl.Vector2) Self {
        return .{ .position = position };
    }

    pub fn calculate_velocity(self: *Self) void {
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
    }

    pub fn update(self: *Self, collisions: []rl.Rectangle) void {
        self.calculate_velocity();
        for (collisions) |collision| {
            self.collision_check(collision);
        }

        self.update_position();
    }

    pub fn update_position(self: *Self) void {
        if (!self.collision_detected) {
            self.position.x += self.velocity.x;
            self.position.y += self.velocity.y;
        } else {
            self.velocity = .{ .x = 0, .y = 0 };
        }
        self.collision_detected = false;
    }

    pub fn collision_check(self: *Self, tile: rl.Rectangle) void {
        const no_velocity = self.velocity.x == 0 and self.velocity.y == 0;
        if (!self.collision_detected) {
            if (!no_velocity) {
                if (rl.checkCollisionCircleRec(self.projected_position(), self.radius * 0.5, tile)) {
                    self.collision_detected = true;
                }
            }
        }
    }

    pub fn debug_player(self: Self) !void {
        var buf: [1000]u8 = undefined;
        const output = try std.fmt.bufPrintZ(&buf, "Velocity: [{d:.2},{d:.2}]\nPosition: [{d:.2},{d:.2}]\nCollision Check: {}", .{ self.velocity.x, self.velocity.y, self.position.x, self.position.y, self.collision_detected });
        rl.drawText(output, 2, 50, 24, rl.Color.dark_blue);
    }

    pub fn projected_position(self: Self) rl.Vector2 {
        return self.position.add(self.velocity);
    }

    pub fn draw(self: Self, camera_offset: rl.Vector2, show_velocity: bool) void {
        const camera_pos = self.position.subtract(camera_offset);
        if (show_velocity) {
            const velocity_pos = self.projected_position().subtract(camera_offset);
            rl.drawCircleV(velocity_pos, self.radius, rl.Color.ray_white);
        }
        rl.drawCircleV(camera_pos, self.radius, self.color);
    }
};

pub const GuardState = enum { moving, waiting, alert, chase };

pub const Guard = struct {
    position: rl.Vector2,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    radius: f32 = 6,
    vision_range: f32 = 60,
    vision_width: f32 = 1,
    state: GuardState = .waiting,
    // Patrol behavior
    patrol_path: std.ArrayList(rl.Vector2),
    patrol_speed: f32 = 25,
    patrol_index: usize = 0,
    wait_timer: Timer,
    // Chase behavior
    last_sighted: rl.Vector2 = .{ .x = 0, .y = 0 },

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, position: rl.Vector2, patrol_points: []rl.Vector2) !Self {
        var patrol_path = std.ArrayList(rl.Vector2).init(allocator);
        for (patrol_points) |p| {
            try patrol_path.append(p);
        }

        const timer = Timer.init(1);

        return Self{ .position = position, .patrol_path = patrol_path, .wait_timer = timer };
    }

    pub fn deinit(self: *Self) void {
        self.patrol_path.deinit();
    }

    pub fn update(self: *Self, player: *Character) void {
        self.check_player_spotted(player);
        self.wait_timer.update();
        switch (self.state) {
            .moving => {
                const target_position = self.patrol_path.items[self.patrol_index];
                if (self.position.distance(target_position) <= 0.3) {
                    self.position = target_position;
                    self.wait_timer.reset();
                    self.state = .waiting;
                    self.increment_patrol_index();
                } else {
                    const delta = target_position.subtract(self.position).normalize();
                    self.facing = self.facing.lerp(delta, 5 * rl.getFrameTime()).normalize();
                    self.velocity = delta.scale(self.patrol_speed * rl.getFrameTime());
                }
            },
            .waiting => {
                if (self.wait_timer.finished) {
                    self.state = .moving;
                }
                self.velocity = rl.Vector2.zero();
            },
            .alert => {
                self.facing = self.facing.rotate(rl.getFrameTime() * 10.0);
            },
            .chase => {},
        }
        self.apply_velocity();
    }

    pub fn check_player_spotted(self: *Self, player: *Character) void {
        const vt = self.vision_triangle();
        const spotted: bool = blk: {
            if (rl.checkCollisionCircleLine(player.position, player.radius, vt[0], vt[1])) {
                break :blk true;
            }
            if (rl.checkCollisionCircleLine(player.position, player.radius, vt[1], vt[2])) {
                break :blk true;
            }
            if (rl.checkCollisionCircleLine(player.position, player.radius, vt[2], vt[0])) {
                break :blk true;
            }
            break :blk false;
        };

        if (spotted) {
            self.state = .alert;
            self.velocity = rl.Vector2.zero();
        }
    }

    pub fn apply_velocity(self: *Self) void {
        self.position = self.position.add(self.velocity);
    }

    pub fn increment_patrol_index(self: *Self) void {
        const paths_length = self.patrol_path.items.len;
        const new_index = self.patrol_index + 1;
        if (new_index > paths_length - 1) {
            self.patrol_index = 0;
        } else {
            self.patrol_index = new_index;
        }
    }

    pub fn vision_triangle(self: Self) [3]rl.Vector2 {
        const a = self.position;
        const m_a = self.position.add(self.facing.scale(self.vision_range));
        const dir: rl.Vector2 = .{ .x = a.x - m_a.x, .y = a.y - m_a.y };
        const orth: rl.Vector2 = .{ .x = -dir.y, .y = dir.x };
        const h_width = self.vision_width / 2;
        const a_l: rl.Vector2 = .{ .x = (orth.x * h_width) + m_a.x, .y = (orth.y * h_width) + m_a.y };
        const a_r: rl.Vector2 = .{ .x = (-orth.x * h_width) + m_a.x, .y = (-orth.y * h_width) + m_a.y };
        return [3]rl.Vector2{ a, a_l, a_r };
    }

    pub fn draw(self: Self, camera_offset: rl.Vector2) void {
        const camera_pos = self.position.subtract(camera_offset);
        const vt = self.vision_triangle();
        const tvt = [3]rl.Vector2{ vt[0].subtract(camera_offset), vt[1].subtract(camera_offset), vt[2].subtract(camera_offset) };
        rl.drawTriangle(tvt[2], tvt[1], tvt[0], rl.Color.yellow.alpha(0.6));
        rl.drawCircleV(camera_pos, self.radius, rl.Color.red);
    }
};

pub const Timer = struct {
    duration: f32,
    current_time: f32,
    finished: bool,

    const Self = @This();

    pub fn init(duration: f32) Self {
        return Self{ .duration = duration, .current_time = 0, .finished = false };
    }

    pub fn update(self: *Self) void {
        if (!self.finished) {
            self.current_time += rl.getFrameTime();
            if (self.current_time >= self.duration) {
                self.finished = true;
            }
        }
    }

    pub fn reset(self: *Self) void {
        self.current_time = 0;
        self.finished = false;
    }
};
