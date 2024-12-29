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

const eq = @import("eq.zig");
const root = @import("root.zig");
const std = @import("std");

pub fn Tester(comptime is: enum { at_runtime, at_comptime }) type {
    return struct {
        allocator: Allocator = default_allocator,
        messages: Messages = &[_]u8{},
        capacity: Capacity = default_capacity,
        init_at: StackTrace,

        const is_comptime = is == .at_comptime;
        const default_capacity = if (is_comptime) {} else 0;
        const default_allocator = if (is_comptime) {} else std.testing.allocator;

        const Allocator = if (is_comptime) void else std.mem.Allocator;
        const Capacity = if (is_comptime) void else usize;
        const Messages = if (is_comptime) []const u8 else []u8;
        const Self = @This();
        const StackTrace = if (is_comptime) void else std.builtin.StackTrace;

        const tester_has_error_messages = "Tester has error messages:\n" ++
            "\x1B[31;1m============================\x1B[m" ++
            "{s}" ++
            "\x1B[31;1m============================\x1B[m\n";

        pub fn init() Self {
            return if (isComptime())
                Self.initComptime()
            else
                Self.initRuntime();
        }

        pub fn initRuntime() Self {
            std.debug.assert(!@inComptime());
            std.debug.assert(!is_comptime);
            var tester = Self{ .init_at = undefined };
            std.debug.captureStackTrace(@returnAddress(), &tester.init_at);
            return tester;
        }

        pub fn initComptime() Self {
            std.debug.assert(@inComptime());
            std.debug.assert(is_comptime);
            return .{ .init_at = {} };
        }

        pub fn initWithAllocator(allocator: Allocator) Self {
            var tester = Self.initRuntime();
            tester.allocator = allocator;
            return tester;
        }

        pub fn deinit(tester: *Self) void {
            defer tester.dismiss();
            if (tester.messages.len == 0)
                return;

            if (isComptime())
                root.compileError(tester_has_error_messages, .{tester.messages})
            else {
                std.debug.panic(tester_has_error_messages ++
                    "Tester panicked here:", .{tester.messages});
            }
        }

        pub fn report(tester: *Self) void {
            if (isComptime())
                root.compileLog(tester_has_error_messages, .{tester.messages})
            else {
                tester.write(
                    "Tester reported here:\n",
                );
                tester.writeCurrentStackTrace();
                std.debug.print(tester_has_error_messages, .{tester.messages});
            }

            tester.reset();
        }

        pub fn dismiss(tester: *Self) void {
            defer tester.* = undefined;
            if (isComptime())
                return;

            tester.allocator.free(tester.allocatedSlice());
        }

        pub fn reset(tester: *Self) void {
            tester.messages = tester.messages[0..0];
        }

        pub fn expectEqual(tester: *Self, expected: anytype, actual: anytype) void {
            if (!tester.expectEqualInternal(expected, actual))
                tester.writeCurrentStackTrace();
        }

        pub fn expectEqualInternal(tester: *Self, expected: anytype, actual: anytype) bool {
            const T = @TypeOf(expected, actual);
            const t_info = @typeInfo(T);
            const expected_as_t = @as(T, expected);
            const actual_as_t = @as(T, actual);
            return switch (t_info) {
                .void, .null, .noreturn, .undefined => true,
                .bool,
                .comptime_float,
                .comptime_int,
                .@"enum",
                .enum_literal,
                .error_set,
                .float,
                .int,
                .type,
                => {
                    if (expected_as_t == actual_as_t)
                        return true;

                    tester.err(expect_equal_messages.value, .{ expected_as_t, actual_as_t });
                    return false;
                },
                .vector, .array => for (expected_as_t, actual_as_t, 1..) |expected_item, actual_item, number| {
                    if (!tester.expectEqualInternal(expected_item, actual_item)) {
                        tester.info(expect_equal_messages.which_item, .{ number, @tagName(t_info) });
                        break false;
                    }
                } else true,
                .@"struct" => |struct_info| inline for (struct_info.fields) |field| {
                    if (!tester.expectEqualInternal(@field(expected_as_t, field.name), @field(actual_as_t, field.name))) {
                        tester.info(expect_equal_messages.which_field, .{field.name});
                        break false;
                    }
                } else true,
                .@"union" => |union_info| {
                    if (union_info.tag_type == null) root.compileError(
                        "Union `{s}` can't be compared by equality, as it's untagged!",
                        .{@typeName(T)},
                    );

                    const actual_tag = std.meta.activeTag(actual_as_t);
                    const expected_tag = std.meta.activeTag(expected_as_t);
                    if (actual_tag != expected_tag) {
                        tester.err(expect_equal_messages.variant, .{ @tagName(expected_tag), @tagName(actual_tag) });
                        return false;
                    }

                    return switch (actual_tag) {
                        inline else => |tag| {
                            const expected_payload = @field(expected_as_t, @tagName(tag));
                            const actual_payload = @field(actual_as_t, @tagName(tag));
                            if (!tester.expectEqualInternal(expected_payload, actual_payload)) {
                                tester.info(expect_equal_messages.which_variant, .{@tagName(expected_tag)});
                                return false;
                            }

                            return true;
                        },
                    };
                },
                .error_union => if (expected_as_t) |expected_payload| {
                    if (actual_as_t) |actual_payload| {
                        if (tester.expectEqualInternal(expected_payload, actual_payload))
                            return true;

                        tester.info(expect_equal_messages.payload_of_error_union, .{});
                        return false;
                    } else |actual_error| {
                        tester.err(expect_equal_messages.error_instead_of_payload, .{actual_error});
                        return false;
                    }
                } else |expected_error| {
                    if (actual_as_t) |_| {
                        tester.err(expect_equal_messages.payload_instead_of_error, .{expected_error});
                        return false;
                    } else |actual_error| {
                        if (tester.expectEqualInternal(expected_error, actual_error))
                            return true;

                        tester.info(expect_equal_messages.error_of_error_union, .{});
                        return false;
                    }
                },
                .optional => if (expected_as_t) |expected_payload| {
                    if (actual_as_t) |actual_payload| {
                        if (tester.expectEqualInternal(expected_payload, actual_payload))
                            return true;

                        tester.info(expect_equal_messages.payload_of_optional, .{});
                        return false;
                    } else {
                        tester.err(expect_equal_messages.null_instead_of_payload, .{});
                        return false;
                    }
                } else if (actual_as_t) |_| {
                    tester.err(expect_equal_messages.payload_instead_of_null, .{});
                    return false;
                } else true,
                .pointer => root.compileError(
                    "Pointers can't be trivially compared by equality!",
                    .{},
                ),
                .@"anyframe", .@"fn", .@"opaque", .frame => root.compileError(
                    "Types `.{s}` can't be compared by equality!",
                    .{@tagName(t_info)},
                ),
            };
        }

        pub fn expectTrue(tester: *Self, condition: bool) void {
            tester.expectEqual(true, condition);
        }

        pub fn err(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print("\n\x1B[31;1merror\x1B[0m: " ++ fmt, args);
        }

        pub fn warn(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print("\n\x1B[33;1mwarning\x1B[0m: " ++ fmt, args);
        }

        pub fn info(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print("\n\x1B[36;1minfo\x1B[0m: " ++ fmt, args);
        }

        pub fn debug(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print("\n\x1B[1mdebug\x1B[0m: " ++ fmt, args);
        }

        pub fn print(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            if (isComptime())
                tester.messages = tester.messages ++ std.fmt.comptimePrint(fmt, args)
            else
                tester.writer().print(fmt, args) catch unreachable;
        }

        pub fn write(tester: *Self, bytes: []const u8) void {
            if (isComptime()) {
                tester.messages = tester.messages ++ bytes;
            } else {
                tester.ensureUnusedCapacity(bytes.len);
                @memcpy(tester.messages.ptr[tester.messages.len..][0..bytes.len], bytes);
                tester.messages.len += bytes.len;
            }
        }

        inline fn writeCurrentStackTrace(tester: *Self) void {
            if (isComptime())
                return;

            tester.write("\n");
            std.debug.writeCurrentStackTrace(
                tester.writer(),
                std.debug.getSelfDebugInfo() catch root.oom(),
                .escape_codes,
                @returnAddress(),
            ) catch root.oom();
        }

        const Writer = std.io.Writer(*Self, error{}, writeFn);
        fn writer(tester: *Self) Writer {
            return Writer{ .context = tester };
        }

        fn writeFn(tester: *Self, bytes: []const u8) !usize {
            tester.write(bytes);
            return bytes.len;
        }

        fn ensureUnusedCapacity(tester: *Self, unused: usize) void {
            if (isComptime()) return;
            tester.ensureCapacity(tester.messages.len + unused);
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
            @memcpy(new_error_message[0..tester.messages.len], tester.messages);
            tester.allocator.free(tester.allocatedSlice());
            tester.messages = new_error_message[0..tester.messages.len];
        }

        fn allocatedSlice(tester: *Self) Messages {
            return tester.messages.ptr[0..tester.capacity];
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

const expect_equal_messages = .{
    // those are errors
    .value = "Expected value `{any}`, got `{any}`!",
    .variant = "Expected union variant `.{s}`, got `.{s}`!",
    .error_instead_of_payload = "Expected payload of error_union, got error `{any}`!",
    .payload_instead_of_error = "Expected error `{any}` of error_union, got payload!",
    .null_instead_of_payload = "Expected payload of optional, got `null`!",
    .payload_instead_of_null = "Expected `null`, got payload of optional!",
    // those are additional informations
    .which_item = "Item {} of the {s}.",
    .which_field = "Field `.{s}` of the struct.",
    .which_variant = "Variant `.{s}` of the union.",
    .payload_of_error_union = "Payload of error union.",
    .error_of_error_union = "Error of error union.",
    .payload_of_optional = "Payload of optional.",
};
test "Tester(...).expectEqual" {
    var t = Tester(.at_runtime).init();
    defer t.deinit();

    // booleans
    t.expectEqual(true, true);
    t.expectEqual(false, false);
    try std.testing.expectEqual(t.messages.len, 0);

    t.expectEqual(true, false);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.value, .{ true, false }),
    ));
    t.report();

    // arrays
    t.expectEqual([3]u16{ 1, 2, 3 }, [3]u16{ 1, 1000, 3 });
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.value, .{ 2, 1000 }),
    ));
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.which_item, .{ 2, "array" }),
    ));
    t.reset();

    // structs
    const Struct = struct { a: usize, b: isize };
    t.expectEqual(Struct{ .a = 1, .b = 2 }, Struct{ .a = 1, .b = 1000 });
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.value, .{ 2, 1000 }),
    ));
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.which_field, .{"b"}),
    ));
    t.reset();

    // unions
    const Union = union(enum) { a: usize, b: isize };
    t.expectEqual(Union{ .a = 1 }, Union{ .b = 2 });
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.variant, .{ "a", "b" }),
    ));
    t.reset();

    // error unions
    const ErrorUnion = error{ ErrorA, ErrorB }!u8;
    t.expectEqual(@as(ErrorUnion, 1), 2);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        expect_equal_messages.payload_of_error_union,
    ));
    t.report();
    t.expectEqual(@as(ErrorUnion, error.ErrorA), error.ErrorB);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.error_of_error_union, .{}),
    ));
    t.expectEqual(@as(ErrorUnion, error.ErrorA), 0);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.payload_instead_of_error, .{error.ErrorA}),
    ));
    t.expectEqual(@as(ErrorUnion, 1), error.ErrorB);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.error_instead_of_payload, .{error.ErrorB}),
    ));
    t.reset();

    // optionals
    t.expectEqual(@as(?u8, 1), 2);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.payload_of_optional, .{}),
    ));
    t.expectEqual(@as(?u8, null), 0);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.payload_instead_of_null, .{}),
    ));
    t.expectEqual(@as(?u8, 1), null);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        t.messages,
        1,
        std.fmt.comptimePrint(expect_equal_messages.null_instead_of_payload, .{}),
    ));
    t.reset();
}

test "Tester(...).{ initComptime, initRuntime, dismiss, write, print }" {
    comptime {
        var ct = Tester(.at_comptime).init();
        defer ct.dismiss();

        ct.write("Hello");
        std.debug.assert(std.mem.eql(u8, "Hello", ct.messages));

        ct.print(", {s}!", .{"world"});
        std.debug.assert(std.mem.eql(u8, "Hello, world!", ct.messages));
    }

    var rt = Tester(.at_runtime).init();
    defer rt.dismiss();

    rt.write("Hello");
    try std.testing.expectEqualStrings("Hello", rt.messages);

    rt.print(", {s}!", .{"world"});
    try std.testing.expectEqualStrings("Hello, world!", rt.messages);
}
