const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");

const ComponentStore = @import("ComponentStore.zig");
const PendingComponent = @import("PendingComponent.zig");

const Self = @This();

stores: core.List(ComponentStore),
pending: core.List(PendingComponent),

free_list: core.List(usize),
next_entity_index: usize,

allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .pending = .init(allocator),
        .stores = .init(allocator),

        .free_list = .init(allocator),
        .next_entity_index = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.reset();

    self.pending.deinit();
    self.stores.deinit();

    self.* = undefined;
}

pub fn reset(self: *Self) void {
    const stores_len = self.stores.len();
    for (1..stores_len + 1) |j| {
        const index = stores_len - j;
        const element = &self.stores.items()[index];

        element.deinit();
        _ = self.stores.swapRemove(index);
    }

    const pending_len = self.pending.len();
    for (1..pending_len + 1) |j| {
        const index = pending_len - j;
        const element = &self.pending.items()[index];

        element.deinit();
        _ = self.pending.swapRemove(index);
    }

    core.assert(self.stores.len() == 0, "stores wasn't cleared");
    core.assert(self.pending.len() == 0, "pending wasn't cleared");
}

fn getEntityId(self: *Self) usize {
    if (self.free_list.pop()) |value| return value;

    const value = self.next_entity_index;
    self.next_entity_index += 1;

    return value;
}

pub fn addEntity(self: *Self, components: anytype) !void {
    const id = self.getEntityId();

    switch (@typeInfo(@TypeOf(components))) {
        .@"struct" => |val| {
            core.comptimeAssert(val.is_tuple, "param \"components\" must be a tuple");
        },
    }

    for (components) |component| {
        const pending: PendingComponent = try .init(self.allocator, id, component);
        try self.pending.append(pending);
    }
}

fn addPendingComponent(self: *Self, pending: PendingComponent) !void {
    for (self.stores.items()) |store| {
        if (store.component_id != pending.id) continue;

        try store.storePending(pending);
        return;
    }

    try self.stores.append(try .fromPending(self.allocator, pending));
}

fn addPendingComponents(self: *Self) !void {
    const len = self.pending.len();
    for (1..len + 1) |j| {
        const index = len - j;
        const elem = &self.pending.items()[index];

        try self.addPendingComponent(elem.*);
        elem.deinit();
        _ = self.pending.swapRemove(index);
    }
    self.pending.clearAndFree();
}
