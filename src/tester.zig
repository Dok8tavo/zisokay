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

const root = @import("root.zig");
const std = @import("std");

pub fn Tester(comptime is_comptime: bool) type {
    return struct {
        allocator: Allocator = default_allocator,
        error_message: Slice = &[_]u8{},
        capacity: Capacity = default_capacity,

        const default_capacity = if (is_comptime) {} else 0;
        const default_allocator = if (is_comptime) {} else std.testing.allocator;

        const Allocator = if (is_comptime) void else std.mem.Allocator;
        const Capacity = if (is_comptime) void else usize;
        const Self = @This();
        const Slice = if (is_comptime) []const u8 else []u8;

        pub fn initComptime() Self {
            std.debug.assert(@inComptime());
            std.debug.assert(is_comptime);
            return .{};
        }

        pub fn initRuntime() Self {
            std.debug.assert(!@inComptime());
            std.debug.assert(!is_comptime);
            return .{};
        }

        pub fn initWithAllocator(allocator: Allocator) Self {
            var tester = Self.initRuntime();
            tester.allocator = allocator;
            return tester;
        }

        pub fn deinit(tester: *Self) void {
            defer tester.dismiss();
            if (tester.error_message.len == 0)
                return;

            if (isComptime())
                @compileError(tester.error_message)
            else
                @panic(tester.error_message);
        }

        pub fn dismiss(tester: *Self) void {
            defer tester.* = undefined;
            if (isComptime())
                return;

            tester.allocator.free(tester.allocatedSlice());
        }

        pub fn report(tester: *Self) void {
            if (isComptime())
                @compileLog(tester.error_message)
            else
                std.debug.print("{s}\n", .{tester.error_message});

            tester.error_message = tester.error_message[0..0];
        }

        pub fn print(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            if (isComptime())
                tester.error_message = tester.error_message ++ std.fmt.comptimePrint(fmt, args)
            else
                std.fmt.format(std.io.GenericWriter(*Self, error{}, writeFn){ .context = tester }, fmt, args) catch unreachable;
        }

        pub fn write(tester: *Self, bytes: []const u8) void {
            if (isComptime()) {
                tester.error_message = tester.error_message ++ bytes;
            } else {
                tester.ensureUnusedCapacity(bytes.len);
                @memcpy(tester.error_message.ptr[tester.error_message.len..][0..bytes.len], bytes);
                tester.error_message.len += bytes.len;
            }
        }

        fn writeFn(tester: *Self, bytes: []const u8) !usize {
            tester.write(bytes);
            return bytes.len;
        }

        fn ensureUnusedCapacity(tester: *Self, unused: usize) void {
            if (isComptime()) return;
            tester.ensureCapacity(tester.error_message.len + unused);
        }

        fn ensureCapacity(tester: *Self, capacity: usize) void {
            if (isComptime())
                return;
            if (capacity <= tester.capacity)
                return;

            var new = tester.capacity;
            while (new < capacity)
                new +|= new / 2 + 8;

            defer tester.capacity = new;
            if (tester.allocator.resize(tester.allocatedSlice(), new))
                return;

            const new_error_message = tester.allocator.alloc(u8, new) catch root.oom();
            @memcpy(new_error_message[0..tester.error_message.len], tester.error_message);
            tester.allocator.free(tester.allocatedSlice());
            tester.error_message = new_error_message[0..tester.error_message.len];
        }

        fn allocatedSlice(tester: *Self) Slice {
            return tester.error_message.ptr[0..tester.capacity];
        }

        inline fn isComptime() bool {
            assertTime();
            return is_comptime;
        }

        inline fn assertTime() void {
            std.debug.assert(@inComptime() == is_comptime);
            std.debug.assert(@import("builtin").is_test);
        }
    };
}

test {
    comptime {
        var ct = Tester(true).initComptime();
        defer ct.dismiss();

        ct.write("Hello");
        std.debug.assert(std.mem.eql(u8, "Hello", ct.error_message));

        ct.print(", {s}!", .{"world"});
        std.debug.assert(std.mem.eql(u8, "Hello, world!", ct.error_message));
    }

    var rt = Tester(false).initRuntime();
    defer rt.dismiss();

    rt.write("Hello");
    try std.testing.expectEqualStrings("Hello", rt.error_message);

    rt.print(", {s}!", .{"world"});
    try std.testing.expectEqualStrings("Hello, world!", rt.error_message);
}
