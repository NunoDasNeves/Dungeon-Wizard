const std = @import("std");
const utl = @import("../util.zig");

pub const Platform = @import("../raylib.zig");
const core = @import("../core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("../debug.zig");
const assert = debug.assert;
const draw = @import("../draw.zig");
const Colorf = draw.Colorf;
const geom = @import("../geometry.zig");
const V2f = @import("../V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("../V2i.zig");
const v2i = V2i.v2i;

const App = @import("../App.zig");
const getPlat = App.getPlat;
const Room = @import("../Room.zig");
const Thing = @import("../Thing.zig");
const TileMap = @import("../TileMap.zig");
const StatusEffect = @import("../StatusEffect.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Blank Mind";

pub const enum_name = "blank_mind";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .after_cast_slot_cooldown_secs = 0,
        .draw_immediate = true,
        .color = StatusEffect.proto_array.get(.protected).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

shield_amount: f32 = 15,
duration_secs: f32 = 5,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);

    const blank_mind: @This() = self.kind.blank_mind;
    if (caster.hp) |*hp| {
        hp.addShield(blank_mind.shield_amount, core.secsToTicks(blank_mind.duration_secs));
    }
    _ = room;
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const blank_mind: @This() = self.kind.blank_mind;
    const fmt =
        \\Gain {any}{d:.0} shield for {d:.0} seconds.
        \\{any}Draw 1 spell (immediately).
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.shield),
            @floor(blank_mind.shield_amount),
            @floor(blank_mind.duration_secs),
            StatusEffect.getIcon(.quickdraw),
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .shield });
    tt.infos.appendAssumeCapacity(.{ .status = .quickdraw });
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const blank_mind: @This() = self.kind.blank_mind;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .wizard, .tint = .orange } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .shield_empty } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{blank_mind.shield_amount}) },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .arrow_180_CC } },
            .{ .icon = .{ .sprite_enum = .card } },
        },
    });
}
