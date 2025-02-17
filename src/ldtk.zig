const std = @import("std");

const cwd = std.fs.cwd();

const Rules = struct {
    active: bool,
    size: u32,
    tileRectsIds: [][]u32,
    alpha: f32,
    chance: f32,
    breakOnMatch: bool,
    pattern: []i64,
    flipX: bool,
    flipY: bool,
    tileXOffset: i32,
    tileYOffset: i32,
    xModulo: u8,
    yModulo: u8,
};

const Tile = struct {
    px: [2]i32,
    src: [2]f32,
    f: u2,
    d: []i32,
    t: u32,
    a: f32,
};

const AutoRuleGroup = struct {
    name: []const u8,
    active: bool,
    rules: []Rules,
};

const Layer = struct {
    __type: []const u8,
    identifier: []const u8,
    pxOffsetX: i32,
    pxOffsetY: i32,
    autoRuleGroups: ?[]AutoRuleGroup,
};

const LayerInstance = struct {
    __identifier: []const u8,
    __type: []const u8,
    __pxTotalOffsetX: i32,
    __pxTotalOffsetY: i32,
    intGridCsv: []i32,
    levelId: u32,
    autoLayerTiles: []Tile,
    gridTiles: []Tile,
};

const Level = struct {
    uid: u32,
    layerInstances: []LayerInstance,
    worldX: i32,
    worldY: i32,
};

const Tileset = struct {
    identifier: []const u8,
    relPath: ?[]const u8, // This is nullable only because 'internal icons'
    tileGridSize: u8,
};

const Defs = struct {
    layers: []Layer,
    tilesets: []Tileset,
};

pub const Ldtk = struct {
    defs: Defs,
    levels: []Level,

    pub fn init(path: []const u8) !@This() {
        const allocator = std.heap.page_allocator;
        const file = try cwd.openFile(path, .{});
        const buf = try file.readToEndAlloc(allocator, 200_000_000);
        const parser = try std.json.parseFromSlice(@This(), allocator, buf, .{ .ignore_unknown_fields = true });
        return parser.value;
    }
};
