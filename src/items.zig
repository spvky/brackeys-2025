const rl = @import("raylib");

pub const ItemPickup = struct {
    item_type: Item,
    position: rl.Vector2,
    held: bool = false,

    const Self = @This();

    pub fn draw(self: Self, camera_offset: rl.Vector2) void {
        const pos_on_camera = self.position.subtract(camera_offset);
        if (!self.held) {
            switch (self.item_type) {
                .rock => rl.drawCircleV(pos_on_camera, 3.0, rl.Color.light_gray),
                else => return,
            }
        }
    }

    pub fn pickup(self: *Self) Item {
        self.held = true;
    }
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
