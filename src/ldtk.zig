const std = @import("std");

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

const EntityInstance = struct {
    __identifier: []const u8,
    px: [2]i32,
    fieldInstances: []FieldInstance,
    iid: []const u8,
    width: u32,
    height: u32,
};

const EntityRef = struct {
    entityIid: []const u8,
    layerIid: []const u8,
    levelIid: []const u8,
    worldIid: []const u8,
};

const FieldInstanceValue = union(enum) {
    points: []Point,
    entity_ref: EntityRef,
    _,
};

const FieldInstance = struct {
    __type: []const u8,
    __value: std.json.Value,

    pub fn parse_value(self: @This()) !FieldInstanceValue {
        const Case = enum {
            @"Array<Point>",
            EntityRef,
        };
        const case = std.meta.stringToEnum(Case, self.__type) orelse unreachable;
        switch (case) {
            .@"Array<Point>" => {
                const result = try std.json.parseFromValue([]Point, std.heap.page_allocator, self.__value, .{ .ignore_unknown_fields = true });
                return .{ .points = result.value };
            },
            .EntityRef => {
                const result = try std.json.parseFromValue(EntityRef, std.heap.page_allocator, self.__value, .{ .ignore_unknown_fields = true });
                return .{ .entity_ref = result.value };
            },
        }
    }
};

const Point = struct {
    cx: i32,
    cy: i32,
};

const LayerInstance = struct {
    __identifier: []const u8,
    __type: []const u8,
    __pxTotalOffsetX: i32,
    __pxTotalOffsetY: i32,
    __cWid: i32,
    __cHei: i32,
    intGridCsv: []i32,
    entityInstances: []EntityInstance,
    levelId: u32,
    autoLayerTiles: []Tile,
    gridTiles: []Tile,
};

const Level = struct {
    uid: u32,
    layerInstances: []LayerInstance,
    worldX: i32,
    worldY: i32,
    pxWid: u32,
    pxHei: u32,
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
        const cwd = std.fs.cwd();
        const allocator = std.heap.page_allocator;
        const file = try cwd.openFile(path, .{});
        const buf = try file.readToEndAlloc(allocator, 200_000_000);
        const parser = try std.json.parseFromSlice(@This(), allocator, buf, .{ .ignore_unknown_fields = true });
        return parser.value;
    }
};
