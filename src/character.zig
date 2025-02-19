const std = @import("std");
const rl = @import("raylib");
const util = @import("utils.zig");

pub const Character = struct {
    position: rl.Vector2,
    speed: f32 = 80,
    radius: f32 = 4,
    collision_detected: bool = false,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    color: rl.Color = rl.Color.sky_blue,

    animation_t: f32 = 0,

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
        if (self.velocity.length() > 0) self.facing = self.velocity;
    }

    pub fn update(self: *Self, collisions: []rl.Rectangle, frametime: f32) void {
        self.calculate_velocity();
        for (collisions) |collision| {
            self.collision_check(collision);
        }

        self.update_position();
        self.animation_t += frametime;
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
        const output = try std.fmt.bufPrintZ(&buf, "Velocity: [{d:.2},{d:.2}]\nPosition: [{d:.2},{d:.2}]\nCollision Check: {}\nFacing: [{d:.2}, {d:.2}]", .{ self.velocity.x, self.velocity.y, self.position.x, self.position.y, self.collision_detected, self.facing.x, self.facing.y });
        rl.drawText(output, 2, 50, 24, rl.Color.dark_blue);
    }

    pub fn projected_position(self: Self) rl.Vector2 {
        return self.position.add(self.velocity);
    }

    pub fn draw(self: Self, camera_offset: rl.Vector2, show_velocity: bool) void {
        const pos_on_camera = self.position.subtract(camera_offset);
        if (show_velocity) {
            const velocity_pos = self.projected_position().subtract(camera_offset);
            rl.drawCircleV(velocity_pos, self.radius, rl.Color.ray_white);
        }

        const rotation_degrees = std.math.atan2(self.facing.y, self.facing.x) * (180.0 / std.math.pi);
        rl.drawRectanglePro(.{ .x = pos_on_camera.x, .y = pos_on_camera.y, .height = 8, .width = 8 }, .{ .x = 4, .y = 4 }, rotation_degrees, self.color);

        // NOTE: if we don't take the abs value of the head, it will go 'faaar' back. It looks cool! but not the way we usually walk...
        // probably fits well if we are 'sneaking' or 'crouching' or something
        const t = @abs(std.math.cos(self.animation_t * 15 * self.velocity.length()));
        // draw head
        rl.drawRectanglePro(.{ .x = pos_on_camera.x, .y = pos_on_camera.y, .height = 4, .width = 4 }, .{ .x = 2 - t * 2, .y = 2 }, rotation_degrees, rl.Color.black);
    }
};

pub const GuardState = enum { moving, waiting, alert, chase };

pub const Guard = struct {
    position: rl.Vector2,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    start_facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    radius: f32 = 6,
    vision_range: f32 = 60,
    vision_width: f32 = 1,
    state: GuardState = .waiting,
    // Patrol behavior
    patrol_path: std.ArrayList(rl.Vector2),
    patrol_speed: f32 = 25,
    patrol_index: usize = 0,
    wait_timer: Timer = Timer.init(1),
    turning_timer: Timer = Timer.init(0.75),
    // Chase behavior
    last_sighted: rl.Vector2 = .{ .x = 0, .y = 0 },

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, position: rl.Vector2, patrol_points: []rl.Vector2) !Self {
        var patrol_path = std.ArrayList(rl.Vector2).init(allocator);
        for (patrol_points) |p| {
            try patrol_path.append(p);
        }

        return Self{ .position = position, .patrol_path = patrol_path };
    }

    pub fn deinit(self: *Self) void {
        self.patrol_path.deinit();
    }

    pub fn update(self: *Self, player: Character, occlusions: []rl.Rectangle, frametime: f32) void {
        self.check_player_spotted(player, occlusions);
        self.wait_timer.update(frametime);
        self.turning_timer.update(frametime);

        const target_position = self.patrol_path.items[self.patrol_index];
        switch (self.state) {
            .moving => {
                if (self.position.distance(target_position) <= 0.3) {
                    self.position = target_position;
                    self.wait_timer.reset();
                    self.state = .waiting;
                    self.start_facing = self.facing;
                    self.increment_patrol_index();
                } else {
                    const delta = target_position.subtract(self.position).normalize();
                    const progress = self.turning_timer.current_time / self.turning_timer.duration;
                    const f = util.ease_in_out_back(progress);
                    self.facing.x = std.math.lerp(self.start_facing.x, delta.x, f);
                    self.facing.y = std.math.lerp(self.start_facing.y, delta.y, f);
                    self.velocity = delta.scale(self.patrol_speed * frametime);
                }
            },
            .waiting => {
                if (self.wait_timer.finished) {
                    self.state = .moving;
                    self.turning_timer.reset();
                }
                self.velocity = rl.Vector2.zero();
            },
            .alert => {
                self.facing = self.facing.rotate(frametime * 10.0);
            },
            .chase => {},
        }
        self.apply_velocity();
    }

    pub fn check_player_spotted(self: *Self, player: Character, occlusions: []rl.Rectangle) void {
        const dist = player.position.subtract(self.position);
        const angle_to_player = std.math.atan2(dist.y, dist.x) * (180.0 / std.math.pi);
        const facing_angle = std.math.atan2(self.facing.y, self.facing.x) * (180.0 / std.math.pi);
        // find angles from -180, 180 degrees

        // find our bounds in degrees
        const half_width_degrees = self.vision_width / 2 * (180.0 / std.math.pi);

        const diff = @abs(angle_to_player - facing_angle);
        const abs_diff = @min(diff, 360 - diff);
        if (abs_diff > half_width_degrees) {
            return;
        }

        for (0..@intFromFloat(self.vision_range)) |i| {
            const marching_position = self.position.moveTowards(player.position, @floatFromInt(i));

            for (occlusions) |occlusion| {
                if (rl.checkCollisionPointRec(marching_position, occlusion)) return;
            }

            const TOLERANCE = 0.01;
            if (marching_position.subtract(player.position).length() < TOLERANCE) {
                self.state = .alert;
                self.velocity = rl.Vector2.zero();
                return;
            }
        }
    }

    fn apply_velocity(self: *Self) void {
        self.position = self.position.add(self.velocity);
    }

    fn increment_patrol_index(self: *Self) void {
        const paths_length = self.patrol_path.items.len;
        const new_index = self.patrol_index + 1;
        if (new_index > paths_length - 1) {
            self.patrol_index = 0;
        } else {
            self.patrol_index = new_index;
        }
    }

    fn vision_triangle(self: Self) [3]rl.Vector2 {
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

    pub fn init(comptime duration: f32) Self {
        return Self{ .duration = duration, .current_time = 0, .finished = false };
    }

    pub fn update(self: *Self, frametime: f32) void {
        if (!self.finished) {
            self.current_time += frametime;
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
