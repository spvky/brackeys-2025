const std = @import("std");
const rl = @import("raylib");
const Path = @import("path.zig").Path;
const transitions = @import("transition.zig");
const Camera = @import("camera.zig").Camera;
const Level = @import("level.zig").Level;
const Portal = @import("level.zig").Portal;
const UiState = @import("ui.zig").UiState;
const SoundBank = @import("audio.zig").SoundBank;
const UiAssets = @import("ui.zig").UiAssets;
const consts = @import("consts.zig");
const RENDER_WIDTH = consts.RENDER_WIDTH;
const RENDER_HEIGHT = consts.RENDER_HEIGHT;
const TITLE = consts.TITLE;

const MENU_WIDTH: i32 = 280;
const MENU_HEIGHT: i32 = 180;

var WINDOW_WIDTH: i32 = 1080;
var WINDOW_HEIGHT: i32 = 720;

const Particle = struct {
    rect: rl.Rectangle,
    color: rl.Color,
    velocity: rl.Vector2,
    ttl: f32,
};

const GameState = enum {
    gameplay,
    main_menu,
    pause,
};

const State = struct {
    state: GameState,
    gameplay_scene: GameplayScene,
    main_menu_scene: MenuScene,
    pause_scene: MenuScene,
    frame_count: u32 = 0,

    pub fn update(self: *@This()) !void {
        const dt = rl.getFrameTime();
        self.frame_count = self.frame_count + 1;
        switch (self.state) {
            .gameplay => {
                self.gameplay_scene.update_player(dt);
                try self.gameplay_scene.update(dt, self.frame_count);

                // SUPER UGLY
                // should be 'escape' key
                if (rl.isKeyPressed(.escape)) {
                    self.state = .pause;
                }
            },
            .main_menu => {
                self.main_menu_scene.update();
                try self.gameplay_scene.update(dt, self.frame_count);

                // SUPER UGLY
                // should be a callback inside 'MenuOption' but i couldn't make it work due to comptime
                if (rl.isKeyPressed(.e)) {
                    switch (self.main_menu_scene.selected_index) {
                        0 => self.state = .gameplay,
                        1 => rl.closeWindow(),
                        else => {},
                    }
                }
            },
            .pause => {
                self.pause_scene.update();

                // SUPER UGLY
                // should be a callback inside 'MenuOption' but i couldn't make it work due to comptime
                if (rl.isKeyPressed(.e)) {
                    switch (self.pause_scene.selected_index) {
                        0 => self.state = .gameplay,
                        1 => rl.closeWindow(),
                        else => {},
                    }
                }
            },
        }
    }

    pub fn draw(self: @This()) void {
        switch (self.state) {
            .gameplay => {
                self.gameplay_scene.prepare_scene();
                self.gameplay_scene.draw();
            },
            .main_menu => {
                self.gameplay_scene.prepare_scene();
                const gameplay_render_texture = self.gameplay_scene.render_texture;
                self.main_menu_scene.draw(gameplay_render_texture.texture);
            },
            .pause => {
                self.gameplay_scene.prepare_scene();
                const gameplay_render_texture = self.gameplay_scene.render_texture;
                self.pause_scene.draw(gameplay_render_texture.texture);
            },
        }
    }
};

const MenuOption = struct {
    title: []const u8,
};

const MenuScene = struct {
    selected_index: u64 = 0,
    title: []const u8,
    /// the final render texture that is upscaled and shown to the player
    render_texture: rl.RenderTexture,
    menu_options: []const MenuOption,

    pub fn update(self: *@This()) void {
        if (rl.isKeyPressed(.w)) {
            self.selected_index = (self.selected_index + self.menu_options.len - 1) % self.menu_options.len;
        }
        if (rl.isKeyPressed(.s)) {
            self.selected_index = (self.selected_index + 1) % self.menu_options.len;
        }
    }

    pub fn draw(self: @This(), gameplay_texture: rl.Texture) void {
        self.render_texture.begin();
        var background_color = rl.Color.black;
        background_color = background_color.alpha(0.3);
        rl.clearBackground(background_color);

        const big_size = 20;
        const str_len: i32 = @intCast(rl.textLength(@ptrCast(self.title.ptr)));
        rl.drawText(@ptrCast(self.title.ptr), MENU_WIDTH / 2 - (big_size * @divTrunc(str_len, 2)), 20, big_size, rl.Color.black);

        const font_size = 8;
        for (self.menu_options, 0..) |option, idx| {
            const x: i32 = @intCast(MENU_WIDTH / 4);
            const y: i32 = @intCast(MENU_HEIGHT / 4 + idx * font_size * 2);

            const clr = if (idx != self.selected_index) rl.Color.black else rl.Color.white;
            const text = if (idx != self.selected_index) rl.textFormat("  %s", .{option.title.ptr}) else rl.textFormat("* %s", .{option.title.ptr});
            rl.drawText(text, x, y, font_size, clr);
        }
        self.render_texture.end();

        rl.beginDrawing();
        rl.drawTexturePro(gameplay_texture, .{
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

        rl.drawTexturePro(self.render_texture.texture, .{
            .x = 0,
            .y = 0,
            .width = MENU_WIDTH,
            .height = -MENU_HEIGHT,
        }, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(WINDOW_WIDTH),
            .height = @floatFromInt(WINDOW_HEIGHT),
        }, rl.Vector2.zero(), 0, rl.Color.white);
        rl.endDrawing();
    }
};

const GameplayScene = struct {
    /// the scene we draw to, it's dimensions are static
    scene: rl.RenderTexture,
    /// the version of the scene which is not visible
    invisible_scene: rl.RenderTexture,
    /// the mask which decides what are occluders
    occlusion_mask: rl.RenderTexture,
    /// the final render texture that is upscaled and shown to the player
    render_texture: rl.RenderTexture,
    occlusion_shader: rl.Shader,
    camera: Camera,
    level: Level,
    level_proto: Level,
    transition: transitions.Diamond,
    particles: std.ArrayList(Particle),

    level_index: usize = 2,

    // game contexts
    clicked_portal: ?Portal = null,
    has_died: bool = false,
    sound_bank: SoundBank,
    ui_assets: UiAssets,
    relic1: bool = false,
    relic2: bool = false,
    relic3: bool = false,

    /// this is not great. It's supposed to seperate the 'update' from the 'input' so that we can use input for other things
    /// while still 'updating' gameplay scene state
    pub fn update_player(state: *@This(), frametime: f32) void {
        var player = &state.level.player;
        const raw_cursor_position = rl.getMousePosition();
        const render_ratio: rl.Vector2 = .{
            .x = @as(f32, @floatFromInt(RENDER_WIDTH)) / @as(f32, @floatFromInt(WINDOW_WIDTH)),
            .y = @as(f32, @floatFromInt(RENDER_HEIGHT)) / @as(f32, @floatFromInt(WINDOW_HEIGHT)),
        };
        const cursor_pos = raw_cursor_position.multiply(render_ratio).add(state.camera.offset);

        player.update(state.level.collisions[state.level_index], state.level.items[state.level_index], frametime, cursor_pos, state.sound_bank);
    }

    pub fn update(state: *@This(), frametime: f32, frame_count: u32) !void {
        var player = &state.level.player;
        const target_pos = player.position.subtract(.{ .x = RENDER_WIDTH / 2, .y = RENDER_HEIGHT / 2 });
        var level_bounds = state.level.get_bounds(state.level_index);
        level_bounds.width -= RENDER_WIDTH;
        level_bounds.height -= RENDER_HEIGHT;

        state.camera.set_target(target_pos, level_bounds);
        state.camera.update();

        if (player.velocity.length() > 0) {
            try try_spawning_particle(state, player.position, player.velocity, frame_count, 10);
        }

        for (state.level.guards[state.level_index]) |*g| {
            const lvl = state.level.ldtk.levels[state.level_index];
            const level_offset: rl.Vector2 = .{
                .x = @floatFromInt(lvl.worldX),
                .y = @floatFromInt(lvl.worldY),
            };
            g.update(player.*, state.level.items[state.level_index], state.level.collisions[state.level_index], state.level.navigation_maps[state.level_index], level_offset, frametime, state.sound_bank);
            if (g.velocity.length() > 0) {
                try try_spawning_particle(state, g.position, g.velocity, frame_count, 20);
            }

            const distance = g.position.distance(player.position);
            if (!state.has_died and distance <= player.radius * 2) {
                state.transition.start(state.render_texture.texture, null);
                state.has_died = true;
            }
        }

        if (state.has_died and state.transition.progress == 1) {
            state.has_died = false;
            state.level.player = state.level_proto.player;
            state.level.guards = state.level_proto.guards;
            state.level.items = state.level_proto.items;
            state.level_index = 2;
            state.transition.start(null, state.render_texture.texture);
        }

        for (state.level.items[state.level_index]) |*item| {
            item.update(state.level.collisions[state.level_index], state.sound_bank);
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

        rl.setShaderValue(state.occlusion_shader, rl.getShaderLocation(state.occlusion_shader, "player_pos"), &state.camera.get_pos_on_camera(player.position), .vec2);

        // PSEUDO-CODE for testing portals
        // in reality the portal is a 'rectangle' so we should collision check instead of this.
        // we should also give some feedback that the player can interact with this 'portal'.
        //
        // a button, widget, a feint glow or something.
        if (rl.isKeyPressed(.e)) {
            var iter = state.level.portals.valueIterator();
            while (iter.next()) |portal| {
                if (rl.checkCollisionCircleRec(.{ .x = player.position.x, .y = player.position.y }, player.radius * 0.5, .{
                    .x = portal.position.x,
                    .y = portal.position.y,
                    .width = @floatFromInt(portal.width),
                    .height = @floatFromInt(portal.height),
                })) {
                    // start the 'fade out' transition
                    state.transition.start(state.render_texture.texture, null);
                    state.clicked_portal = portal.*;
                }
            }
        }

        if (state.clicked_portal) |portal| {
            if (state.transition.progress == 1) {
                const new_portal = state.level.use_portal(portal);
                player.position = new_portal.position.add(.{
                    .x = @floatFromInt(new_portal.width / 2),
                    .y = @floatFromInt(new_portal.height / 2),
                });
                const prev_level_index = state.level_index;
                state.level_index = new_portal.level;
                if (state.level_index == 2 and player.held_item == .relic) {
                    switch (prev_level_index) {
                        0 => {
                            player.held_item = .none;
                            state.relic1 = true;
                        },
                        1 => {
                            player.held_item = .none;
                            state.relic2 = true;
                        },
                        3 => {
                            player.held_item = .none;
                            state.relic3 = true;
                        },
                        else => {},
                    }
                }
                state.clicked_portal = null;
                // start the 'fade in' transition
                state.transition.start(null, state.render_texture.texture);

                const lvl = state.level.ldtk.levels[state.level_index];
                state.camera.offset = .{
                    .x = @floatFromInt(lvl.worldX),
                    .y = @floatFromInt(lvl.worldY),
                };
            }
        }

        state.transition.update(frametime);
    }

    pub fn prepare_scene(state: @This()) void {
        const player = state.level.player;
        // clearing occlusion mask
        state.occlusion_mask.begin();
        rl.clearBackground(rl.Color.white);
        state.occlusion_mask.end();

        // clearing scene
        state.scene.begin();
        rl.clearBackground(rl.Color.white);
        state.scene.end();

        state.scene.begin();
        //NOTE: We should draw everything into the scene, and let the shader compose into the render_texture later
        state.level.draw_visible(state.camera, state.level_index);
        for (state.particles.items) |particle| {
            var rect = particle.rect;
            rect.x -= state.camera.offset.x;
            rect.y -= state.camera.offset.y;
            rl.drawRectangleRec(rect, particle.color);
        }

        player.draw(state.camera.offset);
        // Need to draw him normal style
        for (state.level.guards[state.level_index]) |guard| {
            guard.draw(state.camera.offset);
            const lvl = state.level.ldtk.levels[state.level_index];
            const level_offset: rl.Vector2 = .{
                .x = @floatFromInt(lvl.worldX),
                .y = @floatFromInt(lvl.worldY),
            };
            guard.draw_debug(state.camera.offset, level_offset);
        }

        for (state.level.items[state.level_index]) |*item| {
            // TODO these do not take into account the level offset
            // which is honestly really annoying
            // I am considering just removing the level offset for all objects
            // and just naively never care for any level but the one the player is currently in
            // this will need to be revised later though, if multiplayer is on the table
            item.draw(state.ui_assets, state.camera.offset, state.level_index);
        }

        state.scene.end();

        state.invisible_scene.begin();
        state.level.draw_invisible(state.camera, state.level_index);
        for (state.level.guards[state.level_index]) |g| {
            g.draw_intuition(state.camera.offset);
        }
        state.invisible_scene.end();

        state.occlusion_mask.begin();
        state.level.draw_occlusion(state.camera, state.level_index);
        state.occlusion_mask.end();

        state.render_texture.begin();
        state.occlusion_shader.activate();
        rl.setShaderValueTexture(state.occlusion_shader, rl.getShaderLocation(state.occlusion_shader, "occlusion"), state.occlusion_mask.texture);
        rl.setShaderValueTexture(state.occlusion_shader, rl.getShaderLocation(state.occlusion_shader, "invisible_scene"), state.invisible_scene.texture);
        // we draw the scene onto the final render_texture with our shader
        state.scene.texture.draw(0, 0, rl.Color.white);
        state.occlusion_shader.deactivate();

        state.transition.draw();
        state.render_texture.end();
    }

    pub fn draw(state: @This()) void {
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
        UiState.draw(state.level.player, state.ui_assets, state.level_index);
        rl.endDrawing();
    }
};

/// spawns a particle every 'rate' frames. rate does not need to be comptime but i think it makes it more clear if we treat it as if it is
fn try_spawning_particle(state: *GameplayScene, base_position: rl.Vector2, base_velocity: rl.Vector2, frame_count: u32, comptime rate: u8) !void {
    if (frame_count % rate == 0) {
        var velocity = base_velocity.scale(-0.1);

        const f: f32 = @floatFromInt(frame_count);
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

pub fn start_game_cb() void {}

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true, .borderless_windowed_mode = true });

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    const monitor = rl.getCurrentMonitor();
    WINDOW_WIDTH = rl.getMonitorWidth(monitor);
    WINDOW_HEIGHT = rl.getMonitorHeight(monitor);

    rl.setWindowSize(WINDOW_WIDTH, WINDOW_WIDTH);
    rl.setTargetFPS(60);

    const shader = try rl.loadShader(
        null,
        "assets/shaders/occlusion.fs",
    );

    const level = try Level.init(std.heap.page_allocator);
    var state: State = .{
        .gameplay_scene = .{
            .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
            .occlusion_mask = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
            .render_texture = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
            .invisible_scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
            .camera = Camera.init(),
            .level = level,
            .level_proto = level,
            .particles = std.ArrayList(Particle).init(std.heap.page_allocator),
            .transition = try transitions.Diamond.init(RENDER_WIDTH, RENDER_HEIGHT),
            .occlusion_shader = shader,
            .ui_assets = try UiAssets.init(),
            .sound_bank = try SoundBank.init(),
        },
        .main_menu_scene = .{
            .menu_options = &.{ .{ .title = "START GAME" }, .{ .title = "EXIT" } },
            .render_texture = try rl.loadRenderTexture(MENU_WIDTH, MENU_HEIGHT),
            .title = TITLE,
        },
        .pause_scene = .{
            .menu_options = &.{ .{ .title = "RESUME" }, .{ .title = "QUIT" } },
            .render_texture = try rl.loadRenderTexture(MENU_WIDTH, MENU_HEIGHT),
            .title = "PAUSED",
        },
        .state = .main_menu,
    };

    state.gameplay_scene.transition.start(null, state.gameplay_scene.render_texture.texture);

    rl.setExitKey(.backspace);

    rl.setShaderValue(shader, rl.getShaderLocation(shader, "size"), &rl.Vector2{ .x = RENDER_WIDTH, .y = RENDER_HEIGHT }, .vec2);
    while (!rl.windowShouldClose()) {
        state.draw();
        try state.update();
    }
}
