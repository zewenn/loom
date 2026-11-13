const std = @import("std");
const lm_types = @import("lm_types");

const Self = @This();

/// Type-erased callback signature invoked by the archetype runner once per matching archetype.
const GenericSystemFunction = *const fn (entity_count: usize, column_buffers: [*][*]u8) anyerror!void;

const ComponentHashSets = struct {
    all_hashes: []const u64,
    write_hashes: []const u64,
    read_hashes: []const u64,
};

/// Deterministic hash of the wrapped system function type.
id: u64,
/// Comptime type name of the wrapped system function for error diagnostics.
name: []const u8,
/// Wrapped entrypoint accepting raw dense column buffers and an entity count.
callback: GenericSystemFunction,
/// Component type hashes required across all parameters, in parameter order.
hashes: []const u64,
/// Component type hashes accessed mutably by the system.
write_hashes: []const u64,
/// Component type hashes accessed as read-only by the system.
read_hashes: []const u64,

/// Bitmask covering all components required by this system, or null until registered types resolve.
bit_mask: ?u128 = null,
/// Bitmask of components written by this system.
write_mask: ?u128 = null,
/// Bitmask of components read by this system.
read_mask: ?u128 = null,

/// Wrap a Zig function taking component slices into a type-erased `System`.
pub fn init(comptime system_function: anytype) Self {
    const hash_sets = comptime collectComponentHashes(system_function);
    return Self{
        .id = comptime lm_types.type_erasure.typeToHash(@TypeOf(system_function)),
        .name = @typeName(@TypeOf(system_function)),
        .callback = comptime wrapFunction(system_function),
        .hashes = hash_sets.all_hashes,
        .write_hashes = hash_sets.write_hashes,
        .read_hashes = hash_sets.read_hashes,
    };
}

/// Return true if running `self` concurrently with `other` could cause a read/write or write/write race.
pub fn overlaps(self: Self, other: Self) bool {
    const other_write_mask = other.write_mask orelse return true;
    const other_read_mask = other.read_mask orelse return true;

    return self.overlapsMasks(other_write_mask, other_read_mask);
}

/// Return true if running `self` concurrently with the given write/read bitmasks conflicts.
pub fn overlapsMasks(self: Self, other_write_mask: u128, other_read_mask: u128) bool {
    const self_write_mask = self.write_mask orelse return true;
    const self_read_mask = self.read_mask orelse return true;

    return (self_write_mask & other_write_mask) != 0 or
        (self_write_mask & other_read_mask) != 0 or
        (self_read_mask & other_write_mask) != 0;
}

/// Return true when all bitmasks for this system have been resolved against a `World`.
pub fn hasMasks(self: Self) bool {
    return self.bit_mask != null and self.write_mask != null and self.read_mask != null;
}

/// Generate a `GenericSystemFunction` that casts raw archetype column buffers to typed slices.
pub fn wrapFunction(comptime system_function: anytype) GenericSystemFunction {
    return struct {
        pub fn invoke(entity_count: usize, column_buffers: [*][*]u8) anyerror!void {
            const parameter_types = comptime getParameterTypes(system_function);
            const component_types = comptime extractComponentTypes(parameter_types);

            comptime var slice_types: [component_types.len]type = undefined;
            inline for (component_types, 0..) |ComponentType, parameter_index| {
                slice_types[parameter_index] = []ComponentType;
            }
            const ArgumentTuple = @Tuple(&slice_types);

            var slice_arguments: ArgumentTuple = undefined;
            inline for (component_types, 0..) |ComponentType, parameter_index| {
                const typed_buffer: [*]ComponentType = @ptrCast(@alignCast(column_buffers[parameter_index]));
                slice_arguments[parameter_index] = typed_buffer[0..entity_count];
            }

            try @call(.auto, system_function, slice_arguments);
        }
    }.invoke;
}

inline fn getParameterTypes(comptime system_function: anytype) []const ?type {
    return switch (@typeInfo(@TypeOf(system_function))) {
        .@"fn" => |function_info| function_info.param_types,
        else => @compileError("system function must be a function"),
    };
}

inline fn componentTypeOf(comptime ParameterSlice: type) type {
    const type_info = @typeInfo(ParameterSlice);
    if (type_info != .pointer or type_info.pointer.size != .slice) {
        @compileError("system parameter must be a slice");
    }

    const element_type = type_info.pointer.child;
    return switch (@typeInfo(element_type)) {
        .pointer => |child_pointer_info| child_pointer_info.child,
        else => element_type,
    };
}

inline fn isReadOnlyParameter(comptime ParameterSlice: type) bool {
    const Child = componentTypeOf(ParameterSlice);
    return ParameterSlice == []const Child or
        ParameterSlice == []*const Child or
        ParameterSlice == []const *const Child;
}

fn extractComponentTypes(comptime parameter_types: []const ?type) []const type {
    var component_types: lm_types.ComptimeList(type) = .init();

    inline for (parameter_types) |maybe_parameter_type| {
        const parameter_type = maybe_parameter_type orelse @compileError("system parameter must have a concrete type");
        component_types.append(componentTypeOf(parameter_type));
    }

    return component_types.items();
}

fn collectComponentHashes(comptime system_function: anytype) ComponentHashSets {
    const parameter_types = comptime getParameterTypes(system_function);

    var all_hashes: lm_types.ComptimeList(u64) = .init();
    var write_hashes: lm_types.ComptimeList(u64) = .init();
    var read_hashes: lm_types.ComptimeList(u64) = .init();

    inline for (parameter_types) |maybe_parameter_type| {
        const parameter_type = maybe_parameter_type orelse @compileError("system parameter must have a concrete type");
        const component_hash = comptime lm_types.type_erasure.typeToHash(componentTypeOf(parameter_type));
        all_hashes.append(component_hash);
        if (isReadOnlyParameter(parameter_type)) {
            read_hashes.append(component_hash);
        } else {
            write_hashes.append(component_hash);
        }
    }

    return .{
        .all_hashes = all_hashes.items(),
        .write_hashes = write_hashes.items(),
        .read_hashes = read_hashes.items(),
    };
}
