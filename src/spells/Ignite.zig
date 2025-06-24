const std = @import("std");
const utl = @import("../util.zig");

pub const Platform = @import("../raylib.zig");
const core = @import("../core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("../debug.zig");
const assert = debug.assert;
const draw = @import("../draw.zig");
const Colorf = draw.Colorf;
const geom = @import("../geometry.zig");
const V2f = @import("../V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("../V2i.zig");
const v2i = V2i.v2i;

const App = @import("../App.zig");
const getPlat = App.getPlat;
const Room = @import("../Room.zig");
const Thing = @import("../Thing.zig");
const TileMap = @import("../TileMap.zig");
const StatusEffect = @import("../StatusEffect.zig");
const Data = @import("../Data.zig");

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Ignite";

pub const enum_name = "ignite";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = Spell.colors.fire,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
            .max_range = 100,
            .show_max_range_ring = true,
            .requires_los_to_thing = false,
        },
        .mana_cost = .{ .number = 0 },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 2,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
        .lit = 1,
    }),
},

const SoundRef = struct {
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    const ignite: @This() = self.kind.ignite;
    const _target = room.getThingById(params.thing.?);
    if (_target == null) {
        // fizzle
        return;
    }
    const target = _target.?;
    if (target.hurtbox) |*hurtbox| {
        hurtbox.hit(target, room, ignite.hit_effect, null);
        _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
    }
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const ignite: @This() = self.kind.ignite;
    const hit_dmg = Thing.Damage{
        .kind = .fire,
        .amount = ignite.hit_effect.damage,
    };
    const fmt =
        \\Deal {any} to an enemy.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_dmg,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const ignite: @This() = self.kind.ignite;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.fire, ignite.hit_effect.damage, false),
    }) catch unreachable;
}
