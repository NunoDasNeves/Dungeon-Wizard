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
const icon_text = @import("../icon_text.zig");
const Data = @import("../Data.zig");

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Mass Ignite";

pub const enum_name = "mass_ignite";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .mana_cost = Spell.ManaCost.num(2),
        .cast_time = .fast,
        .color = Spell.colors.fire,
        .rarity = .interesting,
        .targeting_data = .{
            .kind = .self,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
        },
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
    params.validate(.self, caster);
    const mass_ignite: @This() = self.kind.mass_ignite;
    var it = room.things.iterator();
    while (it.next()) |target| {
        if (!(target.isAttackableCreature() and target.isEnemy())) {
            continue;
        }
        if (target.hurtbox) |*hurtbox| {
            hurtbox.hit(target, room, mass_ignite.hit_effect, null);
            _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
        }
    }
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const mass_ignite: @This() = self.kind.mass_ignite;
    const hit_dmg = Thing.Damage{
        .kind = .fire,
        .amount = mass_ignite.hit_effect.damage,
    };
    const fmt =
        \\Deal {any} to ALL enemies.
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
    var buf: [64]u8 = undefined;
    const mass_ignite: @This() = self.kind.mass_ignite;
    return Spell.NewTag.Array.fromSlice(&.{
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "{any}{any}{any}{any}", .{ icon_text.Icon.target, icon_text.Icon.skull, icon_text.Icon.skull, icon_text.Icon.skull }),
            ),
        },
        try Spell.NewTag.makeDamage(.fire, mass_ignite.hit_effect.damage, false),
    }) catch unreachable;
}
