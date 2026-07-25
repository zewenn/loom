const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const World = @import("World.zig");

const Self = @This();

const Fn = std.builtin.Type.Fn;

const Param = Fn.Param;
const GenericSystemFunction = *const fn (count: usize, data: [*][*]u8) anyerror!void;

const HashQuery = struct {
    all: []const u64,
    write: []const u64,
    read: []const u64,
};

id: u64,
name: []const u8,
callback: GenericSystemFunction,
hashes: []const u64,
write_hashes: []const u64,
read_hashes: []const u64,

bit_mask: ?u128 = null,
write_mask: ?u128 = null,
read_mask: ?u128 = null,

pub fn init(comptime func: anytype) Self {
    const hashes = comptime getHashes(func);
    return Self{
        .id = comptime core.type_erasure.typeToHash(@TypeOf(func)),
        .name = @typeName(@TypeOf(func)),
        .callback = comptime wrapFunction(func),
        .hashes = hashes.all,
        .write_hashes = hashes.write,
        .read_hashes = hashes.read,
    };
}

pub fn overlaps(self: Self, other: Self) bool {
    const other_write_mask = other.write_mask orelse return true;
    const other_read_mask = other.read_mask orelse return true;

    return self.overlapsMasks(other_write_mask, other_read_mask);
}

pub fn overlapsMasks(self: Self, other_write_mask: u128, other_read_mask: u128) bool {
    const self_write_mask = self.write_mask orelse return true;
    const self_read_mask = self.read_mask orelse return true;

    return (self_write_mask & other_write_mask) != 0 or
        (self_write_mask & other_read_mask) != 0 or
        (self_read_mask & other_write_mask) != 0;
}

pub fn hasMasks(self: Self) bool {
    return self.bit_mask != null and self.write_mask != null and self.read_mask != null;
}

inline fn canError(comptime func: anytype) bool {
    return switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |info| info.return_type == void,
        else => @compileError("system function was not a function"),
    };
}

inline fn getParams(comptime func: anytype) []const Param {
    return switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |info| info.params,
        else => @compileError("system function was not a function"),
    };
}

/// Accepts []T, []*T, []const T, []*const T — returns the bare component type.
inline fn componentTypeOf(comptime BASE: type) type {
    const slice = switch (@typeInfo(BASE)) {
        .pointer => |p| blk: {
            core.comptimeAssert(p.size == .slice, "system param must be a slice");
            break :blk p;
        },
        else => @compileError("system param must be a slice"),
    };

    return switch (@typeInfo(slice.child)) {
        .pointer => |ptr| ptr.child, // []*T  or []*const T
        else => slice.child, // []T   or []const T
    };
}

/// Returns true for []const T or []*const T.
inline fn isConstParam(comptime BASE: type) bool {
    const slice = @typeInfo(BASE).pointer;
    return switch (@typeInfo(slice.child)) {
        .pointer => |ptr| ptr.is_const,
        else => slice.is_const,
    };
}

fn getTypes(comptime params: []const Param) []const type {
    var types: core.ComptimeList(type) = .init();

    inline for (params) |param| {
        const BASE = param.type orelse continue;
        types.append(componentTypeOf(BASE));
    }

    return types.items();
}

fn getHashes(comptime func: anytype) HashQuery {
    const params = comptime getParams(func);

    var all: core.ComptimeList(u64) = .init();
    var write: core.ComptimeList(u64) = .init();
    var read: core.ComptimeList(u64) = .init();

    inline for (params) |param| {
        const BASE = param.type orelse continue;

        const hash = comptime core.type_erasure.typeToHash(componentTypeOf(BASE));
        all.append(hash);
        if (isConstParam(BASE)) read.append(hash) else write.append(hash);
    }

    return .{
        .all = all.items(),
        .write = write.items(),
        .read = read.items(),
    };
}

pub fn wrapFunction(comptime func: anytype) GenericSystemFunction {
    const local = struct {
        pub fn wrapper(count: usize, slices: [*][*]u8) anyerror!void {
            const params = comptime getParams(func);
            const types = comptime getTypes(params);

            comptime var slice_types: [types.len]type = undefined;
            inline for (types, 0..) |T, index| {
                slice_types[index] = []T;
            }
            const Tuple = std.meta.Tuple(&slice_types);

            var result: Tuple = undefined;
            inline for (0..types.len) |index| {
                const Target = types[index];
                result[index] = @as([*]Target, @ptrCast(@alignCast(slices[index])))[0..count];
            }

            try @call(.auto, func, result);
        }
    };
    return local.wrapper;
}
