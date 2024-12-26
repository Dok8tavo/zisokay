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

pub inline fn send(message: Message) void {
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

pub inline fn print(message: *Message, comptime fmt: []const u8, args: anytype) void {
    message.writer().print(fmt, args) catch unreachable;
}

pub inline fn writer(message: *Message) Writer {
    return .{ .context = message };
}

pub inline fn writeFn(message: *Message, bytes: []const u8) error{}!usize {
    message.write(bytes);
    return bytes.len;
}
