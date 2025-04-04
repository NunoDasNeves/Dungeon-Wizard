const std = @import("std");
const assert = std.debug.assert;
const Self = @This();
const u = @import("util.zig");
const V2i = @import("V2i.zig");

x: f32 = 0,
y: f32 = 0,

pub const right = v2f(1, 0);
pub const left = v2f(-1, 0);
pub const up = v2f(0, -1);
pub const down = v2f(0, 1);

pub fn v2f(x: f32, y: f32) Self {
    return .{
        .x = x,
        .y = y,
    };
}

pub fn splat(val: f32) Self {
    return v2f(val, val);
}

pub fn iToV2f(comptime T: type, x: T, y: T) Self {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
}

pub fn eq(self: Self, other: Self) bool {
    return self.x == other.x and self.y == other.y;
}

pub fn add(self: Self, other: Self) Self {
    return .{
        .x = self.x + other.x,
        .y = self.y + other.y,
    };
}

pub fn sub(self: Self, other: Self) Self {
    return .{
        .x = self.x - other.x,
        .y = self.y - other.y,
    };
}

pub fn neg(self: Self) Self {
    return .{
        .x = -self.x,
        .y = -self.y,
    };
}

pub fn scale(self: Self, s: f32) Self {
    return .{
        .x = self.x * s,
        .y = self.y * s,
    };
}

pub fn abs(self: Self) Self {
    return .{
        .x = @abs(self.x),
        .y = @abs(self.y),
    };
}

pub fn lengthSquared(self: Self) f32 {
    return self.x * self.x + self.y * self.y;
}

pub fn length(self: Self) f32 {
    return @sqrt(self.lengthSquared());
}

pub fn normalized(self: Self) Self {
    const len = self.length();
    assert(len >= 0.001);
    return self.scale(1 / len);
}

pub fn normalizedChecked(self: Self) ?Self {
    const len = self.length();
    if (len < 0.001) {
        return null;
    }
    return self.scale(1 / len);
}

pub fn normalizedOrZero(self: Self) Self {
    const len = self.length();
    if (len < 0.001) {
        return .{};
    }
    return self.scale(1 / len);
}

pub fn isZero(self: Self) bool {
    return self.x == 0 and self.y == 0;
}

pub fn isAlmostZero(self: Self) bool {
    return @abs(self.x) < 0.001 and @abs(self.y) < 0.001;
}

pub fn eql(self: Self, other: Self) bool {
    return self.x == other.x and self.y == other.y;
}

pub fn clampLength(self: Self, maxLen: f32) Self {
    const len = self.length();

    if (maxLen < 0.001) {
        return .{};
    }
    if (len < maxLen) {
        return self;
    }

    return self.scale(maxLen / len);
}

pub fn dist(self: Self, point: Self) f32 {
    return point.sub(self).length();
}

pub fn dot(self: Self, other: Self) f32 {
    return self.x * other.x + self.y * other.y;
}

pub fn cross(self: Self, other: Self) f32 {
    return self.x * other.y - self.y * other.x;
}

pub fn toAngleRadians(self: Self) f32 {
    return std.math.atan2(self.y, self.x);
}

pub fn rot90CW(self: Self) Self {
    return v2f(-self.y, self.x);
}

pub fn rot90CCW(self: Self) Self {
    return v2f(self.y, -self.x);
}

pub fn rotRadians(self: Self, radians: f32) Self {
    const c = @cos(radians);
    const s = @sin(radians);
    return v2f(
        self.x * c - self.y * s,
        self.x * s + self.y * c,
    );
}

pub fn fromAngleRadians(radians: f32) Self {
    return right.rotRadians(radians);
}

pub fn toV2i(self: Self) V2i {
    return .{
        .x = @intFromFloat(self.x),
        .y = @intFromFloat(self.y),
    };
}

pub fn fromArr(arr: [2]f32) Self {
    return v2f(arr[0], arr[1]);
}

pub fn toArr(self: Self) [2]f32 {
    return .{ self.x, self.y };
}

pub fn setLengthOrZero(self: Self, new_len: f32) Self {
    const len = self.length();
    if (len < 0.001) return .{};
    if (new_len < 0.001) return .{};
    return self.scale(new_len / len);
}

pub fn remapLength(self: Self, orig_from: f32, orig_to: f32, target_from: f32, target_to: f32) Self {
    const len = self.length();
    const new_len = u.remapClampf(orig_from, orig_to, target_from, target_to, len);
    return self.setLengthOrZero(new_len);
}

pub fn remapLengthTo0_1(self: Self, orig_from: f32, orig_to: f32) Self {
    return remapLength(self, orig_from, orig_to, 0, 1);
}

pub fn round(self: Self) Self {
    return v2f(@round(self.x), @round(self.y));
}

pub fn floor(self: Self) Self {
    return v2f(@floor(self.x), @floor(self.y));
}

pub fn ceil(self: Self) Self {
    return v2f(@ceil(self.x), @ceil(self.y));
}

pub fn max(self: Self) f32 {
    return @max(self.x, self.y);
}

pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    const vec_fmt = "({" ++ fmt ++ "}, {" ++ fmt ++ "})";
    try writer.print(vec_fmt, .{ self.x, self.y });
}

pub const Error = error{
    ParseFail,
};

pub fn parse(buf: []const u8, val: *Self) Error![]const u8 {
    if (buf.len < 2) return Error.ParseFail;
    if (buf[0] != '(') return Error.ParseFail;
    var end_idx: usize = 1;
    for (buf[1..], 1..) |c, i| {
        if (c == ')') {
            end_idx = i;
            break;
        }
    } else return Error.ParseFail;
    const inner = buf[1..end_idx];

    var comma_idx: usize = 0;
    for (inner, 0..) |c, i| {
        if (c == ',') {
            comma_idx = i;
            break;
        }
    } else return Error.ParseFail; // TODO single element splat?
    const x_trimmed = std.mem.trim(u8, inner[0..comma_idx], &std.ascii.whitespace);
    const x = std.fmt.parseFloat(f32, x_trimmed) catch return Error.ParseFail;
    const y_trimmed = std.mem.trim(u8, inner[comma_idx + 1 ..], &std.ascii.whitespace);
    const y = std.fmt.parseFloat(f32, y_trimmed) catch return Error.ParseFail;
    val.* = v2f(x, y);

    return buf[end_idx..];
}
