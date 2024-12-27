// MIT License
//
// Copyright (c) 2024 Dok8tavo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

allocator: Allocator = std.testing.allocator,
message: List(u8) = .{},

const root = @import("root.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const NoError = error{};
const Test = @This();

pub const Error = error{TestFailed};
pub const Writer = std.io.GenericWriter(*Test, NoError, writeFn);

pub inline fn expectVariant(t: *Test, sum_value: anytype, variant_selector: anytype) void {
    const VariantSelector = @TypeOf(variant_selector);
    const vs_info = @typeInfo(VariantSelector);
    const variant_string: []const u8 = switch (vs_info) {
        .enum_literal, .@"enum" => @tagName(variant_selector),
        .@"union" => |u| if (u.tag_type == null) root.compileError(
            \\The type of the `variant_selector` parameter can only be:
            \\- an enum literal,
            \\- an enum variant,
            \\- a tagged union,
            \\- a string type.
            \\
            \\`{s}` is a union type, but it's not tagged!
            \\
        , .{}) else @tagName(variant_selector),
        .pointer => if (root.isStringType(variant_selector))
            variant_selector
        else
            root.compileError(
                \\The type of the `variant_selector` parameter can only be:
                \\- an enum literal,
                \\- an enum variant,
                \\- a tagged union,
                \\- a string type.
                \\
                \\`{s}` is a pointer type, but not a string type!
                \\
            , .{@typeName(VariantSelector)}),
        else => root.compileError(
            \\The type of the `variant_selector` parameter can only be:
            \\- an enum literal,
            \\- an enum variant,
            \\- a tagged union,
            \\- a string type.
            \\
            \\Not a `.{s}` type like `{s}`!
            \\
        , .{ @tagName(vs_info), @typeName(VariantSelector) }),
    };

    const tag_name = @tagName(sum_value);
    const is_tag = tag_name.len == variant_string.len and for (tag_name, variant_string) |tn, vs| {
        if (tn != vs) break false;
    } else true;
    if (!is_tag) t.print(
        "Expected variant `.{s}`, found `.{s}`!\n",
        .{ variant_string, tag_name },
    );
}

pub inline fn expectPayload(t: *Test, value: anytype) void {
    const Value = @TypeOf(value);
    const info = @typeInfo(Value);
    switch (info) {
        .error_union => if (value) |_| {} else |err| t.print(
            "Expected payload, found error `{s}`!\n",
            .{@errorName(err)},
        ),
        .error_set => t.print(
            "Expected payload, found error `{s}`!\n",
            .{@errorName(value)},
        ),
        .optional, .null => if (value == null) t.write("Expected payload, found `null`!\n"),
        else => root.compileError(
            \\The type of the `value` parameter can be:
            \\- an optional,
            \\- null,
            \\- an error union,
            \\- or an error set.
            \\
            \\Not a `.{s}` like `{s}`!,
            \\
        , .{@tagName(info)}),
    }
}

pub inline fn expectTrue(t: *Test, value: bool) void {
    if (!value) t.write("Expected `true`, found `false`!");
}

/// This function panics or emit a compile error if the message of the test isn't empty.
pub inline fn logPanic(t: Test) void {
    if (t.message.items.len == 0)
        return;

    if (@inComptime())
        @compileError(t.message.items)
    else
        @panic(t.message.items);
}

/// This function reports the message of the test and propagate the error further.
/// During compile-time this function calls `@compileLog`, so even if the compilation process
/// can continue, it can't actually recover.
pub inline fn logReport(t: Test) Error!void {
    if (t.message.items.len == 0)
        return;

    if (@inComptime())
        @compileLog(t.message.items)
    else
        std.debug.print("{s}", .{t.message.items});

    return Error.TestFailed;
}

pub inline fn print(t: *Test, comptime format: []const u8, args: anytype) void {
    t.writer().print(format, args) catch unreachable;
}

pub inline fn writeStructEndian(t: *Test, value: anytype, endian: std.builtin.Endian) void {
    t.writer().writeStructEndian(value, endian) catch unreachable;
}

pub inline fn writeStruct(t: *Test, value: anytype) void {
    t.writer().writeStruct(value) catch unreachable;
}

pub inline fn writeInt(t: *Test, comptime T: type, value: T, endian: std.builtin.Endian) void {
    t.writer().writeInt(T, value, endian) catch unreachable;
}

pub inline fn writeBytesNTimes(t: *Test, bytes: []const u8, n: usize) void {
    t.writer().writeBytesNTimes(bytes, n) catch unreachable;
}

pub inline fn writeByteNTimes(t: *Test, byte: u8, n: usize) void {
    t.writer().writeByteNTimes(byte, n) catch unreachable;
}

pub inline fn writeByte(t: *Test, byte: u8) void {
    t.writer().writeByte(byte) catch unreachable;
}

pub inline fn writeAll(t: *Test, bytes: []const u8) void {
    t.writer().writeAll(bytes) catch unreachable;
}

pub inline fn write(t: *Test, bytes: []const u8) usize {
    return t.writer().write(bytes) catch unreachable;
}

pub inline fn writer(t: *Test) Writer {
    return Writer{ .context = t };
}

pub inline fn any(t: *Test) std.io.AnyWriter {
    return t.writer().any();
}

inline fn writeFn(t: *Test, bytes: []const u8) NoError!usize {
    return if (@inComptime())
        t.writeAtComptime(bytes)
    else
        t.writeAtRuntime(bytes);
}
inline fn writeAtRuntime(t: *Test, bytes: []const u8) usize {
    t.message.appendSlice(t.allocator, bytes) catch root.oom();
    return bytes.len;
}
inline fn writeAtComptime(t: *Test, bytes: []const u8) usize {
    t.message.items = t.message.items ++ bytes;
    t.message.capacity = t.message.items;
    return bytes.len;
}
