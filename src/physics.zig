const std = @import("std");
const rl = @import("raylib");

pub const Particle = struct {
    position: rl.Vector2,
    velocity: rl.Vector2,
    mass: f32,

    const Self = @This();

    pub fn init(rand: std.Random) Self {
        const position = .{ .x = rand.float(f32) * 10, .y = rand.float(f32) * 10 };
        const velocity = .{ .x = 0, .y = 0 };
        const mass = 1;
        return .{ .position = position, .velocity = velocity, .mass = mass };
    }

    pub fn physics_update(self: *Self) void {
        const force = self.compute_gravity();
        const acceleration: rl.Vector3 = .{ .x = force.x / self.mass, .y = force.y / self.mass };
        self.velocity.x += acceleration.x;
        self.velocity.y += acceleration.y;

        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;
    }

    pub fn compute_gravity(self: *Self) rl.Vector2 {
        return .{ .x = 0, .y = self.mass * -9.81 };
    }

    pub fn print(self: Self) void {
        std.debug.print("{},{},{}\n", .{ self.position.x, self.position.y });
    }
};

pub fn particle_sim() !void {
    const particle_count: u8 = 1;

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    const p1 = Particle.init(rand);
    var particles = [particle_count]Particle{p1};

    for (particles) |p| {
        p.print();
    }

    const sim_time: u8 = 100;
    var current_time: u8 = 0;

    while (current_time < sim_time) {
        std.time.sleep(1_000_000_000);

        for (&particles) |*p| {
            p.physics_update();
            p.print();
        }
        current_time += 1;
    }
}

const Box = struct {
    width: f32,
    height: f32,
    mass: f32,
    momentOfInertia: f32 = 0,

    const Self = @This();

    pub fn calculateIntertia(self: *Self) void {
        const m = self.mass;
        const w = self.width;
        const h = self.height;
        self.momentOfInertia = m * (w * w + h * h) / 12;
    }
};

const RigidBody = struct {
    position: rl.Vector2,
    linear_velocity: rl.Vector2,
    angle: f32,
    angular_velocity: f32,
    force: rl.Vector2,
    torque: f32,
    shape: Box,

    const Self = @This();

    pub fn init(rand: std.Random) Self {
        const position: rl.Vector2 = .{ .x = rand.float(f32) * 20, .y = rand.float(f32) * 20 };
        const angle: f32 = ((rand.float(f32) * 360) / 360) * std.math.pi * 2;

        const width = 1 + rand.float(f32) * 2;
        const height = 1 + rand.float(f32) * 2;
        var shape: Box = .{ .mass = 10, .width = width, .height = height };
        shape.calculateIntertia();
        return Self{ .position = position, .angle = angle, .shape = shape, .angular_velocity = 0, .linear_velocity = .{ .x = 0, .y = 0 } };
    }

    pub fn compute_force_and_torque(self: *Self) void {
        const f: rl.Vector2 = .{ .x = 0, .y = 100 };
        self.force = f;
        const r: rl.Vector2 = .{ .x = self.shape.width / 2, .y = self.shape.height / 2 };
        self.torque = r.x * f.y - r.y * f.x;
    }

    pub fn print(self: Self) void {
        std.debug.print("position: {},{}\nangle: {}\n", .{ self.position.x, self.position.y, self.angle });
    }
};

pub fn simulate_rigidbodies(total_sim_time: u8) void {
    var current_time: u8 = 0;
    const dt: u8 = 1;

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const rand = prng.random();
    var rigidbodies = [1]RigidBody{RigidBody.init(rand)};

    for (rigidbodies) |rb| {
        rb.print();
    }

    while (current_time < total_sim_time) {
        for (&rigidbodies) |*rb| {
            rb.compute_force_and_torque();
            const mass = rb.shape.mass;
            const linear_accelleration: rl.Vector2 = .{ .x = rb.force.x / mass, .y = rb.force.y / mass };
            rb.linear_velocity.x += linear_accelleration.x;
            rb.linear_velocity.y += linear_accelleration.y;

            rb.position.x += rb.linear_velocity.x;
            rb.position.y += rb.linear_velocity.y;

            const angular_acceleration: f32 = rb.torque / rb.shape.momentOfInertia;

            rb.angular_velocity += angular_acceleration;
            rb.angle += rb.angular_velocity;
        }

        for (rigidbodies) |rb| {
            rb.print();
        }
        current_time += dt;
    }
}

// Broad Phase
const AABB = struct {
    min: rl.Vector2,
    max: rl.Vector2,

    const Self = @This();

    pub fn overlaps(self: Self, rhs: Self) bool {
        const d1x = rhs.min.x - self.max.x;
        const d1y = rhs.min.y - self.max.y;
        const d2x = self.min.x - rhs.max.x;
        const d2y = self.min.y - rhs.max.y;

        if (d1x > 0 or d1y > 0) {
            return false;
        } else if (d2x > 0 or d2y > 0) {
            return false;
        } else {
            return true;
        }
    }
};

//Space Partitioning
pub const PartitionMethod = enum { sort_and_sweep, dbvt };
pub const SpacePartitioner = struct {
    method: PartitionMethod = .sort_and_sweep,
};

pub const Collider = struct { center: rl.Vector2, radius: f32 };

// Narrow phase
fn collide_circles(a: *Collider, b: *Collider) bool {
    const x = a.center.x - b.center.x;
    const y = a.center.y - b.center.y;

    const sqaured_dist: f32 = (x * x) + (y * y);
    const radius: f32 = a.radius * b.radius;
    const r2 = radius * radius;
    return sqaured_dist <= r2;
}

const Tile = struct {
    position: rl.Vector2,
    extents: rl.Vector2
};

fn tile_collision(collider: *Collider, tile: *Tile) bool {
    
}
