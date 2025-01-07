const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

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
const debug = @import("debug.zig");

const Run = @This();
const config = @import("config");
const App = @import("App.zig");
const Log = App.Log;
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const menuUI = @import("menuUI.zig");
const gameUI = @import("gameUI.zig");
const Shop = @import("Shop.zig");
const Item = @import("Item.zig");
const player = @import("player.zig");
const ImmUI = @import("ImmUI.zig");
const sprites = @import("sprites.zig");
const Tooltip = @import("Tooltip.zig");
const TileMap = @import("TileMap.zig");
const icon_text = @import("icon_text.zig");

pub const Mode = enum {
    pub const Mask = std.EnumSet(Mode);

    frank_4_slot,
    mandy_3_mana,
    crispin_picker,
};

pub const Reward = struct {
    const max_rewards: usize = 8;
    const base_spells: usize = 3;
    const max_spells = 8;
    const base_items = 1;
    const max_items = 8;

    pub const UI = struct {
        rewards: std.BoundedArray(Reward, max_rewards) = .{},
        selected_spell_choice_idx: ?usize = null,
    };
    pub const SpellChoice = struct {
        spell: Spell,
        long_hover: menuUI.LongHover = .{},
    };
    pub const SpellChoiceArray = std.BoundedArray(SpellChoice, max_spells);

    kind: union(enum) {
        spell_choice: SpellChoiceArray,
        item: Item,
        gold: i32,
    },
    long_hover: menuUI.LongHover = .{},
};

pub const DeadMenu = struct {
    modal: menuUI.Modal,
    retry_room_button: menuUI.Button,
    new_run_button: menuUI.Button,
    quit_button: menuUI.Button,
};

pub fn makeStarterDeck(dbg: bool) Spell.SpellArray {
    var ret = Spell.SpellArray{};
    // TODO placeholder
    const unherring = Spell.getProto(.unherring);
    const protec = Spell.getProto(.protec);
    const frost = Spell.getProto(.frost_vom);
    const blackmail = Spell.getProto(.blackmail);
    const mint = Spell.getProto(.mint);
    const impling = Spell.getProto(.impling);
    const promptitude = Spell.getProto(.promptitude);
    const flamey_explodey = Spell.getProto(.flamey_explodey);
    const expose = Spell.getProto(.expose);
    const zap_dash = Spell.getProto(.zap_dash);
    const shield_fu = Spell.getProto(.shield_fu);

    const deck_cards = if (dbg)
        &[_]struct { Spell, usize }{
            .{ unherring, 1 },
            .{ protec, 1 },
            .{ frost, 1 },
            .{ blackmail, 1 },
            .{ mint, 1 },
            .{ impling, 1 },
            .{ promptitude, 1 },
            .{ flamey_explodey, 1 },
            .{ zap_dash, 1 },
        }
    else
        &[_]struct { Spell, usize }{
            .{ unherring, 4 },
            .{ shield_fu, 2 },
            .{ expose, 1 },
        };

    deck: for (deck_cards) |t| {
        for (0..t[1]) |_| {
            ret.append(t[0]) catch break :deck;
        }
    }

    return ret;
}

pub const RoomLoadParams = struct {
    kind: Data.RoomKind,
    idx: usize = 0,
    difficulty_per_wave: f32 = 0,
    waves_params: Room.WavesParams,
};

pub const Place = struct {
    pub const Array = std.BoundedArray(Place, 32);
    room: RoomLoadParams,
};

gold: i32 = 0,
room: Room = undefined,
// debug room history states
room_buf: []Room = undefined,
room_buf_tail: usize = 0,
room_buf_head: usize = 0,
room_buf_size: usize = 0,

reward_ui: ?Reward.UI = null,
shop: ?Shop = null,
screen: enum {
    room,
    reward,
    shop,
    dead,
    win,
} = .room,
seed: u64,
rng: std.Random.DefaultPrng = undefined,
places: Place.Array = .{},
curr_place_idx: usize = 0,
ui_slots: gameUI.Slots = .{},
mode: Mode = undefined,
deck: Spell.SpellArray = .{},
load_timer: u.TickCounter = u.TickCounter.init(20),
load_state: enum {
    none,
    fade_in,
    fade_out,
} = .fade_in,
curr_tick: i64 = 0,
imm_ui: struct {
    commands: ImmUI.CmdBuf = .{},
} = .{},
tooltip_ui: struct {
    commands: ImmUI.CmdBuf = .{},
} = .{},
ui_clicked: bool = false,
ui_hovered: bool = false,
exit_to_menu: bool = false,

pub fn initSeeded(run: *Run, mode: Mode, seed: u64) Error!*Run {
    const plat = getPlat();
    const app = App.get();
    run.* = .{
        .rng = std.Random.DefaultPrng.init(seed),
        .seed = seed,
        .deck = makeStarterDeck(false),
        .mode = mode,
    };

    if (!config.is_release) {
        Log.info("Allocating debug room buf: {}KiB\n", .{(@sizeOf(Room) * 60) / 1024});
        run.room_buf = try plat.heap.alloc(Room, 60);
        run.room_buf_size = 0;
        run.room_buf_head = 0;
        run.room_buf_tail = 0;
    }

    run.ui_slots.init(
        4,
        &.{ Item.getProto(.pot_hp), null, null, null },
        mode == .mandy_3_mana,
    );

    // init places
    var places = Place.Array{};

    var smol_room_idxs = std.BoundedArray(usize, 16){};
    for (0..app.data.room_kind_tilemaps.get(.smol).len) |i| {
        smol_room_idxs.append(i) catch unreachable;
    }
    run.rng.random().shuffleWithIndex(usize, smol_room_idxs.slice(), u32);

    for (0..@min(smol_room_idxs.len, 3)) |i| {
        try places.append(.{ .room = .{
            .difficulty_per_wave = 0,
            .kind = .smol,
            .idx = smol_room_idxs.get(i),
            .waves_params = .{ .room_kind = .smol },
        } });
    }

    var big_room_idxs = std.BoundedArray(usize, 16){};
    for (0..app.data.room_kind_tilemaps.get(.big).len) |i| {
        big_room_idxs.append(i) catch unreachable;
    }
    run.rng.random().shuffleWithIndex(usize, big_room_idxs.slice(), u32);

    for (0..@min(big_room_idxs.len, 3)) |i| {
        try places.append(.{ .room = .{
            .difficulty_per_wave = 0,
            .kind = .big,
            .idx = big_room_idxs.get(i),
            .waves_params = .{ .room_kind = .big },
        } });
    }

    for (places.slice(), 0..) |*place, i| {
        // TODO this better
        if (i < 2) {
            place.room.waves_params.enemy_probabilities.getPtr(.slime).* = 1;
            place.room.waves_params.enemy_probabilities.getPtr(.bat).* = 0.5;
        }
        if (i >= 2) {
            place.room.waves_params.enemy_probabilities.getPtr(.slime).* = 1;
            place.room.waves_params.enemy_probabilities.getPtr(.bat).* = 0.5;
            place.room.waves_params.enemy_probabilities.getPtr(.gobbow).* = 1;
            place.room.waves_params.enemy_probabilities.getPtr(.gobbomber).* = 0.5;
        }
        if (i >= 3) {
            place.room.waves_params.enemy_probabilities.getPtr(.slime).* = 0;
            place.room.waves_params.enemy_probabilities.getPtr(.bat).* = 0;
            place.room.waves_params.enemy_probabilities.getPtr(.gobbow).* = 0.5;
            place.room.waves_params.enemy_probabilities.getPtr(.gobbomber).* = 1;
            place.room.waves_params.enemy_probabilities.getPtr(.acolyte).* = 1;
        }
        if (i >= 4) {
            place.room.waves_params.enemy_probabilities.getPtr(.gobbow).* = 1;
            place.room.waves_params.enemy_probabilities.getPtr(.sharpboi).* = 1;
            place.room.waves_params.enemy_probabilities.getPtr(.troll).* = 1;
            place.room.waves_params.num_waves = 3;
        }
        place.room.difficulty_per_wave = 1 + u.as(f32, i) * 0.6;
        //TODO unhack this?
        place.room.waves_params.difficulty_per_wave = place.room.difficulty_per_wave;
    }
    try places.insert(places.len / 2, .{ .room = .{ .kind = .shop, .waves_params = .{ .room_kind = .shop, .first_wave_delay_secs = 0 } } });
    try places.insert(0, .{ .room = .{ .kind = .first, .waves_params = .{ .room_kind = .first, .first_wave_delay_secs = 0 } } });
    // shop at very start
    //try places.insert(0, .{ .room = .{ .kind = .shop, .waves_params = .{ .room_kind = .shop, .first_wave_delay_secs = 0 } } });
    try places.append(.{ .room = .{ .kind = .shop, .waves_params = .{ .room_kind = .shop, .first_wave_delay_secs = 0 } } });
    try places.append(.{ .room = .{ .difficulty_per_wave = 5, .kind = .boss, .idx = 0, .waves_params = .{ .room_kind = .boss } } });
    // TODO this better
    {
        const boss_params = &places.buffer[places.len - 1].room.waves_params;
        boss_params.difficulty_per_wave = 5;
        boss_params.num_waves = 4;
        boss_params.enemy_probabilities.getPtr(.slime).* = 0;
        boss_params.enemy_probabilities.getPtr(.sharpboi).* = 1;
        boss_params.enemy_probabilities.getPtr(.acolyte).* = 1;
        boss_params.enemy_probabilities.getPtr(.gobbow).* = 1;
        boss_params.enemy_probabilities.getPtr(.troll).* = 0.5;
    }

    //try places.append(.{ .room = .{ .difficulty = 4, .idx = 0, .kind = .testu } });
    run.places = places;

    // TODO dummy room
    const player_thing = player.modePrototype(mode);
    try run.initRoom(
        &run.room,
        &player_thing,
        .{
            .difficulty_per_wave = 0,
            .kind = .first,
            .idx = 0,
            .waves_params = .{ .room_kind = .first },
        },
    );

    return run;
}

pub fn initRandom(run: *Run, mode: Mode) Error!*Run {
    var rng = std.Random.DefaultPrng.init(u.as(u64, std.time.microTimestamp()));
    const seed = rng.random().int(u64);
    Log.info("Initting seeded run: {}", .{seed});
    return try initSeeded(run, mode, seed);
}

pub fn deinit(self: *Run) void {
    self.room.deinit();
    if (!config.is_release) {
        getPlat().heap.free(self.room_buf);
    }
}

pub fn reset(self: *Run) Error!void {
    self.deinit();
    _ = try initRandom(self, self.mode);
}

pub fn startRun(self: *Run) Error!void {
    try self.loadPlaceFromCurrIdx();
}

pub fn initRoom(self: *Run, room: *Room, player_thing: *const Thing, params: RoomLoadParams) Error!void {
    const data = App.get().data;
    const room_indices = data.room_kind_tilemaps.get(params.kind);
    const room_idx = room_indices.get(params.idx);
    const tilemap_ref = data.getByIdx(TileMap, room_idx).?.data_ref;
    const init_params: Room.InitParams = .{
        .deck = self.deck,
        .waves_params = params.waves_params,
        .tilemap_ref = tilemap_ref,
        .seed = self.rng.random().int(u64),
        .player = player_thing.*,
        .mode = self.mode,
    };
    try room.init(&init_params);
}

pub fn loadPlaceFromCurrIdx(self: *Run) Error!void {
    if (self.shop) |*shop| {
        shop.deinit();
        self.shop = null;
    }
    const r = self.places.get(self.curr_place_idx).room;
    var player_thing = player.modePrototype(self.mode);
    if (self.room.getConstPlayer()) |p| {
        player_thing.hp.?.max = p.hp.?.max;
        player_thing.hp.?.curr = p.hp.?.curr;
        player_thing.dir = if (p.dir.x > 0) V2f.right else V2f.left;
    }
    self.room.deinit();
    try self.initRoom(&self.room, &player_thing, r);
    self.ui_slots.beginRoom(&self.room, r.kind != .shop);
    if (r.kind == .smol or r.kind == .big or r.kind == .boss) {
        self.makeRewards(r.difficulty_per_wave);
    } else {
        self.reward_ui = null;
    }
    if (r.kind == .shop) {
        self.shop = try Shop.init(self.rng.random().int(u64), self);
    }
    // TODO hacky
    // update once to clear fog
    self.room.parent_run_this_frame = self;
    try self.room.update();
    self.screen = .room;
}

pub fn makeRewards(self: *Run, difficulty: f32) void {
    const random = self.rng.random();
    var reward_ui = Reward.UI{};

    { // spells
        const num_spells = Reward.base_spells;
        var reward: Reward = .{ .kind = .{ .spell_choice = .{} } };
        var buf: [Reward.max_spells]Spell = undefined;
        const spells = Spell.makeRoomReward(random, self.mode, buf[0..num_spells]);
        for (spells) |spell| {
            reward.kind.spell_choice.appendAssumeCapacity(.{ .spell = spell });
        }
        reward_ui.rewards.appendAssumeCapacity(reward);
    }
    { // items
        const num_items = random.uintAtMost(usize, Reward.base_items);
        if (num_items > 0) {
            var buf: [Reward.max_items]Item = undefined;
            const items = Item.makeRoomReward(random, self.mode, buf[0..num_items]);
            for (items) |item| {
                reward_ui.rewards.appendAssumeCapacity(.{ .kind = .{ .item = item } });
            }
        }
    }
    { // gold
        const gold = u.as(i32, @ceil(difficulty)) + self.rng.random().uintAtMost(u8, 5);
        if (gold > 0) { // should be above 0 but ya never know
            reward_ui.rewards.appendAssumeCapacity(.{ .kind = .{ .gold = gold } });
        }
    }

    self.reward_ui = reward_ui;
}

pub fn canPickupProduct(self: *Run, product: *const Shop.Product) bool {
    switch (product.kind) {
        .spell => |_| {
            if (self.deck.len >= self.deck.buffer.len) return false;
        },
        .item => |_| {
            if (self.ui_slots.getNextEmptyItemSlot() == null) return false;
        },
    }
    return true;
}

pub fn pickupProduct(self: *Run, product: *const Shop.Product) void {
    assert(self.canPickupProduct(product));
    switch (product.kind) {
        .spell => |spell| {
            assert(self.deck.len < self.deck.buffer.len);
            self.deck.append(spell) catch unreachable;
            // TODO ugh?
            self.room.init_params.deck.append(spell) catch unreachable;
            self.room.draw_pile.append(spell) catch unreachable;
        },
        .item => |item| {
            const slot = self.ui_slots.getNextEmptyItemSlot().?;
            slot.item = item;
        },
    }
}

fn loadNextPlace(self: *Run) void {
    self.load_state = .fade_out;
}

pub fn resolutionChanged(self: *Run) void {
    self.room.resolutionChanged();
    self.ui_slots.reflowRects();
}

pub fn roomUpdate(self: *Run) Error!void {
    const plat = getPlat();
    const room = &self.room;

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f4)) {
            try room.reset();
            const r = self.places.get(self.curr_place_idx).room;
            self.ui_slots.beginRoom(&self.room, r.kind != .shop);
        }
        if (room.edit_mode) {
            if (plat.input_buffer.getNumberKeyJustPressed()) |num| {
                const app = App.get();
                const n: usize = if (num == 0) 9 else num - 1;
                const test_rooms = app.data.room_kind_tilemaps.getPtr(.testu);
                if (n < test_rooms.len) {
                    const data = App.getData();
                    const tilemap_idx = test_rooms.get(n);
                    const ref = data.getByIdx(TileMap, tilemap_idx).?.data_ref;
                    try room.reloadFromTileMap(ref);
                    self.ui_slots.beginRoom(&self.room, true);
                }
            }
        }
        if (!config.is_release) {
            if (plat.input_buffer.keyIsJustPressed(.comma)) {
                if (self.room_buf_size > 0) {
                    const prev = (self.room_buf_head + self.room_buf.len - 1) % self.room_buf.len;
                    self.room.deinit();
                    self.room = self.room_buf[prev];
                    self.room_buf_head = prev;
                    self.room_buf_size -= 1;
                }
                self.room.paused = true;
            }
        }
    }
    room.parent_run_this_frame = self;
    if (!room.edit_mode) {
        //if (plat.input_buffer.keyIsJustPressed(.escape)) {
        //    room.paused = true;
        //    self.screen = .pause_menu;
        //}
    }
    if (!config.is_release) {
        if (!room.paused) {
            const next_head = (self.room_buf_head + 1) % self.room_buf.len;
            const next_tail = (self.room_buf_tail + 1) % self.room_buf.len;
            // equal means either full or empty
            if (self.room_buf_head == self.room_buf_tail and self.room_buf_size == self.room_buf.len) {
                // full, deinit so we can overwrite, and bump tail along
                self.room_buf[self.room_buf_head].deinit();
                self.room_buf_tail = next_tail;
                self.room_buf_size -= 1;
            }
            try room.clone(&self.room_buf[self.room_buf_head]);
            self.room_buf_head = next_head;
            self.room_buf_size += 1;
        }
    }

    // update spell slots, and player input
    if (room.getPlayer()) |thing| {
        // uses self.ui_slots
        try thing.player_input.?.update(self, thing);
    }
    try room.update();

    switch (room.progress_state) {
        .none => {},
        .lost => {
            self.screen = .dead;
        },
        .won => {
            //
        },
        .exited => |exit_door| {
            _ = exit_door;
            self.loadNextPlace();
        },
    }
    if (room.paused) {
        // TODO update game pause ui
    }
}

pub fn itemsUpdate(self: *Run) Error!void {
    //const data = App.get().data;
    const plat = getPlat();
    const ui_scaling: f32 = plat.ui_scaling;
    const mouse_pos = plat.getMousePosScreen();
    const slot_bg_color = Colorf.rgb(0.07, 0.05, 0.05);

    for (self.ui_slots.items.slice()) |slot| {
        const rect = slot.rect;
        self.imm_ui.commands.append(.{ .rect = .{
            .pos = rect.pos,
            .dims = rect.dims,
            .opt = .{
                .fill_color = slot_bg_color,
            },
        } }) catch @panic("Fail to append rect cmd");
        if (slot.kind) |kind| {
            const item = kind.action.item;
            try item.unqRenderIcon(&self.imm_ui.commands, rect.pos, ui_scaling);
        }
    }

    for (self.ui_slots.items.slice()) |*slot| {
        const rect = slot.rect;
        const hovered = geom.pointIsInRectf(mouse_pos, rect);
        const clicked_somewhere = (plat.input_buffer.mouseBtnIsJustPressed(.left) or plat.input_buffer.mouseBtnIsJustPressed(.right));
        const clicked_on = hovered and clicked_somewhere;
        const menu_is_open = if (self.ui_slots.item_menu_open) |idx| idx == slot.idx else false;

        if (slot.kind) |kind| {
            const item = kind.action.item;
            if (slot.long_hover.update(hovered)) {
                try item.unqRenderTooltip(&self.tooltip_ui.commands, rect.pos.add(v2f(rect.dims.x, 0)), ui_scaling);
            }
            if (clicked_on) {
                self.ui_slots.item_menu_open = slot.idx;
            }
        } else if (menu_is_open) {
            self.ui_slots.item_menu_open = null;
        }
    }
    if (self.ui_slots.item_menu_open) |idx| {
        self.tooltip_ui.commands.clear(); // TODO - rethink??
        assert(idx < self.ui_slots.items.len);
        const slot: *gameUI.Slots.Slot = &self.ui_slots.items.buffer[idx];
        const item: *Item = &slot.kind.?.action.item;
        const slot_rect: geom.Rectf = slot.rect;
        const btn_dims = v2f(100, 75);
        const can_use = item.canUse(&self.player_thing, self);
        const menu_padding = V2f.splat(4);
        const num_menu_items: f32 = if (can_use) 2 else 1;
        const menu_dims = v2f(btn_dims.x, btn_dims.y * num_menu_items).add(menu_padding.scale(2).add(v2f(0, (num_menu_items - 1) * menu_padding.y)));
        const menu_pos = slot_rect.pos.add(v2f(0, -menu_dims.y));

        self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
            .pos = menu_pos,
            .dims = menu_dims,
            .opt = .{ .fill_color = .gray },
        } });

        var curr_pos = menu_pos.add(menu_padding);
        const use_pressed = if (can_use) blk: {
            const ret = menuUI.textButton(&self.imm_ui.commands, curr_pos, "Use", btn_dims, ui_scaling);
            curr_pos.y += btn_dims.y + menu_padding.y;
            break :blk ret;
        } else false;
        const discard_pressed = menuUI.textButton(&self.imm_ui.commands, curr_pos, "Discard", btn_dims, ui_scaling);

        if (use_pressed and !discard_pressed) {
            try item.useInRun(&self.player_thing, self);
            slot.kind = null;
        } else if (discard_pressed) {
            slot.kind = null;
        } else {
            const hovered = geom.pointIsInRectf(mouse_pos, slot_rect);
            const clicked_somewhere = (plat.input_buffer.mouseBtnIsJustPressed(.left) or plat.input_buffer.mouseBtnIsJustPressed(.right));
            const clicked_on_slot = hovered and clicked_somewhere;
            if (clicked_somewhere and !use_pressed and !discard_pressed and !clicked_on_slot) {
                self.ui_slots.item_menu_open = null;
            }
        }
        // TODO ugh
        self.syncPlayerThing(.run);
    }
}

pub fn rewardSpellChoiceUI(self: *Run, idx: usize) Error!void {
    const plat = getPlat();
    const data = App.getData();
    const ui_scaling: f32 = plat.ui_scaling;

    // modal background
    var modal_dims = plat.screen_dims_f.scale(0.8);
    var modal_topleft = plat.screen_dims_f.sub(modal_dims).scale(0.5);

    const game_rect_dims = self.ui_slots.getGameScreenRect();
    modal_dims = v2f(game_rect_dims.x * 0.8, game_rect_dims.y * 0.94);
    modal_topleft = game_rect_dims.sub(modal_dims).scale(0.5);

    self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
        .pos = modal_topleft,
        .dims = modal_dims,
        .opt = .{
            .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
            .outline = .{ .color = Colorf.rgba(0.1, 0.1, 0.2, 0.8), .thickness = 4 },
        },
    } });

    var curr_row_y = modal_topleft.y + 10 * ui_scaling;
    const modal_center_x = modal_topleft.x + modal_dims.x * 0.5;

    // title
    const title_font = data.fonts.get(.pixeloid);
    const title_center = v2f(modal_center_x, curr_row_y + 10 * ui_scaling);
    self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
        .pos = title_center,
        .text = ImmUI.initLabel("Choose a spell"),
        .opt = .{
            .size = title_font.base_size * u.as(u32, ui_scaling + 1),
            .font = title_font,
            .smoothing = .none,
            .color = .white,
            .center = true,
        },
    } });
    curr_row_y += 30 * ui_scaling;

    // spells
    var spell_choices: *Reward.SpellChoiceArray = &self.reward_ui.?.rewards.buffer[idx].kind.spell_choice;
    assert(spell_choices.len > 0);
    const spell_dims = Spell.card_dims.scale(ui_scaling + 1);
    var spell_rects = std.BoundedArray(geom.Rectf, Reward.max_spells){};
    spell_rects.resize(spell_choices.len) catch unreachable;
    gameUI.layoutRectsFixedSize(
        spell_rects.len,
        spell_dims,
        v2f(modal_center_x, curr_row_y + spell_dims.y * 0.5),
        .{ .direction = .horizontal, .space_between = 10 * ui_scaling },
        spell_rects.slice(),
    );

    const mouse_pos = plat.getMousePosScreen();
    for (spell_choices.slice(), 0..) |*spell_choice, i| {
        var rect = spell_rects.get(i);
        const hovered = geom.pointIsInRectf(mouse_pos, rect);
        const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
        if (hovered) {
            rect.pos.y -= 4;
        }
        _ = spell_choice.spell.unqRenderCard(&self.imm_ui.commands, rect.pos, null, ui_scaling + 1);
        if (clicked) {
            const product = Shop.Product{ .kind = .{ .spell = spell_choice.spell } };
            if (self.canPickupProduct(&product)) {
                self.pickupProduct(&product);
                _ = self.reward_ui.?.rewards.orderedRemove(idx);
                self.reward_ui.?.selected_spell_choice_idx = null;
                break;
            }
        }
        if (spell_choice.long_hover.update(hovered)) {
            const tooltip_pos = rect.pos.add(v2f(rect.dims.x, 0));
            try spell_choice.spell.unqRenderTooltip(&self.tooltip_ui.commands, tooltip_pos, ui_scaling);
        }
    }

    // anchor button to bottom of modal
    const btn_dims = v2f(60, 25).scale(ui_scaling);
    const btn_topleft = v2f(
        modal_topleft.x + (modal_dims.x - btn_dims.x) * 0.5,
        modal_topleft.y + modal_dims.y - 7 * ui_scaling - btn_dims.y,
    );
    if (menuUI.textButton(&self.imm_ui.commands, btn_topleft, "Back", btn_dims, ui_scaling)) {
        self.reward_ui.?.selected_spell_choice_idx = null;
    }
}

pub fn rewardUpdate(self: *Run) Error!void {
    const data = App.get().data;
    const plat = getPlat();
    const ui_scaling: f32 = plat.ui_scaling;
    assert(self.reward_ui != null);
    const reward_ui = &self.reward_ui.?;

    if (reward_ui.selected_spell_choice_idx) |idx| {
        try self.rewardSpellChoiceUI(idx);
        return;
    }

    // modal background
    var modal_dims = plat.screen_dims_f.scale(0.6);
    var modal_topleft = plat.screen_dims_f.sub(modal_dims).scale(0.5);

    const game_rect_dims = self.ui_slots.getGameScreenRect();
    modal_dims = v2f(game_rect_dims.x * 0.6, game_rect_dims.y * 0.9);
    modal_topleft = game_rect_dims.sub(modal_dims).scale(0.5);

    self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
        .pos = modal_topleft,
        .dims = modal_dims,
        .opt = .{
            .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
            .outline = .{
                .color = Colorf.rgba(0.1, 0.1, 0.2, 0.8),
                .thickness = 2 * ui_scaling,
            },
        },
    } });

    var curr_row_y = modal_topleft.y + 10 * ui_scaling;
    const modal_center_x = modal_topleft.x + modal_dims.x * 0.5;

    // title
    const title_font = data.fonts.get(.pixeloid);
    const title_center = v2f(modal_center_x, curr_row_y + 10 * ui_scaling);
    self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
        .pos = title_center,
        .text = ImmUI.initLabel("Found some stuff"),
        .opt = .{
            .size = title_font.base_size * u.as(u32, ui_scaling + 1),
            .font = title_font,
            .smoothing = .none,
            .color = .white,
            .center = true,
        },
    } });
    curr_row_y += 30 * ui_scaling;

    // reward rows
    const row_icon_dims = Item.icon_dims.scale(ui_scaling);
    const row_rect_dims = v2f(modal_dims.x - 10 * ui_scaling, row_icon_dims.y + 10 * ui_scaling);
    const row_rect_x = modal_topleft.x + 5 * ui_scaling;
    const mouse_pos = plat.getMousePosScreen();

    var removed_idx: ?usize = null;
    for (reward_ui.rewards.slice(), 0..) |*reward, i| {
        var row_rect_color = Colorf.rgba(0.4, 0.4, 0.4, 0.7);
        var row_rect_pos = v2f(row_rect_x, curr_row_y);
        const hovered = geom.pointIsInRectf(mouse_pos, .{ .pos = row_rect_pos, .dims = row_rect_dims });
        const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
        if (hovered) {
            //row_rect_pos.y -= 4;
            row_rect_color = Colorf.rgba(0.6, 0.6, 0.6, 0.7);
        }
        self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
            .pos = row_rect_pos,
            .dims = row_rect_dims,
            .opt = .{
                .fill_color = row_rect_color,
                .edge_radius = 0.1,
            },
        } });
        const row_text_font = data.fonts.get(.pixeloid);
        const row_text_opt = draw.TextOpt{
            .font = row_text_font,
            .color = .white,
            .size = row_text_font.base_size * u.as(u32, ui_scaling),
        };
        const row_icon_pos = row_rect_pos.add(v2f(5, 5).scale(ui_scaling));
        const row_text_pos = row_icon_pos.add(v2f(5 * ui_scaling + row_icon_dims.x + 5 * ui_scaling, 7 * ui_scaling));

        switch (reward.kind) {
            .spell_choice => {
                const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(.cards).? };
                try info.unqRender(&self.imm_ui.commands, row_icon_pos, ui_scaling);
                self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
                    .pos = row_text_pos,
                    .text = ImmUI.initLabel("Spell"),
                    .opt = row_text_opt,
                } });
                if (clicked) {
                    reward_ui.selected_spell_choice_idx = i;
                }
                if (reward.long_hover.update(hovered)) {
                    const tt = Tooltip{
                        .title = Tooltip.Title.fromSlice("Choose a spell") catch unreachable,
                    };
                    try tt.unqRender(&self.tooltip_ui.commands, mouse_pos, ui_scaling);
                }
            },
            .item => |item| {
                try item.unqRenderIcon(&self.imm_ui.commands, row_icon_pos, ui_scaling);
                self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
                    .pos = row_text_pos,
                    .text = ImmUI.initLabel(item.getName()),
                    .opt = row_text_opt,
                } });
                if (clicked) {
                    const product = Shop.Product{ .kind = .{ .item = item } };
                    if (self.canPickupProduct(&product)) {
                        self.pickupProduct(&product);
                        removed_idx = i;
                    }
                }
                if (reward.long_hover.update(hovered)) {
                    try item.unqRenderTooltip(&self.tooltip_ui.commands, mouse_pos, ui_scaling);
                }
            },
            .gold => |gold_amount| {
                const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(.gold_stacks).? };
                try info.unqRender(&self.imm_ui.commands, row_icon_pos, ui_scaling);
                const gold_str = try u.bufPrintLocal("{}", .{gold_amount});
                self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
                    .pos = row_text_pos,
                    .text = ImmUI.initLabel(gold_str),
                    .opt = row_text_opt,
                } });
                if (clicked) {
                    self.gold += gold_amount;
                    removed_idx = i;
                }
                if (reward.long_hover.update(hovered)) {
                    const tt = Tooltip{
                        .title = Tooltip.Title.fromSlice("It's money...") catch unreachable,
                    };
                    try tt.unqRender(&self.tooltip_ui.commands, mouse_pos, ui_scaling);
                }
            },
        }
        curr_row_y += row_rect_dims.y + 10;
    }
    if (removed_idx) |idx| {
        _ = reward_ui.rewards.orderedRemove(idx);
    }

    // anchor skip button to bottom of modal
    const skip_btn_dims = v2f(60, 25).scale(ui_scaling);
    const skip_btn_topleft = v2f(
        modal_topleft.x + (modal_dims.x - skip_btn_dims.x) * 0.5,
        modal_topleft.y + modal_dims.y - 7 * ui_scaling - skip_btn_dims.y,
    );
    const skip_btn_text: []const u8 = "Close";
    if (menuUI.textButton(&self.imm_ui.commands, skip_btn_topleft, skip_btn_text, skip_btn_dims, ui_scaling) or reward_ui.rewards.len == 0) {
        self.screen = .room;
        self.room.took_reward = reward_ui.rewards.len == 0;
    }
}

pub fn shopUpdate(self: *Run) Error!void {
    const plat = App.getPlat();
    assert(self.shop != null);
    const shop = &self.shop.?;

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f4)) {
            _ = try shop.reset(self);
        }
        if (plat.input_buffer.keyIsJustPressed(.k)) {
            self.gold += 100;
        }
    }

    if (try shop.update(self)) |*product| {
        const price = product.price.gold;
        assert(self.gold >= price);
        self.gold -= price;
        self.pickupProduct(product);
    }
    if (shop.state == .done) {
        self.screen = .room;
        shop.state = .shopping;
    }
}

pub fn deadUpdate(self: *Run) Error!void {
    const data = App.getData();
    const plat = getPlat();
    const ui_scaling = plat.ui_scaling;
    // modal background
    var modal_dims = plat.screen_dims_f.scale(0.6);
    var modal_topleft = plat.screen_dims_f.sub(modal_dims).scale(0.5);

    const game_rect_dims = self.ui_slots.getGameScreenRect();
    modal_dims = v2f(game_rect_dims.x * 0.6, game_rect_dims.y * 0.9);
    modal_topleft = game_rect_dims.sub(modal_dims).scale(0.5);

    self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
        .pos = modal_topleft,
        .dims = modal_dims,
        .opt = .{
            .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
            .outline = .{
                .color = Colorf.rgba(0.1, 0.1, 0.2, 0.8),
                .thickness = 2 * ui_scaling,
            },
        },
    } });

    var curr_row_y = modal_topleft.y + 10 * ui_scaling;
    const modal_center_x = modal_topleft.x + modal_dims.x * 0.5;

    // title
    const title_font = data.fonts.get(.pixeloid);
    const title_center = v2f(modal_center_x, curr_row_y + 10 * ui_scaling);
    self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
        .pos = title_center,
        .text = ImmUI.initLabel("Your HP reached 0"),
        .opt = .{
            .size = title_font.base_size * u.as(u32, ui_scaling + 1),
            .font = title_font,
            .smoothing = .none,
            .color = .white,
            .center = true,
        },
    } });
    curr_row_y += 30 * ui_scaling;

    const btn_dims = v2f(70, 30).scale(ui_scaling);
    const btn_spacing: f32 = 10 * ui_scaling;
    const btns_x = modal_topleft.x + (modal_dims.x - btn_dims.x) * 0.5;
    var curr_btn_pos = v2f(btns_x, curr_row_y);

    if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "New Run", btn_dims, ui_scaling)) {
        try self.reset();
        try self.startRun();
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "Main Menu", btn_dims, ui_scaling)) {
        self.exit_to_menu = true;
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "Exit", btn_dims, ui_scaling)) {
        plat.exit();
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (debug.allow_room_retry) {
        if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "Retry Room", btn_dims, ui_scaling)) {
            try self.room.reset();
            const r = self.places.get(self.curr_place_idx).room;
            self.ui_slots.beginRoom(&self.room, r.kind != .shop);
            self.screen = .room;
        }
        curr_btn_pos.y += btn_dims.y + btn_spacing;
    }
}

pub fn winUpdate(self: *Run) Error!void {
    const data = App.getData();
    const plat = getPlat();
    const ui_scaling = plat.ui_scaling;
    // modal background
    var modal_dims = plat.screen_dims_f.scale(0.6);
    var modal_topleft = plat.screen_dims_f.sub(modal_dims).scale(0.5);

    const game_rect_dims = self.ui_slots.getGameScreenRect();
    modal_dims = v2f(game_rect_dims.x * 0.6, game_rect_dims.y * 0.9);
    modal_topleft = game_rect_dims.sub(modal_dims).scale(0.5);

    self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
        .pos = modal_topleft,
        .dims = modal_dims,
        .opt = .{
            .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
            .outline = .{
                .color = Colorf.rgba(0.1, 0.1, 0.2, 0.8),
                .thickness = 2 * ui_scaling,
            },
        },
    } });

    var curr_row_y = modal_topleft.y + 10 * ui_scaling;
    const modal_center_x = modal_topleft.x + modal_dims.x * 0.5;

    // title
    const title_font = data.fonts.get(.pixeloid);
    const title_center = v2f(modal_center_x, curr_row_y + 10 * ui_scaling);
    self.imm_ui.commands.appendAssumeCapacity(.{ .label = .{
        .pos = title_center,
        .text = ImmUI.initLabel("You have survived!"),
        .opt = .{
            .size = title_font.base_size * u.as(u32, ui_scaling + 1),
            .font = title_font,
            .smoothing = .none,
            .color = .white,
            .center = true,
        },
    } });
    curr_row_y += 30 * ui_scaling;

    const btn_dims = v2f(70, 30).scale(ui_scaling);
    const btn_spacing: f32 = 10 * ui_scaling;
    const btns_x = modal_topleft.x + (modal_dims.x - btn_dims.x) * 0.5;
    var curr_btn_pos = v2f(btns_x, curr_row_y);

    if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "New Run", btn_dims, ui_scaling)) {
        try self.reset();
        try self.startRun();
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "Main Menu", btn_dims, ui_scaling)) {
        self.exit_to_menu = true;
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.imm_ui.commands, curr_btn_pos, "Exit", btn_dims, ui_scaling)) {
        plat.exit();
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;
}

pub fn update(self: *Run) Error!void {
    const plat = App.getPlat();

    self.ui_clicked = false;
    self.ui_hovered = false;

    self.imm_ui.commands.clear();
    self.tooltip_ui.commands.clear();

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f3)) {
            try self.reset();
            try self.startRun();
            return;
        }
        if (plat.input_buffer.keyIsJustPressed(.o)) {
            const curr_room_place = self.places.get(self.curr_place_idx).room;
            self.room.took_reward = false;
            self.makeRewards(curr_room_place.difficulty_per_wave * u.as(f32, curr_room_place.waves_params.num_waves));
            if (self.room.reward_chest == null) {
                self.room.spawnRewardChest();
            }
        }
        if (plat.input_buffer.keyIsJustPressed(.l)) {
            self.loadNextPlace();
        }
    }

    switch (self.load_state) {
        .none => {},
        .fade_in => {
            if (self.load_timer.tick(true)) {
                self.load_state = .none;
            }
        },
        .fade_out => {
            if (self.load_timer.tick(true)) {
                self.curr_place_idx += 1;
                if (self.curr_place_idx >= self.places.len) {
                    self.screen = .win;
                    self.load_state = .none;
                } else {
                    try self.loadPlaceFromCurrIdx();
                    self.load_state = .fade_in;
                }
            }
        },
    }

    if (self.room.getPlayer()) |thing| {
        if (self.screen == .room) {
            try self.ui_slots.roomUpdate(&self.imm_ui.commands, &self.tooltip_ui.commands, self, thing);
        } else {
            try self.ui_slots.runUpdate(&self.imm_ui.commands, &self.tooltip_ui.commands, self, thing);
        }
    }

    switch (self.load_state) {
        .none => switch (self.screen) {
            .room => try self.roomUpdate(),
            .reward => try self.rewardUpdate(),
            .shop => try self.shopUpdate(),
            .dead => try self.deadUpdate(),
            .win => try self.winUpdate(),
        },
        .fade_in => {
            self.ui_slots.unselectAction(); // effectively disables UI while fading
        },
        .fade_out => {
            self.ui_slots.unselectAction(); // effectively disables UI while fading
        },
    }

    { // gold
        const scaling = plat.ui_scaling + 1;
        const padding = v2f(5, 5);
        const gold_text = try u.bufPrintLocal("{any}{}", .{ icon_text.Icon.coin, self.gold });
        const rect_dims = icon_text.measureIconText(gold_text).scale(scaling).add(padding.scale(2));
        const topleft = v2f(
            10,
            10,
        );
        self.imm_ui.commands.appendAssumeCapacity(.{ .rect = .{
            .pos = topleft,
            .dims = rect_dims,
            .opt = .{
                .fill_color = Colorf.black.fade(0.7),
            },
        } });
        try icon_text.unqRenderIconText(&self.imm_ui.commands, gold_text, topleft.add(padding), scaling);
    }

    self.curr_tick += 1;

    if (self.exit_to_menu) {
        self.deinit();
        App.get().screen = .menu;
    }
}

pub fn render(self: *Run, ui_render_texture: Platform.RenderTexture2D, game_render_texture: Platform.RenderTexture2D) Error!void {
    const plat = getPlat();

    // clear ui here cos Room may draw something there (debug only tho)
    // all the other UI is rendered here though so could be done after room render
    plat.startRenderToTexture(ui_render_texture);
    plat.clear(.blank);
    plat.endRenderToTexture();

    // room
    if (self.screen == .win) {
        plat.startRenderToTexture(ui_render_texture);
        plat.clear(.black);
        plat.endRenderToTexture();
    } else {
        try self.room.render(ui_render_texture, game_render_texture);
    }

    // ui
    plat.startRenderToTexture(ui_render_texture);
    plat.setBlend(.render_tex_alpha);

    try ImmUI.render(&self.imm_ui.commands);
    try ImmUI.render(&self.tooltip_ui.commands);
    switch (self.load_state) {
        .none => {},
        .fade_in => {
            const color = Colorf.black.fade(1 - self.load_timer.remapTo0_1());
            plat.rectf(.{}, plat.screen_dims_f, .{ .fill_color = color });
        },
        .fade_out => {
            const color = Colorf.black.fade(self.load_timer.remapTo0_1());
            plat.rectf(.{}, plat.screen_dims_f, .{ .fill_color = color });
        },
    }
    plat.endRenderToTexture();
}
