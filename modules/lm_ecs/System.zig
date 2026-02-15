const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const World = @import("World.zig");

const Self = @This();

const Fn = std.builtin.Type.Fn;
const StructField = std.builtin.Type.StructField;
const Param = Fn.Param;

const HashQuery = struct {
    all: []const u64,
    write: []const u64,
    read: []const u64,
};

id: u64,
name: []const u8,
// TODO:    change systems to use bulk component arrays instead of single pointers
//          fn signiture changes from fn ([]const *anyopaque) !void to
//          fn ([]const []u8) !void probably
//          system changes from fn (mycomp: *mut, other: *const c) !void to
//          fn (mycomp: []mut, other: []const c) !void
callback: *const fn ([]const *anyopaque) anyerror!void,
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
    const self_write_mask = self.write_mask orelse return true;
    const self_read_mask = self.read_mask orelse return true;
    const other_write_mask = other.write_mask orelse return true;
    const other_read_mask = other.read_mask orelse return true;

    return ((self_write_mask & other_write_mask) != 0 and
        (self_write_mask & other_read_mask) != 0 and
        (self_read_mask & other_write_mask) != 1);
}

pub fn overlapsMasks(self: Self, other_write_mask: u128, other_read_mask: u128) bool {
    const self_write_mask = self.write_mask orelse return true;
    const self_read_mask = self.read_mask orelse return true;

    return ((self_write_mask & other_write_mask) != 0 and
        (self_write_mask & other_read_mask) != 0 and
        (self_read_mask & other_write_mask) != 1);
}

pub fn hasMasks(self: Self) bool {
    return self.bit_mask != null and self.write_mask != null and self.read_mask != null;
}

pub fn invoke(self: Self, ptrs: []const *anyopaque) void {
    self.callback(ptrs) catch |err| {
        std.log.err("system invoke error: {any} @ {s}", .{ err, self.name });
    };
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

fn getTypes(comptime params: []const Param) []const type {
    var types: core.ComptimeList(type) = .init();

    inline for (params) |param| {
        const BASE = param.type orelse continue;
        const T = switch (@typeInfo(BASE)) {
            .pointer => |wrapping| wrapping.child,
            else => @compileError("system param cannot be a non pointer type"),
        };

        types.append(T);
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
        const ptr = switch (@typeInfo(BASE)) {
            .pointer => |wrapping| wrapping,
            else => @compileError("system param cannot be a non pointer type"),
        };
        const hash = comptime core.type_erasure.typeToHash(ptr.child);

        if (ptr.is_const)
            read.append(hash)
        else
            write.append(hash);

        all.append(hash);
    }

    return .{
        .all = all.items(),
        .write = write.items(),
        .read = read.items(),
    };
}

pub fn wrapFunction(comptime func: anytype) *const fn ([]const *anyopaque) anyerror!void {
    const local = struct {
        pub fn wrapper(args: []const *anyopaque) !void {
            const params = comptime getParams(func);
            const types = comptime getTypes(params);

            comptime var fields: core.ComptimeList(StructField) = .init();

            inline for (types, 0..) |T, index| {
                const name = comptime std.fmt.comptimePrint("{d}", .{index});

                comptime fields.append(StructField{
                    .name = name,
                    .type = *T,
                    .default_value_ptr = null,
                    .alignment = @alignOf(*T),
                    .is_comptime = false,
                });
            }

            const Tuple: type = @Type(.{
                .@"struct" = .{
                    .is_tuple = true,
                    .fields = fields.items(),
                    .decls = &.{},
                    .layout = .auto,
                },
            });

            core.assertFmt(types.len == args.len, "args {d} didn't match expected type len {d}", .{ args.len, types.len });
            var result: Tuple = undefined;

            inline for (0..types.len) |index| {
                const Target = types[index];
                result[index] = core.ptrCast(Target, args[index]);
            }

            try @call(.auto, func, result);
        }
    };

    return local.wrapper;
}
