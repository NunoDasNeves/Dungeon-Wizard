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

const creatures = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const AI = @import("AI.zig");
const player = @import("player.zig");
const sprites = @import("sprites.zig");
const icon_text = @import("icon_text.zig");
const Spell = @import("Spell.zig");
const Action = @import("Action.zig");

pub const Kind = enum {
    player,
    dummy,
    troll,
    gobbow,
    sharpboi,
    impling,
    bat,
    acolyte,
    slime,
    gobbomber,

    pub fn getIcon(self: Kind) icon_text.Icon {
        if (self == .player) {
            return .wizard;
        }
        const enum_name = utl.enumToString(Thing.CreatureKind, self);
        if (std.meta.stringToEnum(icon_text.Icon, enum_name)) |icon| {
            return icon;
        }
        return .skull;
    }
    pub fn fmtName(self: Kind, buf: []u8) Error![]const u8 {
        return std.fmt.bufPrint(buf, "{any}", .{self});
    }
    pub fn fmtDesc(self: Kind, buf: []u8) Error![]const u8 {
        const proto = App.get().data.creature_protos.get(self);
        const hp_fmt_opts: usize = @bitCast(Thing.HP.FmtOpts{ .max_only = true });
        const hp_buf = if (proto.hp) |hp| try std.fmt.bufPrint(buf, "{any:." ++ std.fmt.comptimePrint("{}", .{hp_fmt_opts}) ++ "}", .{hp}) else "";
        if (proto.controller != .ai_actor) return hp_buf;
        const ai_actor = proto.controller.ai_actor;
        var curr_idx: usize = hp_buf.len;
        if (false) {
            var action_bufs = std.EnumArray(Action.Slot, []u8).initFill("");
            var action_it = ai_actor.actions.iterator();
            while (action_it.next()) |slot| {
                if (slot.value == null) continue;
                if (curr_idx >= buf.len) break;
                buf[curr_idx] = '\n';
                curr_idx += 1;
                const action_buf = try std.fmt.bufPrint(buf[curr_idx..], "{any}", .{slot.value.?});
                curr_idx += action_buf.len;
                action_bufs.getPtr(slot.key).* = action_buf;
            }
        }
        return buf[0..curr_idx];
    }
    pub fn format(self: Kind, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        const enum_name = utl.enumToString(Thing.CreatureKind, self);
        const first_letter = [1]u8{std.ascii.toUpper(enum_name[0])};
        writer.print("{any}{s}{s}", .{
            self.getIcon(),
            &first_letter,
            enum_name[1..],
        }) catch return Error.EncodingFail;
    }
};

pub const proto_fns = blk: {
    var ret: std.EnumArray(Kind, fn () Thing) = undefined;
    for (@typeInfo(Kind).@"enum".fields) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const fn_name = f.name ++ "Proto";
        ret.getPtr(kind).* = @field(creatures, fn_name);
    }
    break :blk ret;
};

pub fn playerProto() Thing {
    var ret = creatureProto(.player, .wizard, .player, null, 40, .medium, 18);
    ret.accel_params = .{
        .accel = 0.0023 * TileMap.tile_sz_f,
        .friction = 0.0014 * TileMap.tile_sz_f,
        .max_speed = 0.01875 * TileMap.tile_sz_f,
    };
    ret.vision_range = TileMap.tile_sz_f * 4;
    ret.player_input = player.Input{
        .actions = .{},
    };
    ret.controller = .{ .player = .{} };

    return ret;
}

pub fn implingProto() Thing {
    var ret = creatureProto(.impling, .impling, .ally, .{ .aggro = .{} }, 25, .medium, 13);

    ret.accel_params = .{
        .max_speed = 0.0156 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.ally),
                    .radius = 10,
                    .rel_pos = V2f.right.scale(10),
                    .effect = .{ .damage = 6 },
                },
                .range = 15,
            },
        },
        .cooldown = utl.TickCounter.initStopped(60),
    });
    return ret;
}

pub fn slimeProto() Thing {
    var c = creatureProto(.slime, .slime, .enemy, .{ .aggro = .{} }, 14, .big, 13);
    c.accel_params = .{
        .max_speed = 0.0109 * TileMap.tile_sz_f,
    };
    c.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 10,
                    .rel_pos = V2f.right.scale(5),
                    .sweep_to_rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 6 },
                },
                .range = 20,
            },
        },
        .cooldown = utl.TickCounter.initStopped(90),
    });
    c.enemy_difficulty = 0.75;
    return c;
}

pub fn batProto() Thing {
    var ret = creatureProto(.bat, .bat, .enemy, .{ .aggro = .{} }, 4, .smol, 17);
    ret.accel_params = .{
        .max_speed = 0.0172 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 10,
                    .rel_pos = V2f.right.scale(10),
                    .effect = .{ .damage = 3 },
                },
                .range = 12.5,
            },
        },
        .cooldown = utl.TickCounter.initStopped(70),
    });
    ret.enemy_difficulty = 0.25;
    return ret;
}

pub fn trollProto() Thing {
    var ret = creatureProto(.troll, .troll, .enemy, .{ .troll = .{} }, 40, .big, 20);
    ret.accel_params = .{
        .max_speed = 0.0109 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 10,
                    .rel_pos = V2f.right.scale(10),
                    .sweep_to_rel_pos = V2f.right.scale(25),
                    .effect = .{ .damage = 12 },
                },
                .range = 25,
            },
        },
        .cooldown = utl.TickCounter.initStopped(90),
    });
    ret.controller.ai_actor.actions.getPtr(.ability_1).* = (.{
        .kind = .{
            .regen_hp = .{
                .amount_per_sec = 5,
                .max_regen = 25,
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(5)),
    });
    ret.enemy_difficulty = 3;

    return ret;
}

pub fn gobbowProto() Thing {
    var ret = creatureProto(
        .gobbow,
        .gobbow,
        .enemy,
        .{ .ranged_flee = .{} },
        18,
        .medium,
        12,
    );
    ret.accel_params = .{
        .max_speed = 0.0141 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 115;
    ret.controller.ai_actor.actions.getPtr(.projectile_attack_1).* = (.{
        .kind = .{ .projectile_attack = .{
            .projectile = .arrow,
            .range = 110,
            .LOS_thiccness = 5,
        } },
        .cooldown = utl.TickCounter.initStopped(60),
    });
    ret.enemy_difficulty = 1.5;
    return ret;
}

pub fn sharpboiProto() Thing {
    var ret = creatureProto(.sharpboi, .sharpboi, .enemy, .{ .aggro = .{} }, 25, .medium, 18);

    ret.accel_params = .{
        .max_speed = 0.0141 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .lunge_accel = .{
                    .accel = 2.5,
                    .max_speed = 2.4,
                    .friction = 0,
                },
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.enemy),
                    .radius = 7.5,
                    .rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 8 },
                    .deactivate_on_update = false,
                    .deactivate_on_hit = true,
                },
                .hit_to_side_force = 1.25,
                .range = 50,
                .LOS_thiccness = ret.coll_radius * 0.5,
            },
        },
        .cooldown = utl.TickCounter.initStopped(140),
    });
    ret.enemy_difficulty = 2.5;
    return ret;
}

pub fn acolyteProto() Thing {
    var ret = creatureProto(.acolyte, .acolyte, .enemy, .{ .acolyte = .{} }, 25, .medium, 12);
    ret.accel_params = .{
        .accel = 0.0047 * TileMap.tile_sz_f,
        .max_speed = 0.0188 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 120;
    ret.controller.ai_actor.actions.getPtr(.spell_cast_summon_1).* = (.{
        .kind = .{ .spell_cast = .{
            .spell = Spell.getProto(.summon_bat),
        } },
        .cooldown = utl.TickCounter.initStopped(5 * core.fups_per_sec),
    });
    ret.enemy_difficulty = 2.5;
    return ret;
}

pub fn gobbomberProto() Thing {
    var ret = creatureProto(
        .gobbomber,
        .gobbomber,
        .enemy,
        .{ .gobbomber = .{} },
        15,
        .medium,
        12,
    );
    ret.hp.?.addShield(8, null);
    ret.accel_params = .{
        .max_speed = 0.0125 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 90;
    ret.controller.ai_actor.actions.getPtr(.ability_1).* = .{
        .kind = .{ .shield_up = .{
            .amount = 8,
        } },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(10)),
    };
    ret.controller.ai_actor.actions.getPtr(.projectile_attack_1).* = .{
        .kind = .{ .projectile_attack = .{
            .projectile = .bomb,
            .range = 95,
            .LOS_thiccness = 5,
        } },
        .cooldown = utl.TickCounter.initStopped(90),
    };
    ret.enemy_difficulty = 2.0;
    return ret;
}

pub fn dummyProto() Thing {
    var ret = creatureProto(.dummy, .dummy, .enemy, null, 25, .medium, 20);
    ret.enemy_difficulty = 1.5;
    return ret;
}

pub fn creatureProto(creature_kind: Kind, sprite_kind: sprites.CreatureAnim.Kind, faction: Thing.Faction, ai: ?AI.ActorController.KindData, hp: f32, size_cat: Thing.SizeCategory, select_height_px: f32) Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = creature_kind,
        .spawn_state = .instance,
        .vision_range = 80,
        .coll_radius = Thing.SizeCategory.coll_radii.get(size_cat),
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = if (ai) |a| .{ .ai_actor = .{ .ai = a } } else .default,
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = Thing.SizeCategory.draw_radii.get(size_cat),
            .hp_bar_width = Thing.SizeCategory.hp_bar_width.get(size_cat),
        } },
        .animator = .{ .kind = .{ .creature = .{ .kind = sprite_kind } } },
        .hurtbox = .{
            .radius = Thing.SizeCategory.hurtbox_radii.get(size_cat),
        },
        .selectable = .{
            .height = select_height_px * core.game_sprite_scaling,
            .radius = Thing.SizeCategory.select_radii.get(size_cat),
        },
        .hp = Thing.HP.init(hp),
        .faction = faction,
    };
}
