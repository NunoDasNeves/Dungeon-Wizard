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
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const Spell = @import("Spell.zig");
const Action = @import("Action.zig");

pub fn getThingsInRadius(self: *Thing, room: *Room, radius: f32, buf: []*Thing) usize {
    var num: usize = 0;
    for (&room.things.items) |*thing| {
        if (num >= buf.len) break;
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;

        const dist = thing.pos.dist(self.pos);

        if (dist < radius) {
            buf[num] = thing;
            num += 1;
        }
    }
    return num;
}

pub fn getNearestThing(self: *Thing, room: *Room, only_attackable: bool, only_visible: bool, allow_fairy: bool, faction_mask: Thing.Faction.Mask) ?*Thing {
    var closest_dist = std.math.inf(f32);
    var closest: ?*Thing = null;
    for (&room.things.items) |*other| {
        if (!other.isActive()) continue;
        if (other.id.eql(self.id)) continue;
        if (!faction_mask.contains(other.faction)) continue;
        if (only_visible and other.isInvisible()) continue;
        if (only_attackable and !other.isAttackableCreature()) continue;
        if (!allow_fairy and other.isFairy()) continue;
        const dist = other.pos.dist(self.pos);
        if (dist < closest_dist) {
            closest_dist = dist;
            closest = other;
        }
    }
    return closest;
}

pub fn getNearestOpposingThing(self: *Thing, room: *Room) ?*Thing {
    return getNearestThing(self, room, true, true, true, Thing.Faction.opposing_masks.get(self.faction));
}

pub fn getNearestAlliedNonFairy(self: *Thing, room: *Room) ?*Thing {
    return getNearestThing(self, room, true, false, false, Thing.Faction.allied_masks.get(self.faction));
}

pub fn inAttackRangeAndLOS(self: *const Thing, room: *const Room, action: *const Action, params: Action.Params) bool {
    const target: *const Thing = if (params.thing) |id| if (room.getConstThingById(id)) |t| t else return false else return false;
    if (target.hurtbox == null) return false;

    const range = target.getRangeToHurtBox(self.pos);
    switch (action.kind) {
        .melee_attack => |melee| {
            const in_range = range <= melee.range;
            var in_LOS = true;
            if (melee.LOS_thiccness > 0) {
                in_LOS = room.tilemap.isLOSBetweenThicc(self.pos, target.pos, melee.LOS_thiccness);
            }
            return in_range and in_LOS;
        },
        .projectile_attack => |proj| {
            return switch (proj.projectile) {
                .gobarrow, .snowball => range <= proj.range and room.tilemap.isLOSBetweenThicc(self.pos, target.pos, proj.LOS_thiccness),
                .gobbomb => range <= proj.range,
                else => false,
            };
        },
        .spell_cast => |spc| {
            const spell: Spell = spc.spell;
            const in_range = range <= spell.targeting_data.max_range;
            // TODO more here?
            return in_range;
        },
        else => return false,
    }
}

// A decision is the answer to "what am I doing right now?"
// and "how long should I do it for until I decide again?"
pub const Decision = union(enum) {
    idle: struct {
        at_least_secs: f32 = 0,
    },
    pursue_to_attack: struct {
        target_id: Thing.Id, // for sanity check
        attack_range: f32,
        at_least_secs: f32 = 0.1,
    },
    flee: struct {
        min_dist: f32 = 0,
        max_dist: f32 = 9999,
        target_id: Thing.Id,
        at_least_secs: f32 = 1, // flee for at least this long (unless we reach the destination)
        cooldown_secs: f32 = 1,
    },
    move_to: struct {
        target_pos: V2f,
    },
    action: struct {
        slot: Action.Slot,
        params: Action.Params,
    },
};

pub const AIIdle = struct {
    pub fn decide(_: *AIIdle, _: *Thing, _: *Room) Decision {
        return Decision{ .idle = .{} };
    }
};

pub const AIAggro = struct {
    pub fn decide(_: *AIAggro, self: *Thing, room: *Room) Decision {
        var ret: Decision = .{ .idle = .{} };
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        if (nearest_enemy == null) {
            return ret;
        }
        const target = nearest_enemy.?;
        const params = Action.Params{ .target_kind = .thing, .thing = target.id };
        // get (best?) attack with lowest cooldown (or off cooldown)
        const slot = blk: {
            var best_slot: ?Action.Slot = null;
            var best_cd: i64 = undefined;
            for (Action.Slot.attacks) |atk_slot| {
                if (controller.actions.getPtr(atk_slot).*) |*action| {
                    const ticks_left = action.cooldown.ticksLeft();
                    if (ticks_left == 0) {
                        best_slot = atk_slot;
                        break; // TODO find best? priority?
                    } else if (best_slot == null or ticks_left < best_cd) {
                        best_slot = atk_slot;
                        best_cd = ticks_left;
                    }
                }
            }
            if (best_slot) |s| break :blk s else return ret;
        };
        const action = &controller.actions.getPtr(slot).*.?;

        if (inAttackRangeAndLOS(self, room, action, params)) {
            if (!action.cooldown.running) {
                ret = .{ .action = .{
                    .slot = slot,
                    .params = params,
                } };
            }
        } else {
            const range = switch (action.kind) {
                .projectile_attack => |r| r.range,
                .melee_attack => |m| m.range,
                .spell_cast => |spc| spc.spell.targeting_data.max_range,
                else => unreachable,
            };
            ret = .{ .pursue_to_attack = .{
                .target_id = target.id,
                .attack_range = range,
            } };
        }

        return ret;
    }
};

pub const AITroll = struct {
    ai_aggro: AIAggro = .{},

    pub fn decide(ai: *AITroll, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        if (self.hp) |*hp| {
            if (hp.curr < hp.max * 0.5) {
                const action = &controller.actions.getPtr(.ability_1).*.?;
                if (!action.cooldown.running) {
                    return .{ .action = .{
                        .slot = .ability_1,
                        .params = .{
                            .target_kind = .self,
                            .thing = self.id,
                        },
                    } };
                }
            }
        }
        return ai.ai_aggro.decide(self, room);
    }
};

pub const AIGobbomber = struct {
    ai_ranged_flee: AIRangedFlee = .{},
    shield_wait_timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(3)),

    pub fn decide(ai: *AIGobbomber, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        if (self.hp) |*hp| {
            if (hp.shields.len == 0 and !ai.shield_wait_timer.running) {
                ai.shield_wait_timer.restart();
                const action = &controller.actions.getPtr(.ability_1).*.?;
                if (!action.cooldown.running) {
                    return .{ .action = .{
                        .slot = .ability_1,
                        .params = .{
                            .target_kind = .self,
                            .thing = self.id,
                        },
                    } };
                }
            }
        }
        return ai.ai_ranged_flee.decide(self, room);
    }

    pub fn update(ai: *AIGobbomber, self: *Thing, room: *Room) Error!void {
        _ = room;
        const controller = &self.controller.ai_actor;
        // check if doing the shield already
        switch (controller.decision) {
            .action => |doing| {
                if (doing.slot == .ability_1) return;
            },
            else => {},
        }
        if (self.hp) |*hp| {
            if (hp.shields.len == 0) {
                _ = ai.shield_wait_timer.tick(false);
            }
        }
    }
};

pub const AIRangedFlee = struct {
    ai_aggro: AIAggro = .{},
    pub fn decide(ai: *AIRangedFlee, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        const aggro_decision = ai.ai_aggro.decide(self, room);
        const already_pursuing = std.meta.activeTag(controller.decision) == .pursue_to_attack;
        // we've been fleeing, set cooldown
        if (std.meta.activeTag(controller.decision) == .flee) {
            controller.flee_cooldown = utl.TickCounter.init(core.secsToTicks(1));
        }
        // action (attack) takes priority
        if (std.meta.activeTag(aggro_decision) == .action) {
            return aggro_decision;
        } else if (!already_pursuing) { // if pursuing, keep pursuing until attack, otherwise flee if too close and LOS
            if (nearest_enemy) |target| {
                if (!controller.flee_cooldown.running) {
                    // flee if too close and have LOS
                    if (target.pos.dist(self.pos) <= controller.flee_range) { // and room.tilemap.isLOSBetween(self.pos, target.pos)) {
                        return .{ .flee = .{
                            .min_dist = 50,
                            .max_dist = 150,
                            .target_id = target.id,
                            .at_least_secs = 3,
                            .cooldown_secs = 1,
                        } };
                    }
                }
            }
        }
        // otherwise pursue, or idle
        return aggro_decision;
    }
};

pub const AIAcolyte = struct {
    pub fn decide(_: *AIAcolyte, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        const action = &controller.actions.getPtr(.spell_cast_summon_1).*.?;
        // we've been fleeing, set cooldown
        if (std.meta.activeTag(controller.decision) == .flee) {
            controller.flee_cooldown = utl.TickCounter.init(core.secsToTicks(1));
        }
        // prioritize summoning
        // TODO track summons' ids?
        if (!action.cooldown.running and room.enemies_alive.len < 10) {
            const dir = (if (nearest_enemy) |e| e.pos.sub(self.pos) else self.pos.neg()).normalizedOrZero();
            const spawn_pos = self.pos.add(dir.scale(self.coll_radius * 2));
            const params = Action.Params{ .target_kind = .pos, .pos = spawn_pos };
            return .{ .action = .{
                .slot = .spell_cast_summon_1,
                .params = params,
            } };
        }
        // otherwise fleee! (or idle)
        if (nearest_enemy) |target| {
            if (!controller.flee_cooldown.running) {
                if (target.pos.dist(self.pos) <= controller.flee_range) {
                    return .{
                        .flee = .{
                            .min_dist = 50,
                            .max_dist = controller.flee_range,
                            .target_id = target.id,
                            .at_least_secs = core.fups_to_secsf(action.cooldown.num_ticks),
                        },
                    };
                }
            }
        }
        return .{ .idle = .{} };
    }
};

pub const AIDjinn = struct {
    pub fn decide(_: *AIDjinn, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const enemy: *Thing = getNearestOpposingThing(self, room) orelse return .{ .idle = .{} };

        const teleport = &controller.actions.getPtr(.spell_cast_teleport_self).*.?;
        const can_tp = !teleport.cooldown.running;
        const attack_1 = &controller.actions.getPtr(.spell_cast_thing_attack_1).*.?;
        const can_atk_1 = !attack_1.cooldown.running;
        const shield = &controller.actions.getPtr(.spell_cast_self_buff_1).*.?;
        const can_shield = !shield.cooldown.running;

        // prioritize attack, or teleport to attack
        if (can_atk_1) {
            if (enemy.pos.dist(self.pos) <= attack_1.kind.spell_cast.spell.targeting_data.max_range and room.tilemap.isLOSBetweenThicc(self.pos, enemy.pos, 10)) {
                return .{ .action = .{
                    .slot = .spell_cast_thing_attack_1,
                    .params = .{ .target_kind = .pos, .pos = enemy.pos },
                } };
            } else if (can_tp) {
                const rand_dir = V2f.right.rotRadians(utl.tau * room.rng.random().float(f32));
                const pos = enemy.pos.add(rand_dir.scale(self.coll_radius + enemy.coll_radius + 80));
                return .{ .action = .{
                    .slot = .spell_cast_teleport_self,
                    .params = .{ .target_kind = .pos, .pos = pos },
                } };
            }
        }

        // then protec
        if (can_shield) {
            return .{ .action = .{
                .slot = .spell_cast_self_buff_1,
                .params = .{ .target_kind = .self, .thing = self.id },
            } };
        }

        // otherwise fleee!
        if (can_tp) {
            if (getFleePos(room, self.pos, self.pos, 50, 300, self.pathing_layer)) |maybe_pos| {
                if (maybe_pos) |flee_pos| {
                    return .{ .action = .{
                        .slot = .spell_cast_teleport_self,
                        .params = .{ .target_kind = .pos, .pos = flee_pos },
                    } };
                }
            } else |_| {}
        }

        return .{ .idle = .{} };
    }
};

pub const AIDjinnSmoke = struct {
    pub fn decide(_: *AIDjinnSmoke, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const enemy: *Thing = getNearestOpposingThing(self, room) orelse return .{ .idle = .{} };

        const summon = &controller.actions.getPtr(.spell_cast_summon_1).*.?;
        const can_summon = !summon.cooldown.running;

        if (can_summon and room.enemies_alive.len < 10) {
            const dir = enemy.pos.sub(self.pos).normalizedOrZero();
            const spawn_pos = self.pos.add(dir.scale(self.coll_radius * 2));
            const params = Action.Params{ .target_kind = .pos, .pos = spawn_pos };
            return .{ .action = .{
                .slot = .spell_cast_summon_1,
                .params = params,
            } };
        }
        var aggro = AIAggro{};
        return aggro.decide(self, room);
    }
};

pub const AIFairy = struct {
    pub fn decide(_: *AIFairy, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        blk: { // gold fairy creation
            const FairyKind = enum {
                red,
                blue,
                green,
                pub fn fromThing(thing: *const Thing) ?@This() {
                    return switch (thing.creature_kind.?) {
                        .@"fairy-blue" => .blue,
                        .@"fairy-green" => .green,
                        .@"fairy-red" => .red,
                        else => null,
                    };
                }
            };
            const my_kind = FairyKind.fromThing(self) orelse break :blk;
            var kinds = std.EnumArray(FairyKind, ?*Thing).initFill(null);
            kinds.set(my_kind, self);
            for (&room.things.items) |*other| {
                if (!other.isActive()) continue;
                if (other.id.eql(self.id)) continue;
                if (other.faction != self.faction) continue;
                if (!other.isAliveCreature()) continue;
                const kind = FairyKind.fromThing(other) orelse continue;
                const ptr = kinds.getPtr(kind);
                if (ptr.* == null) {
                    ptr.* = other;
                }
            }
            var avg_pos: V2f = .{};
            var total_dist: f32 = 0;
            for (kinds.values) |v| {
                if (v == null) break :blk;
                total_dist += self.pos.dist(v.?.pos);
                avg_pos = avg_pos.add(v.?.pos);
            }
            if (my_kind == .red and total_dist < 15) {
                for (kinds.values) |v| {
                    v.?.hp.?.curr = 0;
                }
                _ = room.queueSpawnCreatureByKind(.@"fairy-gold", self.pos) catch {};
                return .{ .idle = .{} };
            } else {
                avg_pos = avg_pos.scale(0.333);
                return .{ .move_to = .{
                    .target_pos = avg_pos,
                } };
            }
        }
        const maybe_ally: ?*Thing = getNearestAlliedNonFairy(self, room);

        if (maybe_ally) |ally| {
            if (self.pos.dist(ally.pos) > 90) {
                return .{ .move_to = .{
                    .target_pos = ally.pos,
                } };
            }
        }

        if (controller.actions.getPtr(.spell_cast_thing_debuff_1).*) |debuff_1| {
            const can_debuff_1 = !debuff_1.cooldown.running;

            if (can_debuff_1) {
                if (getNearestOpposingThing(self, room)) |enemy| {
                    if (enemy.pos.dist(self.pos) <= debuff_1.kind.spell_cast.spell.targeting_data.max_range) {
                        return .{ .action = .{
                            .slot = .spell_cast_thing_debuff_1,
                            .params = .{ .target_kind = .thing, .pos = enemy.pos, .thing = enemy.id },
                        } };
                    }
                }
            }
        }

        if (controller.actions.getPtr(.spell_cast_thing_buff_1).*) |buff_1| {
            const can_buff_1 = !buff_1.cooldown.running;
            if (maybe_ally) |ally| {
                if (can_buff_1) {
                    if (ally.pos.dist(self.pos) <= buff_1.kind.spell_cast.spell.targeting_data.max_range) {
                        return .{ .action = .{
                            .slot = .spell_cast_thing_buff_1,
                            .params = .{ .target_kind = .thing, .pos = ally.pos, .thing = ally.id },
                        } };
                    }
                }
            }
        }

        if (maybe_ally) |ally| {
            const dir_to_ally = ally.pos.sub(self.pos).normalizedChecked() orelse V2f.right;
            const rot_dir = dir_to_ally.rot90CCW();

            return .{ .move_to = .{
                .target_pos = ally.pos.add(rot_dir.scale(20)),
            } };
        }

        return .{ .idle = .{} };
    }
};

pub const ActorController = struct {
    pub const Kind = enum {
        idle,
        aggro,
        acolyte,
        troll,
        ranged_flee,
        gobbomber,
        djinn,
        djinn_smoke,
        fairy,
    };
    pub const KindData = union(Kind) {
        idle: AIIdle,
        aggro: AIAggro,
        acolyte: AIAcolyte,
        troll: AITroll,
        ranged_flee: AIRangedFlee,
        gobbomber: AIGobbomber,
        djinn: AIDjinn,
        djinn_smoke: AIDjinnSmoke,
        fairy: AIFairy,
    };

    actions: Action.Slot.Array = Action.Slot.Array.initFill(null),
    ai: KindData = .{ .aggro = .{} },
    decision: Decision = .{ .idle = .{} },
    // Continue the current decision for this long before making a new one
    // Doesn't apply to Actions! Which can't be interrupted by a new Decision anyway.
    // This can be futzed with at runtime by the specific AIs..
    non_action_decision_cooldown: utl.TickCounter = utl.TickCounter.initStopped(0),

    // range at which we should flee
    flee_range: f32 = 125,
    // dont flee again for this long (TODO for all Decisions?)
    flee_cooldown: utl.TickCounter = utl.TickCounter.initStopped(1 * core.fups_per_sec),
    flee_pos: ?V2f = null,
    // debug for flee
    hiding_places: HidingPlacesArray = .{},
    to_enemy: V2f = .{},

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const renderer = &self.renderer.sprite;
        const controller = &self.controller.ai_actor;

        // tick action cooldowns
        for (&controller.actions.values) |*action| {
            if (action.*) |*a| {
                _ = a.cooldown.tick(false);
            }
        }
        _ = controller.flee_cooldown.tick(false);

        // tick ai
        switch (controller.ai) {
            inline else => |*ai| {
                if (std.meta.hasMethod(@TypeOf(ai), "update")) {
                    try ai.update(self, room);
                }
            },
        }

        // decide what to do, if not doing an action (actions are committed to until done)
        if (std.meta.activeTag(controller.decision) != .action and controller.non_action_decision_cooldown.tick(false)) {
            switch (controller.ai) {
                inline else => |*ai| {
                    controller.decision = ai.decide(self, room);
                    switch (controller.decision) {
                        .idle => |idle| {
                            controller.non_action_decision_cooldown = utl.TickCounter.init(core.secsToTicks(idle.at_least_secs));
                        },
                        .pursue_to_attack => |pursue| {
                            controller.non_action_decision_cooldown = utl.TickCounter.init(core.secsToTicks(pursue.at_least_secs));
                        },
                        .flee => |flee| {
                            controller.flee_pos = null;
                            controller.non_action_decision_cooldown = utl.TickCounter.init(core.secsToTicks(flee.at_least_secs));
                        },
                        .action => {
                            const doing = &controller.decision.action;
                            try controller.actions.getPtr(doing.slot).*.?.begin(self, room, doing.params);
                        },
                        .move_to => {
                            controller.non_action_decision_cooldown = utl.TickCounter.init(10);
                        },
                    }
                },
            }
        }

        decision: switch (controller.decision) {
            .idle => {
                self.updateVel(.{}, .{});
                _ = self.renderer.sprite.playCreatureAnim(self, .idle, .{ .loop = true });
            },
            .action => |doing| {
                const action = &controller.actions.getPtr(doing.slot).*.?;
                if (try action.update(self, room)) {
                    action.cooldown.restart();
                    controller.decision = .{ .idle = .{} };
                    // make sure we make a new decision next update
                    controller.non_action_decision_cooldown.stop();
                }
            },
            .move_to => |move| {
                _ = renderer.playCreatureAnim(self, .move, .{ .loop = true });
                try self.findPath(room, move.target_pos);
                const p = self.followPathGetNextPoint(5);
                self.move(p.sub(self.pos).normalizedOrZero());

                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
            },
            .pursue_to_attack => |s| {
                const _target = room.getThingById(s.target_id);
                if (_target == null) {
                    controller.decision = .{ .idle = .{} };
                    controller.non_action_decision_cooldown.stop();
                    continue :decision controller.decision;
                }
                const target = _target.?;
                const range = target.getRangeToHurtBox(self.pos);
                _ = renderer.playCreatureAnim(self, .move, .{ .loop = true });

                const dist_til_in_range = range - s.attack_range;
                var target_pos = target.pos;
                // predictive movement if close enough
                const my_max_speed = self.getEffectiveAccelParams().max_speed;
                if (my_max_speed > 0 and range < 40) {
                    const time_til_reach = dist_til_in_range / my_max_speed;
                    target_pos = target.pos.add(target.vel.scale(time_til_reach));
                }
                try self.findPath(room, target_pos);
                const p = self.followPathGetNextPoint(5);
                self.move(p.sub(self.pos).normalizedOrZero());

                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
            },
            .flee => |flee| {
                const _thing = room.getThingById(flee.target_id);
                if (_thing == null) {
                    controller.decision = .{ .idle = .{} };
                    controller.non_action_decision_cooldown.stop();
                    continue :decision controller.decision;
                }
                const thing = _thing.?;

                if (controller.flee_pos == null) {
                    controller.flee_pos = try getFleePos(room, self.pos, thing.pos, flee.min_dist, flee.max_dist, self.pathing_layer);
                }
                if (controller.flee_pos) |pos| {
                    try self.findPath(room, pos);
                    _ = renderer.playCreatureAnim(self, .move, .{ .loop = true });
                    const p = self.followPathGetNextPoint(5);
                    self.move(p.sub(self.pos).normalizedOrZero());
                    if (!self.vel.isAlmostZero()) {
                        self.dir = self.vel.normalized();
                    }
                }
                // end of flee, or fallback if couldn't flee for some reason
                if (self.path.len == 0 or controller.flee_pos == null) {
                    // make sure we make a new decision now we've arrived
                    controller.non_action_decision_cooldown.stop();
                    // in general the specialized ai will set this, but always set it if we reached the end of the path
                    controller.flee_cooldown = utl.TickCounter.init(core.secsToTicks(flee.cooldown_secs));
                }
            },
        }
    }
};

pub const HidingPlacesArray = std.BoundedArray(struct { pos: V2f, fleer_dist: f32, flee_from_dist: f32 }, 32);
pub fn getHidingPlaces(room: *const Room, mask: TileMap.PathLayer.Mask, fleer_pos: V2f, flee_from_pos: V2f, min_flee_dist: f32, max_flee_dist: f32) Error!HidingPlacesArray {
    const plat = getPlat();
    const tilemap = &room.tilemap;
    const start_coord = TileMap.posToTileCoord(fleer_pos);
    var places = HidingPlacesArray{};
    var queue = std.BoundedArray(V2i, 128){};
    var seen = std.AutoArrayHashMap(V2i, void).init(plat.heap);
    defer seen.deinit();
    try seen.put(start_coord, {});
    queue.append(start_coord) catch unreachable;

    while (queue.len > 0) {
        const curr = queue.orderedRemove(0);
        const pos = TileMap.tileCoordToCenterPos(curr);
        const flee_from_dist = pos.dist(flee_from_pos);
        const fleer_dist = pos.dist(fleer_pos);
        if (fleer_dist >= min_flee_dist and fleer_dist < max_flee_dist) {
            places.append(.{ .pos = pos, .fleer_dist = fleer_dist, .flee_from_dist = flee_from_dist }) catch {};
        }
        if (places.len >= places.buffer.len) break;

        for (TileMap.neighbor_dirs) |dir| {
            const dir_v = TileMap.neighbor_dirs_coords.get(dir);
            const next = curr.add(dir_v);
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });
            if (!tilemap.tileCoordIsPathable(mask, next)) {
                continue;
            }
            if (seen.get(next)) |_| continue;
            try seen.put(next, {});
            queue.append(next) catch break;
        }
    }
    return places;
}

pub fn getFleePos(room: *const Room, fleer_pos: V2f, flee_from_pos: V2f, min_dist: f32, max_dist: f32, pathing_layer: TileMap.PathLayer) !?V2f {
    const hiding_places = try getHidingPlaces(
        room,
        TileMap.PathLayer.Mask.initOne(pathing_layer),
        fleer_pos,
        flee_from_pos,
        min_dist,
        max_dist,
    );
    if (hiding_places.len == 0) return null;
    const to_enemy = flee_from_pos.sub(fleer_pos);
    var best_score: f32 = -std.math.inf(f32);
    var best_pos: ?V2f = null;
    for (hiding_places.constSlice()) |h| {
        const self_to_pos = h.pos.sub(fleer_pos).normalizedOrZero();
        const len = @max(to_enemy.length() - min_dist, 0);
        const to_enemy_n = to_enemy.setLengthOrZero(len);
        const dir_f = self_to_pos.dot(to_enemy_n.neg());
        const score = h.flee_from_dist + dir_f;
        if (best_pos == null or score > best_score) {
            best_score = score;
            best_pos = h.pos;
        }
    }
    return best_pos;
}
