const std = @import("std");
const rl = @import("raylib");
const util = @import("utils.zig");
const items = @import("items.zig");
const Path = @import("path.zig").Path;

pub const PlayerActionStateTags = enum {
    normal,
    throwing,
    stunned,
};

pub const PlayerActionState = union(PlayerActionStateTags) {
    normal,
    throwing,
    stunned: Timer,
};

pub const PlayerHeldItem = union(items.Item) { none, rock: *items.ItemPickup, key: *items.ItemPickup };

pub const StunStar = struct {
    position: rl.Vector2,
    ttl: f32,

    const Self = @This();
};

pub const Player = struct {
    position: rl.Vector2,
    base_speed: f32 = 80,
    radius: f32 = 4,
    action_state: PlayerActionState = .normal,
    min_throw_strength: f32 = 10,
    max_throw_strength: f32 = 100,
    current_throw_strength: f32 = 10,
    throw_charge_timer: Timer = Timer.init(1.5),
    held_item: PlayerHeldItem = .none,
    cursor_position: rl.Vector2 = .{ .x = 0, .y = 0 },
    collision_detected: bool = false,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    color: rl.Color = rl.Color.sky_blue,
    animation_t: f32 = 0,
    over_item: items.Item = .none,

    const Self = @This();

    pub fn init(position: rl.Vector2) Self {
        return .{ .position = position };
    }

    fn calculate_velocity(self: *Self, frametime: f32) void {
        switch (self.action_state) {
            .stunned => |*stunned_timer| {
                self.velocity = rl.Vector2.zero();
                stunned_timer.*.update(frametime);
                if (stunned_timer.finished) {
                    self.action_state = .normal;
                }
            },
            else => {
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
                velo_normalized.x *= (self.speed() * frametime);
                velo_normalized.y *= (self.speed() * frametime);
                self.velocity = velo_normalized;
                if (self.velocity.length() > 0) self.facing = self.facing.lerp(self.velocity, frametime * 10);
            },
        }
    }

    pub fn throw_strength(self: Self) f32 {
        return std.math.lerp(self.min_throw_strength, self.max_throw_strength, self.throw_charge_timer.progress());
    }

    pub fn throw_item(self: *Self, frametime: f32) void {
        switch (self.held_item) {
            .rock => |*item| {
                item.*.position = self.position;
                const throw_direction = self.cursor_position.subtract(self.position).normalize();
                const throw_velocity = throw_direction.scale(frametime * self.throw_strength() * 2.5);
                item.*.state = items.ItemState{ .moving = .{ .velocity = throw_velocity, .ricochets = 0 } };
                self.held_item = .none;
            },
            .key => |*item| {
                item.*.position = self.position;
                const throw_direction = self.cursor_position.subtract(self.position).normalize();
                const throw_velocity = throw_direction.scale(frametime * self.throw_strength() * 2.5);
                item.*.state = items.ItemState{ .moving = .{ .velocity = throw_velocity, .ricochets = 0 } };
                self.held_item = .none;
            },
            else => {},
        }
    }

    pub fn handle_action_state(self: *Self, frametime: f32) void {
        if (self.is_actionable()) {
            if (rl.isMouseButtonDown(.left) and self.held_item != .none) {
                self.action_state = .throwing;
                self.throw_charge_timer.update(frametime);
            } else {
                if (self.action_state == .throwing) {
                    self.throw_item(frametime);
                }
                self.action_state = .normal;
                self.throw_charge_timer.reset();
            }
        }
    }

    pub fn speed(self: Self) f32 {
        switch (self.action_state) {
            .throwing => return self.base_speed * 0.5,
            else => return self.base_speed,
        }
    }

    pub fn is_actionable(self: Self) bool {
        return self.action_state != .stunned;
    }

    pub fn charging_throw(self: Self) bool {
        return .throwing == self.action_state and .none != self.held_item;
    }

    pub fn drop_current_item(self: *Self) void {
        switch (self.held_item) {
            .rock => |*item| {
                item.*.position = self.position;
                const throw_direction = self.cursor_position.subtract(self.position).normalize();
                const throw_velocity = throw_direction.scale(20);
                item.*.state = items.ItemState{ .moving = .{ .velocity = throw_velocity, .ricochets = 0 } };
                self.held_item = .none;
            },
            else => {},
        }
    }

    pub fn update(self: *Self, collisions: []rl.Rectangle, items_in_scene: []items.ItemPickup, frametime: f32, cursor_position: rl.Vector2) void {
        self.cursor_position = cursor_position;
        self.calculate_velocity(frametime);
        self.handle_action_state(frametime);
        // Collide with Tiles
        for (collisions) |collision| {
            const projected = self.projected_position();
            if (rl.checkCollisionCircleRec(.{ .x = projected.x, .y = self.position.y }, self.radius * 0.5, collision)) {
                self.velocity.x = 0;
            }
            if (rl.checkCollisionCircleRec(.{ .x = self.position.x, .y = projected.y }, self.radius * 0.5, collision)) {
                self.velocity.y = 0;
            }
        }

        // Item Interactions
        var item_collision_count: u8 = 0;
        for (items_in_scene) |*item| {
            if (rl.checkCollisionCircles(self.position, self.radius, item.center(), item.pickup_radius())) {
                item_collision_count += 1;
                switch (item.state) {
                    // Pickup items logic
                    .dormant => {
                        self.over_item = item.item_type;
                        if (rl.isKeyPressed(.e)) {
                            if (self.held_item != .none) {
                                self.drop_current_item();
                            }
                            item.pickup();
                            switch (item.item_type) {
                                .rock => {
                                    self.held_item = .{ .rock = item };
                                },
                                .key => {
                                    self.held_item = .{ .key = item };
                                },
                                else => {},
                            }
                        }
                    },
                    // Getting hit by a ricochet
                    .moving => |*moving_item| {
                        if (moving_item.ricochets > 0 and moving_item.velocity.length() > 1) {
                            const item_projected_position: rl.Vector2 = item.position.add(moving_item.velocity);
                            if (rl.checkCollisionCircles(self.projected_position(), self.radius * 0.5, item_projected_position, 3)) {
                                moving_item.*.velocity = moving_item.velocity.scale(-1);
                                moving_item.*.ricochets += 1;
                                self.action_state = .{ .stunned = Timer.init(0.5) };
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        if (item_collision_count == 0) {
            self.over_item = .none;
        }
        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;

        if (self.charging_throw()) {
            self.facing = cursor_position.subtract(self.position).normalize();
        }

        const adjusted_frametime = blk: {
            switch (self.action_state) {
                .throwing => break :blk 0.5 * frametime,
                else => break :blk frametime,
            }
        };
        self.animation_t += adjusted_frametime;
    }

    pub fn debug_player(self: Self) !void {
        var buf: [1000]u8 = undefined;
        const output = try std.fmt.bufPrintZ(&buf, "Velocity: [{d:.2},{d:.2}]\nPosition: [{d:.2},{d:.2}]\nCollision Check: {}\nFacing: [{d:.2}, {d:.2}]", .{ self.velocity.x, self.velocity.y, self.position.x, self.position.y, self.collision_detected, self.facing.x, self.facing.y });
        rl.drawText(output, 2, 50, 24, rl.Color.dark_blue);
    }

    pub fn projected_position(self: Self) rl.Vector2 {
        return self.position.add(self.velocity);
    }

    pub fn draw(self: Self, camera_offset: rl.Vector2) void {
        const pos_on_camera = self.position.subtract(camera_offset);

        const rotation_degrees = std.math.atan2(self.facing.y, self.facing.x) * (180.0 / std.math.pi);
        rl.drawRectanglePro(.{ .x = pos_on_camera.x, .y = pos_on_camera.y, .height = 8, .width = 8 }, .{ .x = 4, .y = 4 }, rotation_degrees, self.color);

        // NOTE: if we don't take the abs value of the head, it will go 'faaar' back. It looks cool! but not the way we usually walk...
        // probably fits well if we are 'sneaking' or 'crouching' or something
        const t = @abs(std.math.cos(self.animation_t * 15 * self.velocity.length()));
        // draw head
        rl.drawRectanglePro(.{ .x = pos_on_camera.x, .y = pos_on_camera.y, .height = 4, .width = 4 }, .{ .x = 2 - t * 2, .y = 2 }, rotation_degrees, rl.Color.black);
        if (self.held_item != .none and self.action_state == .throwing) {
            const end_point = self.position.add(self.facing.scale(self.throw_strength())).subtract(camera_offset);
            rl.drawLineV(pos_on_camera, end_point, rl.Color.red);
        }
    }
};

pub const GuardStateTag = enum { moving, waiting, alert, chase, search, stunned };
pub const GuardState = union(GuardStateTag) { moving, waiting, alert, chase, search, stunned: Timer };

const Intuition = struct {
    rect: rl.Rectangle,
    color: rl.Color,
    ttl: f32,
};

pub const Guard = struct {
    position: rl.Vector2,
    velocity: rl.Vector2 = .{ .x = 0, .y = 0 },
    facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    start_facing: rl.Vector2 = .{ .x = 0, .y = 1 },
    radius: f32 = 6,
    vision_range: f32 = 60,
    vision_width: f32 = 1.5,
    state: GuardState = .waiting,
    // Patrol behavior
    patrol_points: std.ArrayList(rl.Vector2),
    patrol_point_index: usize = 0,
    wait_timer: Timer = Timer.init(1),
    turning_timer: Timer = Timer.init(0.35),
    alert_timer: Timer = Timer.init(0.55),
    // Chase behavior
    last_sighted: rl.Vector2 = .{ .x = 0, .y = 0 },
    animation_t: f32 = 0,

    chase_path: Path = undefined,
    chase_index: usize = 0,

    patrol_path: Path = undefined,
    patrol_index: usize = 0,

    intuitions: std.ArrayList(Intuition),
    intuition_t: i32 = 0,
    searching_timer: Timer = Timer.init(2),

    const Self = @This();
    const CHASE_SPEED = 45;
    const PATROL_SPEED = 20;

    pub fn init(allocator: std.mem.Allocator, position: rl.Vector2, patrol_points: []rl.Vector2) !Self {
        var patrol_path = std.ArrayList(rl.Vector2).init(allocator);
        for (patrol_points) |p| {
            try patrol_path.append(p);
        }

        return Self{ .position = position, .patrol_points = patrol_path, .intuitions = std.ArrayList(Intuition).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.patrol_path.deinit();
    }

    pub fn update(self: *Self, player: Player, items_in_scene: []items.ItemPickup, occlusions: []rl.Rectangle, navmap: [][]bool, level_offset: rl.Vector2, frametime: f32) void {
        self.check_player_spotted(player, occlusions);
        self.wait_timer.update(frametime);
        self.turning_timer.update(frametime);
        self.searching_timer.update(frametime);
        self.update_intuition(frametime);
        // Item Interactions
        for (items_in_scene) |*item| {
            if (rl.checkCollisionCircles(self.position, self.radius, item.position, item.pickup_radius())) {
                switch (item.state) {
                    // Getting hit by a ricochet
                    .moving => |*moving_item| {
                        if (moving_item.velocity.length() > 1) {
                            const item_projected_position: rl.Vector2 = item.position.add(moving_item.velocity);
                            if (rl.checkCollisionCircles(self.position, self.radius * 0.5, item_projected_position, 3)) {
                                moving_item.*.velocity = moving_item.velocity.scale(-1);
                                moving_item.*.ricochets += 1;
                                self.state = .{ .stunned = Timer.init(1.5) };
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        switch (self.state) {
            .moving => {
                self.try_add_intuition(rl.Color.light_gray);
                if (self.patrol_index >= self.patrol_path.path.len) {
                    const end_path_position = self.patrol_points.items[self.patrol_point_index];
                    self.patrol_path = Path.find(std.heap.page_allocator, navmap, Path.from_world_space_to_path_space(self.position.subtract(level_offset)), Path.from_world_space_to_path_space(end_path_position.subtract(level_offset))) catch unreachable;
                    self.patrol_index = 0;

                    self.wait_timer.reset();
                    self.state = .waiting;
                    self.start_facing = self.facing;
                    self.increment_patrol_point_index();
                } else {
                    const target_position = Path.from_path_space_to_world_space(self.patrol_path.path[self.patrol_index]).add(level_offset).addValue(4);
                    if (self.position.distance(target_position) <= self.velocity.length()) {
                        self.patrol_index = self.patrol_index + 1;
                        self.start_facing = self.facing;
                        self.turning_timer.reset();
                    } else {
                        const delta = target_position.subtract(self.position).normalize();
                        const progress = self.turning_timer.current_time / self.turning_timer.duration;
                        const f = util.ease_in_out_back(progress);
                        self.facing.x = std.math.lerp(self.start_facing.x, delta.x, f);
                        self.facing.y = std.math.lerp(self.start_facing.y, delta.y, f);
                        self.velocity = delta.scale(PATROL_SPEED * frametime);
                    }
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
                self.alert_timer.update(frametime);
                if (self.alert_timer.finished) {
                    self.state = .chase;

                    const path = Path.find(
                        std.heap.page_allocator,
                        navmap,
                        Path.from_world_space_to_path_space(self.position.subtract(level_offset)),
                        Path.from_world_space_to_path_space(self.last_sighted.subtract(level_offset)),
                    ) catch {
                        self.state = .moving;
                        return;
                    };
                    self.chase_path = path;
                    self.patrol_index = 0;
                }
            },
            .search => {
                if (self.searching_timer.finished) {
                    self.state = .moving;
                    self.start_facing = self.facing;
                    self.turning_timer.reset();
                }
                self.velocity = rl.Vector2.zero();
                const p = self.searching_timer.progress();
                const t = util.ease_in_out(p); // this sucks, but i tried for an hour to improve it and i can't make it nice :(
                self.facing = self.start_facing.rotate(std.math.sin(std.math.pi * 2 * t) * 1.5);
            },
            .stunned => |*stun_timer| {
                stun_timer.*.update(frametime);
                if (stun_timer.finished) {
                    self.searching_timer.reset();
                    self.state = .search;
                }
            },
            .chase => {
                self.try_add_intuition(rl.Color.red);
                if (self.chase_index >= self.chase_path.path.len) {
                    self.state = .search;
                    self.start_facing = self.facing;
                    self.searching_timer.reset();
                    const path = Path.find(
                        std.heap.page_allocator,
                        navmap,
                        Path.from_world_space_to_path_space(self.position.subtract(level_offset)),
                        Path.from_world_space_to_path_space(self.patrol_points.items[(self.patrol_point_index + self.patrol_points.items.len - 1) % self.patrol_points.items.len].subtract(level_offset)),
                    ) catch {
                        self.state = .moving;
                        return;
                    };
                    self.patrol_path = path;
                    self.patrol_index = 0;
                } else {
                    const target_position = Path.from_path_space_to_world_space(self.chase_path.path[self.chase_index]).addValue(4).add(level_offset);
                    const end_position = Path.from_path_space_to_world_space(self.chase_path.path[self.chase_path.path.len - 1]).add(level_offset);
                    if (self.position.distance(target_position) <= self.velocity.length()) {
                        self.chase_index = self.chase_index + 1;
                        self.position = target_position;

                        if (self.last_sighted.distance(end_position) >= 16) {
                            const path = Path.find(
                                std.heap.page_allocator,
                                navmap,
                                Path.from_world_space_to_path_space(self.position.subtract(level_offset)),
                                Path.from_world_space_to_path_space(self.last_sighted.subtract(level_offset)),
                            ) catch {
                                self.state = .moving;
                                return;
                            };
                            self.chase_path = path;
                            self.chase_index = 1;
                        }
                    } else {
                        const delta = target_position.subtract(self.position).normalize();
                        self.facing = self.facing.lerp(self.velocity, frametime * 10);
                        self.velocity = delta.scale(CHASE_SPEED * frametime);
                    }
                }
            },
        }
        if (self.state != .stunned) {
            self.apply_velocity();
        }
        self.animation_t += frametime;
    }

    pub fn check_player_spotted(self: *Self, player: Player, occlusions: []rl.Rectangle) void {
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
                switch (self.state) {
                    .chase, .alert => {},
                    else => {
                        self.state = .alert;
                        self.alert_timer.reset();
                        self.velocity = rl.Vector2.zero();
                    },
                }
                self.last_sighted = player.position;
                return;
            }
        }
    }

    fn apply_velocity(self: *Self) void {
        self.position = self.position.add(self.velocity);
    }

    fn increment_patrol_point_index(self: *Self) void {
        const paths_length = self.patrol_points.items.len;
        const new_index = self.patrol_point_index + 1;
        if (new_index > paths_length - 1) {
            self.patrol_point_index = 0;
        } else {
            self.patrol_point_index = new_index;
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
        const pos_on_camera = self.position.subtract(camera_offset);
        if (self.state != .stunned) {
            const vt = self.vision_triangle();
            const tvt = [3]rl.Vector2{ vt[0].subtract(camera_offset), vt[1].subtract(camera_offset), vt[2].subtract(camera_offset) };
            rl.drawTriangle(tvt[2], tvt[1], tvt[0], rl.Color.yellow.alpha(0.6));
        }

        const rotation_degrees = std.math.atan2(self.facing.y, self.facing.x) * (180.0 / std.math.pi);
        rl.drawRectanglePro(.{ .x = pos_on_camera.x, .y = pos_on_camera.y, .height = 8, .width = 8 }, .{ .x = 4, .y = 4 }, rotation_degrees, rl.Color.red);

        const t = @abs(std.math.cos(self.animation_t * 18 * self.velocity.length()));
        // draw head
        rl.drawRectanglePro(.{ .x = pos_on_camera.x, .y = pos_on_camera.y, .height = 4, .width = 4 }, .{ .x = 2 - t * 2, .y = 2 }, rotation_degrees, rl.Color.black);
    }

    pub fn draw_intuition(self: Self, camera_offset: rl.Vector2) void {
        for (self.intuitions.items) |intuition| {
            var rect = intuition.rect;
            rect.x -= camera_offset.x;
            rect.y -= camera_offset.y;
            rl.drawRectangleRec(rect, intuition.color);
        }
    }

    fn try_add_intuition(self: *Self, comptime color: rl.Color) void {
        if (self.intuition_t > 0) return;
        const base_position = self.position;
        const f: f32 = @floatCast(rl.getTime() * 240);
        var offset = self.velocity;
        const foot_offset = blk: {
            if (std.math.sin(f) > 0.0) {
                break :blk offset.rotate(45 * (180.0 / std.math.pi));
            } else {
                break :blk offset.rotate(-45 * (180.0 / std.math.pi));
            }
        };

        const position = base_position.add(foot_offset.scale(3));
        self.intuitions.append(.{
            .rect = .{ .x = position.x, .y = position.y, .width = 2, .height = 2 },
            .color = color,
            .ttl = 1,
        }) catch {};

        self.intuition_t = 15;
    }

    pub fn draw_debug(self: Self, camera_offset: rl.Vector2, level_offset: rl.Vector2) void {
        const total_offset = camera_offset.subtract(level_offset);
        switch (self.state) {
            .chase => self.chase_path.draw_debug_lines(total_offset, rl.Color.red),
            .moving => if (self.patrol_path.path.len > 0) self.patrol_path.draw_debug_lines(total_offset, rl.Color.blue),
            else => {},
        }

        const pos = self.position.subtract(camera_offset);
        const tag = std.enums.tagName(GuardStateTag, self.state) orelse "invalid";
        rl.drawText(@ptrCast(tag.ptr), @intFromFloat(pos.x), @intFromFloat(pos.y), 1, rl.Color.black);
    }

    fn update_intuition(self: *Self, frametime: f32) void {
        self.intuition_t = @max(0, self.intuition_t - 1);

        var i: usize = self.intuitions.items.len;
        while (i > 0) {
            i -= 1;
            var intuition = &self.intuitions.items[i];

            intuition.ttl = @max(intuition.ttl - frametime, 0);
            if (intuition.ttl == 0) {
                _ = self.intuitions.orderedRemove(i);
            }

            intuition.color.a = @as(u8, @min(255, @as(u64, @intFromFloat(intuition.ttl * 255))));
        }
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

    pub fn progress(self: Self) f32 {
        return self.current_time / self.duration;
    }

    pub fn reset(self: *Self) void {
        self.current_time = 0;
        self.finished = false;
    }
};
