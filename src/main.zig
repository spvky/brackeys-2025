const std = @import("std");
const rl = @import("raylib");

const WINDOW_WIDTH: i32 = 1080;
const WINDOW_HEIGHT: i32 = 720;

const RENDER_WIDTH: i32 = 480;
const RENDER_HEIGHT: i32 = 360;
const TITLE = "brackeys 2025";

const State = struct {
    /// the scene we draw to, it's dimensions are static
    scene: rl.RenderTexture,
};

pub fn main() !void {
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    const state: State = .{ .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT) };
    while (!rl.windowShouldClose()) {
        rl.clearBackground(rl.Color.black);

        rl.beginDrawing();
        rl.drawTexturePro(state.scene.texture, .{
            .x = 0,
            .y = 0,
            .width = RENDER_WIDTH,
            .height = -RENDER_HEIGHT,
        }, .{
            .x = 0,
            .y = 0,
            .width = WINDOW_WIDTH,
            .height = WINDOW_HEIGHT,
        }, rl.Vector2.zero(), 0, rl.Color.white);
        rl.endDrawing();
    }
}
