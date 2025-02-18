const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const Level = @import("ldtk.zig").Ldtk;

const WINDOW_WIDTH: i32 = 1080;
const WINDOW_HEIGHT: i32 = 720;

const RENDER_WIDTH: i32 = 240;
const RENDER_HEIGHT: i32 = 180;
const TITLE = "brackeys 2025";

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
};

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    rl.setTargetFPS(60);

    const levels = try Level.init("assets/sample.ldtk");
    const visible = try rl.loadTexture("assets/visible.png");
    const invisible = try rl.loadTexture("assets/invisible.png");

    var player = character.Character.init(.{ .x = 100, .y = 100 });
    var state: State = .{
        .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .occlusion_mask = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .render_texture = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .invisible_scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .camera = Camera.init(),
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
        const tile_width = 8;
        player.calculate_velocity();
        var player_pos = player.position;
        state.camera.set_target(player_pos.subtract(.{ .x = RENDER_WIDTH / 2, .y = RENDER_HEIGHT / 2 }));
        state.camera.update();
        rl.setShaderValue(shader, player_pos_loc, &state.camera.get_pos_on_camera(player_pos), .vec2);

        // clearing occlusion mask
        state.occlusion_mask.begin();
        rl.clearBackground(rl.Color.white);
        state.occlusion_mask.end();

        // clearing scene
        state.scene.begin();
        rl.clearBackground(rl.Color.white);
        state.scene.end();

        for (levels.levels) |level| {
            var i = level.layerInstances.len;
            while (i > 0) {
                i -= 1;
                const instance = level.layerInstances[i];
                const is_wall = std.mem.eql(u8, instance.__identifier, "Walls");

                state.scene.begin();
                for (instance.autoLayerTiles) |tile| {
                    // 'coercing' error into null, so that we can easily null-check for ease of use.
                    // might indicate that we want bound_check to return null instead of error type hm...
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (state.camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                        const flip_x = (tile.f == 1 or tile.f == 3);
                        const flip_y = (tile.f == 2 or tile.f == 3);
                        rl.drawTexturePro(
                            visible,
                            .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                            .{ .x = camera_pos.x, .y = camera_pos.y, .width = tile_width, .height = tile_width },
                            rl.Vector2.zero(),
                            0,
                            rl.Color.white,
                        );
                    }
                }
                state.scene.end();

                state.invisible_scene.begin();
                for (instance.autoLayerTiles) |tile| {
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (state.camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                        const flip_x = (tile.f == 1 or tile.f == 3);
                        const flip_y = (tile.f == 2 or tile.f == 3);
                        rl.drawTexturePro(
                            invisible,
                            .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                            .{ .x = camera_pos.x, .y = camera_pos.y, .width = tile_width, .height = tile_width },
                            rl.Vector2.zero(),
                            0,
                            rl.Color.white,
                        );
                    }
                }
                state.invisible_scene.end();

                state.occlusion_mask.begin();
                for (instance.autoLayerTiles) |tile| {
                    const tile_world_pos: rl.Vector2 = .{
                        .x = @floatFromInt(tile.px[0] + instance.__pxTotalOffsetX + level.worldX),
                        .y = @floatFromInt(tile.px[1] + instance.__pxTotalOffsetY + level.worldY),
                    };
                    if (is_wall) {
                        if (state.camera.bound_check(tile_world_pos) catch null) |camera_pos| {
                            rl.drawRectangleV(camera_pos, rl.Vector2.one().scale(tile_width), rl.Color.black);
                            player.collision_check(.{ .x = @floatFromInt(tile.px[0]), .y = @floatFromInt(tile.px[1]), .height = 8, .width = 8 });
                        }
                    }
                }
                state.occlusion_mask.end();
            }
        }
        player.update_position();

        state.scene.begin();
        //NOTE: We should draw everything into the scene, and let the shader compose into the render_texture later
        player.draw(state.camera.offset, false);
        state.scene.end();

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
            .width = WINDOW_WIDTH,
            .height = WINDOW_HEIGHT,
        }, rl.Vector2.zero(), 0, rl.Color.white);

        // Ui
        rl.drawFPS(0, 0);
        try player.debug_player();

        rl.endDrawing();
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

    pub fn set_target(self: *@This(), target: rl.Vector2) void {
        self.target_world_pos = target;
    }

    pub fn update(self: *@This()) void {
        self.offset = self.offset.add(self.target_world_pos.subtract(self.offset).divide(.{ .x = PANNING_DELAY, .y = PANNING_DELAY }));
    }

    /// returns the position if succesful, raises 'OutOfBounds' if pos is out of bounds
    pub fn bound_check(self: *@This(), pos: rl.Vector2) !rl.Vector2 {
        const camera_pos = pos.subtract(self.offset);
        if (camera_pos.x > RENDER_WIDTH + PADDING_PX or camera_pos.x < -PADDING_PX) return error.OutOfBounds;
        if (camera_pos.y > RENDER_HEIGHT + PADDING_PX or camera_pos.y < -PADDING_PX) return error.OutOfBounds;

        return camera_pos;
    }
};
