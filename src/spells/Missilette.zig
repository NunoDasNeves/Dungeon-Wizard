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
const Data = @import("../Data.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Missilette";

pub const enum_name = "missilette";
pub const Controllers = [_]type{Projectile};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .obtainableness = std.EnumSet(Spell.Obtainableness).initOne(.starter),
        .color = Spell.colors.ice,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.opposing_masks.get(.player),
            .max_range = 85,
            .show_max_range_ring = true,
            .ray_to_mouse = .{ .thickness = 1 },
            .requires_los_to_thing = true,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 5,
},

const AnimRef = struct {
    var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-missilette");
};
const SoundRef = struct {
    var chime = Data.Ref(Data.Sound).init("crackle");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    target_pos: V2f = .{},
    target_radius: f32 = 50,
    state: enum {
        loop,
        end,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const missilette = spell.kind.missilette;
        const params = spell_controller.params;
        const projectile: *Projectile = &spell_controller.controller.missilette_projectile;
        const target_id = params.thing.?;
        const _target = room.getThingById(target_id);

        switch (projectile.state) {
            .loop => {
                _ = AnimRef.projectile_loop.get();
                _ = self.renderer.sprite.playNormal(AnimRef.projectile_loop, .{ .loop = true });
                if (_target) |target| {
                    projectile.target_pos = target.pos;
                    projectile.target_radius = target.coll_radius;
                    if (target.hurtbox) |*hurtbox| {
                        projectile.target_pos = target.pos.add(hurtbox.rel_pos);
                        projectile.target_radius = hurtbox.radius;
                    }
                }

                const v = projectile.target_pos.sub(self.pos);
                if (v.length() < self.coll_radius + projectile.target_radius) {
                    projectile.state = .end;
                    if (_target) |target| {
                        if (target.hurtbox) |*hurtbox| {
                            hurtbox.hit(target, room, missilette.hit_effect, self);
                        }
                    }
                }
                self.updateVel(v.normalized(), self.accel_params);
                if (self.vel.normalizedChecked()) |n| {
                    self.dir = n;
                }
            },
            .end => {
                self.deferFree(room);
            },
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);

    const _target = room.getThingById(params.thing.?);
    if (_target == null) {
        // fizzle
        return;
    }
    const target = _target.?;

    var herring = Thing{
        .kind = .projectile,
        .dir = caster.dir,
        .accel_params = .{
            .accel = 99,
            .max_speed = 3.75,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{ .missilette_projectile = .{
                .target_pos = target.pos,
                .target_radius = target.coll_radius,
            } },
        } },
        .renderer = .{
            .sprite = .{
                .draw_over = false,
                .draw_normal = true,
                .rotate_to_dir = true,
                .flip_x_to_dir = true,
                .rel_pos = v2f(0, -14),
            },
        },
        .shadow_radius_x = 7,
    };
    herring.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
    _ = try room.queueSpawnThing(&herring, caster.pos.add(caster.dir.scale(10)));
    _ = App.get().sfx_player.playSound(&SoundRef.chime, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const missilette: @This() = self.kind.missilette;
    const hit_damage = Thing.Damage{
        .kind = .magic,
        .amount = missilette.hit_effect.damage,
    };
    const fmt =
        \\Deal {any} damage.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_damage,
        }),
    );
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const missilette: @This() = self.kind.missilette;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.magic, missilette.hit_effect.damage, false),
    }) catch unreachable;
}
