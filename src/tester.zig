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

const Location = @import("Location.zig");
const max_width = 100;

pub fn Tester(comptime is: enum { at_runtime, at_comptime }) type {
    return struct {
        allocator: Allocator = default_allocator,
        messages: Messages = &[_]u8{},
        capacity: Capacity = default_capacity,
        init_stack_trace: StackTrace,

        const is_comptime = is == .at_comptime;
        const default_capacity = if (is_comptime) {} else 0;
        const default_allocator = if (is_comptime) {} else std.testing.allocator;

        const Allocator = if (is_comptime) void else std.mem.Allocator;
        const Capacity = if (is_comptime) void else usize;
        const Messages = if (is_comptime) []const u8 else []u8;
        const Self = @This();
        const StackTrace = if (is_comptime) void else std.ArrayListUnmanaged(u8);

        pub fn init() Self {
            return if (isComptime())
                Self{ .init_stack_trace = {} }
            else
                Self.initWithAllocator(std.testing.allocator);
        }

        pub inline fn initWithAllocator(allocator: Allocator) Self {
            if (isComptime())
                return .{ .init_stack_trace = {} };
            var tester = Self{ .allocator = allocator, .init_stack_trace = .{} };
            tester.captureCurrentStackTrace();
            return tester;
        }

        pub fn deinit(tester: *Self) void {
            defer tester.dismiss();
            if (tester.messages.len == 0)
                return;

            if (isComptime()) root.compileError(
                Separator.tester_has_error_messages.string ++ "{s}",
                .{tester.messages},
            ) else {
                std.debug.print(
                    Separator.tester_has_error_messages.string ++ "{s}" ++
                        Separator.tester_init_stack_trace.string ++ "{s}" ++
                        Separator.tester_deinit_stack_trace.string,
                    .{ tester.messages, tester.init_stack_trace.items },
                );

                @panic("Tester had non-dismissed error messages when deinited.");
            }
        }

        pub fn report(tester: *Self) void {
            if (isComptime()) root.compileError(
                Separator.tester_has_error_messages.string ++ "{s}\n",
                .{tester.messages},
            ) else {
                std.debug.print(
                    Separator.tester_has_error_messages.string ++ "{s}" ++
                        Separator.tester_report_stack_trace.string,
                    .{tester.messages},
                );

                std.debug.dumpCurrentStackTrace(@returnAddress());
                std.debug.print(Separator.tester_init_stack_trace.string, .{});
                std.debug.print("{s}\n", .{tester.init_stack_trace.items});
            }

            tester.reset();
        }

        pub fn dismiss(tester: *Self) void {
            defer tester.* = undefined;
            if (isComptime())
                return;

            tester.allocator.free(tester.allocatedSlice());
            tester.init_stack_trace.clearAndFree(tester.allocator);
        }

        pub fn reset(tester: *Self) void {
            tester.messages = tester.messages[0..0];
            if (!is_comptime) {
                tester.init_stack_trace.clearRetainingCapacity();
                tester.captureCurrentStackTrace();
            }
        }

        pub fn expectEqualAsciiStrings(tester: *Self, expected: []const u8, actual: []const u8) void {
            const min_len = @min(expected.len, actual.len);
            const index_of_difference = for (0..min_len) |index| {
                if (expected[index] != actual[index]) break index;
            } else if (expected.len != actual.len) min_len else return;
            _ = index_of_difference;

            tester.write(Separator.unexpected_string_error.string ++ Separator.expected_string.string);
            tester.writeAsciiString(expected);
            tester.write(Separator.actual_string.string);
            tester.writeAsciiString(actual);
        }

        pub fn expectEqual(tester: *Self, expected: anytype, actual: anytype) void {
            if (!tester.expectEqualInternal(expected, actual)) {
                if (isComptime()) {
                    tester.write(Separator.tester_deinit_stack_trace.string);
                    return;
                }
                tester.write(Separator.tester_expect_stack_trace.string);
                tester.writeCurrentStackTrace();
            }
        }

        pub fn expectTrue(tester: *Self, condition: bool) void {
            tester.expectEqual(true, condition);
        }

        pub fn err(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print(styles.reset ++ styles.err ++ "error" ++ styles.reset ++ ": " ++ fmt ++ "\n", args);
        }

        pub fn warn(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print(styles.reset ++ styles.warn ++ "warning" ++ styles.reset ++ ": " ++ fmt ++ "\n", args);
        }

        pub fn info(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print(styles.reset ++ styles.info ++ "info" ++ styles.reset ++ ": " ++ fmt ++ "\n", args);
        }

        pub fn debug(tester: *Self, comptime fmt: []const u8, args: anytype) void {
            tester.print(styles.reset ++ styles.debug ++ "debug" ++ styles.reset ++ ": " ++ fmt ++ "\n", args);
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

        pub fn writeNTimes(tester: *Self, bytes: []const u8, n: usize) void {
            for (0..n) |_| tester.write(bytes);
        }

        fn writeAsciiString(tester: *Self, string: []const u8) void {
            const code_style = styles.dim;
            const whitespace_style = styles.green ++ styles.dim;
            const delete_style = styles.red ++ styles.dim;
            const invalid_style = styles.red;

            const max_line = Location.maxLine(string);
            const max_line_length: usize = cifers(max_line);
            const clamp = max_width - max_line_length - 2;
            var index: usize = 0;
            var line: usize = 1;
            var column: usize = 1;
            {
                const spaces = max_line_length - 1;
                tester.writeNTimes(" ", spaces);
                tester.print("{s}1:{s} ", .{ styles.dim, styles.reset });
            }
            while (index < string.len) {
                if (clamp <= column) {
                    tester.write("\n");
                    tester.writeNTimes(" ", max_line_length + 2);
                    column = 1;
                }

                switch (string[index]) {
                    0x00...0x08, 0x0C, 0x0E...0x1F => {
                        var symbol: [4]u8 = undefined;
                        const l = std.unicode.utf8Encode(0x2400 + @as(u21, string[index]), &symbol) catch unreachable;
                        tester.print("{s}{s}" ++ styles.reset, .{ switch (string[index]) {
                            0x00...0x08, 0x0E...0x1F => code_style,
                            0x0C => whitespace_style,
                            else => unreachable,
                        }, symbol[0..l] });
                        index += 1;
                        column += 1;
                    },
                    // horizontal tab
                    0x09 => {
                        tester.write(whitespace_style ++ "␉" ++ styles.reset);
                        const length = 4 - (column % 4);
                        tester.writeNTimes(" ", length - 1);
                        index += 1;
                        column += length;
                    },
                    // line feed
                    0x0A => {
                        tester.write(whitespace_style ++ "␤\n" ++ styles.reset);
                        line += 1;
                        column = 1;
                        index += 1;
                        const line_length = cifers(line);
                        const spaces = max_line_length - line_length;
                        tester.writeNTimes(" ", spaces);
                        tester.print("{s}{}:{s} ", .{ styles.dim, line, styles.reset });
                    },
                    // vertical tab
                    0x0B => {
                        tester.write(whitespace_style ++ "␋\n" ++ styles.reset);
                        line += 1;
                        index += 1;
                        const line_length = cifers(line);
                        const spaces = max_line_length - line_length;
                        tester.writeNTimes(" ", spaces);
                        tester.print("{s}{}:{s} ", .{ styles.dim, line, styles.reset });
                        tester.writeNTimes(" ", column);
                    },
                    // carriage return
                    0x0D => {
                        tester.write(delete_style ++ "␍" ++ styles.reset);
                        index += 1;
                        column = 1;
                        tester.write("\n");
                        tester.writeNTimes(" ", max_line_length + 2);
                    },
                    // space
                    0x20 => {
                        tester.write(whitespace_style ++ "␠" ++ styles.reset);
                        index += 1;
                        column += 1;
                    },
                    0x21...0x7E => {
                        tester.write(&[_]u8{string[index]});
                        index += 1;
                        column += 1;
                    },
                    0x7F => {
                        tester.write(delete_style ++ "␡" ++ styles.reset);
                        index += 1;
                        column += 1;
                    },
                    0x80...0xFF => {
                        tester.write(invalid_style ++ "�" ++ styles.reset);
                        index += 1;
                        column += 1;
                    },
                }
            }

            tester.write("\n");
        }

        fn expectEqualInternal(tester: *Self, expected: anytype, actual: anytype) bool {
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

        fn writeStackTrace(tester: *Self, stack_trace: std.builtin.StackTrace) void {
            if (isComptime())
                return;

            tester.write("\n");
            std.debug.writeStackTrace(
                stack_trace,
                tester.writer(),
                std.debug.getSelfDebugInfo() catch root.oom(),
                .escape_codes,
            ) catch root.oom();
        }

        inline fn writeCurrentStackTrace(tester: *Self) void {
            if (isComptime())
                return;

            std.debug.writeCurrentStackTrace(
                tester.writer(),
                std.debug.getSelfDebugInfo() catch root.oom(),
                .escape_codes,
                @returnAddress(),
            ) catch root.oom();
        }

        inline fn captureCurrentStackTrace(tester: *Self) void {
            if (isComptime())
                return;

            std.debug.writeCurrentStackTrace(
                tester.init_stack_trace.writer(tester.allocator),
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
            if (@inComptime() != is_comptime) root.compileError(
                \\Tester inited at {s} must be initiated using one of:
                \\- `Tester(.{s}).init()`,
                \\- `Tester(.{s}).init{s}()`,
                \\{s}
            , if (!is_comptime) .{
                "compile-time", "at_comptime", "at_comptime", "Comptime", "",
            } else .{
                "runtime",                                           "at_runtime",
                "at_comptime",                                       "Runtime",
                "- `Tester(.at_runtime).initWithAllocator(...)`,\n",
            });
            std.debug.assert(@import("builtin").is_test);
        }

        fn cifers(n: u64) u5 {
            return switch (n) {
                0...9 => 1,
                10...99 => 2,
                100...999 => 3,
                1000...9999 => 4,
                10_000...99_999 => 5,
                100000...999_999 => 6,
                1000_000...9999_999 => 7,
                10_000_000...99_999_999 => 8,
                100_000_000...999_999_999 => 9,
                1000_000_000...9999_999_999 => 10,
                10_000_000_000...99_999_999_999 => 11,
                100_000_000_000...999_999_999_999 => 12,
                1000_000_000_000...9999_999_999_999 => 13,
                10_000_000_000_000...99_999_999_999_999 => 14,
                100_000_000_000_000...999_999_999_999_999 => 15,
                1000_000_000_000_000...9999_999_999_999_999 => 16,
                10_000_000_000_000_000...99_999_999_999_999_999 => 17,
                100_000_000_000_000_000...999_999_999_999_999_999 => 18,
                1000_000_000_000_000_000...9999_999_999_999_999_999 => 19,
                else => 20,
            };
        }
    };
}

const styles = struct {
    const reset = "\x1B[0m";

    const bold = "\x1B[1m";
    const dim = "\x1B[2m";
    const italic = "\x1B[3m";
    const underlined = "\x1B[4m";

    const red = "\x1B[31m";
    const green = "\x1B[32m";
    const yellow = "\x1B[33m";
    const blue = "\x1B[34m";
    const magenta = "\x1B[35m";
    const cyan = "\x1B[36m";
    const white = "\x1B[37m";

    const black = "\x1B[30m";

    const line = dim ++ bold;
    const title = red ++ bold;
    const info = cyan ++ bold;
    const debug = bold;
    const warn = yellow ++ bold;
    const err = red ++ bold;
};
const Separator = struct {
    string: []const u8,

    fn from(comptime title: []const u8) Separator {
        comptime {
            const actual_title = if (max_width - 12 < title.len)
                title[0 .. max_width - 15] ++ "..."
            else
                title;

            const lines_width = max_width - actual_title.len - 2;
            const left_line_width = lines_width / 2;
            const right_line_width = lines_width - left_line_width;
            const left_line = "━" ** left_line_width;
            const right_line = "━" ** right_line_width;
            return Separator{ .string = std.fmt.comptimePrint(
                "\n{s}{s} {s}{s}{s} {s}{s}\n",
                .{
                    styles.reset ++ styles.line,  left_line,
                    styles.reset ++ styles.title, title,
                    styles.reset ++ styles.line,  right_line,
                    styles.reset,
                },
            ) };
        }
    }

    pub const untitled = Separator{ .string = "\n" ++
        styles.reset ++ styles.line ++
        "━" ** max_width ++ styles.reset ++
        "\n" };
    pub const tester_has_error_messages = Separator.from("Tester Error Messages");
    pub const tester_expect_stack_trace = Separator.from("Tester Expect Stack Trace");
    pub const tester_report_stack_trace = Separator.from("Tester Report Stack Trace");
    pub const tester_deinit_stack_trace = Separator.from("Tester Deinit Stack Trace");
    pub const tester_init_stack_trace = Separator.from("Tester Init Stack Trace");
    pub const expected_string = Separator.from("Expected String");
    pub const actual_string = Separator.from("Actual String");
    pub const unexpected_string_error = Separator.from("Unexpected String Error");
};

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
    t.reset();

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

test "Tester(...).expectEqualAsciiString" {
    var t = Tester(.at_runtime).init();
    defer t.deinit();

    t.debug("I'm a barbie girl,", .{});
    t.info("In a barbie world!", .{});
    t.warn("Life in plastic,", .{});
    t.err("It's fantastic!", .{});

    t.expectEqualAsciiStrings("", "\n\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F" ++
        "\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F" ++
        "\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F" ++
        "\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F" ++
        "\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F" ++
        "\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F" ++
        "\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F" ++
        "\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F" ++
        "\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F" ++
        "\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F" ++
        "\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF" ++
        "\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF" ++
        "\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF" ++
        "\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF" ++
        "\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF" ++
        "\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF");

    t.expectEqualAsciiStrings("Hello world" ++ "\x08" ** 100, "\x08" ** 500);
}
