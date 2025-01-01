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
                Separator.tester_error_messages.string ++ "{s}" ++ Separator.deinit_stack_trace.string,
                .{tester.messages},
            ) else {
                std.debug.print(
                    Separator.tester_error_messages.string ++ "{s}" ++
                        Separator.tester_stack_traces.string ++
                        Separator.init_stack_trace.string ++ "{s}" ++
                        Separator.deinit_stack_trace.string,
                    .{ tester.messages, tester.init_stack_trace.items },
                );

                @panic("Tester had non-dismissed error messages when deinited.");
            }
        }

        pub fn report(tester: *Self) void {
            if (isComptime()) root.compileError(
                Separator.tester_error_messages.string ++ "{s}" ++ Separator.report_stack_trace.string,
                .{tester.messages},
            ) else {
                std.debug.print(
                    Separator.tester_error_messages.string ++ "{s}" ++
                        Separator.tester_stack_traces.string ++
                        Separator.report_stack_trace.string,
                    .{tester.messages},
                );

                std.debug.dumpCurrentStackTrace(@returnAddress());
                std.debug.print(Separator.init_stack_trace.string, .{});
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
                if (!isComptime())
                    tester.write(Separator.expect_stack_trace.string);
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
                .enum_literal,
                .error_set,
                .float,
                .int,
                .type,
                => {
                    if (expected_as_t == actual_as_t)
                        return true;

                    tester.write(Separator.unexpected_value_error.string ++ "\n");
                    tester.err(expect_equal_messages.value, .{ expected_as_t, actual_as_t });
                    return false;
                },
                .@"enum" => |enum_info| if (expected_as_t == actual_as_t) true else {
                    tester.write(Separator.unexpected_value_error.string ++ "\n");
                    inline for (enum_info.fields) |expected_field| if (expected_field.value == @intFromEnum(expected_as_t)) {
                        inline for (enum_info.fields) |actual_field| if (actual_field.value == @intFromEnum(actual_as_t)) {
                            tester.err(
                                expect_equal_messages.enum_value_str_str,
                                .{ expected_field.name, actual_field.name },
                            );

                            return false;
                        };

                        tester.err(
                            expect_equal_messages.enum_value_str_any,
                            .{ expected_field.name, @intFromEnum(actual_as_t) },
                        );

                        return false;
                    };

                    inline for (enum_info.fields) |actual_field| if (actual_field.value == @intFromEnum(actual_as_t)) {
                        tester.err(
                            expect_equal_messages.enum_value_any_str,
                            .{ @intFromEnum(expected_as_t), actual_field.name },
                        );

                        return false;
                    };

                    tester.err(
                        expect_equal_messages.enum_value_any_any,
                        .{ @intFromEnum(expected_as_t), @intFromEnum(actual_as_t) },
                    );

                    return false;
                },
                inline .vector, .array => |va| for (0..va.len) |index| {
                    if (!tester.expectEqualInternal(expected_as_t[index], actual_as_t[index])) {
                        tester.info(expect_equal_messages.which_item, .{ index + 1, @tagName(t_info) });
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
                        tester.write(Separator.unexpected_value_error.string ++ "\n");
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
                        tester.write(Separator.unexpected_value_error.string ++ "\n");
                        tester.err(expect_equal_messages.error_instead_of_payload, .{actual_error});
                        return false;
                    }
                } else |expected_error| {
                    if (actual_as_t) |_| {
                        tester.write(Separator.unexpected_value_error.string ++ "\n");
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
                        tester.write(Separator.unexpected_value_error.string ++ "\n");
                        tester.err(expect_equal_messages.null_instead_of_payload, .{});
                        return false;
                    }
                } else if (actual_as_t) |_| {
                    tester.write(Separator.unexpected_value_error.string ++ "\n");
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
                "compile-time", "at_comptime",
                "at_comptime",  "Comptime",
                "",
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

    pub const Line = enum {
        simple,
        thick,
        double,
    };

    fn from(comptime title: []const u8, comptime line: Line) Separator {
        comptime {
            const actual_title = if (max_width - 12 < title.len)
                title[0 .. max_width - 15] ++ "..."
            else
                title;

            const line_char = switch (line) {
                .simple => "─",
                .thick => "━",
                .double => "═",
            };

            const lines_width = max_width - actual_title.len - 2;
            const left_line_width = lines_width / 2;
            const right_line_width = lines_width - left_line_width;
            const left_line = line_char ** left_line_width;
            const right_line = line_char ** right_line_width;
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

    pub const tester_stack_traces = Separator.from("Tester: Stack Traces", .thick);
    pub const tester_error_messages = Separator.from("Tester: Error Messages", .thick);
    pub const report_stack_trace = Separator.from("Report Stack Trace", .double);
    pub const deinit_stack_trace = Separator.from("Deinit Stack Trace", .double);
    pub const init_stack_trace = Separator.from("Init Stack Trace", .double);
    pub const expect_stack_trace = Separator.from("Expect Stack Trace", .simple);
    pub const expected_string = Separator.from("Expected String", .double);
    pub const actual_string = Separator.from("Actual String", .double);
    pub const unexpected_string_error = Separator.from("Unexpected String Error", .double);
    pub const unexpected_value_error = Separator.from("Unexpected Value Error", .double);
};

const expect_equal_messages = .{
    // those are errors
    .value = "Expected value `{any}`, got `{any}`!",
    .enum_value_any_any = "Expected enum value `enum({any})`, got `enum({any})`!",
    .enum_value_str_any = "Expected enum value `.{s}`, got `enum({any})`!",
    .enum_value_any_str = "Expected enum value `enum({any})`, got `.{s}`!",
    .enum_value_str_str = "Expected enum value `.{s}`, got `.{s}`!",
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

test "Tester(.at_runtime).expectEqual(some enum, other enum)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const Enum = enum(u8) { variant1, variant2, _ };

    t.expectEqual(Enum.variant1, Enum.variant1);
    t.expectEqual(Enum.variant1, @as(Enum, @enumFromInt(2)));
}

test "Tester(.at_comptime).expectEqual(some enum, other enum)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const Enum = enum(u8) { variant1, variant2, _ };

        t.expectEqual(Enum.variant1, Enum.variant1);
        t.expectEqual(Enum.variant1, @as(Enum, @enumFromInt(2)));
    }
}

// why would you do that?
test "Tester(.at_runtime).expectEqual(some comptime_float, other comptime_float)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(23.29, 31.37);
    t.expectEqual(41.43, 47.53);
}

test "Tester(.at_comptime).expectEqual(some comptime_float, other comptime_float)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(23.29, 31.37);
        t.expectEqual(41.43, 47.53);
    }
}

// seriously, why would you do that?
test "Tester(.at_runtime).expectEqual(some comptime_int, other comptime_int)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(11, 13);
    t.expectEqual(17, 19);
}

test "Tester(.at_comptime).expectEqual(some comptime_int, other comptime_int)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(2, 3);
        t.expectEqual(5, 7);
    }
}

test "Tester(.at_runtime).expectEqual(some float, other float)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(@as(f32, 1.610), @as(f32, 1.611));
    t.expectEqual(@as(f32, 3.141), @as(f32, 3.142));
}

test "Tester(.at_comptime).expectEqual(some float, other float)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(@as(f32, 1.610), @as(f32, 1.611));
        t.expectEqual(@as(f32, 3.141), @as(f32, 3.142));
    }
}

test "Tester(.at_runtime).expectEqual(some int, other int)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(@as(i32, 0), @as(i64, 1));
    t.expectEqual(@as(i32, 0), @as(i64, -1));
}

test "Tester(.at_comptime).expectEqual(some int, other int)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(@as(i32, 0), @as(i64, 1));
        t.expectEqual(@as(i32, 0), @as(i64, -1));
    }
}

test "Tester(.at_runtime).expectEqual(some bool, other bool)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(false, true);
    t.expectEqual(true, false);
}

test "Tester(.at_comptime).expectEqual(some bool, other bool)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(false, true);
        t.expectEqual(true, false);
    }
}

test "Tester(.at_runtime).expectEqual(some thing, same thing)" {
    var t = Tester(.at_runtime).init();
    defer t.deinit();

    // void, null, undefined
    t.expectEqual({}, {});
    t.expectEqual(null, null);
    t.expectEqual(undefined, undefined);

    // booleans
    t.expectEqual(true, true);
    t.expectEqual(false, false);

    // integers
    t.expectEqual(@as(usize, 0), 0);
    t.expectEqual(0, @as(usize, 0));

    // floats
    t.expectEqual(@as(f64, 0.0), 0.0);
    t.expectEqual(0.0, @as(f64, 0.0));

    // comptime integers
    t.expectEqual(0, 0);

    // comptime floats
    t.expectEqual(0.0, 0.0);

    // enum literal
    t.expectEqual(.literal, .literal);

    // enum
    const Enum = enum { variant_1, variant_2 };
    t.expectEqual(Enum.variant_1, Enum.variant_1);

    // errors
    t.expectEqual(error.SomeError, error.SomeError);

    // errors from different sets
    const Set1 = error{Error};
    const Set2 = error{Error};
    t.expectEqual(Set1.Error, Set2.Error);
    t.expectEqual(Set1.Error, error.Error);

    // types
    t.expectEqual(type, type);
    t.expectEqual(void, void);
    t.expectEqual(@TypeOf(t), @TypeOf(t));
    t.expectEqual([]const []volatile [2:0]usize, []const []volatile [2:0]usize);

    // arrays
    t.expectEqual([3]u8{ 1, 2, 3 }, [3]u8{ 1, 2, 3 });

    // vectors
    t.expectEqual(@Vector(4, u8){ 1, 2, 3, 4 }, @Vector(4, u8){ 1, 2, 3, 4 });

    // tuple
    const Tuple = struct { usize, bool };
    t.expectEqual(Tuple{ 0, false }, Tuple{ 0, false });

    // structs
    const Struct = struct { a: usize, b: bool };
    t.expectEqual(Struct{ .a = 0, .b = false }, Struct{ .a = 0, .b = false });

    // unions
    const Union = union(enum) { a: usize, b: bool };
    t.expectEqual(Union{ .a = 0 }, Union{ .a = 0 });

    // error unions
    const ErrorUnion = anyerror!u8;
    t.expectEqual(@as(ErrorUnion, error.SomeError), error.SomeError);
    t.expectEqual(@as(ErrorUnion, 0), 0);

    // optionals
    t.expectEqual(@as(?u8, 0), 0);
    t.expectEqual(@as(?u8, null), null);
}

test "Tester(.at_comptime).expectEqual(some thing, same thing)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.deinit();

        // void, null, undefined
        t.expectEqual({}, {});
        t.expectEqual(null, null);
        t.expectEqual(undefined, undefined);

        // booleans
        t.expectEqual(true, true);
        t.expectEqual(false, false);

        // integers
        t.expectEqual(@as(usize, 0), 0);
        t.expectEqual(0, @as(usize, 0));

        // floats
        t.expectEqual(@as(f64, 0.0), 0.0);
        t.expectEqual(0.0, @as(f64, 0.0));

        // comptime integers
        t.expectEqual(0, 0);

        // comptime floats
        t.expectEqual(0.0, 0.0);

        // enum literal
        t.expectEqual(.literal, .literal);

        // enum
        const Enum = enum { variant_1, variant_2 };
        t.expectEqual(Enum.variant_1, Enum.variant_1);

        // errors
        t.expectEqual(error.SomeError, error.SomeError);

        // errors from different sets
        const Set1 = error{Error};
        const Set2 = error{Error};
        t.expectEqual(Set1.Error, Set2.Error);
        t.expectEqual(Set1.Error, error.Error);

        // types
        t.expectEqual(type, type);
        t.expectEqual(void, void);
        t.expectEqual(@TypeOf(t), @TypeOf(t));
        t.expectEqual([]const []volatile [2:0]usize, []const []volatile [2:0]usize);

        // arrays
        t.expectEqual([3]u8{ 1, 2, 3 }, [3]u8{ 1, 2, 3 });

        // vectors
        t.expectEqual(@Vector(4, u8){ 1, 2, 3, 4 }, @Vector(4, u8){ 1, 2, 3, 4 });

        // tuple
        const Tuple = struct { usize, bool };
        t.expectEqual(Tuple{ 0, false }, Tuple{ 0, false });

        // structs
        const Struct = struct { a: usize, b: bool };
        t.expectEqual(Struct{ .a = 0, .b = false }, Struct{ .a = 0, .b = false });

        // unions
        const Union = union(enum) { a: usize, b: bool };
        t.expectEqual(Union{ .a = 0 }, Union{ .a = 0 });

        // error unions
        const ErrorUnion = anyerror!u8;
        t.expectEqual(@as(ErrorUnion, error.SomeError), error.SomeError);
        t.expectEqual(@as(ErrorUnion, 0), 0);

        // optionals
        t.expectEqual(@as(?u8, 0), 0);
        t.expectEqual(@as(?u8, null), null);
    }
}
