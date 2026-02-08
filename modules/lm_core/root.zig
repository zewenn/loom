const std = @import("std");
const builtin = @import("builtin");

pub const types = @import("types/types.zig");

pub const Array = types.Array;
pub const List = types.List;
pub const coerceTo = types.coerceTo;
pub const iterator_functions = types.iterator_functions;

pub const type_erasure = @import("type_erasure.zig");

pub fn comptimeAssert(comptime statement: bool, comptime fail_msg: []const u8) void {
    if (statement) return;

    @compileError(fail_msg);
}

pub fn assert(statement: bool, comptime fail_msg: []const u8) void {
    assertFmt(statement, fail_msg, .{});
}

pub fn assertFmt(statement: bool, comptime fail_msg: []const u8, fmt: anytype) void {
    if (statement) return;

    std.log.err(fail_msg, fmt);
    @panic("ASSERTION FAILIURE");
}

pub fn deprecated(comptime msg: []const u8) void {
    if (builtin.is_test) return;

    @compileError("[DEPRECATED] " ++ msg);
}
