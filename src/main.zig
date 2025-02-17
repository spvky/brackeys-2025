const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");

const WINDOW_WIDTH: i32 = 1080;
const WINDOW_HEIGHT: i32 = 720;

const RENDER_WIDTH: i32 = 480;
const RENDER_HEIGHT: i32 = 360;
const TITLE = "brackeys 2025";

const State = struct {
    /// the scene we draw to, it's dimensions are static
    scene: rl.RenderTexture,
    /// the mask which decides what are occluders
    occlusion_mask: rl.RenderTexture,
    /// the final render texture that is upscaled and shown to the player
    render_texture: rl.RenderTexture,
};

// just a sample level
const level = &[_]i32{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 };
const level_width = 5;

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    var player = character.Character.init(.{ .x = 100, .y = 100 });
    const state: State = .{
        .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .occlusion_mask = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .render_texture = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
    };

    const shader = try rl.loadShader(
        null,
        "assets/shaders/occlusion.fs",
    );

    const size_loc = rl.getShaderLocation(shader, "size");
    const occlusion_mask_loc = rl.getShaderLocation(shader, "occlusion");
    const player_pos_loc = rl.getShaderLocation(shader, "player_pos");

    rl.setShaderValue(shader, size_loc, &rl.Vector2{ .x = RENDER_WIDTH, .y = RENDER_HEIGHT }, .vec2);
    while (!rl.windowShouldClose()) {
        const tile_width = 16;
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

        for (0..level.len) |i| {
            const tile = level[i];
            const x = i % level_width;
            const y = try std.math.divFloor(usize, i, level_width);
            if (tile == 1) {
                // drawing tile to occlusion mask
                state.occlusion_mask.begin();
                rl.drawRectangle(@intCast(x * tile_width), @intCast(y * tile_width), tile_width, tile_width, rl.Color.black);
                state.occlusion_mask.end();

                // drawing 'real' tile to scene
                state.scene.begin();
                rl.drawRectangle(@intCast(x * tile_width), @intCast(y * tile_width), tile_width, tile_width, rl.Color.red);
                state.scene.end();
            }
        }

        state.scene.begin();
        //NOTE: We should draw everything into the scene, and let the shader compose into the render_texture later
        player.draw();
        state.scene.end();

        state.render_texture.begin();
        shader.activate();
        rl.setShaderValueTexture(shader, occlusion_mask_loc, state.occlusion_mask.texture);
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
        rl.endDrawing();
    }
}
