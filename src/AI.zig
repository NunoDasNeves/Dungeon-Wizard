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

pub const Projectile = enum {
    arrow,

    pub fn prototype(self: Projectile) Thing {
        switch (self) {
            .arrow => return gobbowArrow(),
        }
        unreachable;
    }
};

pub const MeleeAttack = struct {
    hitbox: Thing.HitBox,
    LOS_thiccness: f32 = 10,
    lunge_accel: ?Thing.AccelParams = null,
    hit_to_side_force: f32 = 0,
    range: f32 = 40,
};

pub const ProjectileAttack = struct {
    projectile: Projectile,
    range: f32 = 100,
    LOS_thiccness: f32 = 10,
};

// Loosely defined, an Action is a behavior that occurs over a predictable timespan
// E.g. Shooting an arrow, casting a spell, dashing...
// Walking to player is NOT a predictable timespan, too many variables. so not an Action.
pub const Action = struct {
    pub const Array = std.BoundedArray(Action, 8);
    pub const Kind = enum {
        melee_attack,
        projectile_attack,
    };
    pub const KindData = union(Kind) {
        melee_attack: MeleeAttack,
        projectile_attack: ProjectileAttack,
    };
    pub const Params = struct {
        thing: ?Thing.Id = null,
        pos: V2f = .{}, // there has to be a position. (it may not matter though.)
    };
    pub const Doing = struct {
        idx: usize,
        params: Params,
        can_turn: bool = true,
    };
    kind: KindData,
    cooldown: utl.TickCounter = utl.TickCounter.initStopped(60),
};

fn gobbowArrow() Thing {
    const arrow = Thing{
        .kind = .projectile,
        .coll_radius = 5,
        .accel_params = .{
            .accel = 4,
            .friction = 0,
            .max_speed = 4,
        },
        .coll_mask = Thing.Collision.Mask.initMany(&.{.tile}),
        .controller = .{ .projectile = .{} },
        .renderer = .{ .shape = .{
            .kind = .{ .arrow = .{
                .length = 35,
                .thickness = 4,
            } },
            .poly_opt = .{ .fill_color = draw.Coloru.rgb(220, 172, 89).toColorf() },
        } },
        .hitbox = .{
            .active = true,
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = .{ .damage = 7 },
            .radius = 4,
        },
    };
    return arrow;
}

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

pub fn getNearestOpposingThing(self: *Thing, room: *Room) ?*Thing {
    var closest_dist = std.math.inf(f32);
    var closest: ?*Thing = null;
    for (&room.things.items) |*other| {
        if (!other.isActive()) continue;
        if (other.id.eql(self.id)) continue;
        if (!Thing.Faction.opposing_masks.get(self.faction).contains(other.faction)) continue;
        if (other.isInvisible()) continue;
        if (!other.isAttackableCreature()) continue;
        const dist = other.pos.dist(self.pos);
        if (dist < closest_dist) {
            closest_dist = dist;
            closest = other;
        }
    }
    return closest;
}

pub fn inAttackRange(self: *const Thing, room: *const Room, action: *const Action, params: Action.Params) bool {
    switch (action.kind) {
        inline else => |atk| {
            const target: *const Thing = if (params.thing) |id| if (room.getConstThingById(id)) |t| t else return false else return false;
            const dist = target.pos.dist(self.pos);
            const range = @max(dist - self.coll_radius - target.coll_radius, 0);
            if (range <= atk.range and room.tilemap.isLOSBetweenThicc(self.pos, target.pos, atk.LOS_thiccness)) {
                return true;
            }
        },
    }
    return false;
}

pub fn startAction(self: *Thing, room: *Room, doing: *Action.Doing, action: *Action) Error!void {
    _ = action;
    const maybe_target_thing: ?*const Thing =
        if (doing.params.thing) |target_id|
        if (room.getConstThingById(target_id)) |t| t else null
    else
        null;
    // make sure we always have a pos in the params, if we have a Thing
    if (maybe_target_thing) |t| {
        doing.params.pos = t.pos;
    }
    // TODO other stuff - maybe set pos to self.pos by default? idk
    // face what we're doing
    self.dir = doing.params.pos.sub(self.pos).normalizedChecked() orelse self.dir;
}

// return true if done
pub fn continueAction(self: *Thing, room: *Room, doing: *Action.Doing, action: *Action) Error!bool {
    const maybe_target_thing: ?*const Thing =
        if (doing.params.thing) |target_id|
        if (room.getConstThingById(target_id)) |t| t else null
    else
        null;

    switch (action.kind) {
        .melee_attack => |melee| {
            self.updateVel(.{}, .{});
            const events = self.animator.?.play(.attack, .{ .loop = true });
            if (events.contains(.commit)) {
                doing.can_turn = false;
            }
            // predict hit
            if (doing.can_turn) {
                if (maybe_target_thing) |target| {
                    if (self.animator.?.getTicksUntilEvent(.hit)) |ticks_til_hit_event| {
                        if (target.hurtbox) |hurtbox| {
                            const dist = target.pos.dist(self.pos);
                            const range = @max(dist - hurtbox.radius, 0);
                            var ticks_til_hit = utl.as(f32, ticks_til_hit_event);
                            if (melee.lunge_accel) |accel| {
                                ticks_til_hit += range / accel.max_speed;
                            }
                            const target_pos = target.pos.add(target.vel.scale(ticks_til_hit));
                            self.dir = target_pos.sub(self.pos).normalizedChecked() orelse self.dir;
                        }
                    }
                }
            }
            // end and hit are mutually exclusive
            if (events.contains(.end)) {
                // deactivate hitbox
                if (self.hitbox) |*hitbox| {
                    hitbox.active = false;
                }
                if (melee.lunge_accel) |accel_params| {
                    self.coll_mask.insert(.creature);
                    self.coll_layer.insert(.creature);
                    self.updateVel(.{}, .{ .friction = accel_params.max_speed });
                }
                action.cooldown.restart();
                return true;
            }

            if (events.contains(.hit)) {
                self.renderer.creature.draw_color = Colorf.red;
                self.hitbox = melee.hitbox;
                const hitbox = &self.hitbox.?;
                //std.debug.print("hit targetu\n", .{});
                hitbox.mask = Thing.Faction.opposing_masks.get(self.faction);
                const dir_ang = self.dir.toAngleRadians();
                hitbox.rel_pos = V2f.fromAngleRadians(dir_ang).scale(hitbox.rel_pos.length());
                if (hitbox.sweep_to_rel_pos) |*sw| {
                    sw.* = V2f.fromAngleRadians(dir_ang).scale(sw.length());
                }
                hitbox.active = true;
                if (maybe_target_thing) |target_thing| {
                    if (melee.hit_to_side_force > 0) {
                        const d = if (self.dir.cross(target_thing.pos.sub(self.pos)) > 0) self.dir.rotRadians(-utl.pi / 3) else self.dir.rotRadians(utl.pi / 3);
                        hitbox.effect.force = .{ .fixed = d.scale(melee.hit_to_side_force) };
                    }
                }
                // play sound
                if (App.get().data.sounds.get(.thwack)) |s| {
                    App.getPlat().playSound(s);
                }

                if (melee.lunge_accel) |accel_params| {
                    self.coll_mask.remove(.creature);
                    self.coll_layer.remove(.creature);
                    self.updateVel(self.dir, accel_params);
                }
            }
        },
        .projectile_attack => |atk| {
            self.updateVel(.{}, .{});
            const events = self.animator.?.play(.attack, .{ .loop = true });
            if (events.contains(.commit)) {
                doing.can_turn = false;
            }
            // face/track target
            var projectile = atk.projectile.prototype();
            if (doing.can_turn) {
                // default to original target pos
                self.dir = doing.params.pos.sub(self.pos).normalizedChecked() orelse self.dir;
                if (maybe_target_thing) |target| {
                    if (self.animator.?.getTicksUntilEvent(.hit)) |ticks_til_hit_event| {
                        if (target.hurtbox) |hurtbox| { // TODO hurtbox pos?
                            const dist = target.pos.dist(self.pos);
                            const range = @max(dist - hurtbox.radius, 0);
                            var ticks_til_hit = utl.as(f32, ticks_til_hit_event);
                            ticks_til_hit += range / projectile.accel_params.max_speed;
                            const predicted_target_pos = target.pos.add(target.vel.scale(ticks_til_hit));
                            // make sure we can actually still get past nearby walls with this new angle!
                            if (room.tilemap.isLOSBetweenThicc(self.pos, predicted_target_pos, atk.LOS_thiccness)) {
                                self.dir = predicted_target_pos.sub(self.pos).normalizedChecked() orelse self.dir;
                            } else if (room.tilemap.isLOSBetweenThicc(self.pos, target.pos, atk.LOS_thiccness)) {
                                // otherwise just face target directly
                                self.dir = target.pos.sub(self.pos).normalizedChecked() orelse self.dir;
                            }
                        }
                    }
                }
            }
            if (events.contains(.end)) {
                //std.debug.print("attack end\n", .{});
                action.cooldown.restart();
                return true;
            }

            if (events.contains(.hit)) {
                self.renderer.creature.draw_color = Colorf.red;
                projectile.dir = self.dir;
                projectile.hitbox.?.mask = Thing.Faction.opposing_masks.get(self.faction);
                switch (atk.projectile) {
                    .arrow => {
                        projectile.hitbox.?.rel_pos = self.dir.scale(28);
                        _ = try room.queueSpawnThing(&projectile, self.pos);
                    },
                }
            }
        },
    }
    return false;
}

// TODO these could be thought of as 'behaviors' and be more specific - e.g. 'pursue' instead of 'move'
pub const Decision = union(enum) {
    idle,
    pursue_to_attack: struct {
        target_id: Thing.Id, // for sanity check
        attack_range: f32,
    },
    flee,
    action: Action.Doing,
};

pub const AIAggro = struct {
    attack_action_idx: usize = 0,

    pub fn decide(ai: *AIAggro, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        if (nearest_enemy) |target| {
            const action = &controller.actions.buffer[ai.attack_action_idx];
            const params = Action.Params{ .thing = target.id };
            if (inAttackRange(self, room, action, params)) {
                if (action.cooldown.running) {
                    return .idle;
                } else {
                    return .{ .action = .{
                        .idx = ai.attack_action_idx,
                        .params = params,
                    } };
                }
            }
            const range = switch (action.kind) {
                .projectile_attack => |r| r.range,
                .melee_attack => |m| m.range,
            };
            return .{ .pursue_to_attack = .{
                .target_id = target.id,
                .attack_range = range,
            } };
        }
        return .idle;
    }
};

pub const ActorController = struct {
    pub const Kind = enum {
        aggro,
    };
    pub const KindData = union(Kind) {
        aggro: AIAggro,
    };

    actions: Action.Array = .{},
    ai: KindData = .{ .aggro = .{} },
    decision: Decision = .idle,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.ai_actor;

        // tick action cooldowns
        for (controller.actions.slice()) |*a| {
            _ = a.cooldown.tick(false);
        }

        // decide what to do, if not doing an action (actions are committed to until done)
        if (std.meta.activeTag(controller.decision) != .action) switch (controller.ai) {
            inline else => |*ai| {
                controller.decision = ai.decide(self, room);
                if (std.meta.activeTag(controller.decision) == .action) {
                    const doing = &controller.decision.action;
                    try startAction(self, room, doing, &controller.actions.buffer[doing.idx]);
                }
            },
        };

        switch (controller.decision) {
            .idle => {
                self.updateVel(.{}, .{});
                _ = self.animator.?.play(.idle, .{ .loop = true });
            },
            .action => |*doing| {
                if (try continueAction(self, room, doing, &controller.actions.buffer[doing.idx])) {
                    controller.decision = .idle;
                }
            },
            .pursue_to_attack => |s| {
                const _target = room.getThingById(s.target_id);
                assert(_target != null);
                const target = _target.?;
                const dist = target.pos.dist(self.pos);
                const range = @max(dist - target.hurtbox.?.radius, 0);
                _ = self.animator.?.play(.move, .{ .loop = true });
                const dist_til_in_range = range - s.attack_range;
                var target_pos = target.pos;
                // predictive movement if close enough
                if (range < 80) {
                    const time_til_reach = dist_til_in_range / self.accel_params.max_speed;
                    target_pos = target.pos.add(target.vel.scale(time_til_reach));
                }
                try self.findPath(room, target_pos);
                const p = self.followPathGetNextPoint(10);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
            },
            .flee => {
                // TODO
            },
        }
    }
};

pub const HidingPlacesArray = std.BoundedArray(struct { pos: V2f, fleer_dist: f32, flee_from_dist: f32 }, 32);
pub fn getHidingPlaces(room: *const Room, fleer_pos: V2f, flee_from_pos: V2f, min_flee_dist: f32) Error!HidingPlacesArray {
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
        if (fleer_dist > min_flee_dist) {
            places.append(.{ .pos = pos, .fleer_dist = fleer_dist, .flee_from_dist = flee_from_dist }) catch {};
        }
        if (places.len >= places.buffer.len) break;

        for (TileMap.neighbor_dirs) |dir| {
            const dir_v = TileMap.neighbor_dirs_coords.get(dir);
            const next = curr.add(dir_v);
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });
            if (tilemap.gameTileCoordToConstGameTile(next)) |tile| {
                if (!tile.passable) continue;
            }
            if (seen.get(next)) |_| continue;
            try seen.put(next, {});
            queue.append(next) catch break;
        }
    }
    return places;
}

pub const AcolyteAIController = struct {
    wander_dir: V2f = .{},
    state: enum {
        idle,
        flee,
        cast,
    } = .idle,
    ticks_in_state: i64 = 0,
    flee_range: f32 = 250,
    cast_cooldown: utl.TickCounter = utl.TickCounter.initStopped(5 * core.fups_per_sec),
    flee_cooldown: utl.TickCounter = utl.TickCounter.initStopped(1 * core.fups_per_sec),
    cast_vfx: ?Thing.Id = null,
    // debug
    hiding_places: HidingPlacesArray = .{},
    to_enemy: V2f = .{},

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const nearest_enemy = getNearestOpposingThing(self, room);
        const ai = &self.controller.acolyte_enemy;

        self.renderer.creature.draw_color = Colorf.yellow;
        _ = ai.cast_cooldown.tick(false);
        _ = ai.flee_cooldown.tick(false);
        ai.state = state: switch (ai.state) {
            .idle => {
                if (!ai.flee_cooldown.running) {
                    if (nearest_enemy) |e| {
                        if (e.pos.dist(self.pos) <= ai.flee_range) {
                            ai.ticks_in_state = 0;
                            continue :state .flee;
                        }
                    }
                }
                if (!ai.cast_cooldown.running) {
                    // TODO genericiszesez?
                    if (room.num_enemies_alive < 10) {
                        ai.ticks_in_state = 0;
                        continue :state .cast;
                    }
                }
                self.updateVel(.{}, .{});
                _ = self.animator.?.play(.idle, .{ .loop = true });
                break :state .idle;
            },
            .flee => {
                if (ai.ticks_in_state == 0) {
                    assert(nearest_enemy != null);
                    const flee_from_pos = nearest_enemy.?.pos;
                    ai.hiding_places = try getHidingPlaces(room, self.pos, flee_from_pos, ai.flee_range);
                    ai.to_enemy = flee_from_pos.sub(self.pos);
                    if (ai.hiding_places.len > 0) {
                        var best_f: f32 = -std.math.inf(f32);
                        var best_pos: ?V2f = null;
                        for (ai.hiding_places.constSlice()) |h| {
                            const self_to_pos = h.pos.sub(self.pos).normalizedOrZero();
                            const len = @max(ai.to_enemy.length() - ai.flee_range, 0);
                            const to_enemy_n = ai.to_enemy.setLengthOrZero(len);
                            const dir_f = self_to_pos.dot(to_enemy_n.neg());
                            const f = h.flee_from_dist + dir_f;
                            if (best_pos == null or f > best_f) {
                                best_f = f;
                                best_pos = h.pos;
                            }
                        }
                        if (best_pos) |pos| {
                            try self.findPath(room, pos);
                        }
                    }
                }
                _ = self.animator.?.play(.move, .{ .loop = true });
                const p = self.followPathGetNextPoint(10);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
                if (self.path.len == 0) {
                    ai.flee_cooldown.restart();
                    ai.ticks_in_state = 0;
                    continue :state .idle;
                }
                break :state .flee;
            },
            .cast => {
                if (ai.ticks_in_state == 0) {
                    const cast_proto = Thing.VFXController.castingProto(self);
                    if (try room.queueSpawnThing(&cast_proto, cast_proto.pos)) |id| {
                        ai.cast_vfx = id;
                    }
                }
                if (ai.ticks_in_state == 30) {
                    if (ai.cast_vfx) |id| {
                        if (room.getThingById(id)) |cast| {
                            cast.controller.vfx.anim_to_play = .basic_cast;
                        }
                    }
                    ai.cast_vfx = null;
                }
                if (ai.ticks_in_state == 60) {
                    const dir = (if (nearest_enemy) |e| e.pos.sub(self.pos) else self.pos.neg()).normalizedOrZero();
                    const spawn_pos = self.pos.add(dir.scale(self.coll_radius * 2));
                    var spawner = Thing.SpawnerController.prototype(.bat);
                    spawner.faction = self.faction;
                    _ = try room.queueSpawnThing(&spawner, spawn_pos);
                    ai.cast_cooldown.restart();
                    ai.ticks_in_state = 0;
                    continue :state .idle;
                }
                self.updateVel(.{}, .{});
                _ = self.animator.?.play(.cast, .{ .loop = true });
                break :state .cast;
            },
        };
        ai.ticks_in_state += 1;
    }
};
