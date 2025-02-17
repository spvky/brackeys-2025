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
};

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    rl.setTargetFPS(60);

    const levels = try Level.init("assets/sample.ldtk");
    const visible = try rl.loadTexture("assets/visible.png");
    const invisible = try rl.loadTexture("assets/invisible.png");

    var player = character.Character.init(.{ .x = 100, .y = 100 });
    const state: State = .{
        .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .occlusion_mask = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .render_texture = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .invisible_scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
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
        player.update();
        var player_pos = player.position;
        rl.setShaderValue(shader, player_pos_loc, &player_pos, .vec2);

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

                //TODO measure if changing raylib state texture is expensive
                // if so we can change the iteration here to comply more regarding performance
                // performance kinda sucks which makes no sense, so i am thinking this is the issue
                for (instance.autoLayerTiles) |tile| {
                    state.scene.begin();
                    const flip_x = (tile.f == 1 or tile.f == 3);
                    const flip_y = (tile.f == 2 or tile.f == 3);
                    rl.drawTexturePro(
                        visible,
                        .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                        .{ .x = @floatFromInt(tile.px[0]), .y = @floatFromInt(tile.px[1]), .width = tile_width, .height = tile_width },
                        rl.Vector2.zero(),
                        0,
                        rl.Color.white,
                    );
                    state.scene.end();

                    state.invisible_scene.begin();
                    rl.drawTexturePro(
                        invisible,
                        .{ .x = tile.src[0], .y = tile.src[1], .width = if (flip_x) -tile_width else tile_width, .height = if (flip_y) -tile_width else tile_width },
                        .{ .x = @floatFromInt(tile.px[0]), .y = @floatFromInt(tile.px[1]), .width = tile_width, .height = tile_width },
                        rl.Vector2.zero(),
                        0,
                        rl.Color.white,
                    );
                    state.invisible_scene.end();

                    if (is_wall) {
                        state.occlusion_mask.begin();
                        rl.drawRectangle(tile.px[0], tile.px[1], tile_width, tile_width, rl.Color.black);
                        state.occlusion_mask.end();

                        // TODO: add collision here
                    }
                }
            }
        }

        state.scene.begin();
        //NOTE: We should draw everything into the scene, and let the shader compose into the render_texture later
        player.draw();
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

        rl.drawFPS(0, 0);
        rl.endDrawing();
    }
}
