const std = @import("std");
const rl = @import("raylib");
const Ldtk = @import("ldtk.zig").Ldtk;
const character = @import("character.zig");
const ItemPickup = @import("items.zig").ItemPickup;
const Camera = @import("camera.zig").Camera;

pub const Portal = struct {
    position: rl.Vector2,
    width: u32,
    height: u32,
    other: []const u8,
    level: usize,
};

pub const Level = struct {
    invisible: rl.Texture,
    visible: rl.Texture,
    ldtk: Ldtk,
    player: character.Player,
    // [level][]rl.Rectangle
    collisions: [][]rl.Rectangle,
    // [level][]character.Guard
    guards: [][]character.Guard,
    // [level][]ItemPickup
    items: [][]ItemPickup,
    // [level][y][x]bool
    navigation_maps: [][][]bool,

    // [Iid]
    portals: std.StringHashMap(Portal),

    pub fn init(allocator: std.mem.Allocator) !Level {
        var player: character.Player = undefined;
        const ldtk = try Ldtk.init("assets/sample.ldtk");
        var collisions = std.ArrayList([]rl.Rectangle).init(allocator);
        var guards = std.ArrayList([]character.Guard).init(allocator);
        var items = std.ArrayList([]ItemPickup).init(allocator);
        var navigation_maps = std.ArrayList([][]bool).init(allocator);

        //TODO: REFACTOR
        var portals = std.StringHashMap(Portal).init(allocator);

        const tile_width = 8;

        for (ldtk.levels, 0..) |level, level_index| {
            var level_collisions = std.ArrayList(rl.Rectangle).init(allocator);
            var level_guards = std.ArrayList(character.Guard).init(allocator);
            var level_items = std.ArrayList(ItemPickup).init(allocator);
            var navigation_map = std.ArrayList([]bool).init(allocator);
            for (0..@divTrunc(level.pxHei, tile_width)) |_| {
                var row = try std.ArrayList(bool).initCapacity(allocator, @divTrunc(level.pxWid, tile_width));
                row.expandToCapacity();
                try navigation_map.append(try row.toOwnedSlice());
            }
            // Tile Parsing
            var i = level.layerInstances.len;
            while (i > 0) {
                i -= 1;
                const instance = level.layerInstances[i];
                const is_main_layer = std.mem.eql(u8, instance.__identifier, "Main");
                const is_entities = std.mem.eql(u8, instance.__identifier, "Entities");
                if (is_main_layer) {
                    for (instance.intGridCsv, 0..) |id, index| {
                        if (id == 2) {
                            const i32_index: i32 = @as(i32, @intCast(index));
                            const y: i32 = @divFloor(i32_index, instance.__cWid);
                            const x: i32 = @mod(i32_index, instance.__cWid);
                            const tile_world_pos: rl.Vector2 = .{
                                .x = @floatFromInt((x * tile_width) + instance.__pxTotalOffsetX + level.worldX),
                                .y = @floatFromInt((y * tile_width) + instance.__pxTotalOffsetY + level.worldY),
                            };
                            try level_collisions.append(.{ .x = tile_world_pos.x, .y = tile_world_pos.y, .height = tile_width, .width = tile_width });
                        }
                    }
                }

                if (is_entities) {
                    for (instance.entityInstances) |e| {
                        const Case = enum {
                            Guard,
                            Player,
                            Rock,
                            Key,
                            Relic,
                            Portal,
                        };
                        const case = std.meta.stringToEnum(Case, e.__identifier) orelse unreachable;

                        const position: rl.Vector2 = .{
                            .x = @floatFromInt(e.px[0] + instance.__pxTotalOffsetX + level.worldX),
                            .y = @floatFromInt(e.px[1] + instance.__pxTotalOffsetY + level.worldY),
                        };
                        switch (case) {
                            .Guard => {
                                var patrol_path = std.ArrayList(rl.Vector2).init(allocator);
                                const field_instance_value = try e.fieldInstances[0].parse_value();
                                for (field_instance_value.points) |v| {
                                    const offset_x = instance.__pxTotalOffsetX + level.worldX;
                                    const offset_y = instance.__pxTotalOffsetY + level.worldY;
                                    try patrol_path.append(rl.Vector2{ .x = @floatFromInt(v.cx * tile_width + offset_x), .y = @floatFromInt(v.cy * tile_width + offset_y) });
                                }
                                try level_guards.append(try character.Guard.init(allocator, position, try patrol_path.toOwnedSlice()));
                            },
                            .Player => {
                                player = character.Player.init(position);
                            },
                            .Rock => {
                                try level_items.append(.{ .item_type = .rock, .position = position });
                            },
                            .Key => {
                                try level_items.append(.{ .item_type = .key, .position = position });
                            },
                            .Relic => {
                                try level_items.append(.{ .item_type = .relic, .position = position });
                            },
                            .Portal => {
                                const field_instance_value = try e.fieldInstances[0].parse_value();
                                try portals.put(e.iid, .{
                                    .position = position,
                                    .other = field_instance_value.entity_ref.entityIid,
                                    .width = e.width,
                                    .height = e.height,
                                    .level = level_index, // naive
                                });
                            },
                        }
                    }
                }
            }
            for (level_collisions.items) |collision| {
                const x: usize = @intFromFloat(@divTrunc(collision.x - @as(f32, @floatFromInt(level.worldX)), tile_width));
                const y: usize = @intFromFloat(@divTrunc(collision.y - @as(f32, @floatFromInt(level.worldY)), tile_width));

                navigation_map.items[y][x] = true;
            }

            try navigation_maps.append(try navigation_map.toOwnedSlice());
            try collisions.append(try level_collisions.toOwnedSlice());
            try guards.append(try level_guards.toOwnedSlice());
            try items.append(try level_items.toOwnedSlice());
        }

        return .{
            .ldtk = ldtk,
            .visible = try rl.loadTexture("assets/visible.png"),
            .invisible = try rl.loadTexture("assets/invisible.png"),
            .collisions = try collisions.toOwnedSlice(),
            .guards = try guards.toOwnedSlice(),
            .items = try items.toOwnedSlice(),
            .player = player,
            .navigation_maps = try navigation_maps.toOwnedSlice(),
            .portals = portals,
        };
    }

    /// returns the linked portal
    pub fn use_portal(self: @This(), portal: Portal) Portal {
        return self.portals.get(portal.other) orelse unreachable;
    }

    fn draw_level(self: @This(), camera: Camera, level: usize, tilesheet: rl.Texture) void {
        const tile_width = 8;
        const ldtk_level = self.ldtk.levels[level];
        var i = ldtk_level.layerInstances.len;
        while (i > 0) {
            i -= 1;
            const instance = ldtk_level.layerInstances[i];

            for (instance.autoLayerTiles) |tile| {
                // 'coercing' error into null, so that we can easily null-check for ease of use.
                // might indicate that we want bound_check to return null instead of error type hm...
                const tile_world_pos: rl.Vector2 = .{
                    .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + ldtk_level.worldX),
                    .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + ldtk_level.worldY),
                };
                if (camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                    const flip_x = (tile.f == 1 or tile.f == 3);
                    const flip_y = (tile.f == 2 or tile.f == 3);
                    rl.drawTexturePro(
                        tilesheet,
                        .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                        .{ .x = camera_pos.x, .y = camera_pos.y, .width = tile_width, .height = tile_width },
                        rl.Vector2.zero(),
                        0,
                        rl.Color.white,
                    );
                }
            }
            for (instance.gridTiles) |tile| {
                const tile_world_pos: rl.Vector2 = .{
                    .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + ldtk_level.worldX),
                    .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + ldtk_level.worldY),
                };
                if (camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                    const flip_x = (tile.f == 1 or tile.f == 3);
                    const flip_y = (tile.f == 2 or tile.f == 3);
                    rl.drawTexturePro(
                        tilesheet,
                        .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                        .{ .x = camera_pos.x, .y = camera_pos.y, .width = tile_width, .height = tile_width },
                        rl.Vector2.zero(),
                        0,
                        rl.Color.white,
                    );
                }
            }
        }
    }

    pub fn draw_visible(self: @This(), camera: Camera, level: usize) void {
        self.draw_level(camera, level, self.visible);
    }

    pub fn draw_invisible(self: @This(), camera: Camera, level: usize) void {
        self.draw_level(camera, level, self.invisible);
    }

    pub fn draw_occlusion(self: @This(), camera: Camera, level: usize) void {
        for (self.collisions[level]) |collision| {
            if (camera.bound_check(.{ .x = collision.x, .y = collision.y }) catch null) |camera_pos| {
                rl.drawRectangleRec(.{ .x = camera_pos.x, .y = camera_pos.y, .width = collision.width, .height = collision.width }, rl.Color.black);
            }
        }
    }

    pub fn draw_navigation_map(self: @This()) void {
        for (self.navigation_maps) |level| {
            for (level, 0..) |row, y| {
                for (row, 0..) |col, x| {
                    if (col) rl.drawRectangle(
                        @intCast(x * 8),
                        @intCast(y * 8),
                        8,
                        8,
                        rl.Color.white,
                    );
                }
            }
        }
    }

    pub fn get_bounds(self: @This(), level: usize) rl.Rectangle {
        const lvl = self.ldtk.levels[level];
        return .{
            .x = @floatFromInt(lvl.worldX),
            .y = @floatFromInt(lvl.worldY),
            .width = @floatFromInt(lvl.pxWid),
            .height = @floatFromInt(lvl.pxHei),
        };
    }
};
