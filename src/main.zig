const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const Ldtk = @import("ldtk.zig").Ldtk;

const WINDOW_WIDTH: i32 = 1080;
const WINDOW_HEIGHT: i32 = 720;

const RENDER_WIDTH: i32 = 240;
const RENDER_HEIGHT: i32 = 180;
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
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE);
    rl.setTargetFPS(60);

    var player = character.Character.init(.{ .x = 100, .y = 100 });
    // Debug guard
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    // var patrol_points = [_]rl.Vector2{
    //     .{ .x = 225, .y = 100 },
    //     .{ .x = 225, .y = 150 },
    //     .{ .x = 175, .y = 150 },
    //     .{ .x = 175, .y = 100 },
    // };
    // var guard = try character.Guard.init(allocator, .{ .x = 175, .y = 100 }, patrol_points[0..]);
    var state: State = .{
        .scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .occlusion_mask = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .render_texture = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .invisible_scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
        .camera = Camera.init(),
        .level = try Level.init(std.heap.page_allocator),
        .particles = std.ArrayList(Particle).init(std.heap.page_allocator),
    };

    const before = std.time.microTimestamp();
    var path = try find_path(std.heap.page_allocator, state.level.navigation_maps[0], .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 12 });
    const after = std.time.microTimestamp();
    std.log.debug("pathfinding took: {d:.2}µs", .{after - before});

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
        const target_pos = player.position.subtract(.{ .x = RENDER_WIDTH / 2, .y = RENDER_HEIGHT / 2 });
        const frametime = rl.getFrameTime();
        var level_bounds = state.level.get_bounds(0);
        level_bounds.width -= RENDER_WIDTH;
        level_bounds.height -= RENDER_HEIGHT;

        state.camera.set_target(target_pos, level_bounds);
        state.camera.update();
        player.update(state.level.collisions, frametime);
        if (player.velocity.length() > 0) {
            try try_spawning_particle(&state, player.position, player.velocity, 10);
        }

        if (state.frame_count % 30 == 0) {
            path = try find_path(std.heap.page_allocator, state.level.navigation_maps[0], .{ .x = 0, .y = 0 }, .{ .x = @divFloor(player.position.x, 8), .y = @divFloor(player.position.y, 8) });
        }

        for (state.level.guards) |*g| {
            g.update(player, state.level.collisions, frametime);
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
        for (state.level.guards) |g| {
            g.draw(state.camera.offset);
        }
        path.draw_debug_lines(state.camera.offset);
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
    /// [level][y][x]
    navigation_maps: [][][]bool,

    pub fn init(allocator: std.mem.Allocator) !Level {
        const ldtk = try Ldtk.init("assets/sample.ldtk");
        var collisions = std.ArrayList(rl.Rectangle).init(allocator);
        var guards = std.ArrayList(character.Guard).init(allocator);
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
                        if (is_guard) {
                            const position: rl.Vector2 = .{ .x = @floatFromInt(e.px[0]), .y = @floatFromInt(e.px[1]) };
                            var patrol_path = std.ArrayList(rl.Vector2).init(allocator);
                            for (e.fieldInstances[0].__value) |v| {
                                try patrol_path.append(rl.Vector2{ .x = @floatFromInt(v.cx * 16), .y = @floatFromInt(v.cy * 16) });
                            }
                            try guards.append(character.Guard{ .position = position, .patrol_path = patrol_path });
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

const Path = struct {
    path: []rl.Vector2,

    pub fn draw_debug_lines(self: @This(), camera_offset: rl.Vector2) void {
        const path = self.path;

        for (path[1..], 0..) |step, x| {
            const curr = step.scale(8).addValue(4).subtract(camera_offset);
            const prev = path[x].scale(8).addValue(4).subtract(camera_offset);
            rl.drawLine(
                @intFromFloat(prev.x),
                @intFromFloat(prev.y),
                @intFromFloat(curr.x),
                @intFromFloat(curr.y),
                rl.Color.gold,
            );
        }
    }
};

pub const Node = struct {
    point: rl.Vector2,
    cost: f64, // f = g + heuristic
    g: f64, // cost so far
};

fn node_cmp(_: u8, a: Node, b: Node) std.math.Order {
    if (a.cost < b.cost) return .lt;
    if (a.cost > b.cost) return .gt;
    return .eq;
}

fn movement_cost(dir: rl.Vector2) f64 {
    if (dir.x != 0 and dir.y != 0) return 1.414;
    return 1.0;
}

fn heuristic(a: rl.Vector2, b: rl.Vector2) f64 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return std.math.sqrt(dx * dx + dy * dy);
}

/// Helper: convert (x, y) to a 1D index.
fn idx(x: usize, y: usize, width: usize) usize {
    return y * width + x;
}

///
/// Computes an A* path on the given collision map.
/// - `grid` is a slice of rows (each row is a slice of booleans)
///   where `true` means walkable and `false` is a collision.
/// - `start` and `goal` are the positions to pathfind between.
/// Returns a dynamically allocated slice of Points representing the path,
/// which the caller must free.
///
/// Note: This implementation “flattens” the 2D grid into 1D arrays for
/// tracking costs and parent pointers.
pub fn find_path(
    allocator: std.mem.Allocator,
    grid: [][]bool,
    start: rl.Vector2,
    goal: rl.Vector2,
) !Path {
    // Validate grid dimensions.
    const grid_height = grid.len;
    if (grid_height == 0) return error.InvalidGrid;
    const grid_width = grid[0].len;
    if (grid_width == 0) return error.InvalidGrid;

    var cost_so_far = try std.ArrayList(f64).initCapacity(allocator, grid_width * grid_height);
    var came_from = try std.ArrayList(?rl.Vector2).initCapacity(allocator, grid_width * grid_height);
    cost_so_far.expandToCapacity();
    came_from.expandToCapacity();

    // Initialize arrays: set all costs to "infinity" and all parents to null.
    for (cost_so_far.items) |*cell| {
        cell.* = std.math.inf(f64);
    }
    for (came_from.items) |*cell| {
        cell.* = null;
    }

    cost_so_far.items[idx(@intFromFloat(start.x), @intFromFloat(start.y), grid_width)] = 0;

    var open_set = std.PriorityQueue(Node, u8, node_cmp).init(allocator, 0);
    defer open_set.deinit();

    const start_node: Node = .{
        .point = start,
        .g = 0,
        .cost = heuristic(start, goal),
    };
    try open_set.add(start_node);

    const directions: [8]rl.Vector2 = .{
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 0, .y = -1 },
        .{ .x = 1, .y = 1 },
        .{ .x = 1, .y = -1 },
        .{ .x = -1, .y = 1 },
        .{ .x = -1, .y = -1 },
    };

    var found = false;

    // A* search loop.
    while (open_set.count() != 0) {
        const current: Node = open_set.removeOrNull() orelse break;
        if (current.point.x == goal.x and current.point.y == goal.y) {
            found = true;
            break;
        }

        for (directions) |dir| {
            const next_x: i32 = @intFromFloat(current.point.x + dir.x);
            const next_y: i32 = @intFromFloat(current.point.y + dir.y);

            if (next_x < 0 or next_x >= @as(i32, @intCast(grid_width))) continue;
            if (next_y < 0 or next_y >= @as(i32, @intCast(grid_height))) continue;

            const walkable = !grid[@intCast(next_y)][@intCast(next_x)];
            const index = idx(@intCast(next_x), @intCast(next_y), grid_width);

            // Skip if the cell is not walkable.
            if (!walkable) continue;

            const new_cost = current.g + movement_cost(dir);
            if (new_cost < cost_so_far.items[index]) {
                cost_so_far.items[index] = new_cost;
                const f_next_x: f32 = @floatFromInt(next_x);
                const f_next_y: f32 = @floatFromInt(next_y);
                const priority = new_cost + heuristic(.{ .x = f_next_x, .y = f_next_y }, goal);
                const next_node = Node{
                    .point = .{ .x = f_next_x, .y = f_next_y },
                    .g = new_cost,
                    .cost = priority,
                };
                try open_set.add(next_node);
                came_from.items[index] = current.point;
            }
        }
    }

    if (!found) {
        cost_so_far.deinit();
        came_from.deinit();
        return error.PathNotFound;
    }

    // Reconstruct the path from goal back to start.
    var path = std.ArrayList(rl.Vector2).init(allocator);
    var current_point = goal;
    while (true) {
        try path.append(current_point);
        if (current_point.x == start.x and current_point.y == start.y) break;
        const index = idx(@intFromFloat(current_point.x), @intFromFloat(current_point.y), grid_width);
        const prev = came_from.items[index];
        if (prev == null) break;
        current_point = prev.?;
    }

    // Reverse the path so it runs from start to goal.
    for (0..@divTrunc(path.items.len, 2)) |i| {
        const tmp = path.items[i];
        path.items[i] = path.items[path.items.len - 1 - i];
        path.items[path.items.len - 1 - i] = tmp;
    }

    // Clean up temporary arrays.
    cost_so_far.deinit();
    came_from.deinit();

    return .{ .path = try path.toOwnedSlice() };
}
