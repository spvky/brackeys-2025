const std = @import("std");
const rl = @import("raylib");
const Player = @import("character.zig").Player;
const Item = @import("items.zig").Item;

pub const UiAssets = struct {
    held_item: rl.Texture,
    rock: rl.Texture,
    key: rl.Texture,
    relic_1: rl.Texture,

    pub fn init() !@This() {
        return .{
            .held_item = try rl.loadTexture("assets/ui/held_item.png"),
            .rock = try rl.loadTexture("assets/ui/rock.png"),
            .key = try rl.loadTexture("assets/ui/key.png"),
            .relic_1 = try rl.loadTexture("assets/ui/relic_1.png"),
        };
    }
};

pub const UiState = struct {
    pub fn draw(player: Player, ui_assets: UiAssets, level_index: usize) void {
        rl.drawTextureEx(ui_assets.held_item, .{ .x = 5, .y = 20 }, 0, 4.5, rl.Color.white);

        UiState.draw_pickup_text(player);
        switch (player.held_item) {
            .rock => {
                rl.drawTextureEx(ui_assets.rock, .{ .x = 5, .y = 20 }, 0, 4.5, rl.Color.white);
            },
            .key => {
                rl.drawTextureEx(ui_assets.key, .{ .x = 5, .y = 20 }, 0, 4.5, rl.Color.white);
            },
            .relic => {
                switch (level_index) {
                    0 => rl.drawTextureEx(ui_assets.relic_1, .{ .x = 5, .y = 20 }, 0, 4.5, rl.Color.white),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn draw_pickup_text(player: Player) void {
        if (player.over_item != .none) {
            const tag = std.enums.tagName(Item, player.over_item) orelse "invalid";
            const screen_width: i32 = rl.getScreenWidth();
            const screen_height: i32 = rl.getScreenHeight();

            const insctruction_width = rl.measureText("press [E] to pick up", 50);
            const item_type_width = rl.measureText(@ptrCast(tag.ptr), 50);

            const mid_point: i32 = @divTrunc(screen_width, 2);

            const insctruction_x_pos = mid_point - @divTrunc(insctruction_width, 2);
            const item_type_x_pos = mid_point - @divTrunc(item_type_width, 2);

            const instruction_y_pos: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(screen_height)) * 0.85));
            const item_type_y_pos: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(screen_height)) * 0.9));

            rl.drawText("press [E] to pick up", insctruction_x_pos, instruction_y_pos, 50, rl.Color.black);
            rl.drawText(@ptrCast(tag.ptr), item_type_x_pos, item_type_y_pos, 50, rl.Color.black);
        }
    }
};
