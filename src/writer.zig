const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils.zig");
const Child = std.meta.Child;

const FieldHandlerFn = fn (comptime ns: ?[]const u8, comptime key: ?[]const u8) ?[]const u8;
const WriteValueFn = @TypeOf(defaultWriteValue);

const WriteOptions = struct {
    renameHandler: ?FieldHandlerFn = null,
    writeValue: WriteValueFn = defaultWriteValue,

    // Whether to write fields when they're the same as the default value
    write_default_values: bool = true,
};

pub fn writeFromStruct(data: anytype, writer: *std.Io.Writer, comptime namespace: ?[]const u8, comptime opts: WriteOptions) !void {
    comptime var should_write_ns = namespace != null and namespace.?.len != 0;
    comptime var field_names: [][]const u8 = &.{};
    comptime var field_types: []type = &.{};

    const str = @typeInfo(@TypeOf(data)).@"struct";

    inline for (str.field_names, str.field_types, str.field_attrs) |name, ftype, attr| {
        switch (@typeInfo(ftype)) {
            .@"struct" => {
                field_names = @constCast(field_names ++ .{name});
                field_types = @constCast(field_types ++ .{ftype});
            },
            else => |t_info| {
                if (t_info == .optional and @typeInfo(Child(ftype)) == .@"struct") {
                    field_names = @constCast(field_names ++ .{name});
                    field_types = @constCast(field_types ++ .{ftype});
                    continue;
                }

                comptime var field_name: []const u8 = name;
                comptime if (opts.renameHandler) |handler| {
                    const new_field_name = @call(.auto, handler, .{ namespace, field_name });
                    if (new_field_name != null) {
                        field_name = new_field_name.?;
                    } else continue;
                };

                if (should_write_ns) {
                    comptime var mapped_ns: []const u8 = namespace.?;
                    comptime if (opts.renameHandler) |handler| {
                        mapped_ns = @call(.auto, handler, .{ namespace, null }) orelse mapped_ns;
                    };
                    try writer.print("[{s}]\n", .{mapped_ns});
                    should_write_ns = false;
                }

                const value = @field(data, name);
                if (opts.write_default_values or !utils.isDefaultValue(ftype, value, attr)) {
                    if (t_info == .optional and value == null) {
                        try writeProperty(writer, field_name, "null", opts.writeValue);
                    } else {
                        try writeProperty(writer, field_name, utils.unwrapIfOptional(ftype, value), opts.writeValue);
                    }
                }
            },
        }
    }

    if (namespace == null or namespace.?.len == 0) {
        inline for (field_names, field_types) |name, ftype| {
            if (@typeInfo(ftype) == .@"struct") {
                try writeFromStruct(@field(data, name), writer, name, opts);
            } else if (@field(data, name)) |inner_data| {
                try writeFromStruct(inner_data, writer, name, opts);
            }
        }
    }
}

pub fn defaultWriteValue(writer: *std.Io.Writer, comptime T: type, val: T) anyerror!void {
    switch (@typeInfo(T)) {
        .bool => {
            try writer.print("{s}", .{if (val) "true" else "false"});
        },
        .int, .comptime_int, .float, .comptime_float => {
            try writer.print("{d}", .{val});
        },
        .@"enum" => {
            try writer.print("{s}", .{@tagName(val)});
        },
        else => {
            try writer.print("{s}", .{val});
        },
    }
}

fn writeProperty(writer: *std.Io.Writer, field_name: []const u8, val: anytype, comptime writeValue: WriteValueFn) anyerror!void {
    try writer.print("{s}=", .{field_name});
    try writeValue(writer, @TypeOf(val), val);
    try writer.writeByte('\n');
}
