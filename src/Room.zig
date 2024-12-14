const std = @import("std");
const u = @import("util.zig");

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

const Room = @This();
const App = @import("App.zig");
const Log = App.Log;
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const pool = @import("pool.zig");
const TileMap = @import("TileMap.zig");
const Fog = @import("Fog.zig");
const gameUI = @import("gameUI.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const Run = @import("Run.zig");

pub const max_things_in_room = 128;

pub const ThingBoundedArray = std.BoundedArray(pool.Id, max_things_in_room);

pub const InitParams = struct {
    tilemap_idx: u32,
    player: Thing,
    waves_params: WavesParams,
    seed: u64,
    deck: Spell.SpellArray,
    exits: std.BoundedArray(gameUI.ExitDoor, 4),
    run_slots: gameUI.RunSlots,
    mode: Run.Mode,
};

pub const WavesParams = struct {
    const max_max_kinds_per_wave = 4;

    difficulty: f32 = 0,
    first_wave_delay_secs: f32 = 4,
    wave_secs_per_difficulty: f32 = 8,
    difficulty_error: f32 = 1,
    max_kinds_per_wave: usize = 2,
    min_waves: usize = 2,
    max_waves: usize = 4,
    enemy_probabilities: std.EnumArray(Thing.CreatureKind, f32) = std.EnumArray(Thing.CreatureKind, f32).initDefault(0, .{
        .slime = 1,
    }),
    room_kind: Data.RoomKind,
};

pub const Wave = struct {
    const Spawn = struct {
        proto: Thing = undefined,
        pos: V2f,
    };
    total_difficulty: f32 = 0,
    spawns: std.BoundedArray(Spawn, 16) = .{},
};
pub const WavesArray = std.BoundedArray(Wave, 8);

fn makeWaves(tilemap: *const TileMap, rng: std.Random, params: WavesParams, array: *WavesArray) void {
    const data = App.get().data;
    array.clear();
    switch (params.room_kind) {
        .first => {
            if (tilemap.wave_spawns.len > 0) {
                var wave = Wave{};
                wave.spawns.append(.{ .pos = tilemap.wave_spawns.get(0), .proto = data.creature_protos.get(.dummy) }) catch unreachable;
                array.append(wave) catch unreachable;
                return;
            }
        },
        .boss => {
            // TODO?
        },
        else => {},
    }

    var difficulty_left = params.difficulty;
    Log.raw("#############\n", .{});
    Log.info("Making waves! difficulty: {d:.1}", .{params.difficulty});
    const num_waves = rng.intRangeLessThan(usize, params.min_waves, params.max_waves);
    const difficulty_per_wave = params.difficulty / u.as(f32, num_waves);
    const difficulty_error_per_wave = params.difficulty_error / u.as(f32, num_waves);
    Log.info("num_waves: {}, difficulty per wave: {d:.1}", .{ num_waves, difficulty_per_wave });

    var all_spawn_positions = @TypeOf(tilemap.wave_spawns){};
    all_spawn_positions.insertSlice(0, tilemap.wave_spawns.constSlice()) catch unreachable;
    Log.info("  total spawn positions: {}", .{all_spawn_positions.len});

    for (0..num_waves) |i| {
        var difficulty_left_in_wave = difficulty_per_wave;
        var wave = Wave{};
        Log.info(" Wave {}:", .{i});

        var enemy_protos: std.BoundedArray(Thing, WavesParams.max_max_kinds_per_wave) = .{};

        for (0..params.max_kinds_per_wave) |_| {
            const idx = rng.weightedIndex(f32, &params.enemy_probabilities.values);
            const kind: Thing.CreatureKind = @enumFromInt(idx);
            enemy_protos.append(data.creature_protos.get(kind)) catch unreachable;
            Log.info("  possible enemy: {any} : probability: {d:.2}", .{ kind, params.enemy_probabilities.get(kind) });
        }

        rng.shuffleWithIndex(V2f, all_spawn_positions.slice(), u32);
        var curr_spawn_pos_idx: usize = 0;

        while (difficulty_left_in_wave > difficulty_error_per_wave and curr_spawn_pos_idx < all_spawn_positions.len) {
            const idx = rng.uintLessThan(usize, enemy_protos.len);
            const proto = enemy_protos.get(idx);
            wave.total_difficulty += proto.enemy_difficulty;
            difficulty_left_in_wave -= proto.enemy_difficulty;
            wave.spawns.append(.{
                .pos = all_spawn_positions.buffer[curr_spawn_pos_idx],
                .proto = proto,
            }) catch unreachable;
            Log.info("  spawn: {any}", .{proto.creature_kind.?});
            curr_spawn_pos_idx += 1;
        }

        Log.info("  = wave difficulty: {d:.2}", .{wave.total_difficulty});
        difficulty_left -= wave.total_difficulty;
        array.append(wave) catch unreachable;
        if (difficulty_left < params.difficulty_error) break;
    }

    Log.info("#############\n", .{});
}

camera: draw.Camera2D = .{},
things: Thing.Pool = undefined,
spawn_queue: ThingBoundedArray = .{},
free_queue: ThingBoundedArray = .{},
player_id: ?pool.Id = null,
ui_slots: gameUI.Slots = .{},
draw_pile: Spell.SpellArray = .{},
discard_pile: Spell.SpellArray = .{},
mislay_pile: Spell.SpellArray = .{},
fog: Fog = undefined,
curr_tick: i64 = 0,
paused: bool = false,
advance_one_frame: bool = false, // if true, pause on next frame
waves: WavesArray = .{},
wave_timer: u.TickCounter = undefined,
curr_wave: i32 = 0,
num_enemies_alive: i32 = 0,
progress_state: union(enum) {
    none,
    lost,
    won,
    exited: gameUI.ExitDoor,
} = .none,
took_reward: bool = false,
// reinit stuff, never needs saving or copying, probably?:
moused_over_thing: ?struct {
    thing: Thing.Id,
    faction_mask: Thing.Faction.Mask,
} = null,
edit_mode: bool = false,
ui_clicked: bool = false,
ui_hovered: bool = false,
next_pool_id: u32 = 0, // i hate this, can we change it?
highest_num_things: usize = 0,
rng: std.Random.DefaultPrng = undefined,
// fields to save/load for level loading
//  - spawns, tiles, zones
//  - gets 'append'ed to a file
//  - this could just be a string or idx for lookup in data.rooms or something, or data.load_room() with a cache behind it, or...
//  - could just store its own whole-ass prototype to reinit from
// so this may as well be a different data structure than "Room"
// oh except, the tiles, (like, it IS used at runtime) ya know... so... no it should be just in Room
//
tilemap: TileMap = .{},
init_params: InitParams,

pub fn init(self: *Room, params: *const InitParams) Error!void {
    self.* = .{
        .next_pool_id = 0,
        .fog = try Fog.init(),
        .init_params = params.*,
    };

    // everything is done except spawning stuff
    try self.reset();
}

pub fn deinit(self: *Room) void {
    self.fog.deinit();
}

fn clearThings(self: *Room) void {
    self.things.init(self.next_pool_id);
    self.next_pool_id += 1;
    self.spawn_queue.len = 0;
    self.free_queue.len = 0;
    self.player_id = null;
    self.ui_slots = .{};
    self.draw_pile = .{};
    self.discard_pile = .{};
    self.mislay_pile = .{};
}

pub fn reset(self: *Room) Error!void {
    const plat = getPlat();
    const data = App.get().data;
    self.clearThings();
    self.fog.clearAll();
    self.camera = .{
        .offset = plat.game_canvas_dims_f.scale(0.5),
        .zoom = plat.game_zoom_levels,
    };
    self.curr_tick = 0;
    self.rng = std.Random.DefaultPrng.init(self.init_params.seed);
    self.wave_timer = u.TickCounter.init(core.secsToTicks(self.init_params.waves_params.first_wave_delay_secs));
    self.curr_wave = 0;
    self.num_enemies_alive = 0;
    self.progress_state = .none;
    self.paused = false;
    self.draw_pile = self.init_params.deck;
    const tilemap = &data.tilemaps.items[self.init_params.tilemap_idx];
    self.tilemap = tilemap.*;

    makeWaves(tilemap, self.rng.random(), self.init_params.waves_params, &self.waves);

    for (tilemap.creatures.constSlice()) |spawn| {
        Log.info("Room init: spawning a {any}", .{spawn.kind});
        if (spawn.kind == .player) {
            self.player_id = try self.queueSpawnThing(&self.init_params.player, spawn.pos);
        } else {
            _ = try self.queueSpawnCreatureByKind(spawn.kind, spawn.pos);
        }
    }

    self.ui_slots.init(self, self.init_params.run_slots);
}

pub fn clone(self: *const Room, out: *Room) Error!void {
    out.* = self.*;
    out.fog = try self.fog.clone();
}

pub fn reloadFromTileMap(self: *Room, tilemap_idx: u32) Error!void {
    self.init_params.tilemap_idx = tilemap_idx;
    try self.reset();
}

pub fn resolutionChanged(self: *Room) void {
    const plat = getPlat();
    self.camera.offset = plat.game_canvas_dims_f.scale(0.5);
    self.camera.zoom = plat.game_zoom_levels;
    self.fog.resolutionChanged();
    self.ui_slots.reflowRects();
}

pub fn queueSpawnThing(self: *Room, proto: *const Thing, pos: V2f) Error!?pool.Id {
    const t = self.things.alloc();
    self.highest_num_things = @max(self.things.num_allocated, self.highest_num_things);
    if (t) |thing| {
        try proto.copyTo(thing);
        thing.spawn_state = .spawning;
        thing.pos = pos;
        try self.spawn_queue.append(thing.id);
        if (thing.isEnemy()) self.num_enemies_alive += 1;
        return thing.id;
    } else {
        Log.warn(
            "################# Failed to allocate Thing! {} / {} Things allocated",
            .{ self.things.num_allocated, max_things_in_room },
        );
    }
    return null;
}

pub fn queueSpawnCreatureByKind(self: *Room, kind: Thing.CreatureKind, pos: V2f) Error!?pool.Id {
    const app = App.get();
    const proto = app.data.creature_protos.getPtr(kind);
    return self.queueSpawnThing(proto, pos);
}

pub fn getThingById(self: *Room, id: pool.Id) ?*Thing {
    return self.things.get(id);
}

pub fn getConstThingById(self: *const Room, id: pool.Id) ?*const Thing {
    return self.things.getConst(id);
}

pub fn getThingByPos(self: *Room, pos: V2f) ?*Thing {
    for (&self.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (pos.dist(thing.pos) < thing.coll_radius) {
            return thing;
        }
    }
    return null;
}

pub fn getPlayer(self: *Room) ?*Thing {
    if (self.player_id) |id| {
        return self.getThingById(id);
    }
    return null;
}

pub fn getConstPlayer(self: *const Room) ?*const Thing {
    if (self.player_id) |id| {
        return self.getConstThingById(id);
    }
    return null;
}

pub fn drawSpell(self: *Room) ?Spell {
    if (self.draw_pile.len > 0) {
        const last = u.as(u32, self.draw_pile.len - 1);
        const idx = u.as(usize, self.rng.random().intRangeAtMost(u32, 0, last));
        const spell = self.draw_pile.swapRemove(idx);
        return spell;
    } else {
        self.draw_pile.insertSlice(0, self.discard_pile.constSlice()) catch unreachable;
        self.discard_pile.len = 0;
    }
    return null;
}

pub fn discardSpell(self: *Room, spell: Spell) void {
    self.discard_pile.append(spell) catch @panic("discard pile ran out of space");
}

pub fn mislaySpell(self: *Room, spell: Spell) void {
    self.mislay_pile.append(spell) catch @panic("mislay pile ran out of space");
}

pub fn spawnCurrWave(self: *Room) Error!void {
    assert(self.curr_wave < self.waves.len);
    const wave = self.waves.get(u.as(usize, self.curr_wave));
    const wave_delay_secs = self.init_params.waves_params.wave_secs_per_difficulty * wave.total_difficulty;
    Log.info("Spawning wave {}, next wave in {d:.1} secs", .{ self.curr_wave, wave_delay_secs });
    self.wave_timer = u.TickCounter.init(core.secsToTicks(wave_delay_secs));
    for (wave.spawns.constSlice()) |spawn| {
        const spawner_proto = Thing.SpawnerController.prototype(spawn.proto.creature_kind.?);
        _ = try self.queueSpawnThing(&spawner_proto, spawn.pos);
    }
    self.curr_wave += 1;
}

pub fn getMousedOverThing(self: *Room, faction_mask: Thing.Faction.Mask) ?*Thing {
    const plat = getPlat();
    //cached
    if (self.moused_over_thing) |s| {
        if (s.faction_mask.eql(faction_mask)) return self.getThingById(s.thing);
    }
    const mouse_pos = plat.getMousePosWorld(self.camera);
    var best_thing: ?*Thing = null;
    var best_y = -std.math.inf(f32);
    for (&self.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (thing.selectable == null) continue;
        if (!faction_mask.contains(thing.faction)) continue;
        if (best_thing != null and thing.pos.y < best_y) continue;

        const selectable = thing.selectable.?;
        const rect = geom.Rectf{
            .pos = thing.pos.sub(v2f(selectable.radius, selectable.height)),
            .dims = v2f(selectable.radius * 2, selectable.height),
        };
        //const top_circle_pos = thing.pos.sub(v2f(0, selectable.height));

        if (mouse_pos.dist(thing.pos) < selectable.radius or
            geom.pointIsInRectf(mouse_pos, rect)) //or
            //mouse_pos.dist(top_circle_pos) < selectable.radius)
        {
            best_y = thing.pos.y;
            best_thing = thing;
        }
    }
    if (best_thing) |thing| {
        self.moused_over_thing = .{
            .thing = thing.id,
            .faction_mask = faction_mask,
        };
        return thing;
    }
    return null;
}

pub fn update(self: *Room) Error!void {
    const plat = getPlat();
    self.ui_clicked = false;
    self.ui_hovered = false;
    self.moused_over_thing = null;

    if (self.advance_one_frame) {
        self.paused = true;
        self.advance_one_frame = false;
    }

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.backtick)) {
            self.edit_mode = !self.edit_mode;
        }
        if (plat.input_buffer.keyIsJustPressed(.k)) {
            for (&self.things.items) |*thing| {
                if (!thing.isActive()) continue;
                if (!thing.isEnemy()) continue;
                thing.deferFree(self);
            }
        }
        if (self.paused) {
            if (plat.input_buffer.keyIsJustPressed(.period)) {
                self.paused = false;
                self.advance_one_frame = true;
            }
        }
        if (self.edit_mode) {
            if (plat.input_buffer.mouseBtnIsJustPressed(.left)) {
                const pos = plat.getMousePosWorld(self.camera);
                _ = try self.queueSpawnCreatureByKind(.troll, pos);
            }
        }
    }
    for (self.spawn_queue.constSlice()) |id| {
        const t = self.getThingById(id);
        assert(t != null);
        const thing = t.?;
        assert(thing.alloc_state == .allocated);
        assert(thing.spawn_state == .spawning);
        thing.spawn_state = .spawned;
        if (thing.player_input) |*input| {
            input.actions.initRoom(self);
        }
    }
    self.spawn_queue.len = 0;

    // update spell slots, and player input
    {
        if (self.getPlayer()) |player| {
            try @TypeOf(player.player_input.?).update(player, self);
        }
    }

    if (!self.edit_mode and !self.paused) {
        // waves spawning
        if (self.curr_wave < self.waves.len) {
            if (self.wave_timer.tick(false) or (self.curr_wave > 0 and self.num_enemies_alive == 0)) {
                try self.spawnCurrWave();
            }
        }
        // check if won or lost
        if (self.getPlayer()) |player| {
            assert(player.hp != null);
            const hp = player.hp.?;
            switch (self.progress_state) {
                .none => {
                    const defeated_all_enemies = self.curr_wave >= self.waves.len and self.num_enemies_alive == 0;
                    if (hp.curr <= 0) {
                        // .lost is set below, after player is freed
                    } else if (defeated_all_enemies or self.init_params.waves_params.room_kind == .first) {
                        self.progress_state = .won;
                    }
                },
                .won => {
                    for (self.init_params.exits.slice()) |*exit| {
                        if (try exit.updateSelected(self)) {
                            self.progress_state = .{ .exited = exit.* };
                        }
                    }
                },
                .exited => {},
                else => {
                    // TODO .lost ? rn is set below when player is freed
                },
            }
        } else {
            self.progress_state = .lost;
        }
        // things
        for (&self.things.items) |*thing| {
            if (!thing.isActive()) continue;
            try thing.update(self);
        }
        // fog and camera
        self.fog.clearVisible();
        if (self.getPlayer()) |player| {
            //self.camera.pos = self.camera.pos.add(player.pos.sub(self.camera.pos).scale(0.1));
            self.camera.pos = player.pos;
            try self.fog.addVisibleCircle(
                self.tilemap.getRoomRect(),
                player.pos,
                player.vision_range + player.coll_radius,
            );
            if (false) { // test triangle in fog map
                const points = [_]V2f{
                    player.pos.add(v2f(200, 200)),
                    player.pos.add(v2f(-200, 200)),
                    player.pos.add(v2f(0, -300)),
                };
                try self.fog.addVisiblePoly(self.tilemap.getRoomRect(), &points);
            }
        }
    }
    const wheel = plat.mouseWheelY();
    if (wheel > 0) {
        self.camera.zoom = @min(self.camera.zoom + 1, plat.game_zoom_levels);
    } else if (wheel < 0) {
        self.camera.zoom = @max(self.camera.zoom - 1, 1);
    }

    for (self.free_queue.constSlice()) |id| {
        const t = self.getThingById(id);
        assert(t != null);
        const thing = t.?;
        assert(thing.alloc_state == .allocated);
        assert(thing.spawn_state == .freeable);
        self.things.free(id);
        if (thing.isEnemy()) self.num_enemies_alive -= 1;
    }
    self.free_queue.len = 0;

    // TODO might mess up edit modeu
    if (!self.edit_mode) {
        self.curr_tick += 1;
    }
}

pub fn render(self: *const Room, ui_render_texture: Platform.RenderTexture2D, game_render_texture: Platform.RenderTexture2D) Error!void {
    const plat = getPlat();

    const fog_enabled = !self.edit_mode;
    if (fog_enabled) {
        try self.fog.renderToTexture(self.camera);
    }

    plat.startRenderToTexture(game_render_texture);
    plat.setBlend(.render_tex_alpha);
    plat.clear(.black);

    plat.startCamera2D(self.camera, .{ .round_to_pixel = true });
    try self.tilemap.renderUnderObjects();
    // exit
    for (self.init_params.exits.constSlice()) |exit| {
        try exit.render(self);
    }

    // waves
    if (debug.show_waves) {
        for (self.waves.constSlice(), 0..) |wave, i| {
            for (wave.spawns.constSlice()) |spawn| {
                try plat.textf(spawn.pos, "{}", .{i}, .{ .center = true, .color = .magenta });
            }
        }
    }

    // spell targeting, movement
    if (!self.edit_mode) {
        if (self.getConstPlayer()) |player| {
            try @TypeOf(player.player_input.?).render(player, self);
        }
    }

    {
        var thing_arr = std.BoundedArray(*const Thing, @TypeOf(self.things).max_len){};
        const player = self.getConstPlayer();
        for (&self.things.items) |*thing| {
            if (!thing.isActive()) continue;
            if (fog_enabled) {
                if (player) |p| {
                    if (thing.pos.dist(p.pos) > p.vision_range + p.coll_radius + thing.coll_radius) {
                        continue;
                    }
                } else {
                    // no player? cant see anything
                    continue;
                }
            }
            thing_arr.append(thing) catch unreachable;
        }

        const SortStruct = struct {
            pub fn lessThan(_: void, lhs: *const Thing, rhs: *const Thing) bool {
                return lhs.pos.y < rhs.pos.y;
            }
        };
        std.sort.pdq(*const Thing, thing_arr.slice(), {}, SortStruct.lessThan);
        for (thing_arr.constSlice()) |thing| {
            try thing.renderUnder(self);
        }
        for (thing_arr.constSlice()) |thing| {
            if (thing.player_input != null) {
                plat.endCamera2D();
                plat.startCamera2D(self.camera, .{ .round_to_pixel = false });
                try thing.render(self);
                plat.endCamera2D();
                plat.startCamera2D(self.camera, .{ .round_to_pixel = true });
            } else {
                try thing.render(self);
            }
        }

        try self.tilemap.renderOverObjects(self.camera, thing_arr.constSlice());
        for (thing_arr.constSlice()) |thing| {
            try thing.renderOver(self);
        }
        for (self.init_params.exits.constSlice()) |exit| {
            try exit.renderOver(self);
        }
    }

    if (debug.show_tilemap_grid) {
        self.tilemap.debugDraw(self.camera);
    }
    // show LOS raycast
    if (false) {
        if (self.getConstPlayer()) |player| {
            const mouse_pos = plat.getMousePosWorld(self.camera);
            plat.linef(player.pos, mouse_pos, .{ .thickness = 1, .color = .red });
            if (self.tilemap.raycastLOS(player.pos, mouse_pos)) |tile_coord| {
                const rect = TileMap.tileCoordToRect(tile_coord);
                plat.rectf(rect.pos, rect.dims, .{ .fill_color = Colorf.red.fade(0.4) });
            }
        }
    }
    plat.endCamera2D();

    if (fog_enabled) {
        const fog_texture_opt = draw.TextureOpt{
            .flip_y = true,
        };
        plat.setBlend(.multiply);
        //plat.setShader(App.get().data.shaders.get(.fog_blur));
        plat.texturef(.{}, self.fog.render_tex.texture, fog_texture_opt);
        //plat.setDefaultShader();
        plat.setBlend(.render_tex_alpha);
    }

    if (debug.show_game_canvas_size) {
        plat.rectf(.{}, plat.game_canvas_dims_f, .{
            .fill_color = null,
            .outline = .{
                .color = .red,
                .thickness = 4,
            },
        });
    }
    plat.endRenderToTexture();

    // ui ?
    plat.startRenderToTexture(ui_render_texture);
    // edit mode msg
    if (self.edit_mode) {
        const text_opt: draw.TextOpt = .{ .center = true, .size = 30, .color = .white };
        const txt = "edit mode";
        const dims = (try plat.measureText(txt, text_opt)).add(v2f(10, 4));
        const p: V2f = v2f(plat.screen_dims_f.x * 0.5, plat.screen_dims_f.y - 35);
        plat.rectf(p.sub(dims.scale(0.5)), dims, .{ .fill_color = Colorf.black.fade(0.5) });
        try plat.textf(p, "{s}", .{txt}, text_opt);
    }
    if (debug.show_num_enemies) {
        try plat.textf(v2f(10, 10), "num_enemies_alive: {}", .{self.num_enemies_alive}, .{ .color = .white });
    }
    if (debug.show_highest_num_things_in_room) {
        try plat.textf(v2f(10, 30), "highest_num_things: {} / {}", .{ self.highest_num_things, max_things_in_room }, .{ .color = .white });
    }
    plat.endRenderToTexture();
}
