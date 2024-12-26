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
string: List(u8) = .{},

const root = @import("root.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Message = @This();
pub const Writer = std.io.GenericWriter(*Message, error{}, writeFn);

pub inline fn log(message: Message) void {
    if (message.string.items.len == 0)
        return;
    if (@inComptime())
        root.compileError(message.string.items)
    else
        std.debug.print("{s}", .{message.string.items});
}

pub inline fn write(message: *Message, bytes: []const u8) void {
    const len = message.string.items.len;
    const cap = message.string.items.capacity;
    if (cap - len < bytes) message.string.ensureTotalCapacity(
        message.allocator,
        len + @max(bytes.len, @min(4096, len)),
    ) catch root.oom();
    message.string.appendSliceAssumeCapacity(bytes);
}

pub inline fn writeAll(message: *Message, bytes: []const u8) void {
    message.writer().writeAll(bytes) catch unreachable;
}

pub inline fn print(message: *Message, comptime format: []const u8, args: anytype) void {
    message.writer().print(format, args) catch unreachable;
}

pub inline fn writeByte(message: *Message, byte: u8) void {
    message.writer().writeByte(byte) catch unreachable;
}

pub inline fn writeByteNTimes(message: *Message, byte: u8, n: usize) void {
    message.writer().writeByteNTimes(byte, n) catch unreachable;
}

pub inline fn writeBytesNTimes(message: *Message, bytes: []const u8, n: usize) void {
    message.writer().writeBytesNTimes(bytes, n) catch unreachable;
}

pub inline fn writeInt(
    message: *Message,
    comptime T: type,
    value: T,
    endian: std.builtin.Endian,
) void {
    return message.writer().writeInt(T, value, endian) catch unreachable;
}

pub inline fn writeStruct(message: *Message, value: anytype) void {
    return message.writer().writeStruct(value) catch unreachable;
}

pub inline fn writeStructEndian(
    message: *Message,
    value: anytype,
    endian: std.builtin.Endian,
) void {
    message.writer().writeStructEndian(value, endian) catch unreachable;
}

pub const any = root.compileError(
    \\The `{s}` type doesn't use the `any` name from `GenericWriter(...).any`
    \\You might want to use `.anyWriter` instead!
);

pub inline fn anyWriter(message: *Message) std.io.AnyWriter {
    return message.writer().any();
}

pub inline fn writer(message: *Message) Writer {
    return .{ .context = message };
}

pub inline fn writeFn(message: *Message, bytes: []const u8) error{}!usize {
    message.write(bytes);
    return bytes.len;
}
