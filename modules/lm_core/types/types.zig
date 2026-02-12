pub const Array = @import("array.zig").Array;
pub const List = @import("list.zig").List;
pub const ComptimeList = @import("comptime_list.zig").ComptimeList;
pub const ByteList = @import("ByteList.zig");
pub const PagedList = @import("paged_list.zig").PagedList;
pub const SparseSet = @import("sparse_set.zig").SparseSet;
pub const ByteSparseSet = @import("ByteSparseSet.zig");

pub const coerceTo = @import("type_switcher.zig").coerceTo;

pub const iterator_functions = @import("iterator_functions.zig");
pub const type_switcher = @import("type_switcher.zig");

pub fn KeyValuePair(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,

        pub fn init(key: K, value: V) KeyValuePair(K, V) {
            return .{
                .key = key,
                .value = value,
            };
        }
    };
}

pub inline fn isTuple(value: anytype) bool {
    return comptime switch (@typeInfo(@TypeOf(value))) {
        .@"struct" => |info| info.is_tuple,
        else => false,
    };
}
