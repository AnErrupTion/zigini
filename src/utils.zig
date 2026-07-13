const std = @import("std");
const Child = std.meta.Child;
const FieldAttributes = std.lang.Type.Struct.FieldAttributes;

pub fn isDefaultValue(comptime T: anytype, field_value: T, comptime field_attr: FieldAttributes) bool {
    const default_value = getDefaultValue(T, field_attr) catch return false;

    return std.meta.eql(default_value, field_value);
}

fn getDefaultValue(comptime T: anytype, comptime field_attr: FieldAttributes) !T {
    const default_value = field_attr.defaultValue(T);

    return default_value orelse error.NoDefaultValue;
}

fn RemoveOptional(comptime T: type) type {
    if (@typeInfo(T) == .optional) return Child(T);
    return T;
}

pub fn unwrapIfOptional(comptime T: type, val: T) RemoveOptional(T) {
    if (@typeInfo(T) == .optional) return val.?;
    return val;
}
