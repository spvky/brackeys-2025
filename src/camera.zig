const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");

const RENDER_WIDTH = consts.RENDER_WIDTH;
const RENDER_HEIGHT = consts.RENDER_HEIGHT;

pub const Camera = struct {
    offset: rl.Vector2,
    target_world_pos: rl.Vector2,

    const PADDING_PX = 20;
    const PANNING_DELAY = 12;

    pub fn init() Camera {
        return .{
            .offset = rl.Vector2.zero(),
            .target_world_pos = rl.Vector2.zero(),
        };
    }

    pub fn get_pos_on_camera(self: @This(), pos: rl.Vector2) rl.Vector2 {
        return pos.subtract(self.offset);
    }

    pub fn set_target(self: *@This(), target: rl.Vector2, bounds: rl.Rectangle) void {
        var t = target;
        t.x = @max(t.x, bounds.x);
        t.x = @min(t.x, bounds.x + bounds.width);

        t.y = @max(t.y, bounds.y);
        t.y = @min(t.y, bounds.y + bounds.height);
        self.target_world_pos = t;
    }

    pub fn update(self: *@This()) void {
        self.offset = self.offset.add(self.target_world_pos.subtract(self.offset).divide(.{ .x = PANNING_DELAY, .y = PANNING_DELAY }));
    }

    /// returns the position if succesful, raises 'OutOfBounds' if pos is out of bounds
    pub fn bound_check(self: @This(), pos: rl.Vector2) !rl.Vector2 {
        const camera_pos = pos.subtract(self.offset);
        if (camera_pos.x > RENDER_WIDTH + PADDING_PX or camera_pos.x < -PADDING_PX) return error.OutOfBounds;
        if (camera_pos.y > RENDER_HEIGHT + PADDING_PX or camera_pos.y < -PADDING_PX) return error.OutOfBounds;

        return camera_pos;
    }
};
