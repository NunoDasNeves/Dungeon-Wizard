const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const App = @import("App.zig");
const getPlat = App.getPlat;
const Run = @import("Run.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const sprites = @import("sprites.zig");
const Player = @This();

pub const enum_name = "player";

pub fn runPrototype(run: *const Run) Thing {
    var base = App.get().data.creature_protos.get(.player);
    switch (run.mode) {
        .frank_4_slot => {},
        .mandy_3_mana => {
            base.mana = .{ .max = 3, .curr = 3 };
        },
        .crispin_picker => {
            base.mana = .{ .max = 5, .curr = 3 };
            base.controller.player.mana_regen = .{
                .timer = utl.TickCounter.init(core.secsToTicks(3)),
                .max_threshold = 3,
            };
        },
    }
    base.player_input.?.actions.initRun(run);

    return base;
}

pub const Attack = struct {
    range: f32 = 30,
    hitbox: Thing.HitBox = .{
        .deactivate_on_hit = true,
        .deactivate_on_update = true,
        .effect = .{
            .damage = 2,
            .force = .{ .from_center = 1 },
        },
    },
    cooldown_secs: f32 = 1,
    targeting_data: Spell.TargetingData = .{},

    pub inline fn renderTargeting(self: *const Attack, room: *const Room, caster: *const Thing, params: ?Spell.Params) Error!void {
        return self.targeting_data.render(room, caster, params);
    }
};

pub const Action = struct {
    pub const Kind = enum {
        discard,
        item,
        spell,
        //move,
        //attack,
    };
    pub const KindData = union(Kind) {
        discard: struct {}, // @hasField etc doesn't work with void, so empty struct
        item: Item,
        spell: Spell,
        //move: struct {},
        //attack: Attack,
    };
    // identifies an Action (in context - e.g. a player action, a particular NPC's action, not a universal lookup (yet))
    pub const Id = struct {
        kind: Action.Kind,
        slot_idx: ?usize = null,
    };
    // an Action that isn't being done yet. Just point to it, and the params used to run it
    pub const Buffered = struct {
        id: Action.Id,
        params: ?Spell.Params = null,
    };
    kind: KindData,
    // generic state for running the action
    curr_tick: i64 = 0,
};

pub const Slotu = struct {
    id: Action.Id,
    cooldown_timer: ?utl.TickCounter = null,
    // lazy mapping to input bindings, can use id to get it
    input_idx: ?usize = null,
    // on-screen button, if applicable
    ui_slot_idx: ?usize = null,
};

pub const SpellSlot = struct {
    spell: ?Spell,
    slot: Slotu,
};

pub const ActionSlot = struct {
    action: ?Action,
    cooldown_timer: ?utl.TickCounter = null,
    // identify the kind (if action is empty),
    id: Action.Id,
    // lazy mapping to input bindings, can use id to get it
    input_idx: ?usize = null,
    // on-screen button, if applicable
    ui_slot_idx: ?usize = null,

    pub fn initDiscard() ActionSlot {
        return .{
            .action = .{ .kind = .{ .discard = .{} } },
            .id = .{
                .kind = .discard,
            },
        };
    }
    pub fn initItem(maybe_item: ?Item, slot_idx: usize) ActionSlot {
        return .{
            .action = if (maybe_item) |item| .{ .kind = .{ .item = item } } else null,
            .id = .{
                .kind = .item,
                .slot_idx = slot_idx,
            },
        };
    }
    pub fn initSpell(maybe_spell: ?Spell, slot_idx: usize) ActionSlot {
        return .{
            .action = if (maybe_spell) |spell| .{ .kind = .{ .spell = spell } } else null,
            .id = .{
                .kind = .spell,
                .slot_idx = slot_idx,
            },
        };
    }
    pub fn update(self: *ActionSlot) ?*ActionSlot {
        //
        _ = self;
        return null;
    }
};

pub const ActionSlots = struct {
    discard: ?ActionSlot = null,
    items: std.BoundedArray(ActionSlot, 8) = .{},
    spells: std.BoundedArray(ActionSlot, 6) = .{},
    //move: ActionSlot,
    //attack: ?ActionSlot,
    pub fn initRun(self: *ActionSlots, run: *const Run) void {
        if (run.mode == .mandy_3_mana) {
            self.discard = ActionSlot.initDiscard();
        }
        self.items.clear();
        self.items.appendAssumeCapacity(ActionSlot.initItem(Item.getProto(.pot_hp), 0));
        for (1..4) |i| {
            self.items.appendAssumeCapacity(ActionSlot.initItem(null, i));
        }
        self.spells.clear();
        for (0..4) |i| {
            self.items.appendAssumeCapacity(ActionSlot.initSpell(null, i));
        }
    }
    pub fn initRoom(self: *ActionSlots, room: *Room) void {
        for (self.spells.slice()) |*spell_slot| {
            assert(spell_slot.id.kind == .spell);
            if (room.drawSpell()) |spell| {
                spell_slot.action = .{ .kind = .{ .spell = spell } };
            }
        }
    }

    pub fn getSlotById(self: *ActionSlots, id: Action.Id) ?*ActionSlot {
        return switch (id.kind) {
            .discard => if (self.discard) |*d| d else null,
            .item => if (id.slot_idx) |idx| if (idx < self.items.len) &self.items.buffer[idx] else null else null,
            .spell => if (id.slot_idx) |idx| if (idx < self.spells.len) &self.spells.buffer[idx] else null else null,
        };
    }
    pub fn getSlotByIdConst(self: *const ActionSlots, id: Action.Id) ?*const ActionSlot {
        return @constCast(self).getSlotById(id);
    }
};

pub const Input = struct {
    rmb_press_ui_timer: utl.TickCounter = utl.TickCounter.initStopped(60),
    // TODO use for cursor (or use targeting data later? idk)
    //rmb_press_ui_kind: enum {
    //    move,
    //    attack,
    //} = .move,
    // TODOish
    // used to draw the ui buttons with the right state
    // also look up the input binding and select/buffer the action
    actions: ActionSlots = .{},

    // TODO keep track of selected/buffered here
    //selected_action: ?struct {
    //    id: Action.Id,
    //} = null,
    //queued_action: ?struct {
    //    id: Action.Id,
    //    params: ?Spell.Params = null,
    //} = null,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = App.getPlat();
        const input = &self.player_input.?;
        const controller = &self.controller.player;
        const ui_slots = &room.ui_slots;
        const mouse_pos = plat.getMousePosWorld(room.camera);

        var selected_slot: ?*const ActionSlot = null;
        if (input.actions.discard) |*discard| {
            if (discard.update()) |s| {
                selected_slot = s;
            }
        }
        for (input.actions.items.slice()) |*item_slot| {
            if (item_slot.update()) |s| {
                selected_slot = s;
            }
        }
        for (input.actions.spells.slice()) |*spell_slot| {
            if (spell_slot.update()) |s| {
                selected_slot = s;
            }
        }
        if (false) {
            if (input.actions.move.update()) |s| {
                selected_slot = s;
            }
            if (input.actions.attack) |*atk| {
                if (atk.update()) |s| {
                    selected_slot = s;
                }
            }
        }
        if (selected_slot) |action_slot| {
            _ = action_slot;
            // TODO
        }

        try ui_slots.update(room, self);
        if (!room.paused) {
            ui_slots.updateTimerAndDrawSpell(room);
        }

        if (self.mana) |*mana| {
            if (room.init_params.mode == .mandy_3_mana) {
                // automatically discard when out of mana
                if (mana.curr == 0 and controller.action_buffered == null) {
                    ui_slots.selectSlot(.action, .discard, .quick_release, 0);
                }
            }
        }

        _ = input.rmb_press_ui_timer.tick(true);
        // clicking rmb cancels buffered action
        // !room.ui_clicked and
        if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            input.rmb_press_ui_timer.restart();
            ui_slots.unselectSlot();
            controller.action_buffered = null;
        }
        // holding rmb sets path, only if an action isn't buffered
        // so movement can be 'canceled' with an action, even if still holding RMB
        // !room.ui_hovered and
        if (controller.action_buffered == null and plat.input_buffer.mouseBtnIsDown(.right)) {
            try self.findPath(room, mouse_pos);
            input.rmb_press_ui_timer.restart();
        }

        if (ui_slots.getSelectedActionSlot()) |slot| {
            assert(slot.kind != null);
            assert(std.meta.activeTag(slot.kind.?) == .action);
            const action = slot.kind.?.action;
            const cast_method = ui_slots.selected_method;
            const do_cast = switch (cast_method) {
                .left_click => !room.ui_clicked and plat.input_buffer.mouseBtnIsJustPressed(.left),
                .quick_press => true,
                .quick_release => !plat.input_buffer.keyIsDown(slot.key),
            };
            if (do_cast) {
                const _params: ?Spell.Params = switch (action) {
                    inline else => |a| if (std.meta.hasMethod(@TypeOf(a), "getTargetParams"))
                        a.getTargetParams(room, self, mouse_pos)
                    else
                        null,
                };
                if (_params) |params| {
                    self.path.len = 0; // cancel the current path on cast, but you can buffer a new one
                    controller.action_buffered = Action.Buffered{
                        .id = .{
                            .kind = std.meta.activeTag(action),
                            .slot_idx = slot.idx,
                        },
                        .params = params,
                    };
                    switch (action) {
                        .spell => |s| if (self.mana) |*mana| {
                            if (s.mana_cost.getActualCost(self)) |cost| {
                                assert(mana.curr >= cost);
                            }
                        },
                        else => {},
                    }
                    ui_slots.changeSelectedSlotToBuffered();
                } else if (action == .discard) {
                    controller.action_buffered = Action.Buffered{
                        .id = .{
                            .kind = .discard,
                            .slot_idx = null,
                        },
                    };
                    ui_slots.changeSelectedSlotToBuffered();
                } else if (cast_method == .quick_press or cast_method == .quick_release) {
                    ui_slots.unselectSlot();
                    controller.action_buffered = null;
                }
            }
        }
    }

    fn actionHasTargeting(action: Action.KindData) bool {
        switch (action) {
            inline else => |a| return std.meta.hasMethod(@TypeOf(a), "renderTargeting"),
        }
    }

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const plat = getPlat();
        const input = &self.player_input.?;
        const ui_slots = &room.ui_slots;
        const controller = &self.controller.player;

        var params: ?Spell.Params = null;
        const action_with_targeting: ?Action.KindData = blk: {
            if (ui_slots.getSelectedActionSlot()) |slot| {
                const action = slot.kind.?.action;
                if (actionHasTargeting(action)) {
                    break :blk action;
                }
            }
            if (controller.action_buffered) |b| {
                if (input.actions.getSlotByIdConst(b.id)) |slot| {
                    if (slot.action) |action| {
                        if (actionHasTargeting(action.kind)) {
                            params = b.params;
                            break :blk action.kind;
                        }
                    }
                }
            }
            if (controller.action_casting) |b| {
                if (input.actions.getSlotByIdConst(b.id)) |slot| {
                    if (slot.action) |action| {
                        if (actionHasTargeting(action.kind)) {
                            params = b.params;
                            break :blk action.kind;
                        }
                    }
                }
            }
            break :blk null;
        };
        if (action_with_targeting) |action| {
            switch (action) {
                inline else => |a| {
                    if (std.meta.hasMethod(@TypeOf(a), "renderTargeting")) {
                        try a.renderTargeting(room, self, params);
                    }
                },
            }
        }

        if (self.path.len > 0) {
            const move_pos = self.path.get(self.path.len - 1);
            const release_f = 0;
            const bounce_f = input.rmb_press_ui_timer.remapTo0_1();
            const bounce_t = @sin(bounce_f * 3);
            const bounce_range = 5;
            const y_off = -bounce_range * bounce_t;
            var points: [3]V2f = .{
                v2f(0, 0),
                v2f(4, -5),
                v2f(-4, -5),
            };
            for (&points) |*p| {
                p.* = p.add(move_pos);
                p.y += y_off;
            }
            plat.circlef(
                move_pos,
                if (self.hurtbox) |h| h.radius else 5,
                .{
                    .outline = .{ .color = Colorf.green.fade(0.6 * (1 - release_f)) },
                    .fill_color = null,
                },
            );
            plat.trianglef(points, .{ .fill_color = Colorf.green.fade(1 - release_f) });
        }
    }
};

pub const Controller = struct {
    const State = enum {
        none,
        action,
        walk,
    };

    state: State = .none,
    action_casting: ?Action.Buffered = null,
    action_buffered: ?Action.Buffered = null,
    cast_counter: utl.TickCounter = .{},
    cast_vfx: ?Thing.Id = null,
    ticks_in_state: i64 = 0,
    mana_regen: ?struct {
        timer: utl.TickCounter,
        max_threshold: usize,
    } = null,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.player;
        const input = &self.player_input.?;

        if (controller.mana_regen) |*mrgn| {
            if (self.mana) |*mana| {
                if (mana.curr < mrgn.max_threshold) {
                    if (mrgn.timer.tick(true)) {
                        mana.curr += 1;
                    }
                }
            }
        }

        if (controller.action_buffered) |buffered| {
            if (controller.action_casting == null) {
                if (input.actions.getSlotById(buffered.id)) |slot| {
                    if (slot.action) |action| {
                        switch (action.kind) {
                            .spell => |spell| {
                                const slot_idx = buffered.id.slot_idx.?;
                                room.ui_slots.clearSlotByActionKind(slot_idx, .spell);
                                if (spell.mislay) {
                                    room.mislaySpell(spell);
                                } else {
                                    room.discardSpell(spell);
                                }
                                if (self.mana) |*mana| {
                                    if (spell.mana_cost.getActualCost(self)) |cost| {
                                        assert(mana.curr >= cost);
                                        mana.curr -= cost;
                                    }
                                }
                                if (self.statuses.get(.quickdraw).stacks > 0) {
                                    room.ui_slots.setActionSlotCooldown(slot_idx, .spell, 0);
                                    self.statuses.getPtr(.quickdraw).addStacks(self, -1);
                                } else if (spell.draw_immediate) {
                                    room.ui_slots.setActionSlotCooldown(slot_idx, .spell, 0);
                                } else if (room.init_params.mode == .mandy_3_mana) {
                                    // mandy doesn't set cooldowns on the slots until full discard
                                    room.ui_slots.setActionSlotCooldown(slot_idx, .spell, null);
                                } else {
                                    // otherwise normal cooldown
                                    room.ui_slots.setActionSlotCooldown(slot_idx, .spell, spell.getSlotCooldownTicks());
                                }
                                controller.cast_counter = utl.TickCounter.init(spell.cast_ticks);
                            },
                            .item => {
                                const slot_idx = buffered.id.slot_idx.?;
                                room.ui_slots.clearSlotByActionKind(slot_idx, .item);
                            },
                            else => {},
                        }

                        controller.action_casting = buffered;
                        controller.action_buffered = null;
                        // make sure selected action is still valid! It may be selected but not buffered, bypassing the canUse check in gameUI.Slots
                        room.ui_slots.cancelSelectedActionSlotIfInvalid(room, self);
                    }
                }
            }
        }

        {
            const p = self.followPathGetNextPoint(5);
            const input_dir = p.sub(self.pos).normalizedOrZero();

            const accel_dir: V2f = input_dir;

            controller.state = state: switch (controller.state) {
                .none => {
                    if (controller.action_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .action;
                    }
                    if (!input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .walk;
                    }
                    self.updateVel(.{}, self.accel_params);
                    _ = self.animator.?.play(.idle, .{ .loop = true });
                    break :state .none;
                },
                .walk => {
                    if (controller.action_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .action;
                    }
                    if (input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    self.updateVel(accel_dir, self.accel_params);
                    if (!self.vel.isZero()) {
                        self.dir = self.vel.normalized();
                    }
                    _ = self.animator.?.play(.move, .{ .loop = true });
                    break :state .walk;
                },
                .action => {
                    assert(controller.action_casting != null);

                    const cast_loop_sound = App.get().data.sounds.get(.spell_casting).?;
                    const cast_end_sound = App.get().data.sounds.get(.spell_cast).?;
                    const cast_loop_volume = 0.2;
                    const cast_end_volume = 0.4;
                    const s = controller.action_casting.?;
                    const action = &input.actions.getSlotById(controller.action_casting.?.id).?.action.?;
                    if (controller.ticks_in_state == 0) {
                        if (s.params) |params| {
                            if (params.face_dir) |dir| {
                                self.dir = dir;
                            }
                        }
                        switch (action.kind) {
                            .spell => {
                                const cast_proto = Thing.CastVFXController.castingProto(self);
                                if (try room.queueSpawnThing(&cast_proto, cast_proto.pos)) |id| {
                                    controller.cast_vfx = id;
                                }
                            },
                            else => {},
                        }
                    }
                    if (controller.cast_counter.tick(false)) {
                        switch (action.kind) {
                            .item => |item| try item.use(self, room, s.params.?),
                            .spell => |spell| {
                                try spell.cast(self, room, s.params.?);
                            },
                            .discard => { // discard all cards
                                const ui_slots = &room.ui_slots;
                                // how long to wait if discarding...
                                const discard_secs = if (self.mana) |*mana| blk: {
                                    const max_extra_mana_cooldown_secs: f32 = 1.33;
                                    const per_mana_secs = max_extra_mana_cooldown_secs / utl.as(f32, mana.max);
                                    const num_secs: f32 = 0.66 + per_mana_secs * utl.as(f32, mana.curr);
                                    break :blk num_secs;
                                } else 3;
                                const num_ticks = core.secsToTicks(discard_secs);
                                for (ui_slots.getSlotsByActionKindConst(.spell)) |*slot| {
                                    if (slot.kind) |k| {
                                        const spell = k.action.spell;
                                        room.discardSpell(spell);
                                    }
                                    ui_slots.clearSlotByActionKind(slot.idx, .spell);
                                    ui_slots.setActionSlotCooldown(slot.idx, .spell, num_ticks);
                                }
                                ui_slots.setActionSlotCooldown(0, .discard, num_ticks);
                                ui_slots.unselectSlot();
                                // mana mandy gets all her mana back
                                if (self.mana) |*mana| {
                                    if (room.init_params.mode == .mandy_3_mana) {
                                        mana.curr = mana.max;
                                    }
                                }
                            },
                        }
                        getPlat().stopSound(cast_loop_sound);
                        controller.action_casting = null;
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    getPlat().loopSound(cast_loop_sound);
                    // TODO bit of a hacky wacky
                    const ticks_left = controller.cast_counter.num_ticks - controller.cast_counter.curr_tick;
                    if (ticks_left <= 30) {
                        const vol: f32 = utl.as(f32, ticks_left) / 30.0;
                        getPlat().setSoundVolume(cast_loop_sound, vol * cast_loop_volume);
                        if (controller.cast_vfx) |id| {
                            if (room.getThingById(id)) |cast| {
                                cast.controller.cast_vfx.anim_to_play = .basic_cast;
                            }
                        }
                        if (controller.cast_vfx != null) {
                            getPlat().setSoundVolume(cast_end_sound, cast_end_volume);
                            getPlat().playSound(cast_end_sound);
                        }
                        controller.cast_vfx = null;
                    } else {
                        getPlat().setSoundVolume(cast_loop_sound, cast_loop_volume);
                    }
                    self.updateVel(.{}, self.accel_params);
                    _ = self.animator.?.play(.cast, .{ .loop = true });
                    break :state .action;
                },
            };
            controller.ticks_in_state += 1;
        }
    }
};
