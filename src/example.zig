const std = @import("std");

// Totally "normal" Zig module; no special annotations required

pub fn hello() void {
    std.debug.print("Hello, world!\n", .{});
}

pub fn add(a: u8, b: u8) u8 {
    std.debug.print("add: a={}, b={}\n", .{ a, b });
    return a + b;
}

pub fn mul(a: u8, b: f32, c: f64) f64 {
    return @intToFloat(f64, a) * @floatCast(f64, b) * c;
}
