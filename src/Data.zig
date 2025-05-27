const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const debug = @import("debug.zig");
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
const Log = App.Log;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const sprites = @import("sprites.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const player = @import("player.zig");
const TileMap = @import("TileMap.zig");
const creatures = @import("creatures.zig");
const icon_text = @import("icon_text.zig");
const Data = @This();

// asset classes
// files:
// - images -> spritesheets
//   - really a json and .png
// - sounds
// - fonts
// - shaders
//   - vertex + frag files
// - tilesets
//   - a json and spritesheet^
// - tile object
//   - json and spritesheet
// - tilemaps
//   - json and tilesets and tile objects
// - ???
//
// other or derived:
// - anim -> a spritesheet + tag (index?)
// - ?
//
// all in flat arrays, per-type
// look up an asset with a "Ref" - name + optional index
// - index takes priority, that's faster (validate in debug mode)
// - otherwise lookup name (slow), and populate index in passed-in Ref (pointer)
//

pub const AssetName = u.BoundedString(64);

pub inline fn streq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn assetTypeToLowerCaseName(AssetType: type) []const u8 {
    const basename = u.typeBaseName(AssetType);
    var lower_buf: [basename.len]u8 = undefined;
    const lowercase = std.ascii.lowerString(&lower_buf, basename);

    return lowercase;
}

pub fn assetTypeToBufferFieldName(AssetType: type) []const u8 {
    return assetTypeToLowerCaseName(AssetType) ++ "s";
}

pub fn assetTypeToDefaultIdxName(AssetType: type) []const u8 {
    return assetTypeToLowerCaseName(AssetType) ++ "_default";
}

pub fn Ref(AssetType: type) type {
    return struct {
        const Self = @This();
        const Type = AssetType;
        name: AssetName = .{},
        idx: ?usize = null,

        pub fn init(name: []const u8) Self {
            return .{
                .name = AssetName.fromSlice(name) catch unreachable,
            };
        }

        pub fn tryGet(self: *Self) ?*Self.Type {
            const data = App.getData();
            if (self.idx) |idx| {
                if (data.getByIdx(Self.Type, idx)) |asset| {
                    if (streq(self.name.constSlice(), asset.data_ref.name.constSlice())) {
                        return asset;
                    }
                }
            }
            if (data.getByName(Self.Type, self.name.constSlice())) |asset| {
                self.idx = asset.data_ref.idx;
                return asset;
            }
            return null;
        }

        pub fn tryGetOrDefault(self: *Self) ?*Self.Type {
            if (self.tryGet()) |s| return s;
            const data = App.getData();
            if (data.getDefault(Self.Type)) |d| return d;
            return null;
        }

        pub fn get(self: *Self) *Self.Type {
            if (self.tryGet()) |ret| return ret;
            const data = App.getData();
            if (data.getDefault(Self.Type)) |default| {
                return default;
            }
            Log.fatal("Tried to get nonexistent default asset \"{s}\". Type: \"{s}\"", .{ self.name.constSlice(), @typeName(AssetType) });
            @panic("Failed to get asset");
        }

        pub fn tryGetConstOrDefault(self: *const Self) ?*const Self.Type {
            return @constCast(self).tryGetOrDefault();
        }

        pub fn tryGetConst(self: *const Self) ?*const Self.Type {
            return @constCast(self).tryGet();
        }

        pub fn getConst(self: *const Self) *const Self.Type {
            return @constCast(self).get();
        }

        pub fn isDefault(self: *const Self) bool {
            return std.mem.startsWith(u8, self.name.constSlice(), "__default");
        }
    };
}

pub fn getByName(data: *Data, AssetType: type, name: []const u8) ?*AssetType {
    const field_name = comptime assetTypeToBufferFieldName(AssetType);
    const field = &@field(data, field_name);
    // TODO hashmap for fast lookup
    for (field.slice()) |*asset| {
        if (std.mem.eql(u8, asset.data_ref.name.constSlice(), name)) {
            return asset;
        }
    }
    return null;
}

pub fn getByIdx(data: *Data, AssetType: type, idx: usize) ?*AssetType {
    const field_name = comptime assetTypeToBufferFieldName(AssetType);
    const field = &@field(data, field_name);

    if (idx < field.len) {
        const asset = &field.buffer[idx];
        return asset;
    }

    return null;
}

pub fn getDefault(data: *Data, AssetType: type) ?*AssetType {
    const field_name = comptime assetTypeToDefaultIdxName(AssetType);
    if (@hasField(Data, field_name)) {
        const idx = @field(data, field_name);
        if (data.getByIdx(AssetType, idx)) |asset| {
            return asset;
        }
    }
    return null;
}

pub fn AssetArray(AssetType: type, max_num: usize) type {
    return std.BoundedArray(AssetType, max_num);
}

pub fn allocAsset(data: *Data, AssetType: type, name: []const u8) *AssetType {
    const field_name = comptime assetTypeToBufferFieldName(AssetType);
    const field = &@field(data, field_name);

    var new_asset: *AssetType = undefined;
    var ref = Ref(AssetType).init(name);
    if (data.getByName(AssetType, name)) |existing| {
        Log.warn("Overwriting existing asset \"{s}\" named \"{s}\".", .{ @typeName(AssetType), name });
        ref.idx = existing.data_ref.idx;
        new_asset = existing;
    } else {
        ref.idx = field.len;
        new_asset = field.addOne() catch {
            Log.fatal("Ran out of room for \"{s}\" ({})", .{ @typeName(AssetType), field.buffer.len });
            @panic("Ran out of room in array");
        };
        new_asset.* = .{};
    }
    new_asset.data_ref = ref;
    return new_asset;
}

pub fn putAsset(data: *Data, AssetType: type, asset: *const AssetType, name: []const u8) *AssetType {
    const new_asset = data.allocAsset(AssetType, name);
    const ref = new_asset.data_ref;
    new_asset.* = asset.*;
    new_asset.data_ref = ref;

    return new_asset;
}

pub const asset_extensions = [_][]const u8{
    // images
    "png",
    // sounds + music
    "wav",
    // json (tilemaps, tilesets, spritesheet metadata)
    "tmj",
    "tj",
    "tsj",
    "json",
    // fonts
    "ttf",
    // shaders
    "fs",
    "vs",
};

pub fn filenameToAssetName(filename: []const u8) []const u8 {
    assert(filename.len > 0);
    inline for (asset_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, "." ++ ext)) {
            const end = filename.len - (ext.len + 1);
            return filename[0..end];
        }
    }
    Log.warn("No valid asset extension \"{s}\", using name as-is", .{filename});
    return filename;
}

pub const TileSet = struct {
    pub const GameTileCorner = enum(u4) {
        NW,
        NE,
        SW,
        SE,
        const Map = std.EnumArray(GameTileCorner, bool);
        // map a tile coordinate to a game tile coordinate by adding these
        // note they don't actually point in NW/NE etc directions!
        const dir_map = std.EnumArray(GameTileCorner, V2i).init(.{
            .NW = v2i(-1, -1),
            .NE = v2i(0, -1),
            .SW = v2i(-1, 0),
            .SE = v2i(0, 0),
        });
    };
    pub const TileProperties = struct {
        colls: GameTileCorner.Map = GameTileCorner.Map.initFill(false),
        spikes: GameTileCorner.Map = GameTileCorner.Map.initFill(false),
    };

    // name is filename without extension (.tsj)
    data_ref: Ref(TileSet) = .{},

    texture: Platform.Texture2D = undefined,
    tile_dims: V2i = .{},
    sheet_dims: V2i = .{},
    tiles: std.BoundedArray(TileProperties, TileMap.max_map_tiles) = .{},

    pub fn deinit(self: *TileSet) void {
        const plat = App.getPlat();
        plat.unloadTexture(self.texture);
    }
};

pub const SpriteAnim = sprites.SpriteAnim;
pub const DirectionalSpriteAnim = sprites.DirectionalSpriteAnim;

pub const SpriteSheet = struct {
    pub const Frame = struct {
        pos: V2i,
        size: V2i,
        // cropped_size: V2i, // TODO
        duration_ms: i64,
    };
    pub const Tag = struct {
        name: u.BoundedString(32),
        from_frame: i32,
        to_frame: i32,
    };
    pub const Meta = struct {
        name: u.BoundedString(32) = .{},
        data: union(enum) {
            int: i64,
            float: f32,
            vecf: V2f,
            string: u.BoundedString(32),
        } = undefined,

        pub fn asf32(self: @This()) Error!f32 {
            return switch (self.data) {
                .int => |i| u.as(f32, i),
                .float => |f| f,
                else => {
                    Log.warn("Failed to parse Meta.data \"{s}\" as f32. Is {any}\n", .{ self.name.constSlice(), std.meta.activeTag(self.data) });
                    return Error.ParseFail;
                },
            };
        }
    };

    data_ref: Ref(SpriteSheet) = .{}, // filename without extension (.png)

    texture: Platform.Texture2D = undefined,
    crop_color: ?Colorf = null,
    frames: []Frame = &.{},
    tags: []Tag = &.{},
    meta: []Meta = &.{},

    pub fn deinit(self: SpriteSheet) void {
        const plat = App.getPlat();
        plat.unloadTexture(self.texture);
        plat.heap.free(self.frames);
        plat.heap.free(self.tags);
        plat.heap.free(self.meta);
    }
};

pub const Sound = struct {
    data_ref: Ref(Sound) = .{},
    sound: Platform.Sound = undefined,

    pub fn deinit(self: *Sound) void {
        const plat = App.getPlat();
        plat.unloadSound(self.sound);
    }
};

pub const CreatureSpriteName = enum {
    creature, // misc anim
    wizard,
    dummy,
    bat,
    troll,
    gobbow,
    sharpboi,
    impling,
    acolyte,
    slime,
    gobbomber,
    shopspider,
    djinn,
    djinn_smoke,
    snowfren,
    @"fairy-blue",
    @"fairy-green",
    @"fairy-red",
    @"fairy-gold",
};
pub const ActionAnimName = enum {
    idle,
    move,
    attack,
    charge,
    cast,
    hit,
    die,
};

pub const DirAnimCache = std.EnumArray(ActionAnimName, ?Ref(DirectionalSpriteAnim));
pub const CreatureDirAnimCache = std.EnumArray(CreatureSpriteName, DirAnimCache);

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

fn EnumSpriteSheet(EnumType: type) type {
    return struct {
        pub const SpriteFrameIndexArray = std.EnumArray(EnumType, ?i32);

        sprite_sheet: Ref(SpriteSheet) = undefined,
        sprite_indices: SpriteFrameIndexArray = undefined,
        sprite_dims_cropped: ?std.EnumArray(EnumType, V2f) = null,

        pub fn init(sprite_sheet: *SpriteSheet) Error!@This() {
            var ret = @This(){
                .sprite_sheet = sprite_sheet.data_ref,
                .sprite_indices = SpriteFrameIndexArray.initFill(null),
            };
            tags: for (sprite_sheet.tags) |t| {
                inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                    if (std.mem.eql(u8, f.name, t.name.constSlice())) {
                        const kind = std.meta.stringToEnum(EnumType, f.name).?;
                        ret.sprite_indices.set(kind, t.from_frame);
                        continue :tags;
                    }
                }
            }
            return ret;
        }
        pub fn initCropped(sprite_sheet: *SpriteSheet, crop_color: draw.Coloru) Error!@This() {
            const plat = App.getPlat();
            var ret = try @This().init(sprite_sheet);
            ret.sprite_dims_cropped = std.EnumArray(EnumType, V2f).initFill(.{});
            const image_buf = plat.textureToImageBuf(sprite_sheet.texture);
            defer plat.unloadImageBuf(image_buf);
            tags: for (sprite_sheet.tags) |t| {
                inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                    if (std.mem.eql(u8, f.name, t.name.constSlice())) {
                        const kind = std.meta.stringToEnum(EnumType, f.name).?;
                        const render_frame = ret.getRenderFrame(kind).?;
                        const cropped_dims = ret.sprite_dims_cropped.?.getPtr(kind);
                        cropped_dims.* = render_frame.size.toV2f();
                        for (0..u.as(usize, render_frame.size.x)) |x_off| {
                            const x = render_frame.pos.x + u.as(i32, x_off);
                            const y = render_frame.pos.y;
                            const color: draw.Coloru = image_buf.data[u.as(usize, x + y * sprite_sheet.texture.dims.x)];
                            if (color.eql(crop_color)) {
                                cropped_dims.x = u.as(f32, x - render_frame.pos.x);
                                break;
                            }
                        }
                        for (0..u.as(usize, render_frame.size.y)) |y_off| {
                            const y = render_frame.pos.y + u.as(i32, y_off);
                            const x = render_frame.pos.x;
                            const color: draw.Coloru = image_buf.data[u.as(usize, x + y * sprite_sheet.texture.dims.x)];
                            if (color.eql(crop_color)) {
                                cropped_dims.y = u.as(f32, y - render_frame.pos.y);
                                break;
                            }
                        }
                        continue :tags;
                    }
                }
            }
            return ret;
        }
        pub fn getRenderFrame(self: @This(), kind: EnumType) ?sprites.RenderFrame {
            if (self.sprite_indices.get(kind)) |idx| {
                const sheet = self.sprite_sheet.getConst();
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
    pub const dims = Item.icon_dims;

    discard,
    hourglass_up,
    hourglass_down,
    cards,
    gold_stacks,
    knife,
    deck,
    gearwheel,
    help,
    card_remove,
};

pub const TileMapIdxBuf = std.BoundedArray(usize, 16);

pub const Shader = struct {
    data_ref: Ref(Shader) = .{},
    shader: Platform.Shader = undefined,

    pub fn deinit(self: Shader) void {
        App.getPlat().unloadShader(self.shader);
    }
};

pub const FontName = enum {
    alagard,
    pixeloid,
    seven_x_five,
};
pub const FontArr = std.EnumArray(FontName, Platform.Font);

pub const RoomKind = enum {
    testu,
    first,
    smol,
    big,
    boss,
    shop,
};

// iterates over files in a directory, with a given suffix (including dot, e.g. ".json")
pub fn FileWalkerIterator(assets_rel_dir: []const u8, file_suffix: []const u8) type {
    return struct {
        allocator: std.mem.Allocator,
        dir: std.fs.Dir,
        walker: std.fs.Dir.Walker,

        pub fn init(allocator: std.mem.Allocator) Error!@This() {
            const plat = App.getPlat();
            const path = try u.bufPrintLocal("{s}/{s}", .{ plat.assets_path, assets_rel_dir });
            var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| {
                Log.err("Error opening dir \"{s}\"", .{path});
                Log.errorAndStackTrace(err);
                return Error.FileSystemFail;
            };
            const walker = try dir.walk(allocator);

            return .{
                .allocator = allocator,
                .dir = dir,
                .walker = walker,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.walker.deinit();
            self.dir.close();
        }

        pub fn nextFile(self: *@This()) Error!?std.fs.File {
            while (self.walker.next() catch return Error.FileSystemFail) |entry| {
                if (!std.mem.endsWith(u8, entry.basename, file_suffix)) continue;
                const file = self.dir.openFile(entry.basename, .{}) catch return Error.FileSystemFail;
                return file;
            }
            return null;
        }

        pub fn nextFileAsOwnedString(self: *@This()) Error!?[]u8 {
            while (self.walker.next() catch return Error.FileSystemFail) |entry| {
                if (!std.mem.endsWith(u8, entry.basename, file_suffix)) continue;
                const file = self.dir.openFile(entry.basename, .{}) catch return Error.FileSystemFail;
                const str = file.readToEndAlloc(self.allocator, 8 * 1024 * 1024) catch return Error.FileSystemFail;
                return str;
            }
            return null;
        }
        pub const NextEntry = struct {
            basename: []const u8,
            owned_string: []u8,
            pub fn deinit(self: NextEntry, allocator: std.mem.Allocator) void {
                allocator.free(self.owned_string);
            }
        };
        pub fn next(self: *@This()) Error!?NextEntry {
            while (self.walker.next() catch return Error.FileSystemFail) |entry| {
                if (!std.mem.endsWith(u8, entry.basename, file_suffix)) continue;
                const file = self.dir.openFile(entry.basename, .{}) catch return Error.FileSystemFail;
                const str = file.readToEndAlloc(self.allocator, 8 * 1024 * 1024) catch return Error.FileSystemFail;
                return .{
                    .basename = entry.basename,
                    .owned_string = str,
                };
            }
            return null;
        }
    };
}

creature_protos: std.EnumArray(Thing.CreatureKind, Thing),
room_kind_tilemaps: std.EnumArray(RoomKind, TileMapIdxBuf),
// "new" universal asset arrays - all assets of given type stored here
// directionalspriteanims: std.ArrayList(DirectionalSpriteAnim), // TODO
spritesheets: AssetArray(SpriteSheet, 128),
tilesets: AssetArray(TileSet, 8),
tilemaps: AssetArray(TileMap, 32),
sounds: AssetArray(Sound, 128),
shaders: AssetArray(Shader, 8),
spriteanims: AssetArray(SpriteAnim, 512),
spriteanim_default: usize,
directionalspriteanims: AssetArray(DirectionalSpriteAnim, 128),
directionalspriteanim_default: usize,
// caches for faster simpler lookups for some stuff
creature_dir_anims: CreatureDirAnimCache,
// hopefully-soon-deprecated stuff
spell_icons: EnumSpriteSheet(Spell.Kind),
item_icons: EnumSpriteSheet(Item.Kind),
misc_icons: EnumSpriteSheet(MiscIcon),
text_icons: EnumSpriteSheet(icon_text.Icon),
card_sprites: EnumSpriteSheet(Spell.CardSpriteEnum),
card_mana_cost: EnumSpriteSheet(Spell.ManaCost.SpriteEnum),
fonts: FontArr,

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");

    // TODO default init these
    data.spritesheets.clear();
    data.tilesets.clear();
    data.tilemaps.clear();
    data.sounds.clear();
    data.shaders.clear();
    data.spriteanims.clear();

    return data;
}

pub fn getCreatureDirAnim(self: *Data, creature_kind: Thing.CreatureKind, anim: ActionAnimName) ?*const DirectionalSpriteAnim {
    var creature_name: ?CreatureSpriteName = std.meta.stringToEnum(CreatureSpriteName, @tagName(creature_kind));
    if (creature_name == null) {
        if (creature_kind == .player) {
            creature_name = .wizard;
        } else {
            creature_name = .creature;
        }
    }
    if (self.creature_dir_anims.get(creature_name.?).get(anim)) |ref| {
        return ref.getConst();
    } else if (self.creature_dir_anims.get(.creature).get(anim)) |ref| {
        return ref.getConst();
    } else if (self.creature_dir_anims.get(creature_name.?).get(.idle)) |ref| {
        return ref.getConst();
    }
    return null;
}

pub fn reloadSounds(self: *Data) Error!void {
    const plat = App.getPlat();
    for (self.sounds.slice()) |*s| {
        s.deinit();
    }
    self.sounds.clear();

    var file_it = try plat.iterateAssets("", &[_][]const u8{".wav"});
    defer file_it.deinit();
    while (try file_it.next()) |next| {
        defer next.deinit(file_it);
        const sound = Sound{
            .sound = try plat.loadSound(next.path),
        };
        const asset = self.putAsset(Sound, &sound, filenameToAssetName(next.basename));
        Log.info("Loaded sound: {s}", .{asset.data_ref.name.constSlice()});
    }
}

pub fn loadSpriteSheetFromJsonString(data: *Data, sheet_filename: []const u8, json_string: []u8, assets_rel_dir_path: []const u8) Error!*SpriteSheet {
    const plat = App.getPlat();
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, json_string);
    var tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = json_string.len }) catch return Error.ParseFail;
    // TODO I guess tree just leaks rn? use arena?

    const meta = tree.object.get("meta").?.object;
    const image_filename = meta.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_rel_dir_path, image_filename });

    var it_dot = std.mem.tokenizeScalar(u8, sheet_filename, '.');
    const sheet_name = it_dot.next().?;

    var sheet = SpriteSheet{};
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
            .name = try @TypeOf(sheet.tags[0].name).fromSlice(name),
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
                    if (cel.object.get("data")) |cel_data| {
                        var it_data = std.mem.tokenizeScalar(u8, cel_data.string, ';');
                        while (it_data.next()) |item| {
                            var it_eq = std.mem.tokenizeScalar(u8, item, '=');
                            const key = it_eq.next().?;
                            const val = it_eq.next().?;
                            var m = SpriteSheet.Meta{};
                            m.name = @TypeOf(m.name).fromSlice(key) catch {
                                Log.warn("Fail to parse spritesheet meta name. spritesheet: \"{s}\" item: \"{s}\"", .{ sheet_name, item });
                                continue;
                            };
                            blk: {
                                vecf_blk: {
                                    var v: V2f = undefined;
                                    _ = V2f.parse(val, &v) catch break :vecf_blk;
                                    m.data = .{ .vecf = v };
                                    break :blk;
                                }
                                int_blk: {
                                    const int = std.fmt.parseInt(i64, val, 0) catch break :int_blk;
                                    m.data = .{ .int = int };
                                    break :blk;
                                }
                                float_blk: {
                                    const float = std.fmt.parseFloat(f32, val) catch break :float_blk;
                                    m.data = .{ .float = float };
                                    break :blk;
                                }
                                m.data = .{ .string = @TypeOf(m.data.string).fromSlice(val) catch {
                                    Log.warn("Fail to parse spritesheet meta value. spritesheet: \"{s}\" item: \"{s}\"", .{ sheet_name, item });
                                    continue;
                                } };
                            }
                            try sheet_meta.append(m);
                        }
                    }
                }
            }
        }
    }
    sheet.meta = try sheet_meta.toOwnedSlice();

    return data.putAsset(SpriteSheet, &sheet, sheet_name);
}

pub fn reloadSpriteSheets(self: *Data) Error!void {
    const plat = App.getPlat();
    for (self.spritesheets.slice()) |*s| {
        s.deinit();
    }
    self.spritesheets.clear();

    var file_it = try plat.iterateAssets("", &[_][]const u8{".json"});
    defer file_it.deinit();
    while (try file_it.next()) |next| {
        defer next.deinit(file_it);
        if (self.loadSpriteSheetFromJsonString(next.basename, next.owned_string, next.subdir)) |spritesheet| {
            Log.info("Loaded spritesheet: {s}", .{spritesheet.data_ref.name.constSlice()});
        } else |err| {
            Log.err("Failed load spritesheet: {s}. Error: {any}", .{ next.basename, err });
        }
    }

    self.item_icons = try @TypeOf(self.item_icons).init(self.getByName(SpriteSheet, "item_icons").?);
    self.misc_icons = try @TypeOf(self.misc_icons).init(self.getByName(SpriteSheet, "misc-icons").?);
    self.spell_icons = try @TypeOf(self.spell_icons).init(self.getByName(SpriteSheet, "spell-icons").?);
    self.text_icons = try @TypeOf(self.text_icons).initCropped(self.getByName(SpriteSheet, "small_text_icons").?, .magenta);
    self.card_sprites = try @TypeOf(self.card_sprites).init(self.getByName(SpriteSheet, "card").?);
    self.card_mana_cost = try @TypeOf(self.card_mana_cost).initCropped(self.getByName(SpriteSheet, "card-mana-cost").?, .magenta);
}

pub fn loadTileSetFromJsonString(data: *Data, filename: []const u8, json_string: []u8, assets_rel_path: []const u8) Error!*TileSet {
    const plat = App.getPlat();
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, json_string);
    const _tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = json_string.len }) catch return Error.ParseFail;
    var tree = _tree.object;
    // TODO I guess tree just leaks rn? use arena?

    const image_filename = tree.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_rel_path, image_filename });

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

    const tileset_name = filenameToAssetName(filename);
    const tileset: *TileSet = data.allocAsset(TileSet, tileset_name);
    const ref = tileset.data_ref;
    tileset.* = .{
        .data_ref = ref,
        .sheet_dims = sheet_dims,
        .tile_dims = tile_dims,
        // TODO spritesheet
        .texture = try plat.loadTexture(image_path),
    };
    assert(tileset.texture.dims.eql(image_dims));

    try tileset.tiles.resize(u.as(usize, tileset.sheet_dims.x * tileset.sheet_dims.y));
    if (tree.get("tiles")) |tiles| {
        for (tiles.array.items) |t| {
            const id = t.object.get("id").?.integer;
            const idx = u.as(usize, id);
            const props = t.object.get("properties").?.array;
            var prop = TileSet.TileProperties{};
            for (props.items) |p| {
                const prop_name = p.object.get("name").?.string;
                const val = p.object.get("value").?.string;
                const type_info = @typeInfo(TileSet.TileProperties);
                inline for (type_info.@"struct".fields) |f| {
                    if (std.mem.eql(u8, prop_name, f.name)) {
                        var prop_it = std.mem.tokenizeScalar(u8, val, ',');
                        var c_i: usize = 0;
                        while (prop_it.next()) |c| {
                            const set: bool = if (c[0] == '0') false else true;
                            @field(prop, f.name).getPtr(@enumFromInt(c_i)).* = set;
                            c_i += 1;
                        }
                    }
                }
            }
            assert(idx < tileset.tiles.len);
            tileset.tiles.buffer[idx] = prop;
        }
    }

    return tileset;
}

pub fn reloadTileSets(self: *Data) Error!void {
    const plat = App.getPlat();

    for (self.tilesets.slice()) |*t| {
        t.deinit();
    }
    self.tilesets.clear();

    var file_it = try FileWalkerIterator("maps/tilesets", ".tsj").init(plat.heap);
    defer file_it.deinit();

    while (try file_it.next()) |e| {
        defer e.deinit(plat.heap);
        const tileset = try self.loadTileSetFromJsonString(e.basename, e.owned_string, "maps/tilesets");
        Log.info("Loaded tileset: {s}", .{tileset.data_ref.name.constSlice()});
    }
}

pub fn loadTileMapFromJsonString(data: *Data, filename: []const u8, json_string: []u8) Error!*TileMap {
    const plat = App.getPlat();
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, json_string);
    const _tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = json_string.len }) catch return Error.ParseFail;
    var tree = _tree.object;
    // TODO I guess tree just leaks rn? use arena?

    // TODO use?
    const tile_dims = V2i.iToV2i(
        i64,
        tree.get("tilewidth").?.integer,
        tree.get("tileheight").?.integer,
    );
    _ = tile_dims;
    const map_dims = V2i.iToV2i(
        i64,
        tree.get("width").?.integer,
        tree.get("height").?.integer,
    );
    const game_dims = map_dims.sub(v2i(1, 1));

    const tilemap_name = filenameToAssetName(filename);
    const tilemap: *TileMap = data.allocAsset(TileMap, tilemap_name);
    const ref = tilemap.data_ref;
    tilemap.* = .{
        .data_ref = ref,
        .dims_tiles = map_dims,
        .dims_game = game_dims,
        .rect_dims = map_dims.toV2f().scale(TileMap.tile_sz_f),
    };

    var game_tile_coord: V2i = .{};
    for (0..u.as(usize, tilemap.dims_game.x * tilemap.dims_game.y)) |_| {
        tilemap.game_tiles.append(.{ .coord = game_tile_coord }) catch unreachable;
        game_tile_coord.x += 1;
        if (game_tile_coord.x >= tilemap.dims_game.x) {
            game_tile_coord.x = 0;
            game_tile_coord.y += 1;
        }
    }
    if (tree.get("properties")) |_props| {
        const props = _props.array;
        for (props.items) |p| {
            const p_name = p.object.get("name").?.string;
            if (std.mem.eql(u8, p_name, "room_kind")) {
                const kind_str = p.object.get("value").?.string;
                tilemap.kind = std.meta.stringToEnum(RoomKind, kind_str).?;
                continue;
            }
        }
    }
    {
        // get tilesets without looking them up yet
        const tilesets = tree.get("tilesets").?.array;
        for (tilesets.items) |ts| {
            const first_gid = ts.object.get("firstgid").?.integer;
            const tileset_path = ts.object.get("source").?.string;
            const tileset_file_name = std.fs.path.basename(tileset_path);
            const tileset_name = tileset_file_name[0..(tileset_file_name.len - 4)];
            try tilemap.tilesets.append(.{
                .ref = Ref(TileSet).init(tileset_name),
                .first_gid = u.as(usize, first_gid),
            });
        }
    }
    {
        const startsWith = std.mem.startsWith;
        const layers = tree.get("layers").?.array;
        var above_objects = false;
        for (layers.items) |_layer| {
            const layer = _layer.object;
            const visible = layer.get("visible").?.bool;
            if (!visible) continue;
            const kind = layer.get("type").?.string;
            if (std.mem.eql(u8, kind, "tilelayer")) {
                var tile_layer = TileMap.TileLayer{
                    .above_objects = above_objects,
                };
                // TODO x,y,width,height?
                const layer_data = layer.get("data").?.array;
                for (layer_data.items) |d| {
                    const tile_gid = d.integer;
                    try tile_layer.tiles.append(.{
                        .idx = u.as(TileMap.TileIndex, tile_gid),
                    });
                }
                try tilemap.tile_layers.append(tile_layer);
            } else if (std.mem.eql(u8, kind, "objectgroup")) {
                //const group_name = layer.get("name").?.string;
                const objects = layer.get("objects").?.array;
                above_objects = true;
                for (objects.items) |_obj| {
                    const obj = _obj.object;
                    const obj_pos = v2f(
                        u.as(f32, switch (obj.get("x").?) {
                            .float => |f| f,
                            .integer => |i| u.as(f64, i),
                            else => return Error.ParseFail,
                        }),
                        u.as(f32, switch (obj.get("y").?) {
                            .float => |f| f,
                            .integer => |i| u.as(f64, i),
                            else => return Error.ParseFail,
                        }),
                    ).scale(core.game_sprite_scaling).sub(TileMap.tile_dims_2);
                    const obj_name = obj.get("name").?.string;

                    if (obj.get("point")) |p| {
                        assert(p.bool == true);
                        if (!obj.get("visible").?.bool) continue;

                        // TODO clean up arrgh
                        // transform map pixel pos to game tile pixel pos
                        if (startsWith(u8, obj_name, "creature")) {
                            var it = std.mem.tokenizeScalar(u8, obj_name, ':');
                            _ = it.next() orelse return Error.ParseFail;
                            const creature_kind_str = it.next() orelse return Error.ParseFail;
                            try tilemap.creatures.append(.{
                                .kind = std.meta.stringToEnum(Thing.CreatureKind, creature_kind_str) orelse return Error.ParseFail,
                                .pos = obj_pos,
                            });
                        } else if (startsWith(u8, obj_name, "exit")) {
                            const exit = TileMap.ExitDoor{
                                .pos = obj_pos,
                            };
                            try tilemap.exits.append(exit);
                        } else if (startsWith(u8, obj_name, "spawn")) {
                            var spawn = TileMap.SpawnPos{ .pos = obj_pos };
                            if (obj.get("properties")) |_props| {
                                const props = _props.array;
                                for (props.items) |prop| {
                                    const p_name = prop.object.get("name").?.string;
                                    if (std.mem.eql(u8, p_name, "reward")) {
                                        spawn.reward = true;
                                    }
                                }
                            }
                            try tilemap.wave_spawns.append(spawn);
                        }
                    } else if (startsWith(u8, obj_name, "exitdoor")) {
                        const door_pos = obj_pos.sub(v2f(0, 32).scale(core.game_sprite_scaling));
                        const exit_pos = door_pos.add(v2f(16.5, 23.5).scale(core.game_sprite_scaling));
                        const exit = TileMap.ExitDoor{
                            .pos = exit_pos,
                            .door_pos = door_pos,
                            .door_rect = .{
                                .pos = door_pos.add(v2f(11, 5).scale(core.game_sprite_scaling)),
                                .dims = v2f(11, 19).scale(core.game_sprite_scaling),
                            },
                        };
                        try tilemap.exits.append(exit);
                    } else if (startsWith(u8, obj_name, "shop")) {
                        const spr_pos = obj_pos.sub(v2f(0, 89).scale(core.game_sprite_scaling));
                        const shop_pos = spr_pos.add(v2f(48, 46).scale(core.game_sprite_scaling));
                        const shop = TileMap.Shop{
                            .pos = shop_pos,
                            .spr_pos = spr_pos,
                        };
                        tilemap.shop = shop;
                    } else {
                        Log.err("Invalid map object found: \"{s}\"", .{obj_name});
                    }
                }
            }
        }
    }
    return tilemap;
}

pub fn tileIdxAndTileSetRefToTileProperties(_: *Data, tileset_ref: *const TileMap.TileSetRef, tile_idx: usize) ?Data.TileSet.TileProperties {
    if (tileset_ref.ref.tryGetConst()) |tileset| {
        assert(tile_idx >= tileset_ref.first_gid);
        const tileset_tile_idx = tile_idx - tileset_ref.first_gid;
        assert(tileset_tile_idx < tileset.tiles.len);
        return tileset.tiles.get(tileset_tile_idx);
    } else return null;
}

pub fn reloadTileMaps(self: *Data) Error!void {
    const plat = App.getPlat();
    self.tilemaps.clear();

    var file_it = try FileWalkerIterator("maps", ".tmj").init(plat.heap);
    defer file_it.deinit();

    while (try file_it.next()) |e| {
        defer e.deinit(plat.heap);
        var tilemap = try self.loadTileMapFromJsonString(e.basename, e.owned_string);
        // init tilemap refs
        for (tilemap.tilesets.slice()) |*ts_ref| {
            _ = ts_ref.ref.get();
        }
        // init game tiles
        for (tilemap.tile_layers.constSlice()) |*layer| {
            if (layer.above_objects) continue;
            var tile_coord: V2i = .{};
            for (layer.tiles.slice()) |*tile| {
                var props = blk: {
                    if (tilemap.tileIdxToTileSetRef(tile.idx)) |ref| {
                        break :blk self.tileIdxAndTileSetRefToTileProperties(ref, tile.idx);
                    }
                    break :blk null;
                };
                if (props) |*tile_props| {
                    inline for (std.meta.fields(TileSet.GameTileCorner)) |f| {
                        const corner: TileSet.GameTileCorner = @enumFromInt(f.value);
                        const dir = TileSet.GameTileCorner.dir_map.get(corner);
                        const game_tile_coord = tile_coord.add(dir);
                        if (tilemap.gameTileCoordToGameTile(game_tile_coord)) |game_tile| {
                            if (tile_props.colls.get(corner)) {
                                game_tile.coll_layers.insert(.wall);
                                game_tile.path_layers = TileMap.PathLayer.Mask.initEmpty();
                            }
                            if (tile_props.spikes.get(corner)) {
                                game_tile.coll_layers.insert(.spikes);
                                game_tile.path_layers.remove(.normal);
                            }
                        }
                    }
                }
                tile_coord.x += 1;
                if (tile_coord.x >= tilemap.dims_tiles.x) {
                    tile_coord.x = 0;
                    tile_coord.y += 1;
                }
            }
        }
        try tilemap.updateConnectedComponents();
        Log.info("Loaded tilemap: {s}", .{tilemap.data_ref.name.constSlice()});
    }
}

pub fn reloadShaders(self: *Data) Error!void {
    const plat = App.getPlat();
    for (self.shaders.slice()) |*s| {
        s.deinit();
    }
    self.shaders.clear();

    const list = [_]struct {
        vs: ?[]const u8 = null,
        fs: ?[]const u8 = null,
    }{
        .{ .fs = "tile_foreground_fade.fs" },
        .{ .fs = "fog_blur.fs" },
    };
    for (list) |s| {
        const shader = Shader{
            .shader = try plat.loadShader(s.vs, s.fs),
        };
        _ = self.putAsset(Shader, &shader, filenameToAssetName(s.fs orelse s.vs.?));
    }
}

pub fn reloadSpriteAnims(self: *Data) Error!void {
    self.spriteanims.clear();
    for (self.spritesheets.slice()) |*spritesheet| {
        for (spritesheet.tags, 0..) |tag, i| {
            const from = u.as(usize, tag.from_frame);
            const to = u.as(usize, tag.to_frame);
            var ticks_sum: i64 = 0;
            for (spritesheet.frames[from..(to + 1)]) |frame| {
                const frame_ticks = u.as(i32, core.ms_to_ticks(frame.duration_ms));
                ticks_sum += frame_ticks;
            }
            var anim = SpriteAnim{
                .sheet = spritesheet.data_ref,
                .tag_idx = i,
                .first_frame_idx = from,
                .last_frame_idx = to,
                .num_frames = to - from + 1,
                .dur_ticks = ticks_sum,
            };
            meta_blk: for (spritesheet.meta) |m| {
                const m_name = m.name.constSlice();
                //std.debug.print("Meta '{s}'\n", .{m_name});
                if (std.mem.eql(u8, m_name, "pivot-y")) {
                    const y = m.asf32() catch continue;
                    const x = u.as(f32, spritesheet.frames[0].size.x) * 0.5;
                    anim.origin = .{ .offset = v2f(x, y) };
                    continue;
                } else if (std.mem.startsWith(u8, m_name, "pt-")) {
                    const pt_name_str = m_name[3..];
                    if (std.meta.stringToEnum(sprites.SpriteAnim.PointName, pt_name_str)) |pt_name| {
                        if (std.meta.activeTag(m.data) == .vecf) {
                            anim.points.getPtr(pt_name).* = m.data.vecf.scale(core.game_sprite_scaling);
                        } else {
                            Log.warn("Spritesheet \"{s}\". Invalid Point data type \"{any}\" (expect vecf)", .{ spritesheet.data_ref.name.constSlice(), std.meta.activeTag(m.data) });
                        }
                    } else {
                        Log.warn("Spritesheet \"{s}\". Invalid Point.Name \"{s}\"", .{ spritesheet.data_ref.name.constSlice(), pt_name_str });
                    }
                }
                const event_info = @typeInfo(sprites.AnimEvent.Kind);
                inline for (event_info.@"enum".fields) |f| {
                    if (std.mem.eql(u8, m_name, f.name)) {
                        //std.debug.print("Adding event '{s}' on frame {}\n", .{ f.name, m.data.int });
                        anim.events.append(.{
                            .frame = u.as(i32, m.data.int),
                            .kind = @enumFromInt(f.value),
                        }) catch {
                            Log.err("Skipped adding anim event \"{s}\"; buffer full", .{f.name});
                        };
                        continue :meta_blk;
                    }
                }
            }

            const name = try u.bufPrintLocal("{s}-{s}", .{ spritesheet.data_ref.name.constSlice(), tag.name.constSlice() });
            const put_anim = self.putAsset(SpriteAnim, &anim, name);
            if (put_anim.data_ref.isDefault() and std.mem.endsWith(u8, put_anim.data_ref.name.constSlice(), "loop")) {
                self.spriteanim_default = put_anim.data_ref.idx.?;
            }
            Log.info("Got spriteanim: {s}", .{name});
        }
    }
    // directional anims
    self.directionalspriteanims.clear();
    for (self.spriteanims.slice()) |*spriteanim| {
        const spriteanim_name = spriteanim.data_ref.name.constSlice();
        const last_letter = spriteanim_name[spriteanim_name.len - 1 ..];
        const last_2letters = spriteanim_name[spriteanim_name.len - 2 ..];
        if (std.meta.stringToEnum(DirectionalSpriteAnim.Dir, last_letter) == null and std.meta.stringToEnum(DirectionalSpriteAnim.Dir, last_2letters) == null) {
            continue;
        }
        var dir: DirectionalSpriteAnim.Dir = undefined;
        var directional_spriteanim_name: []const u8 = undefined;
        for (DirectionalSpriteAnim.dir_suffixes, 0..) |dir_suffix, i| {
            if (std.mem.endsWith(u8, spriteanim_name, dir_suffix)) {
                directional_spriteanim_name = spriteanim_name[0..(spriteanim_name.len - dir_suffix.len)];
                dir = @enumFromInt(i);
                break;
            }
        } else continue;

        var dir_spriteanim: *DirectionalSpriteAnim = if (self.getByName(DirectionalSpriteAnim, directional_spriteanim_name)) |a| a else self.allocAsset(DirectionalSpriteAnim, directional_spriteanim_name);
        const dir_slot = dir_spriteanim.anims_by_dir.getPtr(dir);
        if (dir_slot.* != null) {
            Log.warn("Same anim direction found for \"{s}\", dir: \"{any}\"", .{ directional_spriteanim_name, dir });
        }
        dir_slot.* = spriteanim.data_ref;
    }
    for (self.directionalspriteanims.slice()) |*dir_spriteanim| {
        dir_spriteanim.num_dirs = 0;
        for (0..DirectionalSpriteAnim.max_dirs) |i| {
            const dir: DirectionalSpriteAnim.Dir = @enumFromInt(i);
            const slot = dir_spriteanim.anims_by_dir.getPtr(dir);
            if (slot.*) |anim_ref| {
                dir_spriteanim.num_dirs += 1;

                // try creating flipped anim if opposite slot is empty
                const opp_dir = dir.getOpposite();
                const opp_slot = dir_spriteanim.anims_by_dir.getPtr(opp_dir);
                if (opp_slot.* != null) continue;
                const anim: *SpriteAnim = self.getByIdx(SpriteAnim, anim_ref.idx.?).?;
                const flip_x = anim.can_flip_x and dir != .N and dir != .S;
                const flip_y = anim.can_flip_y and dir != .E and dir != .W;
                if (!flip_x and !flip_y) continue;

                const opp_name = u.bufPrintLocal(
                    "{s}-{s}",
                    .{ dir_spriteanim.data_ref.name.constSlice(), u.enumToString(@TypeOf(opp_dir), opp_dir) },
                ) catch unreachable;
                const opp_anim = self.allocAsset(SpriteAnim, opp_name);
                // copy the anim, but retain the new data ref
                const opp_anim_data_ref = opp_anim.data_ref;
                opp_anim.* = anim.*;
                opp_anim.data_ref = opp_anim_data_ref;
                opp_anim.flip_x = flip_x;
                opp_anim.flip_y = flip_y;
                opp_slot.* = opp_anim.data_ref;
                Log.info("Created flipped anim: {s}", .{opp_anim.data_ref.name.constSlice()});
                // NOTE num_dirs will get incremented later in the loop
            }
        }
        if (dir_spriteanim.data_ref.isDefault()) {
            self.directionalspriteanim_default = dir_spriteanim.data_ref.idx.?;
        }
        Log.info(
            "Got directionalspriteanim: {s} with {} dir{s}",
            .{
                dir_spriteanim.data_ref.name.constSlice(),
                dir_spriteanim.num_dirs,
                if (dir_spriteanim.num_dirs > 1) "s" else "",
            },
        );
    }
    // caches
    self.creature_dir_anims = CreatureDirAnimCache.initFill(DirAnimCache.initFill(null));
    for (u.enumValueList(CreatureSpriteName)) |creature_name| {
        for (u.enumValueList(ActionAnimName)) |action_name| {
            for (0..2) |i| {
                // TODO clean up assets to use a single form
                const dir_sprite_name = (if (i == 0)
                    u.bufPrintLocal("{s}-{s}", .{ @tagName(creature_name), @tagName(action_name) })
                else
                    u.bufPrintLocal("{s}-{s}-{s}", .{ @tagName(creature_name), @tagName(action_name), @tagName(action_name) })) catch {
                    Log.warn("{s}:{}: Fail to format buf", .{ @src().file, @src().line });
                    continue;
                };
                var ref = Ref(DirectionalSpriteAnim).init(dir_sprite_name);
                if (ref.tryGet()) |anim| {
                    self.creature_dir_anims.getPtr(creature_name).getPtr(action_name).* = anim.data_ref;
                }
            }
        }
    }
}

pub fn loadFonts(self: *Data) Error!void {
    const plat = App.getPlat();
    // TODO deinit?
    const fontsu = [_]struct { FontName, []const u8, u32 }{
        .{ .alagard, "alagard.png", 16 },
        .{ .pixeloid, "PixeloidSans.ttf", 11 },
        .{ .seven_x_five, "7x5.ttf", 8 },
    };
    for (fontsu) |f| {
        self.fonts.getPtr(f[0]).* = plat.loadPixelFont(f[1], f[2]) catch {
            Log.err("Failed to load font: {any}", .{f[0]});
            continue;
        };
        Log.info("Loaded font: {any}", .{f[0]});
    }
}

pub fn reload(self: *Data) Error!void {
    self.reloadSpriteSheets() catch |err| Log.warn("failed to load all sprites: {any}", .{err});
    self.reloadSounds() catch |err| Log.warn("failed to load all sounds: {any}", .{err});
    inline for (@typeInfo(creatures.Kind).@"enum".fields) |f| {
        const kind: creatures.Kind = @enumFromInt(f.value);
        self.creature_protos.getPtr(kind).* = creatures.proto_fns.get(kind)();
    }
    self.reloadTileSets() catch |err| Log.warn("failed to load all tilesets: {any}", .{err});
    self.reloadTileMaps() catch |err| Log.warn("failed to load all tilemaps: {any}", .{err});
    inline for (std.meta.fields(RoomKind)) |f| {
        const kind: RoomKind = @enumFromInt(f.value);
        const tilemaps = self.room_kind_tilemaps.getPtr(kind);
        tilemaps.clear();
        for (self.tilemaps.constSlice()) |*tilemap| {
            if (tilemap.kind == kind) {
                try tilemaps.append(tilemap.data_ref.idx.?);
            }
        }
    }
    self.reloadShaders() catch |err| Log.warn("failed to load all shaders: {any}", .{err});
    self.loadFonts() catch |err| Log.warn("failed to load all fonts: {any}", .{err});
    self.reloadSpriteAnims() catch |err| Log.warn("failed to load all spriteanims: {any}", .{err});
}
