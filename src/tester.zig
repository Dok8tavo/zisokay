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

            tester.write(Separator.unexpected_string_error.string ++ Separator.expected_string.string);
            tester.writeAsciiDifferenceString(expected, index_of_difference);
            tester.write(Separator.actual_string.string);
            tester.writeAsciiDifferenceString(actual, index_of_difference);

            if (!isComptime())
                tester.write(Separator.expect_stack_trace.string);
            tester.writeCurrentStackTrace();
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

        pub fn expect(tester: *Self, comptime predicate: anytype, args: anytype) void {
            @call(.always_inline, predicate, .{tester} ++ args);
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

        fn writeAsciiDifferenceString(tester: *Self, string: []const u8, index_of_difference: usize) void {
            const last_line = blk: {
                var line: usize = 1;
                for (string) |byte| switch (byte) {
                    0x0A, 0x0D => line += 1,
                    else => {},
                };

                break :blk line;
            };

            const max_prefix_length: usize = @max(cifers(last_line) + 3, 4);
            var line_number: usize = 0;
            var column: usize = 0;

            tester.writeNewLine(max_prefix_length, &line_number);

            for (string[0..index_of_difference]) |byte| {
                tester.write(styles.green);
                if (column + max_prefix_length == max_width)
                    tester.writeNewLine(max_prefix_length, &line_number);
                switch (byte) {
                    0x00...0x08, 0x0B...0x1F, 0x7F => {
                        var symbol: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(0x2400 + @as(u21, byte), &symbol) catch unreachable;
                        tester.print(styles.dim ++ "{s}" ++ styles.normal, .{symbol[0..len]});
                        column += 1;
                    },
                    // horizontal tab
                    0x09 => {
                        const len = 4 - (column % 4);
                        const max_len = max_width - max_prefix_length - column;
                        const print_len = @min(len, max_len);

                        tester.write(styles.dim);
                        tester.writeNTimes("⇥", print_len);
                        tester.write(styles.normal);
                        column += print_len;
                    },
                    // line feed
                    0x0A => {
                        tester.write(styles.dim ++ "⏎" ++ styles.normal);
                        tester.writeNewLine(max_prefix_length, &line_number);
                        column = 0;
                    },
                    // space
                    0x20 => {
                        tester.write(styles.dim ++ "␣" ++ styles.normal);
                        column += 1;
                    },
                    // printable
                    0x21...0x7E => {
                        tester.write(&[_]u8{byte});
                        column += 1;
                    },
                    // non-ascii
                    0x80...0xFF => {
                        tester.write(styles.dim ++ "�" ++ styles.normal);
                        column += 1;
                    },
                }

                if (column + max_prefix_length == max_width) {
                    column = 0;
                    tester.writeNewLine(max_prefix_length, null);
                    tester.write(styles.green ++ styles.normal);
                }
            }

            if (string.len == index_of_difference)
                return tester.write("\n");

            for (string[index_of_difference..]) |byte| {
                tester.write(styles.red);
                if (column + max_prefix_length == max_width)
                    tester.writeNewLine(max_prefix_length, &line_number);
                switch (byte) {
                    0x00...0x08, 0x0B...0x1F, 0x7F => {
                        var symbol: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(0x2400 + @as(u21, byte), &symbol) catch unreachable;
                        tester.print(styles.dim ++ "{s}" ++ styles.normal, .{symbol[0..len]});
                        column += 1;
                    },
                    // horizontal tab
                    0x09 => {
                        const len = 4 - (column % 4);
                        const max_len = max_width - max_prefix_length - column;
                        const print_len = @min(len, max_len);

                        tester.write(styles.dim);
                        tester.writeNTimes("⇥", print_len);
                        tester.write(styles.normal);
                        column += print_len;
                    },
                    // line feed
                    0x0A => {
                        tester.write(styles.dim ++ "⏎" ++ styles.normal);
                        tester.writeNewLine(max_prefix_length, &line_number);
                        column = 0;
                    },
                    // space
                    0x20 => {
                        tester.write(styles.dim ++ "␣" ++ styles.normal);
                        column += 1;
                    },
                    // printable
                    0x21...0x7E => {
                        tester.write(&[_]u8{byte});
                        column += 1;
                    },
                    // non-ascii
                    0x80...0xFF => {
                        tester.write(styles.dim ++ "�" ++ styles.normal);
                        column += 1;
                    },
                }

                if (column + max_prefix_length == max_width) {
                    column = 0;
                    tester.writeNewLine(max_prefix_length, null);
                    tester.write(styles.red ++ styles.normal);
                }
            }

            tester.write("\n");
        }

        fn writeNewLine(tester: *Self, max_prefix_length: usize, line_number: ?*usize) void {
            const prefix_length = 3 + if (line_number) |ln| blk: {
                defer ln.* += 1;
                break :blk cifers(ln.*);
            } else 0;

            tester.write("\n" ++ styles.reset ++ styles.dim);
            tester.writeNTimes(" ", max_prefix_length - prefix_length);
            if (line_number) |ln|
                tester.print("{}", .{ln.*});
            tester.write(" │ " ++ styles.normal);
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
                        tester.info(expect_equal_messages.which_item, .{ index, @tagName(t_info) });
                        break false;
                    }
                } else true,
                .@"struct" => |struct_info| inline for (struct_info.fields) |field| {
                    if (!tester.expectEqualInternal(@field(expected_as_t, field.name), @field(actual_as_t, field.name))) {
                        tester.info(expect_equal_messages.which_field, if (struct_info.is_tuple)
                            .{ "at index ", field.name, "", "tuple" }
                        else
                            .{ "`.", field.name, "`", "struct" });
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
    const normal = "\x1B[1;22m";
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

    const code = styles.dim;
    const whitespace = styles.green ++ styles.dim;
    const delete = styles.red ++ styles.dim;
    const invalid = styles.red;
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
    pub const expected_string = Separator.from("Expected String", .simple);
    pub const actual_string = Separator.from("Actual String", .simple);
    pub const unexpected_string_error = Separator.from("Unexpected String Error", .double);
    pub const expected_string_line = Separator.from("Expected Line", .simple);
    pub const actual_string_line = Separator.from("Actual Line", .simple);
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
    .error_instead_of_payload = "Expected payload of error union, got error `{any}`!",
    .payload_instead_of_error = "Expected error `{any}` of error union, got payload!",
    .null_instead_of_payload = "Expected payload of optional, got `null`!",
    .payload_instead_of_null = "Expected `null`, got payload of optional!",
    // those are additional informations
    .which_item = "Item at index {} of the {s}.",
    .which_field = "Field {s}{s}{s} of the {s}.",
    .which_variant = "Variant `.{s}` of the union.",
    .payload_of_error_union = "Payload of error union.",
    .error_of_error_union = "Error of error union.",
    .payload_of_optional = "Payload of optional.",
};

test "Tester(...).expect(...)" {
    const namespace = struct {
        inline fn isPrime(tester: anytype, number: u32) void {
            if (number <= 1) {
                tester.write(comptime Separator.from("Expected Prime number", .double).string);
                tester.err("The number `{}` isn't a prime number! It has {s}.", .{
                    number,
                    if (number == 1) "only itself as a divider" else "an infinite amount of dividers",
                });
                tester.write(Separator.expect_stack_trace.string);
                tester.writeCurrentStackTrace();
                return;
            }

            if (number == 2) return;

            const float_number: f32 = @floatFromInt(number);
            const float_sqrt_number = @sqrt(float_number);
            const ceil_sqrt_number: u32 = @intFromFloat(@ceil(float_sqrt_number) + 1);

            for (2..ceil_sqrt_number) |i| {
                if (number % i == 0) break {
                    tester.write(comptime Separator.from("Expected Prime number", .double).string);
                    tester.err("The number `{}` isn't a prime Number! It has {} as a divider", .{
                        number,
                        i,
                    });

                    tester.write(Separator.expect_stack_trace.string);
                    tester.writeCurrentStackTrace();
                };
            }
        }
    };

    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expect(namespace.isPrime, .{0});
        t.expect(namespace.isPrime, .{1});
        t.expect(namespace.isPrime, .{2});
        t.expect(namespace.isPrime, .{3});
        t.expect(namespace.isPrime, .{4});
        t.expect(namespace.isPrime, .{5});
        t.expect(namespace.isPrime, .{6});
        t.expect(namespace.isPrime, .{7});
        t.expect(namespace.isPrime, .{8});
        t.expect(namespace.isPrime, .{9});
        t.expect(namespace.isPrime, .{10});
        t.expect(namespace.isPrime, .{11});
    }

    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expect(namespace.isPrime, .{0});
    t.expect(namespace.isPrime, .{1});
    t.expect(namespace.isPrime, .{2});
    t.expect(namespace.isPrime, .{3});
    t.expect(namespace.isPrime, .{4});
    t.expect(namespace.isPrime, .{5});
    t.expect(namespace.isPrime, .{6});
    t.expect(namespace.isPrime, .{7});
    t.expect(namespace.isPrime, .{8});
    t.expect(namespace.isPrime, .{9});
    t.expect(namespace.isPrime, .{10});
    t.expect(namespace.isPrime, .{11});
}

test "Tester(.at_runtime).expectEqualAsciiStrings(some string, some other string)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqualAsciiStrings(
        "Simple, small string.",
        "Simple, tiny string.",
    );

    t.expectEqualAsciiStrings(
        "This one is a very long string. You can't even fathom how long and annoying it is! " ++
            "It's tedious how big and long it is, I can't believe it!",
        "This one is a short string though.",
    );

    t.expectEqualAsciiStrings(
        \\And now a multiline string.
        \\I know you like them a lot.
        \\Well, actually it depends whether it's a matter of aesthetics or parsing ease.
        \\But all in all, I think they're great!
        \\
    , "me too");
}

test "Tester(.at_comptime).expectEqualAsciiStrings(some string, some other string)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqualAsciiStrings(
            "Simple, small string.",
            "Simple, tiny string.",
        );

        t.expectEqualAsciiStrings(
            "This one is a very long string. You can't even fathom how long and annoying it is! " ++
                "It's tedious how big and long it is, I can't believe it!",
            "This one is a short string though.",
        );

        t.expectEqualAsciiStrings(
            \\And now a multiline string.
            \\I know you like them a lot.
            \\Well, actually it depends whether it's a matter of aesthetics or parsing ease.
            \\But all in all, I think they're great!
            \\
        , "me too");
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

test "Tester(.comptime_int).expectEqual(some optional, other optional)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(@as(?u8, 0), 1);
        t.expectEqual(@as(?u8, null), 0);
        t.expectEqual(@as(?u8, 0), null);
    }
}

test "Tester(.at_runtime).expectEqual(some optional, other optional)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(@as(?u8, 0), 1);
    t.expectEqual(@as(?u8, null), 0);
    t.expectEqual(@as(?u8, 0), null);
}

test "Tester(.at_runtime).expectEqual(some error union, other error union)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const ErrorUnion = anyerror!u8;
    t.expectEqual(@as(ErrorUnion, error.SomeError), error.AnotherError);
    t.expectEqual(@as(ErrorUnion, error.Error), 0);
    t.expectEqual(@as(ErrorUnion, 0), error.Error);
}

test "Tester(.at_comptime).expectEqual(some error union, other error union)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const ErrorUnion = anyerror!u8;
        t.expectEqual(@as(ErrorUnion, error.SomeError), error.AnotherError);
        t.expectEqual(@as(ErrorUnion, error.Error), 0);
        t.expectEqual(@as(ErrorUnion, 0), error.Error);
    }
}

test "Tester(.at_comptime).expectEqual(some union, other union)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const Union = union(enum) { a: usize, b: usize };

        t.expectEqual(Union{ .a = 0 }, Union{ .b = 0 });
        t.expectEqual(Union{ .a = 1 }, Union{ .a = 10 });
    }
}

test "Tester(.at_runtime).expectEqual(some union, other union)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const Union = union(enum) { a: usize, b: usize };

    t.expectEqual(Union{ .a = 0 }, Union{ .b = 0 });
    t.expectEqual(Union{ .a = 1 }, Union{ .a = 10 });
}

test "Tester(.at_comptime).expectEqual(some struct, other struct)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const Struct = struct { a: bool, b: usize };

        t.expectEqual(Struct{ .a = true, .b = 7 }, Struct{ .a = true, .b = 1000 });
        t.expectEqual(Struct{ .a = false, .b = 1234 }, Struct{ .a = true, .b = 1234 });
    }
}

test "Tester(.at_runtime).expectEqual(some struct, other struct)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const Struct = struct { a: bool, b: usize };

    t.expectEqual(Struct{ .a = true, .b = 7 }, Struct{ .a = true, .b = 1000 });
    t.expectEqual(Struct{ .a = false, .b = 1234 }, Struct{ .a = true, .b = 1234 });
}

test "Tester(.at_runtime).expectEqual(some tuple, other tuple)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const Tuple = struct { bool, [2]u8 };

    t.expectEqual(Tuple{ true, .{ 'E', 'O' } }, Tuple{ false, .{ 'E', 'O' } });
    t.expectEqual(Tuple{ true, .{ 'A', 'B' } }, Tuple{ true, .{ 'A', 'C' } });
}

test "Tester(.at_comptime).expectEqual(some tuple, other tuple)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const Tuple = struct { bool, [2]u8 };

        t.expectEqual(Tuple{ true, .{ 'E', 'O' } }, Tuple{ false, .{ 'E', 'O' } });
        t.expectEqual(Tuple{ true, .{ 'A', 'B' } }, Tuple{ true, .{ 'A', 'C' } });
    }
}

test "Tester(.at_comptime).expectEqual(some array, other array)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual([_]isize{ 1, -1 }, .{ -1, 1 });
        t.expectEqual([_]u8{ 'H', 'e', 'l', 'l', 'o' }, [_]u8{ 'H', 'e', 'l', 'l', '!' });
        t.expectEqual(
            [_]@Vector(2, bool){ .{ true, false }, .{ false, true } },
            [_]@Vector(2, bool){ .{ true, false }, .{ false, false } },
        );
    }
}

test "Tester(.at_runtime).expectEqual(some array, other array)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual([_]isize{ 1, -1 }, .{ -1, 1 });
    t.expectEqual([_]u8{ 'H', 'e', 'l', 'l', 'o' }, [_]u8{ 'H', 'e', 'l', 'l', '!' });
    t.expectEqual(
        [_]@Vector(2, bool){ .{ true, false }, .{ false, true } },
        [_]@Vector(2, bool){ .{ true, false }, .{ false, false } },
    );
}

test "Tester(.at_comptime).expectEqual(some vector, other vector)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const VectorInt = @Vector(2, isize);
        const VectorBool = @Vector(2, bool);
        const VectorFloat = @Vector(2, f32);

        t.expectEqual(VectorInt{ 0, 0 }, VectorInt{ 0, 1 });
        t.expectEqual(VectorBool{ false, false }, VectorBool{ true, false });
        t.expectEqual(VectorFloat{ 1000, 10 }, VectorFloat{ 100, 1 });
    }
}

test "Tester(.at_runtime).expectEqual(some vector, other vector)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const VectorInt = @Vector(2, isize);
    const VectorBool = @Vector(2, bool);
    const VectorFloat = @Vector(2, f32);

    t.expectEqual(VectorInt{ 0, 0 }, VectorInt{ 0, 1 });
    t.expectEqual(VectorBool{ false, false }, VectorBool{ true, false });
    t.expectEqual(VectorFloat{ 1000, 10 }, VectorFloat{ 100, 1 });
}

test "Tester(.at_comptime).expectEqual(some error, other error)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        const OurErrors = error{ MyError, YourError };
        const YourErrors = error{ YourError, TheirError };

        t.expectEqual(error.MyError, error.YourError);
        t.expectEqual(OurErrors.YourError, YourErrors.TheirError);
    }
}

test "Tester(.at_runtime).expectEqual(some error, other error)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    const OurErrors = error{ MyError, YourError };
    const YourErrors = error{ YourError, TheirError };

    t.expectEqual(error.MyError, error.YourError);
    t.expectEqual(OurErrors.YourError, YourErrors.TheirError);
}

test "Tester(.at_comptime).expectEqual(some type, other type)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(i32, i64);
        t.expectEqual(f32, f64);
        t.expectEqual(struct {}, struct {});
    }
}

test "Tester(.at_runtime).expectEqual(some type, other type)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(i32, i64);
    t.expectEqual(f32, f64);
    t.expectEqual(struct {}, struct {});
}

test "Tester(.at_runtime).expectEqual(some enum literal, other enum literal)" {
    var t = Tester(.at_runtime).init();
    defer t.dismiss();

    t.expectEqual(.variant1, .variant2);
    t.expectEqual(.variant2, .variant3);
}

test "Tester(.at_comptime).expectEqual(some enum literal, other enum literal)" {
    comptime {
        var t = Tester(.at_comptime).init();
        defer t.dismiss();

        t.expectEqual(.variant1, .variant2);
        t.expectEqual(.variant2, .variant3);
    }
}

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
