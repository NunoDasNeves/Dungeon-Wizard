const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const debug = @import("debug.zig");
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
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Data = @import("Data.zig");
const TileMap = @This();

pub const max_map_sz: i64 = 64;
pub const max_map_sz_f: f32 = max_map_sz;
pub const max_map_tiles: i64 = max_map_sz * max_map_sz;
pub const max_map_layers = 8;
pub const max_map_tilesets = 16;
pub const max_map_exits = 4;
pub const max_map_spawns = 32;
pub const max_map_creatures = 32;

pub const tile_sz: i64 = 64;
pub const tile_sz_f: f32 = tile_sz;
pub const tile_dims = V2f.splat(tile_sz);
pub const tile_dims_2 = V2f.splat(tile_sz_f * 0.5);

pub const NeighborDir = enum {
    N,
    E,
    S,
    W,
};
pub const neighbor_dirs: [4]NeighborDir = .{ .N, .E, .S, .W };
pub const neighbor_dirs_coords = std.EnumArray(NeighborDir, V2i).init(.{
    .N = v2i(0, -1),
    .E = v2i(1, 0),
    .S = v2i(0, 1),
    .W = v2i(-1, 0),
});

pub const Tile = struct {
    coord: V2i,
    passable: bool = true,
};

pub const GameTile = struct {
    coord: V2i,
    passable: bool = true,
};

pub const TileIndex = u32;
pub const TileLayer = struct {
    pub const Tile = struct {
        idx: u32 = undefined,
    };
    above_objects: bool = false,
    tiles: std.BoundedArray(TileLayer.Tile, max_map_tiles) = .{},
};
pub const TileSetReference = struct {
    name: Data.TileSet.NameBuf,
    data_idx: usize = 0,
    first_gid: usize = 1,
};

pub const NameBuf = utl.BoundedString(64);

name: NameBuf = .{},
kind: Data.RoomKind = .testu,
id: i32 = 0,
game_tiles: std.BoundedArray(GameTile, max_map_tiles) = .{},
tile_layers: std.BoundedArray(TileLayer, max_map_layers) = .{},
tilesets: std.BoundedArray(TileSetReference, max_map_tilesets) = .{},
creatures: std.BoundedArray(struct { kind: Thing.CreatureKind, pos: V2f }, max_map_creatures) = .{},
exits: std.BoundedArray(V2f, max_map_exits) = .{},
wave_spawns: std.BoundedArray(V2f, max_map_spawns) = .{},
dims_tiles: V2i = .{},
dims_game: V2i = .{},
rect_dims: V2f = .{},

pub fn tileIdxToTileSetRef(self: *const TileMap, tile_idx: usize) ?TileSetReference {
    if (tile_idx == 0) return null;
    assert(self.tilesets.len > 0);

    var tileset_ref = self.tilesets.get(self.tilesets.len - 1);
    for (0..self.tilesets.len - 1) |i| {
        const curr_ts_ref = self.tilesets.get(i);
        const next_ts_ref = self.tilesets.get(i + 1);
        if (tile_idx >= curr_ts_ref.first_gid and tile_idx < next_ts_ref.first_gid) {
            tileset_ref = curr_ts_ref;
            break;
        }
    }
    return tileset_ref;
}

pub fn tileCoordToGameTile(self: *TileMap, tile_coord: V2i) ?*GameTile {
    const idxi = tile_coord.x + tile_coord.y * self.dims_tiles.x;
    if (idxi < 0) return null;
    const idx = utl.as(usize, idxi);
    if (idx >= self.game_tiles.len) return null;
    const gt = &self.game_tiles.buffer[idx];
    // TODO ? change?
    if (!gt.coord.eql(tile_coord)) return null;
    return gt;
}

fn gameTileCoordToIdx(self: *const TileMap, gt_coord: V2i) ?usize {
    if (gt_coord.x < 0 or gt_coord.y < 0) return null;
    if (gt_coord.x >= self.dims_game.x or gt_coord.y >= self.dims_game.y) return null;
    const idxi = gt_coord.x + gt_coord.y * self.dims_game.x;
    if (idxi < 0) return null;
    const idx = utl.as(usize, idxi);
    if (idx >= self.game_tiles.len) return null;
    return idx;
}

pub fn gameTileCoordToGameTile(self: *TileMap, gt_coord: V2i) ?*GameTile {
    if (self.gameTileCoordToIdx(gt_coord)) |idx| {
        const gt = &self.game_tiles.buffer[idx];
        assert(gt.coord.eql(gt_coord));
        return gt;
    }
    return null;
}

pub fn gameTileCoordToConstGameTile(self: *const TileMap, gt_coord: V2i) ?*const GameTile {
    return @constCast(self).gameTileCoordToGameTile(gt_coord);
}

pub fn posToTileCoord(pos: V2f) V2i {
    return .{
        .x = utl.as(i32, @floor(pos.x / tile_sz_f)),
        .y = utl.as(i32, @floor(pos.y / tile_sz_f)),
    };
}

pub fn tileCoordToPos(coord: V2i) V2f {
    return coord.scale(tile_sz).toV2f();
}

pub fn tileCoordToCenterPos(coord: V2i) V2f {
    return tileCoordToPos(coord).add(tile_dims_2);
}

pub fn posToTileTopLeft(pos: V2f) V2f {
    return tileCoordToPos(posToTileCoord(pos));
}

pub fn tileTopLeftToCornersCW(topleft: V2f) [4]V2f {
    return .{
        topleft,
        topleft.add(v2f(tile_sz_f, 0)),
        topleft.add(tile_dims),
        topleft.add(v2f(0, tile_sz_f)),
    };
}

pub fn tileCoordToRect(coord: V2i) geom.Rectf {
    return .{
        .pos = tileCoordToPos(coord),
        .dims = tile_dims,
    };
}

pub fn getTileNeighborsPassable(self: *const TileMap, coord: V2i) std.EnumArray(NeighborDir, bool) {
    var ret: std.EnumArray(NeighborDir, bool) = undefined;
    for (neighbor_dirs) |nd| {
        const neighbor_coord = coord.add(neighbor_dirs_coords.get(nd));
        const tile = self.gameTileCoordToConstGameTile(neighbor_coord);
        const passable = if (tile) |t| t.passable else true;
        ret.set(nd, passable);
    }
    return ret;
}

pub fn findPathAStar(self: *const TileMap, allocator: std.mem.Allocator, start: V2f, goal: V2f) Error!std.BoundedArray(V2f, 32) {
    const AStar = struct {
        const PqEl = struct {
            p: V2i,
            g: f32,
            f: f32,
            fn lessThan(ctx: void, a: PqEl, b: PqEl) std.math.Order {
                _ = ctx;
                return std.math.order(a.f, b.f);
            }
        };
        const SeenEntry = struct {
            visited: bool,
            prev: V2i,
            best_g: f32,
        };
    };
    const start_coord = posToTileCoord(start);
    const goal_coord = posToTileCoord(goal);
    var path_arr = std.ArrayList(V2f).init(allocator);
    defer path_arr.deinit();
    var queue = std.PriorityQueue(AStar.PqEl, void, AStar.PqEl.lessThan).init(allocator, {});
    defer queue.deinit();
    var seen = std.AutoArrayHashMap(V2i, AStar.SeenEntry).init(allocator);
    defer seen.deinit();

    try queue.add(.{
        .p = start_coord,
        .g = 0,
        .f = start.sub(goal).length(),
    });
    try seen.put(
        start_coord,
        .{
            .visited = false,
            .prev = undefined,
            .best_g = 0,
        },
    );

    while (queue.items.len > 0) {
        const curr = queue.remove();

        seen.getPtr(curr.p).?.visited = true;

        if (curr.p.eql(goal_coord)) {
            break;
        }
        for (neighbor_dirs) |dir| {
            const dir_v = neighbor_dirs_coords.get(dir);
            const this_move_cost = tile_sz_f;
            const next_g = curr.g + this_move_cost;
            const next_p = tileCoordToCenterPos(curr.p.add(dir_v));
            const next = AStar.PqEl{
                .p = posToTileCoord(next_p),
                .g = next_g,
                .f = next_g + next_p.sub(goal).length(),
            };
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });
            if (self.gameTileCoordToGameTile(posToTileCoord(next_p))) |tile| {
                if (!tile.passable) continue;
            }
            const entry = try seen.getOrPut(next.p);
            if (entry.found_existing) {
                if (entry.value_ptr.visited) continue;

                if (next.g < entry.value_ptr.best_g) {
                    entry.value_ptr.best_g = next.g;
                    entry.value_ptr.prev = curr.p;
                }
            } else {
                entry.value_ptr.* = .{
                    .visited = false,
                    .prev = curr.p,
                    .best_g = next.g,
                };
            }

            try queue.add(next);
        }
    }
    // backtrack to get path
    {
        var curr = goal_coord;
        while (!curr.eql(start_coord)) {
            try path_arr.append(tileCoordToCenterPos(curr));
            curr = seen.get(curr).?.prev;
        }
        try path_arr.append(start);
        path_arr.items[0] = goal;
    }
    std.mem.reverse(V2f, path_arr.items);

    var ret = std.BoundedArray(V2f, 32){};
    const ret_path_len = @min(ret.buffer.len, path_arr.items.len);

    for (0..ret_path_len) |i| {
        ret.append(path_arr.items[i]) catch unreachable;
    }

    return ret;
}

pub fn tileCoordIsPassable(self: *const TileMap, coord: V2i) bool {
    if (self.gameTileCoordToConstGameTile(coord)) |tile| {
        return tile.passable;
    }
    return true;
}

pub fn isLOSBetweenThicc(self: *const TileMap, a: V2f, b: V2f, thickness: f32) bool {
    const a_to_b = a.sub(b);
    const n = a_to_b.rot90CW().normalizedOrZero();
    if (n.isZero()) {
        return self.isLOSBetween(a, b);
    }
    const offset = n.scale(thickness * 0.5);
    const a_right = a.add(offset);
    const b_right = b.add(offset);
    const a_left = a.sub(offset);
    const b_left = b.sub(offset);
    return self.isLOSBetween(a_right, b_right) and self.isLOSBetween(a_left, b_left);
}

pub fn raycastLOS(self: *const TileMap, _a: V2f, _b: V2f) ?V2i {
    const a_coord = posToTileCoord(_a);
    const b_coord = posToTileCoord(_b);
    const a = _a.scale(1 / tile_sz_f);
    const b = _b.scale(1 / tile_sz_f);
    const dx: f32 = @abs(b.x - a.x);
    const dy: f32 = @abs(b.y - a.y);

    var sx: i32 = undefined;
    var sy: i32 = undefined;
    var err: f32 = dx + dy;

    if (dx < 0.001) {
        sx = 0;
        err = std.math.inf(f32);
    } else if (a.x < b.x) {
        sx = 1;
        err = (@floor(a.x) + 1 - a.x) * dy;
    } else {
        sx = -1;
        err = (a.x - @floor(a.x)) * dy;
    }
    if (dy < 0.001) {
        sy = 0;
        err = -std.math.inf(f32);
    } else if (a.y < b.y) {
        sy = 1;
        err -= (@floor(a.y) + 1 - a.y) * dx;
    } else {
        sy = -1;
        err -= (a.y - @floor(a.y)) * dx;
    }

    var curr: V2i = a_coord;
    //std.debug.print("a_coord: {}, {}\n", .{ curr.x, curr.y });
    //std.debug.print("b_coord: {}, {}\n", .{ b_coord.x, b_coord.y });
    //std.debug.print("s: {}, {}\n", .{ sx, sy });
    //std.debug.print("d: {}, {}\n", .{ dx, dy });
    while (true) {
        //std.debug.print("curr: {}, {}\n", .{ curr.x, curr.y });
        if (!self.tileCoordIsPassable(curr)) return curr;
        if (curr.eql(b_coord)) break;
        //std.debug.print("e: {}\n", .{err});

        if (err > 0) {
            curr.y += sy;
            err -= dx;
        } else {
            curr.x += sx;
            err += dy;
        }
    }
    //std.debug.print("\n", .{});
    return null;
}

pub fn isLOSBetween(self: *const TileMap, _a: V2f, _b: V2f) bool {
    return self.raycastLOS(_a, _b) == null;
}

pub fn findPathThetaStar(self: *const TileMap, allocator: std.mem.Allocator, start: V2f, goal: V2f, radius: f32, coords_searched: *std.BoundedArray(V2i, 128)) Error!std.BoundedArray(V2f, 32) {
    const ThetaStar = struct {
        const PqEl = struct {
            p: V2i,
            g: f32,
            f: f32,
            fn lessThan(ctx: void, a: PqEl, b: PqEl) std.math.Order {
                _ = ctx;
                return std.math.order(a.f, b.f);
            }
        };
        const SeenEntry = struct {
            visited: bool,
            prev: ?V2i,
            best_g: f32,
        };
    };
    const start_coord = posToTileCoord(start);
    const goal_coord = posToTileCoord(goal);

    if (self.gameTileCoordToConstGameTile(goal_coord)) |goal_tile| {
        if (!goal_tile.passable) {
            return .{};
        }
    }
    var path_arr = std.ArrayList(V2f).init(allocator);
    defer path_arr.deinit();
    var queue = std.PriorityQueue(ThetaStar.PqEl, void, ThetaStar.PqEl.lessThan).init(allocator, {});
    defer queue.deinit();
    var seen = std.AutoArrayHashMap(V2i, ThetaStar.SeenEntry).init(allocator);
    defer seen.deinit();

    try queue.add(.{
        .p = start_coord,
        .g = 0,
        .f = start.sub(goal).length(),
    });
    try seen.put(
        start_coord,
        .{
            .visited = false,
            .prev = null,
            .best_g = 0,
        },
    );
    coords_searched.len = 0;

    while (queue.items.len > 0) {
        const curr = queue.remove();
        const curr_seen = seen.getPtr(curr.p).?;
        if (curr_seen.visited) continue;
        curr_seen.visited = true;
        coords_searched.append(curr.p) catch {};

        if (curr.p.eql(goal_coord)) {
            break;
        }
        const parent_stuff: ?struct {
            coord: V2i,
            pos: V2f,
            seen: ThetaStar.SeenEntry,
        } = if (curr_seen.prev) |parent_coord| .{
            .coord = parent_coord,
            .pos = if (parent_coord.eql(start_coord)) start else tileCoordToCenterPos(parent_coord),
            .seen = seen.get(parent_coord).?,
        } else null;

        for (neighbor_dirs) |dir| {
            const dir_v = neighbor_dirs_coords.get(dir);
            const next_coord = curr.p.add(dir_v);
            if (!self.tileCoordIsPassable(next_coord)) continue;
            const entry = try seen.getOrPut(next_coord);
            if (entry.found_existing and entry.value_ptr.visited) continue;
            const next_pos = if (next_coord.eql(goal_coord)) goal else tileCoordToCenterPos(next_coord);

            var this_move_cost = tile_sz_f;
            var prev = curr.p;
            var prev_g = curr.g;
            if (parent_stuff) |parent| {
                const parent_to_next = next_pos.sub(parent.pos);
                const n = parent_to_next.rot90CW().normalized();
                const offset = n.scale(radius);
                const a_right = parent.pos.add(offset);
                const b_right = next_pos.add(offset);
                const a_left = parent.pos.sub(offset);
                const b_left = next_pos.sub(offset);
                if (self.isLOSBetween(a_right, b_right) and self.isLOSBetween(a_left, b_left)) {
                    this_move_cost = parent_to_next.length();
                    prev = parent.coord;
                    prev_g = parent.seen.best_g;
                }
            }
            const next_g = prev_g + this_move_cost;
            const next = ThetaStar.PqEl{
                .p = next_coord,
                .g = next_g,
                .f = next_g + next_pos.sub(goal).length(),
            };
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });

            if (entry.found_existing) {
                if (next.g < entry.value_ptr.best_g) {
                    entry.value_ptr.best_g = next.g;
                    entry.value_ptr.prev = prev;
                    try queue.add(next);
                }
            } else {
                entry.value_ptr.* = .{
                    .visited = false,
                    .prev = prev,
                    .best_g = next.g,
                };
                try queue.add(next);
            }
        }
    }
    // backtrack to get path
    var ret = std.BoundedArray(V2f, 32){};
    if (seen.get(goal_coord) == null) {
        return ret;
    }
    if (start_coord.eql(goal_coord)) {
        ret.append(start) catch unreachable;
        ret.append(goal) catch unreachable;
        return ret;
    }
    {
        var curr = goal_coord;
        while (!curr.eql(start_coord)) {
            try path_arr.append(tileCoordToCenterPos(curr));
            curr = seen.get(curr).?.prev.?;
        }
        try path_arr.append(start);
        path_arr.items[0] = goal;
    }
    std.mem.reverse(V2f, path_arr.items);

    const ret_path_len = @min(ret.buffer.len, path_arr.items.len);

    for (0..ret_path_len) |i| {
        ret.append(path_arr.items[i]) catch unreachable;
    }

    return ret;
}

pub fn debugDrawPath(_: *const TileMap, camera: draw.Camera2D, path: []const V2i) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / camera.zoom;
    const line_thickness = inv_zoom;
    for (0..path.len - 1) |i| {
        const p0 = tileCoordToCenterPos(path[i]);
        const p1 = tileCoordToCenterPos(path[i + 1]);
        plat.linef(p0, p1, .{ .thickness = line_thickness, .color = Colorf.green });
    }
}

pub fn debugDrawGrid(_: *const TileMap, camera: draw.Camera2D) void {
    const plat = getPlat();
    const inv_zoom = 1 / camera.zoom;
    const camera_dims = core.native_dims_f.scale(inv_zoom);
    const line_thickness = inv_zoom;
    // add 2 to grid dims to make sure it covers the screen
    const grid_dims = camera_dims.scale(1 / tile_sz_f).toV2i().add(v2i(2, 2));
    const grid_cols = utl.as(usize, grid_dims.x);
    const grid_rows = utl.as(usize, grid_dims.y);
    // go a tile beyond to make sure grid covers screen
    const grid_topleft = posToTileTopLeft(camera.pos.sub(camera_dims.scale(0.5).add(tile_dims)));
    // exact bottom right by rescaling grid_dims with tile size
    const grid_botright = grid_topleft.add(grid_dims.toV2f().scale(tile_sz_f));

    for (0..grid_cols) |col| {
        const x: f32 = grid_topleft.x + utl.as(f32, col) * tile_sz;
        plat.linef(v2f(x, grid_topleft.y), v2f(x, grid_botright.y), .{ .thickness = line_thickness, .color = Colorf.green.fade(0.5) });
    }
    for (0..grid_rows) |row| {
        const y: f32 = grid_topleft.y + utl.as(f32, row) * tile_sz;
        plat.linef(v2f(grid_topleft.x, y), v2f(grid_botright.x, y), .{ .thickness = line_thickness, .color = Colorf.green.fade(0.5) });
    }
}

pub fn debugDraw(self: *const TileMap, camera: draw.Camera2D) void {
    const plat = getPlat();
    for (self.game_tiles.constSlice()) |game_tile| {
        const color = if (game_tile.passable) continue else Colorf.red.fade(0.3);
        plat.rectf(tileCoordToPos(game_tile.coord), tile_dims, .{ .fill_color = color });
    }
    self.debugDrawGrid(camera);
}

pub fn getRoomRect(self: *const TileMap) geom.Rectf {
    //const topleft_coord = v2i(
    //    -@divFloor(self.dims_tiles.x, 2),
    //    -@divFloor(self.dims_tiles.y, 2),
    //);
    const topleft_coord: V2i = .{};
    const topleft_pos = tileCoordToPos(topleft_coord).sub(tile_dims_2);
    return .{
        .pos = topleft_pos,
        .dims = self.rect_dims,
    };
}

fn renderTile(self: *const TileMap, pos: V2f, tile: TileLayer.Tile) void {
    const plat = getPlat();
    const data = App.get().data;
    const ref = self.tileIdxToTileSetRef(tile.idx) orelse {
        debug.err("unknown tileset ref!", .{});
        return;
    };
    assert(ref.data_idx < data.tilesets.items.len);
    const tileset = &data.tilesets.items[ref.data_idx];
    assert(tile.idx >= ref.first_gid);
    const tileset_tile_idx = tile.idx - ref.first_gid;
    assert(tileset_tile_idx < tileset.tiles.len);
    const tileset_tile_idxi = utl.as(i32, tileset_tile_idx);
    const sheet_coord = v2i(@mod(tileset_tile_idxi, tileset.sheet_dims.x), @divFloor(tileset_tile_idxi, tileset.sheet_dims.x));
    assert(sheet_coord.x < tileset.sheet_dims.x and sheet_coord.y < tileset.sheet_dims.y);
    const src_px_coord = v2i(sheet_coord.x * tileset.tile_dims.x, sheet_coord.y * tileset.tile_dims.y);
    const opt = draw.TextureOpt{
        .src_dims = tileset.tile_dims.toV2f(),
        .src_pos = src_px_coord.toV2f(),
        .uniform_scaling = core.pixel_art_scaling,
    };
    plat.texturef(pos, tileset.texture, opt);
}

fn renderLayer(self: *const TileMap, layer: *const TileLayer) void {
    const room_rect = self.getRoomRect();
    var map_coord: V2i = .{};
    for (layer.tiles.constSlice()) |tile| {
        if (tile.idx != 0) {
            const pos = room_rect.pos.add(tileCoordToPos(map_coord));
            self.renderTile(pos, tile);
        }
        map_coord.x += 1;
        if (map_coord.x >= self.dims_tiles.x) {
            map_coord.x = 0;
            map_coord.y += 1;
        }
    }
}

pub fn renderUnderObjects(self: *const TileMap) Error!void {
    const plat = getPlat();
    const room_rect = self.getRoomRect();
    plat.rectf(room_rect.pos, room_rect.dims, .{ .fill_color = Colorf.rgb(0.4, 0.4, 0.4) });
    for (self.tile_layers.constSlice()) |*layer| {
        if (layer.above_objects) continue;
        self.renderLayer(layer);
    }
}

pub fn renderOverObjects(self: *const TileMap, cam: draw.Camera2D, things: []const *const Thing) Error!void {
    const plat = App.getPlat();
    const data = App.get().data;
    const shader = data.shaders.get(.tile_foreground_fade);
    var num_circles: usize = 0;
    for (things, 0..) |t, i| {
        if (num_circles >= 128) break; // MAX_CIRCLES in shader
        const visible_circle = t.getApproxVisibleCircle();
        var pos = plat.camPosToScreenPos(cam, visible_circle.pos);
        // shader screen pos needs y inverted!
        pos.y = core.native_dims_f.y - pos.y;
        const radius = visible_circle.radius;
        const pos_name = try utl.bufPrintLocal("circles[{}].pos", .{i});
        try plat.setShaderValue(shader, pos_name, pos);
        const radius_name = try utl.bufPrintLocal("circles[{}].radius", .{i});
        try plat.setShaderValue(shader, radius_name, radius);
        num_circles += 1;
    }
    plat.setShaderValuesScalar(shader, .{
        .numCircles = num_circles,
    });
    plat.setShader(shader);
    for (self.tile_layers.constSlice()) |*layer| {
        if (!layer.above_objects) continue;
        self.renderLayer(layer);
    }
    plat.setDefaultShader();
}
