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

const result = @import("result.zig");
const std = @import("std");
const tester = @import("tester.zig");

pub const Tester = tester.Tester;
pub const eq = @import("eq.zig");
pub const Result = result.Result;

test {
    _ = eq;
    _ = result;
    _ = tester;
}

pub inline fn oom() noreturn {
    @panic("Out of memory");
}

pub inline fn compileError(comptime fmt: []const u8, comptime args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

pub inline fn isStringType(comptime T: type) bool {
    const info = @typeInfo(T);
    const is_string_type = switch (info) {
        .pointer => |pointer| switch (pointer.size) {
            .One => {
                const child_info = @typeInfo(pointer.child);
                return switch (child_info) {
                    .array => |array| array.child == u8,
                    else => false,
                };
            },
            .Slice => pointer.child == u8,
            else => false,
        },
        else => false,
    };

    if (is_string_type)
        std.debug.assert(@TypeOf(T, []const u8) == []const u8);

    return is_string_type;
}
