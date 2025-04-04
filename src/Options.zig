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
const Log = App.Log;
const Run = @import("Run.zig");
const Data = @import("Data.zig");
const menuUI = @import("menuUI.zig");
const ImmUI = @import("ImmUI.zig");
const player = @import("player.zig");
const icon_text = @import("icon_text.zig");
const Options = @This();

const ui_el_text_padding: V2f = v2f(5, 5);

pub const Slider = struct {
    grabbed: bool = false,

    pub fn update(self: *Slider, cmd_buf: *ImmUI.CmdBuf, pos: V2f, width: f32, curr: f32, min: f32, max: f32, step: f32) Error!?f32 {
        const plat = App.getPlat();
        const ui_scaling = plat.ui_scaling;
        const mouse_pos = plat.getMousePosScreen();
        const mouse_clicked = plat.input_buffer.mouseBtnIsJustPressed(.left);
        const mouse_down = plat.input_buffer.mouseBtnIsDown(.left);
        const range = max - min;
        const f = curr / range;
        const handle_radius: f32 = 7 * ui_scaling;
        var handle_pos = v2f(pos.x + f * width, pos.y);
        var new_val = curr;

        if (!self.grabbed) {
            if (mouse_clicked) {
                const test_rect = geom.Rectf{ .pos = pos.sub(V2f.splat(handle_radius)), .dims = v2f(width + handle_radius, handle_radius * 2) };
                if (mouse_pos.dist(handle_pos) <= handle_radius or geom.pointIsInRectf(mouse_pos, test_rect)) {
                    self.grabbed = true;
                }
            }
        }
        if (self.grabbed) {
            if (mouse_down) {
                handle_pos.x = utl.clampf(mouse_pos.x, pos.x, pos.x + width);
                const new_f = (handle_pos.x - pos.x) / width;
                new_val = @round((new_f * range + min) / step) * step;
            } else {
                self.grabbed = false;
            }
        }
        cmd_buf.appendAssumeCapacity(.{ .rect = .{
            .pos = pos.sub(V2f.splat(handle_radius * 0.5)),
            .dims = v2f(width + handle_radius, handle_radius),
            .opt = .{
                .fill_color = .gray,
                .edge_radius = 1,
            },
        } });
        cmd_buf.appendAssumeCapacity(.{ .circle = .{
            .pos = handle_pos,
            .radius = handle_radius,
            .opt = .{
                .fill_color = .lightgray,
                .smoothing = .bilinear,
            },
        } });
        if (new_val != curr) {
            return new_val;
        }
        return null;
    }
};

pub const DropdownMenu = struct {
    selected_idx: usize = 0,
    is_open: bool = false,

    pub fn update(self: *DropdownMenu, cmd_buf: *ImmUI.CmdBuf, pos: V2f, z: f32, strings: []const []const u8) Error!?usize {
        const plat = App.getPlat();
        const data = App.getData();
        const font = data.fonts.get(.pixeloid);
        const text_opt = draw.TextOpt{
            .font = font,
            .size = font.base_size * utl.as(u32, plat.ui_scaling),
            .color = .white,
            .smoothing = .none,
        };
        const ui_scaling = plat.ui_scaling;
        const mouse_pos = plat.getMousePosScreen();
        const mouse_clicked = plat.input_buffer.mouseBtnIsJustPressed(.left);
        const el_padding = el_text_padding.scale(ui_scaling);
        var ret: ?usize = null;

        var dropdown_el_pos = pos;
        var dropdown_el_dims = V2f{};
        for (strings) |str| {
            const str_dims = try plat.measureText(str, text_opt);
            if (str_dims.x > dropdown_el_dims.x) {
                dropdown_el_dims.x = str_dims.x;
            }
            if (str_dims.y > dropdown_el_dims.y) {
                dropdown_el_dims.y = str_dims.y;
            }
        }
        dropdown_el_dims = dropdown_el_dims.add(el_padding.scale(2));
        // selected
        cmd_buf.appendAssumeCapacity(.{ .rect = .{
            .pos = dropdown_el_pos,
            .z = z,
            .dims = dropdown_el_dims,
            .opt = .{ .fill_color = el_bg_color_selected },
        } });
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = dropdown_el_pos.add(el_padding),
            .z = z,
            .text = ImmUI.initLabel(strings[self.selected_idx]),
            .opt = text_opt,
        } });
        // open/close dropdown
        var mouse_clicked_inside_menu = false;
        if (mouse_clicked and geom.pointIsInRectf(mouse_pos, .{ .pos = dropdown_el_pos, .dims = dropdown_el_dims })) {
            self.is_open = !self.is_open;
            mouse_clicked_inside_menu = true;
        }
        dropdown_el_pos.y += dropdown_el_dims.y;
        if (self.is_open) {
            for (strings, 0..) |el_string, i| {
                const hovered = geom.pointIsInRectf(mouse_pos, .{ .pos = dropdown_el_pos, .dims = dropdown_el_dims });
                if (i == self.selected_idx) continue;
                cmd_buf.appendAssumeCapacity(.{ .rect = .{
                    .pos = dropdown_el_pos,
                    .z = z,
                    .dims = dropdown_el_dims,
                    .opt = .{
                        .fill_color = if (hovered) el_bg_color_hovered else el_bg_color,
                    },
                } });
                cmd_buf.appendAssumeCapacity(.{ .label = .{
                    .pos = dropdown_el_pos.add(el_padding),
                    .z = z,
                    .text = ImmUI.initLabel(el_string),
                    .opt = text_opt,
                } });
                if (mouse_clicked and hovered) {
                    ret = i;
                    self.is_open = false;
                    mouse_clicked_inside_menu = true;
                }
                dropdown_el_pos.y += dropdown_el_dims.y;
            }
        }
        if (mouse_clicked and !mouse_clicked_inside_menu) {
            self.is_open = false;
        }
        if (ret) |idx| {
            self.selected_idx = idx;
        }
        return ret;
    }
};

pub const Display = struct {
    pub const ResLabel = utl.BoundedString(16);
    pub const max_resolutions = 10;
    //monitor: i32 = 0, // TODO?
    mode: enum {
        windowed,
        borderless,
        fullscreen,
    } = .windowed,
    resolutions_strings: std.BoundedArray(ResLabel, max_resolutions) = .{},
    resolutions: std.BoundedArray(V2i, max_resolutions) = .{},
    selected_resolution: V2i = .{},
    dropdown: DropdownMenu = .{},
    custom_resolution: bool = false, // if true, the 0th resolution in the list is "custom" (manual resize)
    //vsync: bool = false, // TODO?
    pub const OptionSerialize = struct {
        mode: void,
        selected_resolution: void,
    };
};

pub const Controls = struct {
    pub const CastMethod = enum {
        left_click,
        quick_release,
        quick_press,
        pub const strings = std.EnumArray(CastMethod, []const u8).init(.{
            .left_click = "Left mouse click",
            .quick_release = "Release hotkey",
            .quick_press = "Press hotkey",
        });
    };
    cast_method: CastMethod = .left_click,
    dropdown: DropdownMenu = .{
        .selected_idx = @intFromEnum(CastMethod.left_click),
    },
    //auto_self_cast: bool = true, // TODO?
    input_bindings: std.BoundedArray(InputBinding, 32) = .{},
    // serialized e.g.:
    // controls.input_bindings[0].keyboard_key = .q

    pub const OptionSerialize = struct {
        cast_method: void,
    };

    // generic binding for mouse/keyboard controls
    // may have a ui button associated, or not
    pub const InputBinding = struct {
        pub const max_input_bindings = 2;
        pub const Label = utl.BoundedString(16);
        pub const Kind = enum {
            mouse_button,
            keyboard_key,
            // controller button, axis etc...
        };
        pub const KindData = union(InputBinding.Kind) {
            pub const max_input_data_chars = 8;
            mouse_button: core.MouseButton,
            keyboard_key: core.Key,
            pub const key_strings = blk: {
                //var buf: [8]u8 = undefined;
                var ret = std.EnumArray(core.Key, []const u8).initDefault("<>", .{
                    .backtick = "`",
                    .space = "SPC",
                    .apostrophe = "'",
                    .comma = ",",
                    .minus = "-",
                    .period = ".",
                    .semicolon = ";",
                    .equals = "=",
                    .slash = "/",
                    .backslash = "\\",
                    .escape = "ESC",
                });
                //TODO glyphs
                ret.getPtr(.left).* = "left";
                ret.getPtr(.right).* = "right";
                ret.getPtr(.up).* = "up";
                ret.getPtr(.down).* = "down";
                for (0..12) |i| {
                    const k: core.Key = @enumFromInt(@intFromEnum(core.Key.f1) + i);
                    ret.getPtr(k).* = std.fmt.comptimePrint("f{}", .{i + 1});
                }
                for ('a'..('z' + 1)) |char| {
                    const k = std.meta.stringToEnum(core.Key, &.{char}).?;
                    ret.getPtr(k).* = std.fmt.comptimePrint("{c}", .{utl.as(u8, std.ascii.toUpper(char))});
                }
                for (core.Key.numbers, '0'..('9' + 1)) |k, char| {
                    ret.getPtr(k).* = std.fmt.comptimePrint("{c}", .{utl.as(u8, char)});
                }
                break :blk ret;
            };
            pub fn getIconText(self: InputBinding.KindData) []const u8 {
                return switch (self) {
                    .keyboard_key => |key| key_strings.get(key),
                    .mouse_button => |btn| switch (btn) {
                        .left => "LMB",
                        .right => "RMB",
                    },
                };
            }
        };
        pub const InputsArray = std.BoundedArray(InputBinding.KindData, max_input_bindings);
        pub const Command = union(enum) {
            action: player.Action.Id,
            stop_moving,
            pause,
            pause_menu,
            show_deck,
            show_help,
            // etc..?
            pub fn eql(self: Command, other: Command) bool {
                const my_tag = std.meta.activeTag(self);
                if (my_tag != std.meta.activeTag(other)) return false;
                if (my_tag == .action) {
                    return (self.action.eql(other.action));
                }
                return true;
            }
        };
        // what the player sees in Options
        slot_name: Label, // Spell 1, Spell 2, Attack, Move...
        // the player can change the binding(s) anytime
        inputs: InputsArray,
        // what does this input actually map to?
        // this way we can identify it elsewhere in the code (and save the index for later)
        command: InputBinding.Command,
        // mapping to this InputSlot, so an ActionSlot can find its input
        // TODO needed?
        //idx: usize = 0,

        pub fn init(name: []const u8, inputs: []const InputBinding.KindData, cmd: InputBinding.Command) InputBinding {
            return .{
                .slot_name = Label.fromSlice(name) catch unreachable,
                .inputs = InputsArray.fromSlice(inputs) catch unreachable,
                .command = cmd,
            };
        }
        pub fn initAction(name: []const u8, inputs: []const InputBinding.KindData, action_id: player.Action.Id) InputBinding {
            return InputBinding.init(name, inputs, .{ .action = action_id });
        }
        pub fn isJustPressed(self: *const InputBinding) bool {
            const plat = App.getPlat();
            for (self.inputs.constSlice()) |binding| {
                switch (binding) {
                    .keyboard_key => |k| {
                        return plat.input_buffer.keyIsJustPressed(k);
                    },
                    .mouse_button => |m| {
                        return plat.input_buffer.mouseBtnIsJustPressed(m);
                    },
                }
            }
            return false;
        }
    };

    pub fn makeDefaultInputBindings(buf: []InputBinding) []InputBinding {
        var input_bindings = std.ArrayListUnmanaged(InputBinding).initBuffer(buf);
        input_bindings.appendSliceAssumeCapacity(&.{
            //InputBinding.initAction(
            //    "Move",
            //    &.{.{ .mouse_button = .right }},
            //    .{ .kind = .move },
            //),
            //InputBinding.initAction(
            //    "Attack",
            //    &.{ .{ .mouse_button = .right }, .{ .keyboard_key = .a } },
            //    .{ .kind = .attack },
            //),
            //InputBinding.initAction(
            //    "Discard",
            //    &.{.{ .keyboard_key = .d }},
            //    .{ .kind = .discard },
            //),
        });
        const spell_default_keys = &[_]core.Key{ .q, .w, .e, .r };
        for (spell_default_keys, 0..) |key, i| {
            input_bindings.appendAssumeCapacity(
                InputBinding.initAction(
                    utl.bufPrintLocal("Spell {}", .{i + 1}) catch unreachable,
                    &.{.{ .keyboard_key = key }},
                    .{ .kind = .spell, .slot_idx = i },
                ),
            );
        }
        const item_default_keys = &[_]core.Key{ .one, .two, .three, .four };
        for (item_default_keys, 0..) |key, i| {
            input_bindings.appendAssumeCapacity(
                InputBinding.initAction(
                    utl.bufPrintLocal("Item {}", .{i + 1}) catch unreachable,
                    &.{.{ .keyboard_key = key }},
                    .{ .kind = .item, .slot_idx = i },
                ),
            );
        }
        input_bindings.appendSliceAssumeCapacity(&.{
            InputBinding.init(
                "Stop Moving",
                &.{.{ .keyboard_key = .s }},
                .stop_moving,
            ),
            InputBinding.init(
                "Pause/Unpause",
                &.{.{ .keyboard_key = .space }},
                .pause,
            ),
            InputBinding.init(
                "Open Menu",
                &.{.{ .keyboard_key = .escape }},
                .pause_menu,
            ),
            InputBinding.init(
                "Show Deck",
                &.{.{ .keyboard_key = .n }},
                .show_deck,
            ),
        });
        return input_bindings.items;
    }

    pub fn getBindingByCommand(self: *Controls, cmd: InputBinding.Command) ?*InputBinding {
        for (self.input_bindings.slice()) |*binding| {
            if (binding.command.eql(cmd)) {
                return binding;
            }
        }
        return null;
    }

    pub fn init(self: *Controls) void {
        const inputs = Controls.makeDefaultInputBindings(&self.input_bindings.buffer);
        self.input_bindings.resize(inputs.len) catch unreachable;
    }
};

pub const Audio = struct {
    sfx_volume: f32 = 1,
    sfx_slider: Slider = .{},
    music_volume: f32 = 1,
    music_slider: Slider = .{},

    pub const OptionSerialize = struct {
        sfx_volume: void,
        music_volume: void,
    };
};

pub const Kind = enum {
    controls,
    display,
    audio,
};

controls: Controls = .{},
display: Display = .{},
audio: Audio = .{},
other: struct {
    is_first_play: bool = true,
    pub const OptionSerialize = struct {
        is_first_play: void,
    };
} = .{},
kind_selected: Kind = .controls,

pub fn serialize(data: anytype, prefix: []const u8, file: std.fs.File, _: *Platform) void {
    const T = @TypeOf(data);
    inline for (std.meta.fields(T.OptionSerialize)) |s_field| {
        const field = utl.typeFieldByName(T, s_field.name);
        switch (@typeInfo(field.type)) {
            .bool => {
                const line = utl.bufPrintLocal("{s}.{s}={}\n", .{ prefix, field.name, @field(data, field.name) }) catch break;
                file.writeAll(line) catch break;
            },
            .float => {
                const line = utl.bufPrintLocal("{s}.{s}={d:0.2}\n", .{ prefix, field.name, @field(data, field.name) }) catch break;
                file.writeAll(line) catch break;
            },
            .@"enum" => |info| {
                file.writeAll("# Possible values:\n") catch {};
                inline for (info.fields) |efield| {
                    const e = utl.bufPrintLocal("# {s}\n", .{efield.name}) catch break;
                    file.writeAll(e) catch {};
                }
                const val_as_string = @tagName(@field(data, field.name));
                const line = utl.bufPrintLocal("{s}.{s}={s}\n", .{ prefix, field.name, val_as_string }) catch break;
                file.writeAll(line) catch break;
            },
            .@"struct" => {
                if (@hasDecl(field.type, "OptionSerialize")) {
                    serialize(@field(data, field.name), prefix ++ "." ++ field.name, file);
                } else if (comptime std.mem.eql(u8, utl.typeBaseName(field.type), "V2i")) {
                    const v: V2i = @field(data, field.name);
                    const line = utl.bufPrintLocal("{s}.{s}={d}\n", .{ prefix, field.name, v }) catch break;
                    file.writeAll(line) catch break;
                } else {
                    @compileError("Idk how to serialize this struct");
                }
            },
            else => continue,
        }
    }
}

pub fn writeToTxt(self: *const Options, plat: *Platform) void {
    var cwd = std.fs.openDirAbsolute(plat.user_data_path, .{}) catch {
        plat.log.warn("WARNING: Failed to open cwd {s}", .{plat.user_data_path});
        return;
    };
    defer cwd.close();
    const options_file = cwd.createFile("options.txt", .{}) catch {
        plat.log.warn("WARNING: Failed to open options.txt for writing", .{});
        return;
    };
    defer options_file.close();
    serialize(self.controls, "controls", options_file, plat);
    serialize(self.display, "display", options_file, plat);
    serialize(self.audio, "audio", options_file, plat);
    serialize(self.other, "other", options_file, plat);
}

pub fn initDefault(plat: *Platform) Options {
    var ret = Options{};

    // display
    {
        const m_info = plat.getMonitorIdxAndDims();
        const m_res = m_info.dims;
        var idx: usize = 0;
        for (1..100) |i| {
            const dims_4x3 = core.min_resolution.scale(utl.as(i32, i));
            const dims_16x9 = core.min_wide_resolution.scale(utl.as(i32, i));
            var done = false;
            for (&[_]V2i{ dims_4x3, dims_16x9 }) |dims| {
                if (dims.x > m_res.x) {
                    done = true;
                    continue;
                }
                if (ret.display.resolutions.len >= ret.display.resolutions.buffer.len) {
                    // if full, treat as a circular buffer and overwrite smaller ones
                    if (idx >= ret.display.resolutions.buffer.len) {
                        idx = 0;
                    }
                    ret.display.resolutions.buffer[idx] = dims;
                    idx += 1;
                } else {
                    ret.display.resolutions.appendAssumeCapacity(dims);
                }
            }
            if (done) break;
        }

        if (ret.display.resolutions.len >= ret.display.resolutions.buffer.len) {
            // if full, treat as a circular buffer and overwrite smaller ones
            if (idx >= ret.display.resolutions.buffer.len) {
                idx = 0;
            }
            ret.display.resolutions.buffer[idx] = m_res;
            idx += 1;
        } else {
            ret.display.resolutions.appendAssumeCapacity(m_res);
        }
        // sort em
        const Sort = struct {
            pub fn cmp(_: void, lhs: V2i, rhs: V2i) bool {
                return lhs.x < rhs.x;
            }
        };
        std.sort.pdq(V2i, ret.display.resolutions.slice(), {}, Sort.cmp);
        // Pick the third one if possible by default, i.e. not the smallest cos thats really small
        ret.display.selected_resolution = ret.display.resolutions.get(@min(ret.display.resolutions.len, 3) - 1);

        for (ret.display.resolutions.constSlice()) |res| {
            ret.display.resolutions_strings.append(
                Display.ResLabel.fromSlice(
                    utl.bufPrintLocal("{d}x{d}", .{ res.x, res.y }) catch continue,
                ) catch continue,
            ) catch break;
        }
    }

    ret.controls.init();

    return ret;
}

fn setValByName(plat: *Platform, T: type, data: *T, key: []const u8, val: []const u8) void {
    // check if we're at the leaf of the key  (key could be like controls.foo.bar, we do the actual setting at bar)
    switch (@typeInfo(T)) {
        .@"struct", .@"union" => {
            for (key, 0..) |c, i| {
                if (c == '.') {
                    const first_part_of_key = key[0..i];
                    const rest_of_key = key[i + 1 ..];
                    inline for (std.meta.fields(T)) |field| {
                        if (std.mem.eql(u8, first_part_of_key, field.name)) {
                            setValByName(plat, field.type, &@field(data, field.name), rest_of_key, val);
                            return;
                        }
                    } else {
                        plat.log.warn("{s}: Couldn't find key: \"{s}\"", .{ @src().fn_name, key });
                    }
                    return;
                }
            }
        },
        else => {},
    }

    switch (@typeInfo(T)) {
        .bool => {
            if (std.mem.eql(u8, val, "true")) {
                data.* = true;
            } else if (std.mem.eql(u8, val, "false")) {
                data.* = false;
            } else {
                plat.log.warn("{s}: Couldn't parse bool. key: \"{s}\", val: \"{s}\", type \"{s}\"", .{ @src().fn_name, key, val, @typeName(T) });
            }
        },
        .float => {
            if (std.fmt.parseFloat(T, val)) |f| {
                data.* = f;
            } else |err| {
                plat.log.warn("{s}: {any}: Couldn't parse float. key: \"{s}\", val: \"{s}\", type \"{s}\"", .{ @src().fn_name, err, key, val, @typeName(T) });
            }
        },
        .@"enum" => {
            if (std.meta.stringToEnum(T, val)) |v| {
                data.* = v;
            } else {
                plat.log.warn("{s}: Couldn't parse enum. key: \"{s}\", val: \"{s}\", type \"{s}\"", .{ @src().fn_name, key, val, @typeName(T) });
            }
        },
        .@"struct" => {
            if (comptime std.mem.eql(u8, utl.typeBaseName(T), "V2i")) {
                var v = V2i{};
                _ = V2i.parse(val, &v) catch {
                    plat.log.warn("{s}: Couldn't parse V2i key: \"{s}\", val: \"{s}\"", .{ @src().fn_name, key, val });
                };
                data.* = v;
                return;
            } else {
                inline for (std.meta.fields(T)) |f| {
                    if (std.mem.eql(u8, f.name, key)) {
                        setValByName(plat, f.type, &@field(data, f.name), "", val);
                        break;
                    }
                } else {
                    plat.log.warn("{s}: Couldn't parse key: \"{s}\", struct type \"{s}\"\n", .{ @src().fn_name, key, @typeName(T) });
                }
            }
        },
        else => {
            plat.log.warn("{s}: Couldn't parse key: \"{s}\", type \"{s}\"", .{ @src().fn_name, key, @typeName(T) });
        },
    }
}

pub fn updateScreenDims(plat: *Platform, dims: V2i, resize_window: bool) void {
    plat.screen_dims = dims;
    plat.screen_dims_f = dims.toV2f();
    // get ui scale - fit inside or equal screen dims
    var ui_scaling: i32 = 0;
    for (0..100) |_| {
        const ui_dims = core.min_resolution.scale(ui_scaling + 1);
        if (ui_dims.x > dims.x or ui_dims.y > dims.y) {
            break;
        }
        ui_scaling += 1;
    }
    ui_scaling = @max(ui_scaling, 1);
    plat.ui_scaling = utl.as(f32, ui_scaling);
    // get game scale
    if (false) {
        // cover screen
        var game_scaling: i32 = 1;
        for (0..100) |_| {
            const game_dims = core.min_resolution.scale(game_scaling);
            if (game_dims.x >= dims.x and game_dims.y >= dims.y) {
                plat.game_canvas_dims = game_dims;
                break;
            }
            const game_dims_wide = core.min_wide_resolution.scale(game_scaling);
            if (game_dims_wide.x >= dims.x and game_dims_wide.y >= dims.y) {
                plat.game_canvas_dims = game_dims_wide;
                break;
            }
            game_scaling += 1;
        }
        plat.game_scaling = utl.as(f32, game_scaling);
    } else {
        // fit into screen
        const min_dimses = &[_]V2i{ core.min_resolution, core.min_wide_resolution };
        var best_diff: V2i = dims;
        var best_game_dims = core.min_resolution;
        var best_scaling: i32 = 1;
        loop: for (1..100) |i| {
            const game_scaling = utl.as(i32, i);
            for (min_dimses) |min_dims| {
                const game_dims = min_dims.scale(game_scaling);
                const diff = dims.sub(game_dims);
                if (diff.x < 0 or diff.y < 0) break :loop;
                if (diff.mLen() < best_diff.mLen()) {
                    best_game_dims = game_dims;
                    best_scaling = game_scaling;
                }
            }
        }
        plat.game_canvas_dims = best_game_dims.scale(best_scaling);
        plat.game_scaling = 1; //utl.as(f32, best_scaling);
        plat.game_zoom_levels = utl.as(f32, best_scaling);
    }
    plat.game_canvas_dims_f = plat.game_canvas_dims.toV2f();
    plat.game_canvas_screen_topleft_offset = plat.screen_dims_f.sub(plat.game_canvas_dims_f.scale(plat.game_scaling)).scale(0.5);
    plat.log.info("Scaling\n\tScreen: {}x{}\n\tGame: {}x{} scaled by {d}, offset by {d}", .{
        plat.screen_dims.x,      plat.screen_dims.y,
        plat.game_canvas_dims.x, plat.game_canvas_dims.y,
        plat.game_scaling,       plat.game_canvas_screen_topleft_offset,
    });

    const m_info = plat.getMonitorIdxAndDims();
    const m_dims = m_info.dims;
    if (resize_window) {
        plat.setWindowSize(dims);
        plat.setWindowPosition(m_dims.sub(dims).toV2f().scale(0.5).toV2i());
    }
}

// this may be called when getPlat() doesn't work yet!
pub fn initTryLoad(plat: *App.Platform) Options {
    var ret = initDefault(plat);
    defer ret.writeToTxt(plat);
    var cwd = std.fs.openDirAbsolute(plat.user_data_path, .{}) catch {
        plat.log.warn("WARNING: Failed to open cwd {s}", .{plat.user_data_path});
        return ret;
    };
    defer cwd.close();
    const options_file = cwd.openFile("options.txt", .{}) catch return ret;
    const str = options_file.readToEndAlloc(plat.heap, 1024 * 1024) catch return ret;
    defer plat.heap.free(str);
    var line_it = std.mem.tokenizeScalar(u8, str, '\n');
    while (line_it.next()) |line_untrimmed| {
        const line = std.mem.trim(u8, line_untrimmed, &std.ascii.whitespace);
        if (line[0] == '#') continue;
        var equals_it = std.mem.tokenizeScalar(u8, line, '=');
        const key = equals_it.next() orelse continue;
        const val = equals_it.next() orelse continue;
        setValByName(plat, Options, &ret, key, val);
    }
    options_file.close();

    // fix up controls
    {
        ret.controls.dropdown.selected_idx = @intFromEnum(ret.controls.cast_method);
    }
    // fix up selected resolution
    {
        var selected_res = &ret.display.selected_resolution;
        // crop to monitor size
        const monitor_dims = plat.getMonitorIdxAndDims().dims;
        selected_res.x = @min(monitor_dims.x, selected_res.x);
        selected_res.y = @min(monitor_dims.y, selected_res.y);
        // find an exact match
        for (ret.display.resolutions.constSlice(), 0..) |res, i| {
            if (res.eql(selected_res.*)) {
                ret.display.selected_resolution = res;
                ret.display.dropdown.selected_idx = i;
                break;
            }
        } else {
            ret.setCustomResolution(selected_res.*);
        }
        if (false) {
            // find best match
            var best = ret.display.resolutions.get(0);
            var best_idx: usize = 0;
            var best_diff = ret.display.selected_resolution.sub(best).mLen();
            for (ret.display.resolutions.constSlice()[1..], 1..) |res, i| {
                const diff = ret.display.selected_resolution.sub(res).mLen();
                if (diff < best_diff) {
                    best = res;
                    best_idx = i;
                    best_diff = diff;
                }
            }
            ret.display.selected_resolution = best;
            ret.display.dropdown.selected_idx = best_idx;
        }
    }
    // fix up audio
    {
        ret.audio.sfx_volume = utl.clampf(ret.audio.sfx_volume, 0, 1);
        ret.audio.music_volume = utl.clampf(ret.audio.music_volume, 0, 1);
    }

    return ret;
}

const el_text_padding = v2f(4, 4);
const el_bg_color = Colorf.rgb(0.2, 0.2, 0.2);
const el_bg_color_hovered = Colorf.rgb(0.3, 0.3, 0.3);
const el_bg_color_selected = Colorf.rgb(0.4, 0.4, 0.4);

fn updateAudio(self: *Options, cmd_buf: *ImmUI.CmdBuf, pos: V2f) Error!bool {
    var dirty: bool = false;
    dirty = dirty;
    const audio = self.audio;
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const text_opt = draw.TextOpt{
        .font = font,
        .size = font.base_size * utl.as(u32, plat.ui_scaling),
        .color = .white,
    };
    const ui_scaling = plat.ui_scaling;
    const el_padding = el_text_padding.scale(ui_scaling);
    var curr_row_pos = pos;
    const row_height: f32 = utl.as(f32, text_opt.size) + el_padding.y * 2;

    {
        const sfx_volume_text = try utl.bufPrintLocal("SFX Volume: {d:0.0}", .{audio.sfx_volume * 100});
        const sfx_volume_text_dims = try plat.measureText(sfx_volume_text, text_opt);
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = curr_row_pos.add(el_padding),
            .text = ImmUI.initLabel(sfx_volume_text),
            .opt = text_opt,
        } });

        const slider_pos = curr_row_pos.add(v2f(150 * ui_scaling, sfx_volume_text_dims.y));
        if (try self.audio.sfx_slider.update(
            cmd_buf,
            slider_pos,
            200,
            self.audio.sfx_volume * 100,
            0,
            100,
            1,
        )) |new_volume| {
            self.audio.sfx_volume = utl.clampf(new_volume / 100, 0, 1);
            dirty = true;
        }
        curr_row_pos.y += row_height;
    }
    {
        const music_volume_text = try utl.bufPrintLocal("Music Volume: {d:0.0}", .{audio.music_volume * 100});
        const music_volume_text_dims = try plat.measureText(music_volume_text, text_opt);
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = curr_row_pos.add(el_padding),
            .text = ImmUI.initLabel(music_volume_text),
            .opt = text_opt,
        } });

        const slider_pos = curr_row_pos.add(v2f(150 * ui_scaling, music_volume_text_dims.y));
        if (try self.audio.music_slider.update(
            cmd_buf,
            slider_pos,
            200,
            self.audio.music_volume * 100,
            0,
            100,
            1,
        )) |new_volume| {
            self.audio.music_volume = utl.clampf(new_volume / 100, 0, 1);
            dirty = true;
        }
        curr_row_pos.y += row_height;
    }

    return dirty;
}

fn updateDisplay(self: *Options, cmd_buf: *ImmUI.CmdBuf, pos: V2f) Error!bool {
    var dirty: bool = false;
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const text_opt = draw.TextOpt{
        .font = font,
        .size = font.base_size * utl.as(u32, plat.ui_scaling),
        .color = .white,
    };
    const ui_scaling = plat.ui_scaling;
    const el_padding = el_text_padding.scale(ui_scaling);
    var curr_row_pos = pos;
    const row_height: f32 = utl.as(f32, text_opt.size) + el_padding.y * 2;
    { // resolution
        const cast_method_text = "Resolution:";
        const cast_method_text_dims = try plat.measureText(cast_method_text, text_opt);
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = curr_row_pos.add(el_padding),
            .text = ImmUI.initLabel(cast_method_text),
            .opt = text_opt,
        } });

        const dropdown_pos = pos.add(v2f(cast_method_text_dims.x + 8 * ui_scaling, 0));
        // copy the pointers to the string slices, because we want a []const []const u8 for dropdown.update()
        var strings_buf = std.BoundedArray([]const u8, Display.max_resolutions){};
        for (self.display.resolutions_strings.constSlice()) |*str| {
            strings_buf.appendAssumeCapacity(str.constSlice());
        }
        if (try self.display.dropdown.update(cmd_buf, dropdown_pos, 1, strings_buf.constSlice())) |new_idx| {
            self.display.selected_resolution = self.display.resolutions.get(new_idx);
            updateScreenDims(plat, self.display.selected_resolution, true);
            App.get().resolutionChanged();
            dirty = true;
        }
        curr_row_pos.y += row_height;
    }

    return dirty;
}

fn updateControls(self: *Options, cmd_buf: *ImmUI.CmdBuf, pos: V2f) Error!bool {
    var dirty: bool = false;
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const text_opt = draw.TextOpt{
        .font = font,
        .size = font.base_size * utl.as(u32, plat.ui_scaling),
        .color = .white,
        .smoothing = .none,
    };
    const ui_scaling = plat.ui_scaling;
    const el_padding = el_text_padding.scale(ui_scaling);
    var curr_row_pos = pos;
    const row_height: f32 = utl.as(f32, text_opt.size) + el_padding.y * 2;

    { // cast method
        const cast_method_text = "Cast Method:";
        const cast_method_text_dims = try plat.measureText(cast_method_text, text_opt);
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = curr_row_pos.add(el_padding),
            .text = ImmUI.initLabel(cast_method_text),
            .opt = text_opt,
        } });

        const dropdown_pos = pos.add(v2f(cast_method_text_dims.x + 8 * ui_scaling, 0));
        if (try self.controls.dropdown.update(cmd_buf, dropdown_pos, 1, &Controls.CastMethod.strings.values)) |new_idx| {
            self.controls.cast_method = @enumFromInt(new_idx);
            dirty = true;
        }
        curr_row_pos.y += row_height;
    }
    // bindings
    {
        if (false) {
            cmd_buf.appendAssumeCapacity(.{ .label = .{
                .pos = curr_row_pos.add(el_padding),
                .text = ImmUI.initLabel("Bindings"),
                .opt = text_opt,
            } });
            curr_row_pos.y += row_height;
        }
        for (self.controls.input_bindings.constSlice()) |binding| {
            cmd_buf.appendAssumeCapacity(.{ .label = .{
                .pos = curr_row_pos.add(el_padding),
                .text = ImmUI.initLabel(binding.slot_name.constSlice()),
                .opt = text_opt,
            } });
            var icon_pos = curr_row_pos.add(el_padding).add(v2f(100 * ui_scaling, 0));
            for (binding.inputs.constSlice()) |d| {
                const text = d.getIconText();
                const text_sz = icon_text.measureIconText(text);
                try icon_text.unqRenderIconText(cmd_buf, text, icon_pos, ui_scaling);
                icon_pos.x += text_sz.x + 2 * ui_scaling;
            }
            curr_row_pos.y += row_height;
        }
    }

    return dirty;
}

pub const kind_rect_dims = v2f(300, 260);
pub const full_panel_padding = v2f(20, 20);
pub const top_bot_parts_height = 30;
pub const full_panel_dims = kind_rect_dims.add(v2f(0, top_bot_parts_height * 2)).add(full_panel_padding.scale(2));

pub fn update(self: *Options, cmd_buf: *ImmUI.CmdBuf) Error!enum { dont_close, close } {
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const ui_scaling = plat.ui_scaling;

    const panel_dims = full_panel_dims.scale(ui_scaling);
    const kind_section_dims = kind_rect_dims.scale(ui_scaling);
    const panel_pos = plat.screen_dims_f.sub(panel_dims).scale(0.5);

    cmd_buf.appendAssumeCapacity(.{
        .rect = .{
            .pos = panel_pos,
            .dims = panel_dims,
            .opt = .{
                .fill_color = Colorf.rgb(0.1, 0.1, 0.1),
                .edge_radius = 0.1,
            },
        },
    });
    const padding = full_panel_padding.scale(ui_scaling);
    const selected_btn_dims = v2f(
        80,
        utl.as(f32, font.base_size) + 10,
    ).scale(ui_scaling);
    const selected_info = @typeInfo(Kind).@"enum";
    const num_selected_f = utl.as(f32, selected_info.fields.len);
    const selected_dims = v2f(panel_dims.x - padding.x * 2, selected_btn_dims.y);
    const selected_x_spacing = (selected_dims.x - (num_selected_f * selected_btn_dims.x)) / (num_selected_f - 1);
    var selected_curr_pos = panel_pos.add(padding);
    inline for (0..selected_info.fields.len) |i| {
        const kind: Kind = @enumFromInt(i);
        const enum_name = utl.enumToString(Kind, kind);
        const text = try utl.bufPrintLocal("{c}{s}", .{ std.ascii.toUpper(enum_name[0]), enum_name[1..] });
        if (menuUI.textButton(cmd_buf, selected_curr_pos, text, selected_btn_dims, ui_scaling)) {
            self.kind_selected = kind;
        }
        selected_curr_pos.x += selected_btn_dims.x + selected_x_spacing;
    }

    const kind_section_pos = panel_pos.add(padding).add(v2f(0, top_bot_parts_height * ui_scaling));
    if (switch (self.kind_selected) {
        .controls => try self.updateControls(cmd_buf, kind_section_pos),
        .display => try self.updateDisplay(cmd_buf, kind_section_pos),
        .audio => try self.updateAudio(cmd_buf, kind_section_pos),
    }) {
        self.writeToTxt(plat);
    }

    const back_btn_pos = kind_section_pos.add(v2f(0, kind_section_dims.y));
    const back_btn_dims = v2f(60, top_bot_parts_height).scale(ui_scaling);
    if (menuUI.textButton(cmd_buf, back_btn_pos, "Back", back_btn_dims, ui_scaling)) {
        return .close;
    }
    return .dont_close;
}

pub fn setCustomResolution(options: *Options, res: V2i) void {
    const res_label = Display.ResLabel.fromSlice(
        utl.bufPrintLocal("{d}x{d}", .{ res.x, res.y }) catch "custom",
    ) catch unreachable;
    // old custom resolution is overwritten
    // if no space for a custom resolution, make space by overwriting the 0th (smallest) resolution
    if (options.display.custom_resolution or options.display.resolutions.len >= options.display.resolutions.buffer.len) {
        options.display.resolutions.buffer[0] = res;
        options.display.resolutions_strings.buffer[0] = res_label;
    } else {
        options.display.resolutions.insert(0, res) catch unreachable;
        options.display.resolutions_strings.insert(0, res_label) catch unreachable;
    }
    options.display.dropdown.selected_idx = 0;
    options.display.selected_resolution = res;
    options.display.custom_resolution = true;
}

pub fn alwaysUpdate(options: *Options) void {
    const plat = App.getPlat();
    const curr_screen_dims = plat.getWindowSize();
    if (!plat.screen_dims.eql(curr_screen_dims)) {
        // manually resized
        updateScreenDims(plat, curr_screen_dims, false);
        options.setCustomResolution(curr_screen_dims);
        App.get().resolutionChanged();
        options.writeToTxt(plat);
    }
}
