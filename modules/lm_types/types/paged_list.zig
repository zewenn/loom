const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("../root.zig");
const List = core.List;

pub fn PagedList(comptime T: type, comptime CHUNK_SIZE: comptime_int) type {
    return struct {
        pub const Error = error{
            InvalidChunkData,
        };

        const Self = @This();
        const PositionInfo = struct {
            chunk: usize,
            local: usize,

            pub fn init(at: usize) PositionInfo {
                return PositionInfo{
                    .chunk = @divFloor(at, CHUNK_SIZE),
                    .local = @rem(at, CHUNK_SIZE),
                };
            }
        };

        list: List(?List(?T)),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .list = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.list.items()) |maybe_item| {
                var item = maybe_item orelse continue;
                item.deinit();
            }
            self.list.deinit();

            self.* = undefined;
        }

        pub fn set(self: *Self, at: usize, to: T) !void {
            const pos: PositionInfo = .init(at);

            while (self.list.len() <= pos.chunk)
                try self.list.append(null);

            if (self.list.items()[pos.chunk] == null)
                self.list.items()[pos.chunk] = .init(self.allocator);

            const chunk = &(self.list.items()[pos.chunk] orelse return Error.InvalidChunkData);

            while (chunk.len() <= pos.local)
                try chunk.append(null);

            chunk.items()[pos.local] = to;
        }

        pub fn get(self: *Self, at: usize) ?T {
            const pos: PositionInfo = .init(at);

            if (pos.chunk >= self.list.len()) return null;
            const chunk = &(self.list.items()[pos.chunk] orelse return null);

            if (pos.local >= chunk.len()) return null;
            return chunk.items()[pos.local];
        }

        pub fn getPtr(self: *Self, at: usize) ?*T {
            const pos: PositionInfo = .init(at);

            if (pos.chunk >= self.list.len()) return null;
            const chunk = &(self.list.items()[pos.chunk] orelse return null);

            if (pos.local >= chunk.len()) return null;
            return &(chunk.items()[pos.local] orelse return null);
        }

        pub fn remove(self: *Self, at: usize) void {
            const pos: PositionInfo = .init(at);

            if (pos.chunk >= self.list.len()) return;
            const chunk = &(self.list.items()[pos.chunk] orelse return);

            if (pos.local >= chunk.len()) return;
            chunk.items()[pos.local] = null;

            var last_null_start: ?usize = null;
            for (chunk.items(), 0..) |item, index| {
                if (item != null) {
                    last_null_start = null;
                    continue;
                }

                if (last_null_start != null) continue;
                last_null_start = index;
            }

            if (last_null_start) |new_len| local: {
                chunk.shrinkAndFree(new_len);
                if (new_len != 0) break :local;

                chunk.deinit();
                self.list.items()[pos.chunk] = null;
            }

            last_null_start = null;
            for (self.list.items(), 0..) |item, index| {
                if (item != null) {
                    last_null_start = null;
                    continue;
                }

                if (last_null_start != null) continue;
                last_null_start = index;
            }
            if (last_null_start) |new_len|
                self.list.shrinkAndFree(new_len);
        }

        pub fn removeFast(self: *Self, at: usize) void {
            const pos: PositionInfo = .init(at);

            if (pos.chunk >= self.list.len()) return;
            const chunk = &(self.list.items()[pos.chunk] orelse return);

            if (pos.local >= chunk.len()) return;
            chunk.items()[pos.local] = null;
        }
    };
}
