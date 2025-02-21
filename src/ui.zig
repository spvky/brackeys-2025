const std = @import("std");
const rl = @import("raylib");
const Player = @import("character.zig").Player;

const UiAssets = struct {
    held_item: rl.Texture,
    rock: rl.Texture,

    pub fn init() !@This() {
        return .{
            .held_item = try rl.loadTexture("assets/ui/held_item.png"),
            .rock = try rl.loadTexture("assets/ui/rock.png"),
        };
    }
};

pub const UiState = struct {
    ui_assets: UiAssets,

    const Self = @This();

    pub fn init() !Self {
        return .{ .ui_assets = try UiAssets.init() };
    }

    pub fn draw(self: Self, player: Player) void {
        rl.drawTextureEx(self.ui_assets.held_item, .{ .x = 5, .y = 20 }, 0, 4.5, rl.Color.white);

        switch (player.held_item) {
            .rock => {
                rl.drawTextureEx(self.ui_assets.rock, .{ .x = 5, .y = 20 }, 0, 4.5, rl.Color.white);
            },
            else => {},
        }
    }
};
