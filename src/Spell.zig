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
const Log = App.Log;
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Thing = @import("Thing.zig");
const TileMap = @import("TileMap.zig");
const Data = @import("Data.zig");
const pool = @import("pool.zig");
const Collision = @import("Collision.zig");
const menuUI = @import("menuUI.zig");
const sprites = @import("sprites.zig");
const ImmUI = @import("ImmUI.zig");
const Action = @import("Action.zig");
const Run = @import("Run.zig");
const StatusEffect = @import("StatusEffect.zig");
const icon_text = @import("icon_text.zig");
pub const Tooltip = @import("Tooltip.zig");

const Spell = @This();

pub const Pool = pool.BoundedPool(Spell, 32);
pub const Id = pool.Id;

// no scaling applied
pub const card_dims = v2f(71, 99);
pub const card_art_topleft_offset = v2f(3, 3);
pub const card_art_dims = v2f(65, 46);
pub const card_mana_topleft_offset = v2f(58, 1);
pub const card_tags_topleft_offset = v2f(5, 66);
pub const card_tags_dims = v2f(61, 29);
pub const card_tag_icon_dims = v2f(7, 7);
pub const card_title_center_offset = v2f(36, 56);
pub const card_hourglass_offset = v2f(48, 1);

var desc_buf: [2048]u8 = undefined;

pub const colors = .{
    .shield = draw.Coloru.rgb(238, 229, 170).toColorf(),
    .magic = draw.Coloru.rgb(184, 151, 255).toColorf(),
    .lightning = draw.Coloru.rgb(255, 253, 234).toColorf(),
    .fire = draw.Coloru.rgb(255, 123, 80).toColorf(),
    .ice = draw.Coloru.rgb(178, 220, 255).toColorf(),
};

pub const SpellTypes = blk: {
    const player_spells = [_]type{
        @import("spells/SkyFairy.zig"),
        @import("spells/HeartFairy.zig"),
        @import("spells/SlimeFairy.zig"),
        @import("spells/Protec.zig"),
        @import("spells/SnowFlurry.zig"),
        @import("spells/Snowfren.zig"),
        @import("spells/Rimefrost.zig"),
        @import("spells/ArcBolt.zig"),
        @import("spells/LBolt.zig"),
        @import("spells/Unherring.zig"),
        @import("spells/FrostVom.zig"),
        //@import("spells/Blackmail.zig"),
        //@import("spells/Mint.zig"),
        @import("spells/Impling.zig"),
        @import("spells/Promptitude.zig"),
        @import("spells/FlameyExplodey.zig"),
        @import("spells/Expose.zig"),
        @import("spells/ZapDash.zig"),
        @import("spells/FlareDart.zig"),
        @import("spells/Trailblaze.zig"),
        @import("spells/FlamePurge.zig"),
        @import("spells/BlankMind.zig"),
        @import("spells/ShieldFu.zig"),
        @import("spells/Ignite.zig"),
        @import("spells/MassIgnite.zig"),
        @import("spells/Hmmm.zig"),
        @import("spells/Switcharoo.zig"),
        @import("spells/Missilette.zig"),
    };
    const nonplayer_spells = @import("spells/nonplayer.zig").spells;
    break :blk player_spells ++ nonplayer_spells;
};

pub const Kind = utl.EnumFromTypes(&SpellTypes, "enum_name");
pub const KindData = utl.TaggedUnionFromTypes(&SpellTypes, "enum_name", Kind);
pub const all_spells = blk: {
    const kind_info = @typeInfo(Kind).@"enum";
    var ret: [kind_info.fields.len]Spell = undefined;
    for (kind_info.fields, 0..) |f, i| {
        const kind: Kind = @enumFromInt(f.value);
        const proto = getProto(kind);
        ret[i] = proto;
    }
    break :blk ret;
};
const spell_names = blk: {
    var ret: std.EnumArray(Kind, []const u8) = undefined;
    for (std.meta.fields(Kind)) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const T = GetKindType(kind);
        ret.set(kind, T.title);
    }
    break :blk ret;
};

pub fn GetKindType(kind: Kind) type {
    @setEvalBranchQuota(2000);
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

pub const CardSpriteEnum = enum {
    card_blank,
    card_base,
    rarity_pedestrian,
    rarity_interesting,
    rarity_exceptional,
    rarity_brilliant,

    pub fn fromRarity(r: Rarity) CardSpriteEnum {
        return switch (r) {
            .pedestrian => .rarity_pedestrian,
            .interesting => .rarity_interesting,
            .exceptional => .rarity_exceptional,
            .brilliant => .rarity_brilliant,
        };
    }
};

pub const Rarity = enum {
    pub const Mask = std.EnumSet(Rarity);

    pedestrian,
    interesting,
    exceptional,
    brilliant,
};

pub const TargetKind = Action.TargetKind;
pub const Params = Action.Params;

pub const TargetingData = struct {
    pub const Ray = struct {
        ends_at_coll_mask: Collision.Mask = Collision.Mask.initEmpty(),
        thickness: f32 = 1,
        cast_orig_dist: f32 = 0,
    };
    kind: Action.TargetKind = .self,
    color: Colorf = .cyan,
    fixed_range: bool = false,
    max_range: f32 = std.math.inf(f32),
    show_max_range_ring: bool = false,
    ray_to_mouse: ?Ray = null,
    target_faction_mask: Thing.Faction.Mask = .{},
    target_mouse_pos: bool = false,
    radius_at_target: ?f32 = null,
    cone_from_self_to_mouse: ?struct {
        radius: f32,
        radians: f32,
    } = null,
    requires_los_to_thing: bool = false,

    fn fmtRange(self: *const TargetingData, buf: []u8) Error![]u8 {
        if (self.max_range == std.math.inf(f32)) return buf[0..0];
        return try std.fmt.bufPrint(buf, "Range: {}\n", .{utl.as(u32, @floor(self.max_range))});
    }

    pub fn fmtDesc(self: *const TargetingData, buf: []u8) Error![]u8 {
        var len: usize = 0;
        len += (try std.fmt.bufPrint(buf[len..], "Target: {s}\n", .{
            switch (self.kind) {
                .self => "self",
                .thing => "thing",
                .pos => "ground",
            },
        })).len;
        len += (try self.fmtRange(buf[len..])).len;
        return buf[0..len];
    }

    pub fn getRayEnd(self: *const TargetingData, room: *const Room, caster: *const Thing, ray: Ray, target_pos: V2f) V2f {
        const caster_to_target = target_pos.sub(caster.pos);
        const target_dir = if (caster_to_target.normalizedChecked()) |d| d else return target_pos;
        const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
        const cast_orig_to_target = target_pos.sub(cast_orig);
        if (cast_orig_to_target.dot(target_dir) < 0) return cast_orig;

        const max_radius = self.max_range + caster.coll_radius;
        const capped_dist = if (self.fixed_range) max_radius else @min(max_radius, cast_orig.length());
        const capped_vec = target_dir.scale(capped_dist);
        const ray_radius = ray.thickness * 0.5;

        var target_hit_pos = cast_orig.add(capped_vec);
        var end_ray_pos = target_hit_pos;

        if (Collision.getNextSweptCircleCollision(
            cast_orig,
            capped_vec,
            ray_radius,
            ray.ends_at_coll_mask,
            &.{caster.id},
            room,
        )) |coll| {
            target_hit_pos = coll.pos;
            end_ray_pos = coll.pos.add(coll.normal.scale(ray_radius));
        }

        return end_ray_pos;
    }
    pub fn getTargetedThing(targeting_data: *const TargetingData, room: *Room, caster: *const Thing, mouse_pos: V2f, require_los: bool) ?*Thing {
        const thing = room.getMousedOverThing(targeting_data.target_faction_mask) orelse
            room.getClosestThingToPoint(mouse_pos, null, targeting_data.target_faction_mask) orelse
            return null;
        if (!targeting_data.target_faction_mask.contains(thing.faction)) return null;
        const range = @max(caster.pos.dist(thing.pos) - caster.coll_radius - thing.coll_radius, 0);
        if (range > targeting_data.max_range) {
            return null;
        }
        if (require_los and !room.tilemap.isLOSBetween(caster.pos, thing.pos)) return null;
        return thing;
    }

    pub fn getParams(targeting_data: *const TargetingData, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
        switch (targeting_data.kind) {
            .pos => {
                const caster_to_mouse = mouse_pos.sub(caster.pos);
                const target_dir = if (caster_to_mouse.normalizedChecked()) |d| d else V2f.right;
                const max_radius = targeting_data.max_range + caster.coll_radius;
                const capped_dist = if (targeting_data.fixed_range) max_radius else @min(max_radius, caster_to_mouse.length());
                const capped_vec = target_dir.scale(capped_dist);
                var target_pos = caster.pos.add(capped_vec);
                var ret = Params{
                    .target_kind = .pos,
                    .pos = target_pos,
                    .face_dir = target_pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                };
                if (targeting_data.ray_to_mouse) |ray| {
                    const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
                    if (target_pos.sub(cast_orig).dot(target_dir) < 0) {
                        ret.pos = cast_orig;
                    }
                    ret.cast_orig = cast_orig;
                }
                return ret;
            },
            .self => {
                return .{
                    .target_kind = .self,
                    .thing = caster.id,
                    .pos = caster.pos,
                };
            },
            .thing => {
                const thing = targeting_data.getTargetedThing(
                    room,
                    caster,
                    mouse_pos,
                    targeting_data.requires_los_to_thing,
                ) orelse return null;
                return .{
                    .target_kind = .thing,
                    .face_dir = thing.pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                    .thing = thing.id,
                    .pos = thing.pos,
                };
            },
        }
        return null;
    }

    pub fn render(targeting_data: *const TargetingData, room: *const Room, caster: *const Thing, params: ?Params) Error!void {
        const plat = App.getPlat();

        if (params == null) {
            if (targeting_data.show_max_range_ring and targeting_data.max_range < 99999) {
                plat.circlef(
                    caster.pos,
                    targeting_data.max_range + caster.coll_radius,
                    .{
                        .outline = .{ .color = targeting_data.color.fade(0.5) },
                        .fill_color = null,
                    },
                );
            }
        }

        switch (targeting_data.kind) {
            .pos => {
                const mouse_pos = if (params) |p| p.pos else plat.getMousePosWorld(room.camera);
                const caster_to_mouse = mouse_pos.sub(caster.pos);
                const target_dir = if (caster_to_mouse.normalizedChecked()) |d| d else V2f.right;
                const max_radius = targeting_data.max_range + caster.coll_radius;
                const capped_dist = if (targeting_data.fixed_range) max_radius else @min(max_radius, caster_to_mouse.length());
                const capped_vec = target_dir.scale(capped_dist);
                var target_circle_pos = caster.pos.add(capped_vec);

                if (targeting_data.ray_to_mouse) |ray| {
                    const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
                    if (mouse_pos.sub(cast_orig).dot(target_dir) > 0) {
                        const ray_end = targeting_data.getRayEnd(room, caster, ray, target_circle_pos);
                        if (ray_end.sub(caster.pos).length() < capped_dist) {
                            target_circle_pos = ray_end;
                        }
                    } else {
                        target_circle_pos = cast_orig;
                    }
                    const ray_radius = ray.thickness * 0.5;
                    plat.circlef(cast_orig, ray_radius, .{ .fill_color = targeting_data.color });
                    plat.linef(cast_orig, target_circle_pos, .{ .thickness = ray.thickness, .color = targeting_data.color });
                    plat.circlef(target_circle_pos, ray_radius, .{ .fill_color = targeting_data.color });
                    //if (coll) |c| {
                    //    plat.circlef(c.pos, 3, .{ .fill_color = .red });
                    //}
                }
                if (targeting_data.cone_from_self_to_mouse) |cone| {
                    const start_rads = target_dir.toAngleRadians() - cone.radians * 0.5;
                    const end_rads = start_rads + cone.radians;
                    //try plat.textf(caster.pos.add(V2f.right.scale(cone.radius * 0.5).rotRadians(start_rads)), "{d:.3}", .{start_rads}, .{ .color = .white });
                    plat.sectorf(
                        caster.pos,
                        cone.radius,
                        start_rads,
                        end_rads,
                        .{ .fill_color = targeting_data.color.fade(0.5) },
                    );
                }
                if (targeting_data.radius_at_target) |r| {
                    plat.circlef(target_circle_pos, r, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
                if (targeting_data.target_mouse_pos) {
                    plat.circlef(target_circle_pos, 10, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
            },
            .self => {
                if (caster.selectable) |s| {
                    plat.circlef(caster.pos, s.radius, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
                if (targeting_data.radius_at_target) |r| {
                    plat.circlef(caster.pos, r, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
            },
            .thing => {
                const maybe_targeted_thing = if (params) |p|
                    room.getConstThingById(p.thing.?)
                else
                    targeting_data.getTargetedThing(@constCast(room), caster, plat.getMousePosWorld(room.camera), false);

                // show all possible target...
                // but only if params are not passed in
                if (params == null) {
                    for (&room.things.items) |*thing| {
                        if (!thing.isActive()) continue;
                        if (thing.selectable == null) continue;
                        if (!targeting_data.target_faction_mask.contains(thing.faction)) continue;
                        const range = @max(caster.pos.dist(thing.pos) - caster.coll_radius - thing.coll_radius, 0);
                        if (range > targeting_data.max_range) continue;
                        // we're already drawing it after this loop
                        if (maybe_targeted_thing) |targeted_thing| {
                            if (thing.id.eql(targeted_thing.id)) {
                                continue;
                            }
                        }
                        const selectable = thing.selectable.?;
                        plat.circlef(
                            thing.pos,
                            selectable.radius - 5,
                            .{
                                .fill_color = null,
                                .outline = .{ .color = targeting_data.color.fade(0.5) },
                            },
                        );
                    }
                }
                // selected target, if any
                if (maybe_targeted_thing) |thing| {
                    const range = @max(caster.pos.dist(thing.pos) - caster.coll_radius - thing.coll_radius, 0);
                    if (range <= targeting_data.max_range) {
                        var targeting_color = targeting_data.color;
                        if (targeting_data.requires_los_to_thing) {
                            if (room.tilemap.raycastLOS(caster.pos, thing.pos)) |tile_coord| {
                                targeting_color = .red;
                                const rect = TileMap.tileCoordToRect(tile_coord);
                                plat.rectf(rect.pos, rect.dims, .{
                                    .fill_color = null,
                                    .outline = .{
                                        .color = Colorf.red.fade(0.6),
                                        .thickness = 1,
                                    },
                                });
                            }
                        }
                        if (targeting_data.ray_to_mouse) |ray| {
                            const ray_radius = @max(@round(ray.thickness * 0.5), 1);
                            plat.linef(caster.pos, thing.pos, .{
                                .thickness = ray.thickness,
                                .color = targeting_color,
                                .round_to_pixel = true,
                                .smoothing = .bilinear,
                            });
                            plat.circlef(thing.pos, ray_radius, .{
                                .fill_color = targeting_color,
                                .round_to_pixel = true,
                                .smoothing = .bilinear,
                            });
                        }
                        if (targeting_data.radius_at_target) |r| {
                            plat.circlef(thing.pos, r, .{
                                .fill_color = targeting_color.fade(0.4),
                                .round_to_pixel = true,
                            });
                        }
                        // we always gotta check this... things can become unselectable e.g. when dying
                        if (thing.selectable) |s| {
                            plat.circlef(
                                thing.pos,
                                s.radius,
                                .{ .fill_color = targeting_color.fade(0.5) },
                            );
                        }
                    }
                }
            },
        }
    }
};

pub const Controller = struct {
    const ControllerTypes = blk: {
        var num = 0;
        for (SpellTypes) |M| {
            if (@hasDecl(M, "Controllers")) {
                for (M.Controllers) |_| {
                    num += 1;
                }
            }
        }
        var Types: [num]type = undefined;
        var i = 0;
        for (SpellTypes) |M| {
            if (@hasDecl(M, "Controllers")) {
                for (M.Controllers) |C| {
                    Types[i] = C;
                    i += 1;
                }
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

pub const max_spells_in_array = 256;
pub const SpellArray = std.BoundedArray(Spell, max_spells_in_array);
const WeightsArray = std.BoundedArray(f32, max_spells_in_array);
pub const RarityWeights = std.EnumArray(Rarity, f32);
pub const rarity_weight_offsets_base = RarityWeights.init(.{
    .pedestrian = 0.0,
    .interesting = 0.0,
    .exceptional = 0.0,
    .brilliant = 0.0,
});

pub fn getSpellWeights(rarity_weights: RarityWeights, spells: []const Spell) WeightsArray {
    var ret = WeightsArray{};
    for (spells) |spell| {
        ret.append(rarity_weights.get(spell.rarity)) catch unreachable;
    }
    return ret;
}

pub fn makeRoomReward(rng: std.Random, mode: Run.Mode, rarity_weight_offsets: *RarityWeights, buf: []Spell) []Spell {
    const rarity_weight_base = RarityWeights.init(.{
        .pedestrian = 0.60,
        .interesting = 0.40,
        .exceptional = -0.08,
        .brilliant = 0.00,
    });
    var num: usize = 0;
    var spell_pool = SpellArray{};
    for (all_spells) |spell| {
        if (spell.obtainable_modes.contains(mode) and spell.obtainableness.intersectWith(Obtainableness.Mask.initOne(.room_reward)).count() > 0) {
            spell_pool.append(spell) catch unreachable;
        }
    }
    var rarity_weights = rarity_weight_base;
    for (utl.enumValueList(Rarity)) |r| {
        rarity_weights.getPtr(r).* += rarity_weight_offsets.get(r);
    }

    for (0..buf.len) |i| {
        if (spell_pool.len == 0) break;
        // fix up negative rare value
        var adjusted_weights = rarity_weights;
        {
            const rare_weight = rarity_weights.get(.exceptional);
            if (rare_weight < 0) {
                adjusted_weights.set(.exceptional, 0);
            }
        }
        const weights = getSpellWeights(adjusted_weights, spell_pool.constSlice());
        const idx = rng.weightedIndex(f32, weights.constSlice());
        // no duplicates! remove from pool
        const spell = spell_pool.swapRemove(idx);
        buf[i] = spell;
        buf[i].debug_rarity_weight = rarity_weights.get(spell.rarity);
        {
            const rare_weight = rarity_weights.get(.exceptional);
            switch (spell.rarity) {
                .pedestrian, .interesting => if (rare_weight <= 0.40) {
                    rarity_weight_offsets.getPtr(.pedestrian).* -= 0.02;
                    rarity_weight_offsets.getPtr(.interesting).* -= 0.02;
                    rarity_weight_offsets.getPtr(.exceptional).* += 0.04;
                },
                .exceptional, .brilliant => {
                    rarity_weight_offsets.* = rarity_weight_offsets_base;
                },
            }
            rarity_weights = rarity_weight_base;
            for (utl.enumValueList(Rarity)) |r| {
                rarity_weights.getPtr(r).* += rarity_weight_offsets.get(r);
            }
        }
        num += 1;
    }
    return buf[0..num];
}

pub fn makeShopSpells(rng: std.Random, mode: Run.Mode, rarity_weights: *const RarityWeights, buf: []Spell) []Spell {
    var num: usize = 0;
    var spell_pool = SpellArray{};
    for (all_spells) |spell| {
        if (spell.obtainable_modes.contains(mode) and spell.obtainableness.intersectWith(Obtainableness.Mask.initOne(.shop)).count() > 0) {
            spell_pool.append(spell) catch unreachable;
        }
    }
    for (0..buf.len) |i| {
        if (spell_pool.len == 0) break;
        const weights = getSpellWeights(rarity_weights.*, spell_pool.constSlice());
        const idx = rng.weightedIndex(f32, weights.constSlice());
        // no duplicates! remove from pool
        const spell = spell_pool.swapRemove(idx);
        buf[i] = spell;
        num += 1;
    }
    return buf[0..num];
}

pub const Obtainableness = enum {
    pub const Mask = std.EnumSet(Obtainableness);

    starter,
    room_reward,
    shop,
};

pub const ManaCost = union(enum) {
    pub const SpriteEnum = enum {
        zero,
        one,
        two,
        three,
        four,
        five,
        six,
        seven,
        eight,
        nine,
        X,
        unknown,
        crystal,
        hourglass,
    };
    number: u8,
    X,
    unknown,

    pub fn num(n: u8) ManaCost {
        assert(n < 10);
        return ManaCost{ .number = n };
    }

    pub fn getActualCost(self: ManaCost, caster: *const Thing) ?u8 {
        return switch (self) {
            .number => |n| n,
            .X => if (caster.mana) |mana| utl.as(u8, mana.curr) else 0,
            .unknown => null,
        };
    }

    pub fn toSpriteEnum(self: ManaCost) SpriteEnum {
        return switch (self) {
            .number => |n| @enumFromInt(n),
            .X => .X,
            .unknown => .unknown,
        };
    }
};

pub const NewTag = struct {
    pub const Array = std.BoundedArray(NewTag, 8);
    pub const CardLabel = utl.BoundedString(16);

    card_label: CardLabel = .{},
    start_on_new_line: bool = false,

    pub fn fromFmt(comptime fmt: []const u8, args: anytype) NewTag {
        return .{
            .card_label = CardLabel.fromSlice(
                std.fmt.bufPrint(desc_buf[0..16], fmt, args) catch "FMT ERR:TOO LONG",
            ) catch unreachable,
        };
    }

    pub fn makeDamage(kind: Thing.Damage.Kind, amount: f32, aoe_hits_allies: bool) Error!NewTag {
        var ret = NewTag{};
        var icon: icon_text.Icon = .blood_splat;
        var dmg_type_string: []const u8 = "";
        switch (kind) {
            .magic => {
                icon = if (aoe_hits_allies) .aoe_magic else .magic;
                dmg_type_string = "Magic ";
            },
            .fire => {
                icon = if (aoe_hits_allies) .aoe_fire else .fire;
                dmg_type_string = "Fire ";
            },
            .ice => {
                icon = if (aoe_hits_allies) .aoe_ice else .icicle;
                dmg_type_string = "Ice ";
            },
            .lightning => {
                icon = if (aoe_hits_allies) .aoe_lightning else .lightning;
                dmg_type_string = "Lightning ";
            },
            else => {},
        }
        var buf: [64]u8 = undefined;
        ret.card_label = try CardLabel.fromSlice(
            try icon_text.partsToUtf8(&buf, &.{
                .{ .icon = icon },
                .{ .text = try utl.bufPrintLocal("{d:.0}", .{@floor(amount)}) },
            }),
        );
        return ret;
    }
    pub fn makeStatus(kind: StatusEffect.Kind, stacks: i32) Error!NewTag {
        var buf: [64]u8 = undefined;
        var ret = NewTag{};
        ret.card_label = try CardLabel.fromSlice(try StatusEffect.fmtTag(&buf, kind, stacks));
        return ret;
    }
};

pub const Keyword = enum {
    mislay,

    pub fn getIcon(self: Keyword) icon_text.Icon {
        const enum_name = utl.enumToString(Keyword, self);
        if (std.meta.stringToEnum(icon_text.Icon, enum_name)) |icon| {
            return icon;
        }
        return .target; // TODO?
    }
    pub fn fmtName(self: Keyword, buf: []u8) Error![]const u8 {
        return std.fmt.bufPrint(buf, "{any}", .{self});
    }
    pub fn fmtDesc(self: Keyword, buf: []u8) Error![]const u8 {
        return switch (self) {
            .mislay => try std.fmt.bufPrint(buf, "The card is lost until the next room", .{}),
        };
    }
    pub fn format(self: Keyword, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        const enum_name = utl.enumToString(Keyword, self);
        const first_letter = [1]u8{std.ascii.toUpper(enum_name[0])};
        writer.print("{any}{s}{s}", .{
            self.getIcon(),
            &first_letter,
            enum_name[1..],
        }) catch return Error.EncodingFail;
    }
};

pub const CastTime = enum {
    fast,
    medium,
    slow,
};

pub const cast_time_to_secs = std.EnumArray(CastTime, f32).init(.{
    .fast = 0.1,
    .medium = 0.66,
    .slow = 1.2,
});

kind: KindData = undefined,
rarity: Rarity = .pedestrian,
obtainableness: Obtainableness.Mask = Obtainableness.Mask.initMany(&.{ .room_reward, .shop }),
obtainable_modes: Run.Mode.Mask = Run.Mode.Mask.initFull(),
color: Colorf = .white,
cast_sound: Data.Ref(Data.Sound) = Data.Ref(Data.Sound).init("cast-end"),
targeting_data: TargetingData = .{},
cast_time: CastTime,
cast_secs: f32 = 1, // time from spell starting to when it's cast() is called - caster can't move or do anything except buffer inputs
cast_ticks: i32 = 60,
after_cast_slot_cooldown_secs: f32 = 4,
after_cast_slot_cooldown_ticks: i32 = 4 * 60,
mislay: bool = false,
draw_immediate: bool = false,
mana_cost: ManaCost = .{ .number = 1 },
debug_rarity_weight: f32 = 0,

pub fn getSlotCooldownTicks(self: *const Spell) i32 {
    return self.cast_ticks + self.after_cast_slot_cooldown_ticks;
}

pub fn makeProto(kind: Kind, the_rest: Spell) Spell {
    var ret = the_rest;
    ret.kind = @unionInit(KindData, @tagName(kind), .{});
    ret.cast_secs = cast_time_to_secs.get(ret.cast_time);
    //ret.cast_secs = cast_time_to_secs.get(.fast);
    ret.cast_ticks = utl.as(i32, core.fups_per_sec_f * ret.cast_secs);
    ret.after_cast_slot_cooldown_ticks = utl.as(i32, core.fups_per_sec_f * ret.after_cast_slot_cooldown_secs);
    return ret;
}

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

pub fn canUse(self: *const Spell, caster: *const Thing) bool {
    if (!caster.canAct()) return false;
    if (caster.mana) |mana| {
        if (self.mana_cost.getActualCost(caster)) |cost| {
            if (mana.curr < cost) return false;
        }
    }
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "canUse")) {
                return K.canUse(self, caster);
            }
        },
    }
    return true;
}

pub fn getFlavor(self: *const Spell) []const u8 {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getFlavor")) {
                return K.getFlavor(self);
            }
        },
    }
    return "";
}

pub fn getTooltip(self: *const Spell, info: *Tooltip) Error!void {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getTooltip")) {
                return try K.getTooltip(self, info);
            }
        },
    }
}

pub fn getNewTags(self: *const Spell) Error!NewTag.Array {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getNewTags")) {
                return try K.getNewTags(self);
            } else {
                return .{};
            }
        },
    }
}

const rarity_price_base = std.EnumArray(Rarity, i32).init(.{
    .pedestrian = 5,
    .interesting = 9,
    .exceptional = 15,
    .brilliant = 27,
});

const rarity_price_variance = std.EnumArray(Rarity, i32).init(.{
    .pedestrian = 1,
    .interesting = 3,
    .exceptional = 4,
    .brilliant = 5,
});

pub fn getShopPrice(self: *const Spell, rng: std.Random) i32 {
    const base = rarity_price_base.get(self.rarity);
    const variance = rarity_price_variance.get(self.rarity);
    return base - variance + rng.intRangeAtMost(i32, 0, variance * 2);
}

pub inline fn getTargetParams(self: *const Spell, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
    return self.targeting_data.getParams(room, caster, mouse_pos);
}

pub inline fn renderTargeting(self: *const Spell, room: *const Room, caster: *const Thing, params: ?Params) Error!void {
    return self.targeting_data.render(room, caster, params);
}

pub fn getName(self: *const Spell) []const u8 {
    const kind = std.meta.activeTag(self.kind);
    return spell_names.get(kind);
}

pub fn unqRenderCard(self: *const Spell, cmd_buf: *ImmUI.CmdBuf, pos: V2f, caster: ?*const Thing, scaling: f32) void {
    const data = App.get().data;
    var have_enough_mana = true;
    if (caster) |c|
        if (c.mana) |mana|
            if (self.mana_cost.getActualCost(c)) |cost| {
                have_enough_mana = (cost <= mana.curr);
            };
    // this does check mana so a little redundant but...
    const show_as_disabled = if (caster) |c| !self.canUse(c) else false;

    if (data.card_sprites.getRenderFrame(.card_base)) |rf| {
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = pos,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
                .round_to_pixel = true,
            },
        } });
    }
    // art and rarity frame
    const art_topleft = pos.add(card_art_topleft_offset.scale(scaling));
    const rii: sprites.RenderIconInfo = blk: {
        const kind = std.meta.activeTag(self.kind);
        if (data.spell_icons.getRenderFrame(kind)) |render_frame| {
            break :blk .{ .frame = render_frame };
        } else {
            const name = spell_names.get(kind);
            break :blk .{ .letter = .{
                .str = [1]u8{std.ascii.toUpper(name[0])},
                .color = self.color,
            } };
        }
    };
    rii.unqRender(cmd_buf, art_topleft, scaling) catch @panic("failed renderino");
    if (data.card_sprites.getRenderFrame(CardSpriteEnum.fromRarity(self.rarity))) |rf| {
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = pos,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
                .round_to_pixel = true,
            },
        } });
    }
    // title
    const title_center_pos = pos.add(card_title_center_offset.scale(scaling));
    const title_font = data.fonts.get(.pixeloid);
    cmd_buf.appendAssumeCapacity(.{ .label = .{
        .pos = title_center_pos,
        .text = ImmUI.initLabel(self.getName()),
        .opt = .{
            .color = .white,
            .size = title_font.base_size * utl.as(u32, scaling),
            .center = true,
            .font = title_font,
            .smoothing = .none,
            .border = .{
                .color = .black,
                .dist = scaling,
            },
        },
    } });
    // mana crystal
    const mana_topleft = pos.add(card_mana_topleft_offset.scale(scaling));
    if (data.card_mana_cost.getRenderFrame(.crystal)) |rf| {
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = mana_topleft,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
                .round_to_pixel = true,
            },
        } });
    }
    // mana cost
    if (data.card_mana_cost.getRenderFrame(self.mana_cost.toSpriteEnum())) |rf| {
        const tint: Colorf = if (have_enough_mana) .white else .red;
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = mana_topleft,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
                .tint = tint,
                .round_to_pixel = true,
            },
        } });
    }
    // hourglasses
    const hourglass_right_topleft = pos.add(card_hourglass_offset.scale(scaling));
    if (data.card_mana_cost.getRenderFrame(.hourglass)) |rf| {
        const cropped_dims = data.card_mana_cost.sprite_dims_cropped.?.get(.hourglass);
        var opt = rf.toTextureOpt(scaling);
        opt.src_dims = cropped_dims;
        opt.origin = .topleft;
        opt.round_to_pixel = true;
        const num: usize = @intFromEnum(self.cast_time) + 1;
        for (0..num) |i| {
            const hourglass_pos = hourglass_right_topleft.sub(v2f(
                utl.as(f32, i) * (cropped_dims.x + 1) * scaling,
                0,
            ));
            cmd_buf.appendAssumeCapacity(.{ .texture = .{
                .pos = hourglass_pos,
                .texture = rf.texture,
                .opt = opt,
            } });
        }
    }
    {
        const tags = self.getNewTags() catch |e| blk: {
            Log.errorAndStackTrace(e);
            break :blk NewTag.Array{};
        };
        const tag_topleft = pos.add(card_tags_topleft_offset.scale(scaling));
        var curr_tag_topleft = tag_topleft;
        for (tags.constSlice()) |tag| {
            // first measure
            const tag_dims = icon_text.measureIconText(tag.card_label.constSlice()).add(v2f(2, 1));
            const tag_dims_scaled = tag_dims.scale(scaling);
            if (curr_tag_topleft.x != tag_topleft.x and (tag.start_on_new_line or curr_tag_topleft.x + tag_dims_scaled.x > tag_topleft.x + card_tags_dims.x * scaling)) {
                curr_tag_topleft.y += tag_dims_scaled.y + (1 * scaling);
                curr_tag_topleft.x = tag_topleft.x;
            }
            // now actually draw
            cmd_buf.appendAssumeCapacity(.{
                .rect = .{
                    .pos = curr_tag_topleft,
                    .dims = tag_dims_scaled,
                    .opt = .{
                        .fill_color = .black,
                        .edge_radius = 0.3,
                        .round_to_pixel = true,
                    },
                },
            });
            icon_text.unqRenderIconText(
                cmd_buf,
                tag.card_label.constSlice(),
                curr_tag_topleft.add(V2f.splat(1 * scaling)),
                scaling,
            ) catch {};
            curr_tag_topleft.x += tag_dims_scaled.x + 1 * scaling;
        }
    }
    // tint disabled
    if (show_as_disabled) {
        if (data.card_sprites.getRenderFrame(.card_blank)) |rf| {
            cmd_buf.appendAssumeCapacity(.{ .texture = .{
                .pos = pos,
                .texture = rf.texture,
                .opt = .{
                    .src_dims = rf.size.toV2f(),
                    .src_pos = rf.pos.toV2f(),
                    .uniform_scaling = scaling,
                    .tint = Colorf.black.fade(0.5),
                    .round_to_pixel = true,
                },
            } });
        }
    }
    if (debug.show_rarity_weights) {
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = pos,
            .text = ImmUI.initLabel(utl.bufPrintLocal("rarity: {d:0.3}", .{self.debug_rarity_weight}) catch "rarity: ?"),
            .opt = .{
                .color = .white,
            },
        } });
    }
}

pub fn unqRenderTooltip(self: *const Spell, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32) Error!void {
    var tt: Tooltip = .{};
    try self.getTooltip(&tt);
    if (tt.desc.len > 0) {
        try tt.unqRender(cmd_buf, pos, scaling);
    }
}
