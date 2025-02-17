const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    for (builtin.test_functions) |t| {
        t.func() catch |err| {
            try std.fmt.format(out, "{s} fail: {}\n", .{ t.name, err });
            continue;
        };
        try std.fmt.format(out, "{s} passed\n", .{t.name});
    }
}
