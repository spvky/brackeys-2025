const std = @import("std");
const rl = @import("raylib");

const EventType = enum { ricochet, alarm };

pub const Event = union(EventType) { ricochet: rl.Vector2, alarm };

pub const EventQueue = struct {
    events: std.ArrayList(Event),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const events = std.ArrayList(Event).init(allocator);
        return .{ .events = events };
    }

    pub fn append(self: *Self, event: Event) !void {
        try self.events.append(event);
    }

    pub fn flush(self: *Self) void {
        if (self.events.items.len > 0) {
            std.debug.print("Flushing {} events\n", .{self.events.items.len});
        }
        while (self.events.items.len > 0) {
            _ = self.events.pop();
        }
    }

    pub fn read(self: Self) []Event {
        return self.events.items[0..];
    }
};
