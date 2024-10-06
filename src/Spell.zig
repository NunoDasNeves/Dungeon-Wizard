const std = @import("std");
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("debug.zig");
const assert = debug.assert;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Thing = @import("Thing.zig");
const TileMap = @import("TileMap.zig");
const data = @import("data.zig");
const pool = @import("pool.zig");

const Spell = @This();

pub const Pool = pool.BoundedPool(Spell, 32);
pub const Id = pool.Id;

pub const SpellTypes = [_]type{
    @import("spells/Unherring.zig"),
    @import("spells/Protec.zig"),
};

pub const Kind = utl.EnumFromTypes(&SpellTypes, "enum_name");
pub const KindData = utl.TaggedUnionFromTypes(&SpellTypes, "enum_name", Kind);

pub fn GetKindType(kind: Kind) type {
    const fields: []const std.builtin.Type.UnionField = std.meta.fields(KindData);
    if (std.meta.fieldIndex(KindData, @tagName(kind))) |i| {
        return fields[i].type;
    }
    @compileError("No Spell kind: " ++ @tagName(kind));
}

pub fn getProto(kind: Kind) Spell {
    switch (kind) {
        inline else => |k| {
            return GetKindType(k).proto;
        },
    }
}

pub const Rarity = enum {
    pedestrian,
    interesting,
    exceptional,
    brilliant,
};

pub const TargetKind = enum {
    self,
    thing,
    pos,
};

pub const Params = struct {
    target: union(TargetKind) {
        self,
        thing: Thing.Id,
        pos: V2f,
    },
};

pub const TargetingData = struct {
    kind: TargetKind = .self,
    color: Colorf = .cyan,
    line_to_mouse: bool = false,
    target_faction_mask: Thing.Faction.Mask = .{},
    target_mouse_pos: bool = false,
    radius_under_mouse: ?f32 = null,
    cone_from_self_to_mouse: ?struct {
        radius: f32,
        radians: f32,
    } = null,
};

pub const Controller = struct {
    const ControllerTypes = blk: {
        var num = 0;
        for (SpellTypes) |M| {
            for (M.Controllers) |_| {
                num += 1;
            }
        }
        var Types: [num]type = undefined;
        var i = 0;
        for (SpellTypes) |M| {
            for (M.Controllers) |C| {
                Types[i] = C;
                i += 1;
            }
        }
        break :blk Types;
    };
    pub const ControllerKind = utl.EnumFromTypes(&ControllerTypes, "controller_enum_name");
    pub const ControllerKindData = utl.TaggedUnionFromTypes(&ControllerTypes, "controller_enum_name", ControllerKind);

    controller: ControllerKindData,
    spell: Spell,
    params: Params,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const scontroller = self.controller.spell;
        switch (scontroller.controller) {
            inline else => |s| {
                try @TypeOf(s).update(self, room);
            },
        }
    }
};

pub fn makeProto(kind: Kind, the_rest: Spell) Spell {
    var ret = the_rest;
    ret.kind = @unionInit(KindData, @tagName(kind), .{});
    ret.cast_time_ticks = 30 * ret.cast_time;
    return ret;
}

// TODO move these spells to own files
pub const FrostVom = struct {
    pub const proto: Spell = makeProto(
        .frostvom,
        .{
            .cast_time = 2,
            .color = .blue,
            .targeting_data = .{
                .kind = .pos,
                .cone_from_self_to_mouse = true,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Mint = struct {
    pub const proto: Spell = makeProto(
        .mint,
        .{
            .color = .red,
            .targeting_data = .{
                .kind = .pos,
                .line_to_mouse = true,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Impling = struct {
    pub const proto: Spell = makeProto(
        .impling,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .pos,
                .target_mouse_pos = true,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Promptitude = struct {
    pub const proto: Spell = makeProto(
        .promptitude,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .self,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const FlameExplode = struct {
    pub const proto: Spell = makeProto(
        .flameexplode,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .pos,
                .line_to_mouse = true,
                .radius_under_mouse = 100,
            },
        },
    );

    direct_hit_damage: f32 = 20,
    aoe_damage: f32 = 50,

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Blackmail = struct {
    pub const proto: Spell = makeProto(
        .blackmail,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .thing,
                .target_enemy = true,
            },
        },
    );

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

// only valid if spawn_state == .card
id: Id = undefined,
alloc_state: pool.AllocState = undefined,
//
spawn_state: enum {
    instance, // not in any pool
    card, // a card allocated in a pool
} = .instance,
kind: KindData = undefined,
rarity: Rarity = .pedestrian,
cast_time: i8 = 1,
cast_time_ticks: i64 = 30,
color: Colorf = .black,
targeting_data: TargetingData = .{},

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "cast")) {
                try K.cast(self, caster, room, params);
            }
        },
    }
}

pub fn getTargetParams(self: *const Spell, room: *Room, target_pos: V2f) ?Params {
    const targeting_data = self.targeting_data;
    switch (targeting_data.kind) {
        .pos => {},
        .self => {},
        .thing => {
            for (&room.things.items) |*thing| {
                if (!thing.isActive()) continue;
                if (thing.select_radius == null) continue;
                if (!targeting_data.target_faction_mask.contains(thing.faction)) continue;
                const select_radius = thing.select_radius.?;
                if (target_pos.dist(thing.pos) < select_radius) {
                    return .{ .target = .{ .thing = thing.id } };
                }
            }
        },
    }
    return null;
}

pub fn renderTargeting(self: *const Spell, room: *const Room) Error!void {
    const plat = App.getPlat();
    const targeting_data = self.targeting_data;
    const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());

    switch (targeting_data.kind) {
        .pos => {},
        .self => {},
        .thing => {
            for (&room.things.items) |*thing| {
                if (!thing.isActive()) continue;
                if (thing.select_radius == null) continue;
                if (!targeting_data.target_faction_mask.contains(thing.faction)) continue;
                const select_radius = thing.select_radius.?;
                const draw_radius = if (mouse_pos.dist(thing.pos) < select_radius) select_radius + 20 else select_radius;
                plat.circlef(thing.pos, draw_radius, .{ .fill_color = targeting_data.color.fade(0.8) });
            }
        },
    }
}
