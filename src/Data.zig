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

const App = @import("App.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const sprites = @import("sprites.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const PackedRoom = @import("PackedRoom.zig");
const player = @import("player.zig");
const TileMap = @import("TileMap.zig");
const Data = @This();

pub const TileSet = struct {
    pub const NameBuf = u.BoundedString(64);
    pub const GameTileCorner = enum(u4) {
        NW,
        NE,
        SW,
        SE,
        const Map = std.EnumArray(GameTileCorner, bool);
    };
    pub const TileProperties = struct {
        coll: GameTileCorner.Map = GameTileCorner.Map.initFill(false),
    };

    name: NameBuf = .{}, // filename without extension (.tsj)
    id: i32 = 0,
    texture: Platform.Texture2D = undefined,
    tile_dims: V2i = .{},
    sheet_dims: V2i = .{},
    tiles: std.BoundedArray(TileProperties, TileMap.max_map_tiles) = .{},
};

pub fn EnumToBoundedStringArrayType(E: type) type {
    var max_len = 0;
    const info = @typeInfo(E);
    for (info.@"enum".fields) |f| {
        if (f.name.len > max_len) {
            max_len = f.name.len;
        }
    }
    return std.EnumArray(E, u.BoundedString(max_len));
}

pub fn enumToBoundedStringArray(E: type) EnumToBoundedStringArrayType(E) {
    var ret = EnumToBoundedStringArrayType(E).initUndefined();
    const BoundedArrayType = @TypeOf(ret).Value;
    const info = @typeInfo(E);
    for (info.@"enum".fields) |f| {
        ret.set(@enumFromInt(f.value), BoundedArrayType.init(f.name));
    }
    return ret;
}

pub const SpriteSheet = struct {
    pub const Frame = struct {
        pos: V2i,
        size: V2i,
        duration_ms: i64,
    };
    pub const Tag = struct {
        name: u.BoundedString(16),
        from_frame: i32,
        to_frame: i32,
    };
    pub const Meta = struct {
        name: u.BoundedString(16) = .{},
        data: union(enum) {
            int: i64,
            float: f32,
            string: u.BoundedString(16),
        } = undefined,

        pub fn asf32(self: @This()) Error!f32 {
            return switch (self.data) {
                .int => |i| u.as(f32, i),
                .float => |f| f,
                .string => {
                    std.log.warn("Failed to parse Meta.data \"{s}\" as f32\n", .{self.name.constSlice()});
                    return Error.ParseFail;
                },
            };
        }
    };

    name: u.BoundedString(64) = .{}, // filename without extension (.png)
    texture: Platform.Texture2D = undefined,
    frames: []Frame = &.{},
    tags: []Tag = &.{},
    meta: []Meta = &.{},
};

const test_rooms_strs = [_][]const u8{
    \\#########################
    \\#         ##        ### #
    \\#   ##    ##          # #
    \\##  ###       ###       #
    \\#                    ## #
    \\#         ##        ### #
    \\#         ##       ##   #
    \\#   ##          g  ##   #
    \\#      ##   p           #
    \\#  ##  ##       #   ### #
    \\#  ##           #   ### #
    \\#                       #
    \\#########################
    ,
    \\#########################
    \\#                       #
    \\#                       #
    \\#    ## 2      ###      #
    \\#                       #
    \\#     1    #            #
    \\#      ttt #     3      #
    \\#   ##   p t       ##   #
    \\#          t            #
    \\#     3 2       #       #
    \\#     b    1    #       #
    \\#                       #
    \\#########################
    ,
};

const first_room_str =
    \\#########
    \\#       #
    \\# p 0 & #
    \\#       #
    \\#########
;

const boss_room_str =
    \\###############
    \\###    &    ###
    \\##  2  #  2  ##
    \\#   ##   ##   #
    \\##  ## 0 ##  ##
    \\# 1         1 #
    \\#   # ### #   #
    \\##  3     3  ##
    \\###    p    ###
    \\###############
;

const smol_room_strs = [_][]const u8{
    \\#########
    \\#   #   #
    \\# 0 1 0 #
    \\#       #
    \\# p# # &#
    \\#       #
    \\# 3 2 3 #
    \\#   #   #
    \\#########
    ,
    \\###########
    \\# p1 # 1  #
    \\#         #
    \\#   ###   #
    \\# #2 # 2# #
    \\#         #
    \\##  & &  ##
    \\###########
    ,
    \\############
    \\##   p    ##
    \\#     2    #
    \\#  ## 3##  #
    \\#1 ## 2## 1#
    \\#     3    #
    \\##  &  &  ##
    \\############
    ,
    \\###########
    \\## 1 # 1 ##
    \\#    p    #
    \\#   # #   #
    \\# #2   2# #
    \\#   # #   #
    \\##  & &  ##
    \\###########
    ,
};

const big_room_strs = [_][]const u8{
    \\############
    \\#   &  &   #
    \\#      3   #
    \\#  ##  ##  #
    \\# 1 #  # 1 #
    \\##  0     ##
    \\##     0  ##
    \\# 2 #  # 2 #
    \\#p  3      #
    \\#    ##    #
    \\############
    ,
    \\############
    \\### & &  ###
    \\##  2#    ##
    \\#   ## ##  #
    \\# #    # 2 #
    \\#  1#  # # #
    \\#   #    1 #
    \\# #   ##   #
    \\#   p    ###
    \\############
    ,
    \\############
    \\##    &   ##
    \\#          #
    \\#  ##  ##  #
    \\#  2    2  #
    \\##  1  1  ##
    \\##  3##3  ##
    \\#    ##    #
    \\# 0      0 #
    \\#    ## p  #
    \\############
    ,
    \\############
    \\####&  &####
    \\##     3 ###
    \\#  # ##   ##
    \\# 1  ### 1##
    \\##  0     ##
    \\##   ##0  ##
    \\# 2  ##  2 #
    \\##  3 p   ##
    \\#####    ###
    \\############
    ,
};

pub const CreatureAnimArray = std.EnumArray(sprites.AnimName, ?sprites.CreatureAnim);
pub const AllCreatureAnimArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureAnimArray);
pub const CreatureSpriteSheetArray = std.EnumArray(sprites.AnimName, ?SpriteSheet);
pub const AllCreatureSpriteSheetArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureSpriteSheetArray);

fn IconSprites(EnumType: type) type {
    return struct {
        pub const IconsFrameIndexArray = std.EnumArray(EnumType, ?i32);

        sprite_sheet: SpriteSheet = undefined,
        icon_indices: IconsFrameIndexArray = undefined,

        pub fn init(sprite_sheet: SpriteSheet) Error!@This() {
            var ret = @This(){
                .sprite_sheet = sprite_sheet,
                .icon_indices = IconsFrameIndexArray.initFill(null),
            };
            tags: for (sprite_sheet.tags) |t| {
                inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                    if (std.mem.eql(u8, f.name, t.name.constSlice())) {
                        const kind = std.meta.stringToEnum(EnumType, f.name).?;
                        ret.icon_indices.set(kind, t.from_frame);
                        continue :tags;
                    }
                }
            }
            return ret;
        }
        pub fn getRenderFrame(self: @This(), kind: EnumType) ?sprites.RenderFrame {
            if (self.icon_indices.get(kind)) |idx| {
                const sheet = self.sprite_sheet;
                const frame = sheet.frames[u.as(usize, idx)];
                return .{
                    .pos = frame.pos,
                    .size = frame.size,
                    .texture = sheet.texture,
                    .origin = .center,
                };
            }
            return null;
        }
    };
}

pub const MiscIcon = enum {
    discard,
};

pub const PackedRoomBuf = std.BoundedArray(PackedRoom, 16);

pub const SFX = enum {
    thwack,
    spell_casting,
    spell_cast,
    spell_fizzle,
};

pub const RoomKind = enum {
    testu,
    first,
    smol,
    big,
    boss,
};

pub const room_strs = std.EnumArray(RoomKind, []const []const u8).init(.{
    .testu = &test_rooms_strs,
    .first = &.{first_room_str},
    .smol = &smol_room_strs,
    .big = &big_room_strs,
    .boss = &.{boss_room_str},
});

tilesets: std.ArrayList(TileSet) = undefined,
creatures: std.EnumArray(Thing.CreatureKind, Thing) = undefined,
creature_sprite_sheets: AllCreatureSpriteSheetArrays = undefined,
creature_anims: AllCreatureAnimArrays = undefined,
vfx_sprite_sheets: std.ArrayList(SpriteSheet) = undefined,
vfx_sprite_sheet_mappings: sprites.VFXAnim.IdxMapping = undefined,
vfx_anims: std.ArrayList(sprites.VFXAnim) = undefined,
vfx_anim_mappings: sprites.VFXAnim.IdxMapping = undefined,
spell_icons: IconSprites(Spell.Kind) = undefined,
item_icons: IconSprites(Item.Kind) = undefined,
misc_icons: IconSprites(MiscIcon) = undefined,
sounds: std.EnumArray(SFX, ?Platform.Sound) = undefined,
// roooms
rooms: std.EnumArray(RoomKind, PackedRoomBuf) = undefined,

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");
    data.* = .{};
    data.vfx_anims = @TypeOf(data.vfx_anims).init(plat.heap);
    data.vfx_sprite_sheets = @TypeOf(data.vfx_sprite_sheets).init(plat.heap);
    data.tilesets = @TypeOf(data.tilesets).init(plat.heap);
    try data.reload();
    return data;
}

pub fn getVFXAnim(self: *Data, sheet_name: sprites.VFXAnim.SheetName, anim_name: sprites.AnimName) ?sprites.VFXAnim {
    if (self.vfx_anim_mappings.getPtr(sheet_name).get(anim_name)) |idx| {
        return self.vfx_anims.items[idx];
    }
    return null;
}

pub fn getVFXSpriteSheet(self: *Data, sheet_name: sprites.VFXAnim.SheetName, anim_name: sprites.AnimName) ?SpriteSheet {
    if (self.vfx_sprite_sheet_mappings.getPtr(sheet_name).get(anim_name)) |idx| {
        return self.vfx_sprite_sheets.items[idx];
    }
    return null;
}

pub fn getCreatureAnim(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?sprites.CreatureAnim {
    return self.creature_anims.get(creature_kind).get(anim_kind);
}

pub fn getCreatureAnimOrDefault(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?sprites.CreatureAnim {
    if (self.creature_anims.get(creature_kind).get(anim_kind)) |a| {
        return a;
    }
    return self.creature_anims.get(.creature).get(anim_kind);
}

pub fn getCreatureAnimSpriteSheet(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?SpriteSheet {
    return self.creature_sprite_sheets.get(creature_kind).get(anim_kind);
}

pub fn getCreatureAnimSpriteSheetOrDefault(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?SpriteSheet {
    if (self.creature_sprite_sheets.get(creature_kind).get(anim_kind)) |s| {
        return s;
    }
    return self.creature_sprite_sheets.get(.creature).get(anim_kind);
}

pub fn loadSounds(self: *Data) Error!void {
    const plat = App.getPlat();
    self.sounds = @TypeOf(self.sounds).initFill(null);
    const list = [_]struct { SFX, []const u8 }{
        .{ .thwack, "thwack.wav" },
        .{ .spell_casting, "casting.wav" },
        .{ .spell_cast, "cast-end.wav" },
    };
    for (list) |s| {
        self.sounds.getPtr(s[0]).* = try plat.loadSound(s[1]);
    }
}

pub fn loadSpriteSheetFromJson(json_file: std.fs.File, assets_rel_dir_path: []const u8) Error!SpriteSheet {
    const plat = App.getPlat();
    const s = json_file.readToEndAlloc(plat.heap, 8 * 1024 * 1024) catch return Error.FileSystemFail;
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, s);
    var tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = s.len }) catch return Error.ParseFail;
    // TODO I guess tree just leaks rn? use arena?

    const meta = tree.object.get("meta").?.object;
    const image_filename = meta.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_rel_dir_path, image_filename });

    var sheet = SpriteSheet{};
    var it_dot = std.mem.tokenizeScalar(u8, image_filename, '.');
    const sheet_name = it_dot.next().?;
    sheet.name = try @TypeOf(sheet.name).init(sheet_name);
    const tex = try plat.loadTexture(image_path);
    assert(tex.r_tex.height > 0);
    sheet.texture = tex;

    const frames = tree.object.get("frames").?.array;
    const tags = meta.get("frameTags").?.array;
    const _layers = meta.get("layers");
    var sheet_frames = try std.ArrayList(SpriteSheet.Frame).initCapacity(plat.heap, frames.items.len);
    var sheet_tags = try std.ArrayList(SpriteSheet.Tag).initCapacity(plat.heap, tags.items.len);
    var sheet_meta = try std.ArrayList(SpriteSheet.Meta).initCapacity(plat.heap, tags.items.len);

    for (tags.items) |t| {
        const name = t.object.get("name").?.string;
        const from = t.object.get("from").?.integer;
        const to = t.object.get("to").?.integer;
        assert(from >= 0 and from <= frames.items.len);
        assert(to >= from and to <= frames.items.len);
        try sheet_tags.append(.{
            .name = try @TypeOf(sheet.tags[0].name).init(name),
            .from_frame = u.as(i32, from),
            .to_frame = u.as(i32, to),
        });
    }
    sheet.tags = try sheet_tags.toOwnedSlice();

    for (frames.items) |f| {
        const dur = f.object.get("duration").?.integer;
        const frame = f.object.get("frame").?.object;
        const x = frame.get("x").?.integer;
        const y = frame.get("y").?.integer;
        const w = frame.get("w").?.integer;
        const h = frame.get("h").?.integer;
        try sheet_frames.append(.{
            .duration_ms = dur,
            .pos = V2i.iToV2i(i64, x, y),
            .size = V2i.iToV2i(i64, w, h),
        });
    }
    sheet.frames = try sheet_frames.toOwnedSlice();

    if (_layers) |layers| {
        for (layers.array.items) |layer| {
            if (layer.object.get("cels")) |cels| {
                for (cels.array.items) |cel| {
                    if (cel.object.get("data")) |data| {
                        var it_data = std.mem.tokenizeScalar(u8, data.string, ',');
                        while (it_data.next()) |item| {
                            var it_eq = std.mem.tokenizeScalar(u8, item, '=');
                            const key = it_eq.next().?;
                            const val = it_eq.next().?;
                            var m = SpriteSheet.Meta{};
                            m.name = try @TypeOf(m.name).init(key);
                            blk: {
                                int_blk: {
                                    const int = std.fmt.parseInt(i64, val, 0) catch break :int_blk;
                                    m.data.int = int;
                                    break :blk;
                                }
                                float_blk: {
                                    const float = std.fmt.parseFloat(f32, val) catch break :float_blk;
                                    m.data.float = float;
                                    break :blk;
                                }
                                m.data.string = try @TypeOf(m.data.string).init(val);
                            }
                            try sheet_meta.append(m);
                        }
                    }
                }
            }
        }
    }
    sheet.meta = try sheet_meta.toOwnedSlice();

    return sheet;
}

pub fn loadSpriteSheetFromJsonPath(_: *Data, assets_rel_dir: []const u8, json_file_name: []const u8) Error!SpriteSheet {
    const plat = App.getPlat();
    const path = try u.bufPrintLocal("{s}/{s}/{s}", .{ plat.assets_path, assets_rel_dir, json_file_name });
    const icons_json = std.fs.cwd().openFile(path, .{}) catch return Error.FileSystemFail;
    const sheet = try loadSpriteSheetFromJson(icons_json, assets_rel_dir);
    return sheet;
}

pub fn loadCreatureSpriteSheets(self: *Data) Error!void {
    const plat = App.getPlat();

    self.creature_anims = @TypeOf(self.creature_anims).initFill(CreatureAnimArray.initFill(null));
    self.creature_sprite_sheets = @TypeOf(self.creature_sprite_sheets).initFill(CreatureSpriteSheetArray.initFill(null));

    const path = try u.bufPrintLocal("{s}/images/creature", .{plat.assets_path});
    var creature = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return Error.FileSystemFail;
    defer creature.close();
    var walker = try creature.walk(plat.heap);
    defer walker.deinit();

    while (walker.next() catch return Error.FileSystemFail) |w_entry| {
        if (!std.mem.endsWith(u8, w_entry.basename, ".json")) continue;
        const json_file = creature.openFile(w_entry.basename, .{}) catch return Error.FileSystemFail;
        const sheet = try loadSpriteSheetFromJson(json_file, "images/creature");

        var it_dash = std.mem.tokenizeScalar(u8, sheet.name.constSlice(), '-');
        const creature_name = it_dash.next().?;
        const creature_kind = std.meta.stringToEnum(sprites.CreatureAnim.Kind, creature_name).?;
        const anim_name = it_dash.next().?;
        const anim_kind = std.meta.stringToEnum(sprites.AnimName, anim_name).?;
        self.creature_sprite_sheets.getPtr(creature_kind).getPtr(anim_kind).* = sheet;
        if (anim_kind == .idle) {
            const none_sheet = self.creature_sprite_sheets.getPtr(creature_kind).getPtr(.none);
            if (none_sheet.* == null) {
                none_sheet.* = sheet;
            }
        }

        // sprite sheet to creature anim
        var anim = sprites.CreatureAnim{
            .creature_kind = creature_kind,
            .anim_kind = anim_kind,
            .num_frames = sheet.tags[0].to_frame - sheet.tags[0].from_frame + 1,
            .num_dirs = u.as(u8, sheet.tags.len), // TODO
        };

        meta_blk: for (sheet.meta) |m| {
            const m_name = m.name.constSlice();
            //std.debug.print("Meta '{s}'\n", .{m_name});

            if (std.mem.eql(u8, m_name, "pivot-y")) {
                const y = m.asf32() catch continue;
                const x = u.as(f32, sheet.frames[0].size.x) * 0.5;
                anim.origin = .{ .offset = v2f(x, y) };
                continue;
            }
            if (std.mem.eql(u8, m_name, "cast-y")) {
                anim.cast_offset.y = m.asf32() catch continue;
                continue;
            }
            if (std.mem.eql(u8, m_name, "cast-x")) {
                anim.cast_offset.x = m.asf32() catch continue;
                continue;
            }
            if (std.mem.eql(u8, m_name, "start-angle-deg")) {
                const deg = switch (m.data) {
                    .int => |i| u.as(f32, i),
                    .float => |f| f,
                    .string => return Error.ParseFail,
                };
                const rads = u.degreesToRadians(deg);
                anim.start_angle_rads = rads;
            }

            const event_info = @typeInfo(sprites.AnimEvent.Kind);
            inline for (event_info.@"enum".fields) |f| {
                if (std.mem.eql(u8, m_name, f.name)) {
                    //std.debug.print("Adding event '{s}' on frame {}\n", .{ f.name, m.data.int });
                    anim.events.append(.{
                        .frame = u.as(i32, m.data.int),
                        .kind = @enumFromInt(f.value),
                    }) catch {
                        std.debug.print("Skipped adding anim event \"{s}\"; buffer full\n", .{f.name});
                    };
                    continue :meta_blk;
                }
            }
        }
        self.creature_anims.getPtr(creature_kind).getPtr(anim_kind).* = anim;
        if (anim_kind == .idle) {
            const none_anim = self.creature_anims.getPtr(creature_kind).getPtr(.none);
            if (none_anim.* == null) {
                none_anim.* = anim;
            }
        }
    }
}

pub fn loadVFXSpriteSheets(self: *Data) Error!void {
    const plat = App.getPlat();

    self.vfx_anims.clearRetainingCapacity();
    self.vfx_anim_mappings = @TypeOf(self.vfx_anim_mappings).initFill(sprites.VFXAnim.AnimNameIdxMapping.initFill(null));
    self.vfx_sprite_sheets.clearRetainingCapacity();
    self.vfx_sprite_sheet_mappings = @TypeOf(self.vfx_sprite_sheet_mappings).initFill(sprites.VFXAnim.AnimNameIdxMapping.initFill(null));

    const path = try u.bufPrintLocal("{s}/images/vfx", .{plat.assets_path});
    var vfx = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return Error.FileSystemFail;
    defer vfx.close();
    var walker = try vfx.walk(plat.heap);
    defer walker.deinit();

    while (walker.next() catch return Error.FileSystemFail) |w_entry| {
        if (!std.mem.endsWith(u8, w_entry.basename, ".json")) continue;
        const json_file = vfx.openFile(w_entry.basename, .{}) catch return Error.FileSystemFail;

        const sheet = try loadSpriteSheetFromJson(json_file, "images/vfx");
        const sheet_idx = self.vfx_sprite_sheets.items.len;
        try self.vfx_sprite_sheets.append(sheet);

        if (std.meta.stringToEnum(sprites.VFXAnim.SheetName, sheet.name.constSlice())) |vfx_sheet_name| {
            // sprite sheet to vfx anims
            for (sheet.tags) |tag| {
                if (std.meta.stringToEnum(sprites.AnimName, tag.name.constSlice())) |vfx_anim_name| {
                    var anim: sprites.VFXAnim = .{
                        .sheet_name = vfx_sheet_name,
                        .anim_name = vfx_anim_name,
                        .start_frame = tag.from_frame,
                        .num_frames = tag.to_frame - tag.from_frame + 1,
                    };

                    meta_blk: for (sheet.meta) |m| {
                        const m_name = m.name.constSlice();
                        //std.debug.print("Meta '{s}'\n", .{m_name});

                        if (std.mem.eql(u8, m_name, "pivot-y")) {
                            const y = m.asf32() catch continue;
                            const x = u.as(f32, sheet.frames[0].size.x) * 0.5;
                            anim.origin = .{ .offset = v2f(x, y) };
                            continue;
                        }
                        const event_info = @typeInfo(sprites.AnimEvent.Kind);
                        inline for (event_info.@"enum".fields) |f| {
                            if (std.mem.eql(u8, m_name, f.name)) {
                                //std.debug.print("Adding event '{s}' on frame {}\n", .{ f.name, m.data.int });
                                anim.events.append(.{
                                    .frame = u.as(i32, m.data.int),
                                    .kind = @enumFromInt(f.value),
                                }) catch {
                                    std.debug.print("Skipped adding vfx anim event \"{s}\"; buffer full\n", .{f.name});
                                };
                                continue :meta_blk;
                            }
                        }
                    }
                    const anim_idx = self.vfx_anims.items.len;
                    try self.vfx_anims.append(anim);
                    self.vfx_sprite_sheet_mappings.getPtr(vfx_sheet_name).getPtr(vfx_anim_name).* = sheet_idx;
                    self.vfx_anim_mappings.getPtr(vfx_sheet_name).getPtr(vfx_anim_name).* = anim_idx;
                } else {
                    std.log.warn("Unknown vfx anim skipped: {s}\n", .{tag.name.constSlice()});
                }
            }
        } else {
            std.log.warn("Unknown vfx spritesheet skipped: {s}\n", .{sheet.name.constSlice()});
        }
    }
}

pub fn loadSpriteSheets(self: *Data) Error!void {
    try self.loadCreatureSpriteSheets();
    try self.loadVFXSpriteSheets();
    self.item_icons = try @TypeOf(self.item_icons).init(try self.loadSpriteSheetFromJsonPath("images/ui", "item_icons.json"));
    self.spell_icons = try @TypeOf(self.spell_icons).init(try self.loadSpriteSheetFromJsonPath("images/ui", "spell_icons.json"));
    self.misc_icons = try @TypeOf(self.misc_icons).init(try self.loadSpriteSheetFromJsonPath("images/ui", "misc_icons.json"));
}

pub fn loadTileSetFromJson(json_file: std.fs.File, assets_rel_path: []const u8) Error!TileSet {
    const plat = App.getPlat();
    const s = json_file.readToEndAlloc(plat.heap, 8 * 1024 * 1024) catch return Error.FileSystemFail;
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, s);
    const _tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = s.len }) catch return Error.ParseFail;
    var tree = _tree.object;
    // TODO I guess tree just leaks rn? use arena?

    const image_filename = tree.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_rel_path, image_filename });

    const name = tree.get("name").?.string;
    const tile_dims = V2i.iToV2i(
        i64,
        tree.get("tilewidth").?.integer,
        tree.get("tileheight").?.integer,
    );
    const image_dims = V2i.iToV2i(
        i64,
        tree.get("imagewidth").?.integer,
        tree.get("imageheight").?.integer,
    );
    const columns = tree.get("columns").?.integer;
    const sheet_dims = V2i.iToV2i(i64, columns, @divExact(image_dims.y, tile_dims.y));

    var tileset = TileSet{
        .name = try TileSet.NameBuf.init(name),
        .sheet_dims = sheet_dims,
        .tile_dims = tile_dims,
        .texture = try plat.loadTexture(image_path),
    };
    assert(tileset.texture.dims.x == image_dims.x);
    assert(tileset.texture.dims.y == image_dims.y);

    if (tree.get("tiles")) |tiles| {
        for (tiles.array.items) |t| {
            const id = t.object.get("id").?.integer;
            const idx = u.as(usize, id);
            const props = t.object.get("properties").?.array;
            var prop = TileSet.TileProperties{};
            for (props.items) |p| {
                const prop_name = p.object.get("name").?.string;
                const val = p.object.get("value").?.string;
                if (std.mem.eql(u8, prop_name, "colls")) {
                    var prop_it = std.mem.tokenizeScalar(u8, val, ',');
                    var c_i: usize = 0;
                    while (prop_it.next()) |c| {
                        const coll_bool: bool = if (c[0] == '0') false else true;
                        prop.coll.getPtr(@enumFromInt(c_i)).* = coll_bool;
                        c_i += 1;
                    }
                }
            }
            tileset.tiles.buffer[idx] = prop;
        }
    }
    return tileset;
}

pub fn loadTileSets(self: *Data) Error!void {
    const plat = App.getPlat();

    for (self.tilesets.items) |t| {
        plat.unloadTexture(t.texture);
    }
    self.tilesets.clearRetainingCapacity();

    const path = try u.bufPrintLocal("{s}/maps/tilesets", .{plat.assets_path});
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return Error.FileSystemFail;
    defer dir.close();
    var walker = try dir.walk(plat.heap);
    defer walker.deinit();

    while (walker.next() catch return Error.FileSystemFail) |w_entry| {
        if (!std.mem.endsWith(u8, w_entry.basename, ".tsj")) continue;
        const json_file = dir.openFile(w_entry.basename, .{}) catch return Error.FileSystemFail;
        var tileset = try loadTileSetFromJson(json_file, "maps/tilesets/");
        tileset.id = u.as(i32, self.tilesets.items.len);
        try (self.tilesets.append(tileset));
        std.debug.print("Loaded tileset: {s}\n", .{tileset.name.constSlice()});
    }
}

pub fn reload(self: *Data) Error!void {
    self.loadSpriteSheets() catch std.debug.print("WARNING: failed to load all sprites\n", .{});
    self.loadSounds() catch std.debug.print("WARNING: failed to load all sounds\n", .{});
    self.creatures = @TypeOf(self.creatures).init(
        .{
            .player = player.basePrototype(),
            .dummy = @import("enemies.zig").dummy(),
            .bat = try @import("enemies.zig").bat(),
            .troll = try @import("enemies.zig").troll(),
            .gobbow = try @import("enemies.zig").gobbow(),
            .sharpboi = try @import("enemies.zig").sharpboi(),
            .acolyte = try @import("enemies.zig").acolyte(),
            .impling = try @import("spells/Impling.zig").implingProto(),
        },
    );
    try self.loadTileSets();
    self.rooms = @TypeOf(self.rooms).initDefault(.{}, .{});
    inline for (std.meta.fields(RoomKind)) |f| {
        const kind: RoomKind = @enumFromInt(f.value);
        const strs = room_strs.get(kind);
        const packed_rooms = self.rooms.getPtr(kind);
        for (strs) |s| {
            try packed_rooms.append(try PackedRoom.init(s));
        }
    }
}
