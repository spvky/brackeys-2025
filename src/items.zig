const std = @import("std");
const rl = @import("raylib");
const SoundBank = @import("audio.zig").SoundBank;
const UiAssets = @import("ui.zig").UiAssets;

pub const ItemPickup = struct {
    item_type: Item,
    position: rl.Vector2,
    state: ItemState = .dormant,

    const Self = @This();

    pub fn update(
        self: *Self,
        collisions: []rl.Rectangle,
        sound_bank: SoundBank,
    ) void {
        const position = self.center();
        switch (self.state) {
            .moving => |*moving_item| {
                var velocity = moving_item.velocity;
                var ricochets: u8 = moving_item.ricochets;
                for (collisions) |collision| {
                    const projected_x = position.add(.{ .x = velocity.x, .y = 0 });
                    const projected_y = position.add(.{ .x = 0, .y = velocity.y });
                    var ricocheted = false;
                    if (rl.checkCollisionCircleRec(projected_x, 3, collision)) {
                        velocity.x *= -1;
                        ricocheted = true;
                    }
                    if (rl.checkCollisionCircleRec(projected_y, 3, collision)) {
                        velocity.y *= -1;
                        ricocheted = true;
                    }
                    if (ricocheted) {
                        ricochets = ricochets + 1;
                        self.hit_sound(sound_bank);
                    }
                }
                self.position = self.position.add(velocity);
                velocity = velocity.scale(0.98);
                if (velocity.length() <= 1.0) {
                    self.state = .dormant;
                } else {
                    self.state = .{ .moving = .{ .velocity = velocity, .ricochets = ricochets } };
                }
            },
            else => {},
        }
    }

    pub fn hit_sound(self: Self, sound_bank: SoundBank) void {
        switch (self.item_type) {
            .rock => rl.playSound(sound_bank.rock),
            .key => rl.playSound(sound_bank.key),
            .relic => rl.playSound(sound_bank.relic),
            else => {},
        }
    }

    pub fn center(self: Self) rl.Vector2 {
        return self.position.add(.{ .x = 8, .y = 8 });
    }

    pub fn draw(self: Self, ui_assets: UiAssets, camera_offset: rl.Vector2, level_index: usize) void {
        const pos_on_camera = self.position.subtract(camera_offset);
        if (self.state != .held) {
            var scale: f32 = 0.8;
            if (self.state == .dormant) {
                const f: f32 = @floatCast(rl.getTime() * 4);
                scale = 0.8 + (std.math.sin(f) / 10);
            }
            switch (self.item_type) {
                .rock => rl.drawTextureEx(ui_assets.rock, pos_on_camera, 0, scale, rl.Color.white),
                .key => rl.drawTextureEx(ui_assets.key, pos_on_camera, 0, scale, rl.Color.white),
                .relic => {
                    switch (level_index) {
                        0 => rl.drawTextureEx(ui_assets.relic_1, pos_on_camera, 0, scale, rl.Color.white),
                        else => {},
                    }
                },
                else => return,
            }
            if (self.state == .dormant) {}
        }
    }

    pub fn pickup(self: *Self) void {
        self.state = .held;
    }

    pub fn pickup_radius(self: *Self) f32 {
        switch (self.item_type) {
            .rock => return 3,
            .key => return 3,
            .relic => return 3,
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
    moving: MovingItem,
};

pub const MovingItem = struct { velocity: rl.Vector2, ricochets: u8 };

pub const Item = enum {
    none,
    rock,
    key,
    relic,
};
