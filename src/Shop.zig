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
const debug = @import("debug.zig");

const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const Run = @import("Run.zig");
const menuUI = @import("menuUI.zig");
const gameUI = @import("gameUI.zig");
const Item = @import("Item.zig");
const ImmUI = @import("ImmUI.zig");
const icon_text = @import("icon_text.zig");
const sprites = @import("sprites.zig");
const Tooltip = @import("Tooltip.zig");
const Shop = @This();

const max_num_spells = 5;
const num_nonrare_spells = 4;
const num_rare_spells = 1;
const num_spells = num_nonrare_spells + num_rare_spells;
const spells_spacing: f32 = 16;

const max_num_items = 4;
const num_items = 3;
const items_spacing: f32 = 10;

const slot_margin: f32 = 5;

pub const Product = struct {
    pub const Kind = union(enum) {
        spell: Spell,
        item: Item,
        card_remove: usize, // idx
    };
    kind: Kind,
    price: union(enum) {
        gold: i32,
    } = .{ .gold = 10 },
};

const ProductSlot = struct {
    product: ?Product = null,
    rect: geom.Rectf = .{},
    long_hover: menuUI.LongHover = .{},
};

spells: std.BoundedArray(ProductSlot, max_num_spells) = .{},
items: std.BoundedArray(ProductSlot, max_num_items) = .{},
card_remove_slot: ProductSlot = .{
    .product = .{
        .kind = .{ .card_remove = 0 },
        .price = .{ .gold = 5 },
    },
},
rng: std.Random.DefaultPrng,
state: enum {
    shopping,
    done,
    card_removal,
} = .shopping,

pub fn init(seed: u64, run: *Run) Error!Shop {
    var ret = Shop{
        .rng = std.Random.DefaultPrng.init(seed),
    };
    for (0..num_spells) |_| {
        ret.spells.appendAssumeCapacity(.{});
    }
    for (0..num_items) |_| {
        ret.items.appendAssumeCapacity(.{});
    }
    ret.fillEmptySlots(run);

    return ret;
}

pub fn deinit(self: *Shop) void {
    _ = self;
}

pub fn reset(self: *Shop, run: *Run) Error!*Shop {
    self.deinit();
    var rng = std.Random.DefaultPrng.init(utl.as(u64, std.time.microTimestamp()));
    const seed = rng.random().int(u64);
    self.* = try init(seed, run);
    return self;
}

fn fillEmptySlots(self: *Shop, run: *Run) void {
    const rarity_nonrare = Spell.RarityWeights.init(.{
        .pedestrian = 0.60,
        .interesting = 0.40,
        .exceptional = 0.00,
        .brilliant = 0.00,
    });
    const rarity_rare = Spell.RarityWeights.init(.{
        .pedestrian = 0.0,
        .interesting = 0.0,
        .exceptional = 1.0,
        .brilliant = 0.0,
    });
    var spells_buf: [max_num_spells]Spell = undefined;
    const nonrare_spells_generated = Spell.makeShopSpells(self.rng.random(), run.mode, &rarity_nonrare, spells_buf[0..num_nonrare_spells]);
    const rare_spells_generated = Spell.makeShopSpells(self.rng.random(), run.mode, &rarity_rare, spells_buf[nonrare_spells_generated.len .. nonrare_spells_generated.len + num_rare_spells]);
    const spells_generated = spells_buf[0 .. nonrare_spells_generated.len + rare_spells_generated.len];
    for (spells_generated, 0..) |spell, i| {
        if (i >= self.spells.len) break;
        const slot = &self.spells.buffer[i];
        if (slot.product != null) continue;
        slot.* = .{
            .product = .{
                .kind = .{ .spell = spell },
                .price = .{ .gold = spell.getShopPrice(self.rng.random()) },
            },
        };
    }

    var items_buf: [max_num_items]Item = undefined;
    const items_generated = Item.makeShopItems(self.rng.random(), run.mode, items_buf[0..num_items]);
    for (items_generated, 0..) |item, i| {
        if (i >= self.items.len) break;
        const slot = &self.items.buffer[i];
        if (slot.product != null) continue;
        slot.* = .{
            .product = .{
                .kind = .{ .item = item },
                .price = .{ .gold = item.getShopPrice(self.rng.random()) },
            },
        };
    }
}

pub fn canBuy(run: *Run, product: *const Product) bool {
    const price = product.price.gold;
    return run.gold >= price and run.canPickupProduct(product);
}

fn unqProductSlot(cmd_buf: *ImmUI.CmdBuf, tooltip_buf: *ImmUI.CmdBuf, slot: *ProductSlot, run: *Run, enabled: bool) Error!bool {
    const plat = getPlat();
    const ui_scaling: f32 = plat.ui_scaling;
    var ret: bool = false;

    const mouse_pos = plat.getMousePosScreen();
    const hovered = enabled and geom.pointIsInRectf(mouse_pos, slot.rect);
    const clicked = enabled and hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    // TODO anything else here?
    const slot_enabled = slot.product != null;
    const can_buy = slot_enabled and canBuy(run, &slot.product.?);
    const bg_color = Colorf.rgb(0.17, 0.15, 0.15);
    var slot_contents_pos = slot.rect.pos.add(V2f.splat(slot_margin * ui_scaling));

    // background rect
    if (can_buy and hovered) {
        // TODO animate
        slot_contents_pos = slot_contents_pos.add(v2f(0, -3 * ui_scaling));
    }
    cmd_buf.append(.{ .rect = .{
        .pos = slot.rect.pos,
        .dims = slot.rect.dims,
        .opt = .{
            .fill_color = bg_color,
            .edge_radius = 0.2,
        },
    } }) catch @panic("Fail to append rect cmd");

    // slot contents
    if (slot_enabled) {
        const product = slot.product.?;

        ret = can_buy and hovered and clicked;
        switch (product.kind) {
            .spell => |*spell| {
                spell.unqRenderCard(cmd_buf, slot_contents_pos, null, ui_scaling);
                if (slot.long_hover.update(hovered)) {
                    try spell.unqRenderTooltip(tooltip_buf, slot_contents_pos.add(v2f(slot.rect.dims.x, 0)), ui_scaling);
                }
            },
            .item => |*item| {
                try item.unqRenderIcon(cmd_buf, slot_contents_pos, ui_scaling);
                if (slot.long_hover.update(hovered)) {
                    try item.unqRenderTooltip(tooltip_buf, slot_contents_pos.add(v2f(slot.rect.dims.x, 0)), ui_scaling);
                }
            },
            .card_remove => {
                const data = App.getData();
                const sprite_name = Data.MiscIcon.card_remove;
                const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(sprite_name).? };
                try info.unqRender(cmd_buf, slot_contents_pos, ui_scaling);
                if (slot.long_hover.update(hovered)) {
                    const tt = Tooltip{
                        .title = Tooltip.Title.fromSlice("Remove a card") catch unreachable,
                    };
                    const tooltip_pos = slot.rect.pos.add(v2f(slot.rect.dims.x, 0));
                    try tt.unqRender(tooltip_buf, tooltip_pos, ui_scaling);
                }
            },
        }
        const price_str = try utl.bufPrintLocal(
            "{any}{any}{}",
            .{
                icon_text.Icon.coin,
                icon_text.Fmt{ .tint = if (can_buy) .yellow else .red },
                product.price.gold,
            },
        );
        const price_str_dims = icon_text.measureIconText(price_str).scale(ui_scaling);
        const price_pos = slot.rect.pos.add(slot.rect.dims).sub(price_str_dims.add(v2f(slot_margin, slot_margin - 2).scale(ui_scaling)));
        try icon_text.unqRenderIconText(cmd_buf, price_str, price_pos, ui_scaling);
    }

    return ret;
}

pub fn update(self: *Shop, run: *Run) Error!?Product {
    return switch (self.state) {
        .done => null,
        .shopping => try shoppingUI(self, run, true),
        .card_removal => blk: {
            run.deck_ui.show = true;
            run.deck_ui.close_btn_text = "Cancel";
            run.deck_ui.title_text = "Remove a Spell";
            _ = try shoppingUI(self, run, false);
            if (try run.deckUI(run.deck.constSlice(), &run.deck_ui.hover, &run.deck_ui.scroll)) |interaction| {
                switch (interaction.state) {
                    .hovered => {},
                    .clicked => {
                        self.state = .shopping;
                        const ret = Product{
                            .kind = .{ .card_remove = interaction.idx },
                            .price = self.card_remove_slot.product.?.price,
                        };
                        self.card_remove_slot.product.?.price.gold += 2;
                        break :blk ret;
                    },
                    .closed => {
                        self.state = .shopping;
                    },
                }
            }
            break :blk null;
        },
    };
}

fn shoppingUI(self: *Shop, run: *Run, enabled: bool) Error!?Product {
    const plat = getPlat();
    const data = App.get().data;
    const ui_scaling: f32 = plat.ui_scaling;
    var ret: ?Product = null;
    try run.imm_ui.commands.append(.{ .rect = .{
        .pos = v2f(0, 0),
        .z = -1,
        .dims = plat.screen_dims_f,
        .opt = .{
            .fill_color = .gray,
        },
    } });

    const title_center_pos = v2f(
        plat.screen_dims_f.x * 0.5,
        30 * ui_scaling,
    );
    const title_font = data.fonts.get(.pixeloid);
    try run.imm_ui.commands.append(.{ .label = .{
        .pos = title_center_pos,
        .text = ImmUI.initLabel("Shoppy Woppy"),
        .opt = .{
            .center = true,
            .color = .white,
            .font = title_font,
            .size = title_font.base_size * utl.as(u32, ui_scaling + 1),
        },
    } });

    const price_font = data.fonts.get(.seven_x_five);
    const price_font_base_sz_f = utl.as(f32, price_font.base_size);

    // spells
    const spell_slot_dims = Spell.card_dims.add(V2f.splat(slot_margin).scale(2)).add(v2f(0, price_font_base_sz_f + slot_margin)).scale(ui_scaling);
    const spells_per_row: usize = 4;
    const spell_spacing_scaled = spells_spacing * ui_scaling;
    const spell_row_width = (spell_slot_dims.x + spell_spacing_scaled) * utl.as(f32, spells_per_row) - spell_spacing_scaled;
    const spells_top_center = title_center_pos.add(v2f(0, 25).scale(ui_scaling));
    const spells_topleft = spells_top_center.sub(v2f(spell_row_width * 0.5, 0));
    var spells_curr_pos = spells_topleft;
    var spells_col: usize = 0;

    for (self.spells.slice()) |*slot| {
        slot.rect = .{
            .pos = spells_curr_pos,
            .dims = spell_slot_dims,
        };
        spells_col += 1;
        if (spells_col == spells_per_row) {
            spells_col = 0;
            spells_curr_pos.y += spell_slot_dims.y + spell_spacing_scaled;
            spells_curr_pos.x = spells_topleft.x + spell_slot_dims.x + spell_spacing_scaled;
        } else {
            spells_curr_pos.x += spell_slot_dims.x + spell_spacing_scaled;
        }
    }

    // items
    const item_slot_dims = Item.icon_dims.add(V2f.splat(slot_margin).scale(2)).add(v2f(0, price_font_base_sz_f + slot_margin)).scale(ui_scaling);
    const items_per_row: usize = 3;
    const item_spacing_scaled = spell_spacing_scaled;
    const items_topleft = spells_curr_pos;
    var items_curr_pos = items_topleft;
    var items_col: usize = 0;

    for (self.items.slice()) |*slot| {
        slot.rect = .{
            .pos = items_curr_pos,
            .dims = item_slot_dims,
        };
        items_col += 1;
        if (items_col == items_per_row) {
            items_col = 0;
            items_curr_pos.y += item_slot_dims.y + item_spacing_scaled;
            items_curr_pos.x = items_topleft.x;
        } else {
            items_curr_pos.x += item_slot_dims.x + item_spacing_scaled;
        }
    }

    var emptied_slot = false;

    for (self.spells.slice()) |*slot| {
        if (try unqProductSlot(&run.imm_ui.commands, &run.tooltip_ui.commands, slot, run, enabled)) {
            assert(canBuy(run, &slot.product.?));
            ret = slot.product.?;
            slot.product = null;
            emptied_slot = true;
        }
    }

    for (self.items.slice()) |*slot| {
        if (try unqProductSlot(&run.imm_ui.commands, &run.tooltip_ui.commands, slot, run, enabled)) {
            assert(canBuy(run, &slot.product.?));
            ret = slot.product.?;
            slot.product = null;
            emptied_slot = true;
        }
    }

    // remove card slot
    const remove_slot = &self.card_remove_slot;
    const remove_slot_dims = Item.icon_dims.add(V2f.splat(slot_margin).scale(2)).add(v2f(0, price_font_base_sz_f + slot_margin)).scale(ui_scaling);
    const remove_slot_topleft = items_topleft.add(v2f(0, item_slot_dims.y + 20 * ui_scaling));
    remove_slot.rect.pos = remove_slot_topleft;
    remove_slot.rect.dims = remove_slot_dims;

    if (try unqProductSlot(&run.imm_ui.commands, &run.tooltip_ui.commands, remove_slot, run, enabled)) {
        assert(canBuy(run, &remove_slot.product.?));
        self.state = .card_removal;
    }

    if (emptied_slot) {
        self.fillEmptySlots(run);
    }

    // leave btn
    if (enabled) {
        const proceed_btn_dims = v2f(60, 40).scale(ui_scaling);
        const proceed_btn_pos = remove_slot_topleft.add(v2f(remove_slot_dims.x + 20 * ui_scaling, 0));

        if (menuUI.textButton(&run.imm_ui.commands, proceed_btn_pos, "Leave", proceed_btn_dims, ui_scaling)) {
            self.state = .done;
        }
    }

    return ret;
}

pub fn shopColliderProto() Thing {
    return Thing{
        .kind = .vfx,
        .spawn_state = .instance,
        .coll_radius = 62,
        .coll_mass = std.math.inf(f32),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
    };
}
