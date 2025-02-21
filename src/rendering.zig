const std = @import("std");
const rl = @import("raylib");

const Renderer = struct {
    character_schedule: std.ArrayList(*fn (ptr: anyopaque, camera_offset: rl.Vector2) void),
};
