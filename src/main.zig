const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const Ldtk = @import("ldtk.zig").Ldtk;
const Path = @import("path.zig").Path;
const ItemPickup = @import("items.zig").ItemPickup;

var WINDOW_WIDTH: i32 = 1080;
var WINDOW_HEIGHT: i32 = 720;

const RENDER_WIDTH: i32 = 240;
const RENDER_HEIGHT: i32 = 160;
const TITLE = "brackeys 2025";

const Particle = struct {
    rect: rl.Rectangle,
    color: rl.Color,
    velocity: rl.Vector2,
    ttl: f32,
};

const State = struct {
    /// the scene we draw to, it's dimensions are static
    scene: rl.RenderTexture,
    /// the version of the scene which is not visible
    invisible_scene: rl.RenderTexture,
    /// the mask which decides what are occluders
    occlusion_mask: rl.RenderTexture,
    /// the final render texture that is upscaled and shown to the player
    render_texture: rl.RenderTexture,
    camera: Camera,
    level: Level,
    particles: std.ArrayList(Particle),
    frame_count: u32 = 0,
};

/// spawns a particle every 'rate' frames. rate does not need to be comptime but i think it makes it more clear if we treat it as if it is
fn try_spawning_particle(state: *State, base_position: rl.Vector2, base_velocity: rl.Vector2, comptime rate: u8) !void {
    if (state.frame_count % rate == 0) {
        var velocity = base_velocity.scale(-0.1);

        const f: f32 = @floatFromInt(state.frame_count);
        velocity.x += std.math.sin(f) / 20;
        velocity.y += std.math.sin(f) / 20;
        const position: rl.Vector2 = .{
            .x = base_position.x + std.math.sin(f),
            .y = base_position.y + std.math.sin(f),
        };
        try state.particles.append(.{
            .rect = .{ .x = position.x, .y = position.y, .width = 2, .height = 2 },
            .color = rl.Color.ray_white,
            .ttl = 0.15,
            .velocity = velocity.normalize(),
        });
    }
}

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true, .borderless_windowed_mode = true });

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    const monitor = rl.getCurrentMonitor();
    WINDOW_WIDTH = rl.getMonitorWidth(monitor);
    WINDOW_HEIGHT = rl.getMonitorHeight(monitor);

    rl.setWindowSize(WINDOW_WIDTH, WINDOW_WIDTH);

    rl.setTargetFPS(60);

    var state: State = .{
        .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .occlusion_mask = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .render_texture = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .invisible_scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .camera = Camera.init(),
        .level = try Level.init(std.heap.page_allocator),
        .particles = std.ArrayList(Particle).init(std.heap.page_allocator),
    };

    const shader = try rl.loadShader(
        null,
        "assets/shaders/occlusion.fs",
    );

    const size_loc = rl.getShaderLocation(shader, "size");
    const occlusion_mask_loc = rl.getShaderLocation(shader, "occlusion");
    const player_pos_loc = rl.getShaderLocation(shader, "player_pos");
    const invisible_scene_loc = rl.getShaderLocation(shader, "invisible_scene");

    rl.setShaderValue(shader, size_loc, &rl.Vector2{ .x = RENDER_WIDTH, .y = RENDER_HEIGHT }, .vec2);
    while (!rl.windowShouldClose()) {
        var player = &state.level.player;
        const target_pos = player.position.subtract(.{ .x = RENDER_WIDTH / 2, .y = RENDER_HEIGHT / 2 });
        const frametime = rl.getFrameTime();
        var level_bounds = state.level.get_bounds(0);
        level_bounds.width -= RENDER_WIDTH;
        level_bounds.height -= RENDER_HEIGHT;

        state.camera.set_target(target_pos, level_bounds);
        state.camera.update();

        const raw_cursor_position = rl.getMousePosition();
        const render_ratio: f32 = @as(f32, @floatFromInt(RENDER_WIDTH)) / @as(f32, @floatFromInt(WINDOW_WIDTH));
        const cursor_pos = raw_cursor_position.scale(render_ratio).add(state.camera.offset);

        player.update(state.level.collisions, frametime, cursor_pos);
        if (player.velocity.length() > 0) {
            try try_spawning_particle(&state, player.position, player.velocity, 10);
        }

        for (state.level.guards) |*g| {
            g.update(player.*, state.level.collisions, state.level.navigation_maps[0], frametime);
            if (g.velocity.length() > 0) {
                try try_spawning_particle(&state, g.position, g.velocity, 20);
            }
        }

        var i: usize = state.particles.items.len;
        while (i > 0) {
            i -= 1;
            var particle = &state.particles.items[i];

            particle.ttl = @max(particle.ttl - frametime, 0);
            if (particle.ttl == 0) {
                _ = state.particles.orderedRemove(i);
            }

            particle.rect.x += particle.velocity.x;
            particle.rect.y += particle.velocity.y;

            // we need to convert from 0..1 to 0..255.
            // and then we need to clamp between 0..255 because the maximum size of a u8
            // this means that it will step-wise interpolate from 1> -> 255, to 0 -> 0.
            // but our particles live for a very short time so we can accelerate by 30 times.
            particle.color.a = @as(u8, @min(255, @as(u64, @intFromFloat(particle.ttl * 255 * 30))));
        }

        rl.setShaderValue(shader, player_pos_loc, &state.camera.get_pos_on_camera(player.position), .vec2);

        // clearing occlusion mask
        state.occlusion_mask.begin();
        rl.clearBackground(rl.Color.white);
        state.occlusion_mask.end();

        // clearing scene
        state.scene.begin();
        rl.clearBackground(rl.Color.white);
        state.scene.end();

        state.level.draw(
            state.camera,
            state.scene,
            state.invisible_scene,
            state.occlusion_mask,
        );

        state.scene.begin();
        //NOTE: We should draw everything into the scene, and let the shader compose into the render_texture later
        for (state.particles.items) |particle| {
            var rect = particle.rect;
            rect.x -= state.camera.offset.x;
            rect.y -= state.camera.offset.y;
            rl.drawRectangleRec(rect, particle.color);
        }

        player.draw(state.camera.offset, false);
        // Need to draw him normal style
        for (state.level.guards) |guard| {
            guard.draw(state.camera.offset);
        }

        for (state.level.items) |item| {
            item.draw(state.camera.offset);
        }

        state.scene.end();

        state.invisible_scene.begin();
        for (state.level.guards) |g| {
            g.draw_intuition(state.camera.offset);
        }
        state.invisible_scene.end();

        state.render_texture.begin();
        shader.activate();
        rl.setShaderValueTexture(shader, occlusion_mask_loc, state.occlusion_mask.texture);
        rl.setShaderValueTexture(shader, invisible_scene_loc, state.invisible_scene.texture);
        // we draw the scene onto the final render_texture with our shader
        state.scene.texture.draw(0, 0, rl.Color.white);
        shader.deactivate();
        state.render_texture.end();

        rl.beginDrawing();
        rl.drawTexturePro(state.render_texture.texture, .{
            .x = 0,
            .y = 0,
            .width = RENDER_WIDTH,
            .height = RENDER_HEIGHT,
        }, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(WINDOW_WIDTH),
            .height = @floatFromInt(WINDOW_HEIGHT),
        }, rl.Vector2.zero(), 0, rl.Color.white);

        // Ui
        rl.drawFPS(0, 0);
        try player.debug_player();
        rl.endDrawing();
        state.frame_count += 1;
    }
}

const Camera = struct {
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

const Level = struct {
    ldtk: Ldtk,
    invisible: rl.Texture,
    visible: rl.Texture,
    collisions: []rl.Rectangle,
    guards: []character.Guard,
    player: character.Player,
    items: []ItemPickup,
    navigation_maps: [][][]bool,

    pub fn init(allocator: std.mem.Allocator) !Level {
        var player: character.Player = undefined;
        const ldtk = try Ldtk.init("assets/sample.ldtk");
        var collisions = std.ArrayList(rl.Rectangle).init(allocator);
        var guards = std.ArrayList(character.Guard).init(allocator);
        var items = std.ArrayList(ItemPickup).init(allocator);
        var navigation_maps = std.ArrayList([][]bool).init(allocator);

        const tile_width = 8;

        for (ldtk.levels) |level| {
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
                const is_wall = std.mem.eql(u8, instance.__identifier, "Walls");
                const is_entities = std.mem.eql(u8, instance.__identifier, "Entities");
                for (instance.autoLayerTiles) |tile| {
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (is_wall) {
                        try collisions.append(.{ .x = tile_world_pos.x, .y = tile_world_pos.y, .height = 8, .width = 8 });
                    }
                }

                if (is_entities) {
                    for (instance.entityInstances) |e| {
                        const is_guard = std.mem.eql(u8, e.__identifier, "Guard");
                        const is_player = std.mem.eql(u8, e.__identifier, "Player");
                        const is_rock = std.mem.eql(u8, e.__identifier, "Rock");

                        if (is_guard) {
                            const position: rl.Vector2 = .{ .x = @floatFromInt(e.px[0]), .y = @floatFromInt(e.px[1]) };
                            var patrol_path = std.ArrayList(rl.Vector2).init(allocator);
                            for (e.fieldInstances[0].__value) |v| {
                                try patrol_path.append(rl.Vector2{ .x = @floatFromInt(v.cx * 16), .y = @floatFromInt(v.cy * 16) });
                            }
                            try guards.append(try character.Guard.init(allocator, position, try patrol_path.toOwnedSlice()));
                        }
                        if (is_player) {
                            const position: rl.Vector2 = .{ .x = @floatFromInt(e.px[0]), .y = @floatFromInt(e.px[1]) };
                            player = character.Player.init(position);
                        }

                        if (is_rock) {
                            const position: rl.Vector2 = .{ .x = @floatFromInt(e.px[0]), .y = @floatFromInt(e.px[1]) };
                            try items.append(.{ .item_type = .rock, .position = position });
                        }
                    }
                }
            }
            for (collisions.items) |collision| {
                const x: usize = @intFromFloat(@divTrunc(collision.x - @as(f32, @floatFromInt(level.worldX)), tile_width));
                const y: usize = @intFromFloat(@divTrunc(collision.y - @as(f32, @floatFromInt(level.worldY)), tile_width));

                navigation_map.items[y][x] = true;
            }

            try navigation_maps.append(try navigation_map.toOwnedSlice());
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
        };
    }

    /// at the moment this does not comply with the same rules as other objects. This does not get declaratively called within a pre-configured context.
    /// Instead this is expecte to be called outside of all contexts' and instead control the context shift itself.
    /// However, this should probably be changed in the future.
    /// By being split up into several methods. 'Draw occlusion', 'draw visible/invisible'
    pub fn draw(self: @This(), camera: Camera, scene: rl.RenderTexture, invisible_scene: rl.RenderTexture, occlusion_mask: rl.RenderTexture) void {
        const tile_width = 8;
        for (self.ldtk.levels) |level| {
            var i = level.layerInstances.len;
            while (i > 0) {
                i -= 1;
                const instance = level.layerInstances[i];
                const is_wall = std.mem.eql(u8, instance.__identifier, "Walls");

                scene.begin();
                for (instance.autoLayerTiles) |tile| {
                    // 'coercing' error into null, so that we can easily null-check for ease of use.
                    // might indicate that we want bound_check to return null instead of error type hm...
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                        const flip_x = (tile.f == 1 or tile.f == 3);
                        const flip_y = (tile.f == 2 or tile.f == 3);
                        rl.drawTexturePro(
                            self.visible,
                            .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                            .{ .x = camera_pos.x, .y = camera_pos.y, .width = tile_width, .height = tile_width },
                            rl.Vector2.zero(),
                            0,
                            rl.Color.white,
                        );
                    }
                }
                scene.end();

                invisible_scene.begin();
                for (instance.autoLayerTiles) |tile| {
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                        const flip_x = (tile.f == 1 or tile.f == 3);
                        const flip_y = (tile.f == 2 or tile.f == 3);
                        rl.drawTexturePro(
                            self.invisible,
                            .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                            .{ .x = camera_pos.x, .y = camera_pos.y, .width = tile_width, .height = tile_width },
                            rl.Vector2.zero(),
                            0,
                            rl.Color.white,
                        );
                    }
                }
                invisible_scene.end();

                occlusion_mask.begin();
                for (instance.autoLayerTiles) |tile| {
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (is_wall) {
                        if (camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                            rl.drawRectangleV(camera_pos, rl.Vector2.one().scale(tile_width), rl.Color.black);
                        }
                    }
                }
                occlusion_mask.end();
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
