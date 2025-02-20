const std = @import("std");
const rl = @import("raylib");

const math = std.math;

pub const Diamond = struct {
    progress: f32 = 0.0,
    diamond_size: f32 = 10.0,
    x_coefficient: f32 = 1.0,
    y_coefficient: f32 = 0.0,
    shader: rl.Shader,
    fallback_texture: rl.Texture,

    to: rl.Texture,
    from: rl.Texture,

    pub fn init(width: i32, height: i32) !Diamond {
        const shader = try rl.loadShader(
            null,
            "assets/shaders/transitions/diamond.fs",
        );
        const texture = try rl.loadRenderTexture(width, height);
        texture.begin();
        rl.clearBackground(rl.Color.black);
        texture.end();

        rl.setShaderValue(shader, rl.getShaderLocation(shader, "size"), &.{ .x = width, .y = height }, .vec2);

        return .{
            .shader = shader,
            .fallback_texture = texture.texture,
            .from = texture.texture,
            .to = texture.texture,
        };
    }

    pub fn start(self: *@This(), from_texture: ?rl.Texture, to_texture: ?rl.Texture) void {
        self.from = if (from_texture) |t| t else self.fallback_texture;
        self.to = if (to_texture) |t| t else self.fallback_texture;
        self.progress = 0.0;
    }

    pub fn update(self: *@This(), delta: f32) void {
        self.progress = @min(1.0, self.progress + delta);
        rl.setShaderValue(self.shader, rl.getShaderLocation(self.shader, "progress"), &self.progress, .float);
    }

    pub fn apply_changes(self: *@This()) void {
        rl.setShaderValue(self.shader, rl.getShaderLocation(self.progress, "size"), &self.progress, .float);
        rl.setShaderValue(self.shader, rl.getShaderLocation(self.progress, "diamond_size"), &self.diamond_size, .float);
        rl.setShaderValue(self.shader, rl.getShaderLocation(self.progress, "x_coefficient"), &self.x_coefficient, .float);
        rl.setShaderValue(self.shader, rl.getShaderLocation(self.progress, "y_coefficient"), &self.y_coefficient, .float);
    }

    pub fn draw(self: @This()) void {
        self.shader.activate();
        rl.setShaderValueTexture(self.shader, rl.getShaderLocation(self.shader, "from"), self.from);
        self.to.draw(0, 0, rl.Color.white);
        self.shader.deactivate();
    }
};
