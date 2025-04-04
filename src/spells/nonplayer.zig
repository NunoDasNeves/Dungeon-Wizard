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
const projectiles = @import("../projectiles.zig");
const Data = @import("../Data.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const spells = [_]type{
    struct {
        pub const title = "Summon Bat";
        pub const enum_name = "summon_bat";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .slow,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .pos,
                    .target_mouse_pos = true,
                    .max_range = 50,
                    .show_max_range_ring = true,
                },
                .color = Colorf.purple.lerp(.white, 0.6),
            },
        );
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.pos, caster);
            _ = self;
            const target_pos = params.pos;
            var spawner = Thing.SpawnerController.prototypeSummon(.bat);
            spawner.faction = caster.faction;
            _ = try room.queueSpawnThing(&spawner, target_pos);
        }
    },
    struct {
        pub const title = "Protect Self";
        pub const enum_name = "protect_self";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .slow,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .self,
                },
                .color = Colorf.yellow.lerp(.white, 0.6),
            },
        );
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.self, caster);
            _ = self;
            _ = room;
            caster.statuses.getPtr(.protected).addStacks(caster, 5);
        }
    },
    struct {
        pub const title = "Crescent Throw";
        pub const enum_name = "crescent_throw";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .slow,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .color = draw.Coloru.rgb(143, 56, 165).toColorf(),
                .targeting_data = .{
                    .kind = .pos,
                    .max_range = 100,
                    .show_max_range_ring = true,
                },
            },
        );
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.pos, caster);
            _ = self;
            var cres = projectiles.DjinnCrescent.proto(room);
            cres.controller.projectile.kind.djinncrescent.target_pos = params.pos;
            cres.hitbox.?.mask = Thing.Faction.opposing_masks.get(caster.faction);
            const to_target = params.pos.sub(caster.pos).normalizedChecked() orelse V2f.right;
            const cw = to_target.rot90CW();
            const ccw = to_target.rot90CCW();
            const speed = cres.accel_params.max_speed * 0.2;
            const offset = caster.coll_radius * 1.5;
            cres.vel = cw.scale(speed);
            _ = try room.queueSpawnThing(&cres, caster.pos.add(cw.scale(offset)));
            cres.vel = ccw.scale(speed);
            _ = try room.queueSpawnThing(&cres, caster.pos.add(ccw.scale(offset)));
        }
    },
    struct {
        pub const title = "Teleport Self";
        pub const enum_name = "teleport_self";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .slow,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .color = draw.Coloru.rgb(143, 56, 165).toColorf(),
                .targeting_data = .{
                    .kind = .pos,
                },
            },
        );
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.pos, caster);
            _ = self;
            if (try room.tilemap.getClosestPathablePos(caster.pathing_layer, null, params.pos, caster.coll_radius)) |pos| {
                caster.pos = pos;
            }
        }
    },
    struct {
        pub const title = "Fairy Slime";
        pub const enum_name = "fairy_slime";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .fast,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .thing,
                    .max_range = 70,
                    .show_max_range_ring = true,
                },
            },
        );
        const AnimRef = struct {
            var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-slimeball");
        };
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.thing, caster);
            _ = self;
            var ball = projectiles.FairyBall.proto(room);
            ball.controller.projectile.kind.fairy_ball.target_pos = params.pos;
            ball.controller.projectile.kind.fairy_ball.target_thing = params.thing.?;
            _ = AnimRef.projectile_loop.get();
            ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
            ball.hitbox.?.effect = .{
                .damage = 0,
                .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
                    .slimeballed = 3,
                    .exposed = 3,
                }),
            };
            _ = try room.queueSpawnThing(&ball, caster.pos);
        }
    },
    struct {
        pub const title = "Fairy Heart";
        pub const enum_name = "fairy_heart";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .fast,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .thing,
                    .max_range = 60,
                    .show_max_range_ring = true,
                },
            },
        );
        const AnimRef = struct {
            var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-heart");
        };
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.thing, caster);
            _ = self;
            var ball = projectiles.FairyBall.proto(room);
            ball.controller.projectile.kind.fairy_ball.target_thing = params.thing.?;
            ball.controller.projectile.kind.fairy_ball.target_pos = params.pos;
            _ = AnimRef.projectile_loop.get();
            ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
            ball.hitbox.?.effect = .{
                .damage = 0,
                .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
                    .protected = 4,
                    .hasted = 4,
                }),
            };
            _ = try room.queueSpawnThing(&ball, caster.pos);
        }
    },
    struct {
        pub const title = "Fairy Air";
        pub const enum_name = "fairy_air";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .fast,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .thing,
                    .max_range = 60,
                    .show_max_range_ring = true,
                },
            },
        );
        const AnimRef = struct {
            var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-skyball");
        };
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.thing, caster);
            _ = self;
            var ball = projectiles.FairyBall.proto(room);
            ball.controller.projectile.kind.fairy_ball.target_thing = params.thing.?;
            ball.controller.projectile.kind.fairy_ball.target_pos = params.pos;
            _ = AnimRef.projectile_loop.get();
            ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
            ball.hitbox.?.effect = .{
                .damage = 0,
                .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
                    .unseeable = 3,
                    .promptitude = 3,
                }),
            };
            _ = try room.queueSpawnThing(&ball, caster.pos);
        }
    },
    struct {
        pub const title = "Fairy Gold Buff";
        pub const enum_name = "fairy_gold_buff";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .fast,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .thing,
                    .max_range = 60,
                    .show_max_range_ring = true,
                },
            },
        );
        const AnimRef = struct {
            var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-goldball");
        };
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.thing, caster);
            _ = self;
            var ball = projectiles.FairyBall.proto(room);
            ball.controller.projectile.kind.fairy_ball.target_thing = params.thing.?;
            ball.controller.projectile.kind.fairy_ball.target_pos = params.pos;
            _ = AnimRef.projectile_loop.get();
            ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
            ball.hitbox.?.effect = .{
                .damage = 0,
                .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
                    .protected = 4,
                    .promptitude = 3,
                }),
            };
            _ = try room.queueSpawnThing(&ball, caster.pos);
        }
    },
    struct {
        pub const title = "Fairy Gold Debuff";
        pub const enum_name = "fairy_gold_debuff";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .fast,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .thing,
                    .max_range = 70,
                    .show_max_range_ring = true,
                },
            },
        );
        const AnimRef = struct {
            var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-goldball");
        };
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.thing, caster);
            _ = self;
            var ball = projectiles.FairyBall.proto(room);
            ball.controller.projectile.kind.fairy_ball.target_thing = params.thing.?;
            ball.controller.projectile.kind.fairy_ball.target_pos = params.pos;
            _ = AnimRef.projectile_loop.get();
            ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
            ball.hitbox.?.effect = .{
                .damage = 0,
                .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
                    .exposed = 3,
                    .stunned = 3,
                }),
            };
            _ = try room.queueSpawnThing(&ball, caster.pos);
        }
    },
};
