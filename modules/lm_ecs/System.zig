const std = @import("std");
const Allocator = std.mem.Allocator;

const lm_types = @import("lm_types");
const World = @import("World.zig");

const Self = @This();

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
        .id = comptime lm_types.type_erasure.typeToHash(@TypeOf(func)),
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

inline fn getParamTypes(comptime func: anytype) []const ?type {
    return switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |info| info.param_types,
        else => @compileError("system function was not a function"),
    };
}

inline fn componentTypeOf(comptime BASE: type) type {
    const slice = switch (@typeInfo(BASE)) {
        .pointer => |pointer_info| blk: {
            lm_types.comptimeAssert(pointer_info.size == .slice, "system param must be a slice");
            break :blk pointer_info;
        },
        else => @compileError("system param must be a slice"),
    };

    return switch (@typeInfo(slice.child)) {
        .pointer => |pointer_info| pointer_info.child,
        else => slice.child,
    };
}

inline fn isConstParam(comptime BASE: type) bool {
    const Child = componentTypeOf(BASE);
    return BASE == []const Child or BASE == []*const Child or BASE == []const *const Child;
}

fn getTypes(comptime param_types: []const ?type) []const type {
    var types: lm_types.ComptimeList(type) = .init();

    inline for (param_types) |optional_type| {
        const base_type = optional_type orelse @compileError("system param must have a concrete type");
        types.append(componentTypeOf(base_type));
    }

    return types.items();
}

fn getHashes(comptime func: anytype) HashQuery {
    const param_types = comptime getParamTypes(func);

    var all: lm_types.ComptimeList(u64) = .init();
    var write: lm_types.ComptimeList(u64) = .init();
    var read: lm_types.ComptimeList(u64) = .init();

    inline for (param_types) |optional_type| {
        const base_type = optional_type orelse @compileError("system param must have a concrete type");
        const hash = comptime lm_types.type_erasure.typeToHash(componentTypeOf(base_type));
        all.append(hash);
        if (isConstParam(base_type)) read.append(hash) else write.append(hash);
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
            const param_types = comptime getParamTypes(func);
            const types = comptime getTypes(param_types);

            comptime var slice_types: [types.len]type = undefined;
            inline for (types, 0..) |T, index| {
                slice_types[index] = []T;
            }
            const Tuple = @Tuple(&slice_types);

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
