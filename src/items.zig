const rl = @import("raylib");

pub const ItemPickup = struct {
    item_type: Item,
    position: rl.Vector2,
    state: ItemState = .dormant,

    const Self = @This();

    pub fn update(self: *Self, collisions: []rl.Rectangle) void {
        switch (self.state) {
            .moving => |*velocity| {
                for (collisions) |collision| {
                    const projected_x = self.position.add(.{ .x = velocity.x, .y = 0 });
                    const projected_y = self.position.add(.{ .x = 0, .y = velocity.y });
                    if (rl.checkCollisionCircleRec(projected_x, 3, collision)) {
                        velocity.*.x *= -1;
                    }
                    if (rl.checkCollisionCircleRec(projected_y, 3, collision)) {
                        velocity.*.y *= -1;
                    }
                }
                self.position = self.position.add(velocity.*);
                velocity.* = velocity.*.scale(0.98);
                if (velocity.length() <= 1.0) {
                    self.state = .dormant;
                }
            },
            else => {},
        }
    }

    pub fn draw(self: Self, camera_offset: rl.Vector2) void {
        const pos_on_camera = self.position.subtract(camera_offset);
        if (self.state != .held) {
            switch (self.item_type) {
                .rock => rl.drawCircleV(pos_on_camera, 3.0, rl.Color.light_gray),
                else => return,
            }
        }
    }

    pub fn pickup(self: *Self) void {
        self.state = .held;
    }

    pub fn pickup_radius(self: *Self) f32 {
        switch (self.item_type) {
            .rock => return 20,
            .key => return 20,
            .none => return 0,
        }
    }
};

pub const ItemStateTags = enum {
    held,
    dormant,
    moving,
};

pub const ItemState = union(ItemStateTags) {
    held,
    dormant,
    moving: rl.Vector2,
};

pub const Item = enum {
    none,
    rock,
    key,

    pub fn is_throwable(self: @This()) bool {
        switch (self) {
            .rock => return true,
            else => return false,
        }
    }
};
