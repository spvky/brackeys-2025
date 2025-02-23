const std = @import("std");
const rl = @import("raylib");

pub const SoundBank = struct {
    footstep: rl.Sound,
    rock: rl.Sound,
    key: rl.Sound,
    goblet: rl.Sound,

    const Self = @This();

    pub fn init() !Self {
        return .{
            .footstep = try rl.loadSound("assets/sounds/footstep.wav"),
            .rock = try rl.loadSound("assets/sounds/rock.wav"),
            .key = try rl.loadSound("assets/sounds/key.wav"),
            .goblet = try rl.loadSound("assets/sounds/goblet.wav"),
        };
    }
};
