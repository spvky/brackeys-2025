const std = @import("std");
const ecs = @import("ecs");

pub const World = struct {
    registry: ecs.Registry,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const registry = ecs.Registry.init(allocator);
        return .{ .registry = registry, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.registry.deinit();
    }

    pub fn spawn(self: *Self, components: anytype) ecs.Entity {
        const entity = self.registry.create();
        if (components.len > 0) {
            inline for (components) |component| {
                switch (@typeInfo(@TypeOf(component))) {
                    .type => self.registry.add(entity, std.mem.zeroes(component)),
                    else => self.registry.add(entity, component),
                }
            }
        }
        return entity;
    }
};
