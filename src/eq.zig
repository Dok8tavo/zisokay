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

pub fn eqFn(comptime T: type, comptime pattern: anytype) fn (T, T) bool {
    const Pattern = @TypeOf(pattern);
    if (Pattern == fn (T, T) bool)
        return pattern;

    if (Pattern == bool)
        return eqFn(T, if (pattern) .alwaysTrue else .alwaysFalse);

    if (Pattern == @TypeOf(.enum_literal)) return switch (pattern) {
        .bitEqual => bitEqualFn(T),
        .valueEqual => valueEqualFn(T),
        .approxEqualAbsolute => approxEqualAbsoluteFn(T, std.math.floatEps(T)),
        .approxEqualRelative => approxEqualRelativeFn(T, @sqrt(std.math.floatEps(T))),
        .sameParity => equivalentFn(T, bool, struct {
            fn isPair(t: T) bool {
                return @mod(t, 2) == 0;
            }
        }.isPair),
        .alwaysFalse => struct {
            fn falseFn(_: T, _: T) bool {
                return false;
            }
        }.falseFn,
        .alwaysTrue => struct {
            fn trueFn(_: T, _: T) bool {
                return true;
            }
        }.trueFn,
        else => root.compileError("Unknown pattern name: `{s}`!", .{@tagName(pattern)}),
    };

    const info = @typeInfo(T);
    return struct {
        fn eq(a: T, b: T) bool {
            return switch (info) {
                .@"struct" => |struct_info| inline for (struct_info.fields) |field| {
                    const field_pattern = @field(pattern, field.name);
                    const field_a = @field(a, field.name);
                    const field_b = @field(b, field.name);
                    const fieldEq = eqFn(field.type, field_pattern);
                    const is_eq = fieldEq(field_a, field_b);
                    if (!is_eq) break false;
                } else true,
                .@"union" => switch (std.meta.activeTag(a)) {
                    inline else => |tag| {
                        const variant_name = @tagName(tag);
                        const variant_pattern = @field(pattern, variant_name);
                        const variant_a = @field(a, variant_name);
                        const variant_b = if (b != tag) return false else @field(b, variant_name);
                        const variantEq = eqFn(@TypeOf(variant_a), variant_pattern);
                        return variantEq(variant_a, variant_b);
                    },
                },
                else => root.compileError(
                    "The pattern of a `.{s}` must be the equality function itself, not an" ++
                        " instance of `{s}`!",
                    .{ @tagName(info), @typeName(Pattern) },
                ),
            };
        }
    }.eq;
}

pub fn equivalentFn(
    comptime T: type,
    comptime Class: type,
    comptime classOf: fn (T) Class,
) fn (T, T) bool {
    return struct {
        fn equivalent(a: T, b: T) bool {
            return classOf(a) == classOf(b);
        }
    }.equivalent;
}

pub fn approxEqualAbsoluteFn(
    comptime Float: type,
    comptime tolerance: Float,
) fn (Float, Float) bool {
    std.debug.assert(switch (Float) {
        f16, f32, f64, f80, f128, c_longdouble => true,
        else => false,
    });
    return struct {
        fn approxEqualAbsolute(a: Float, b: Float) bool {
            return std.math.approxEqAbs(Float, a, b, tolerance);
        }
    }.approxEqualAbsolute;
}

pub fn approxEqualRelativeFn(
    comptime Float: type,
    comptime tolerance: Float,
) fn (Float, Float) bool {
    std.debug.assert(switch (Float) {
        f16, f32, f64, f80, f128, c_longdouble => true,
        else => false,
    });
    return struct {
        fn approxEqualRelative(a: Float, b: Float) bool {
            return std.math.approxEqRel(Float, a, b, tolerance);
        }
    }.approxEqualRelative;
}

pub fn valueEqualFn(comptime T: type) fn (T, T) bool {
    return struct {
        fn valueEqual(a: T, b: T) bool {
            return a == b;
        }
    }.valueEqual;
}

pub fn bitEqualFn(comptime T: type) fn (T, T) bool {
    return struct {
        fn bitEqual(a: T, b: T) bool {
            const Vector = @Vector(@sizeOf(T), u8);
            const vec_a: Vector = @bitCast(a);
            const vec_b: Vector = @bitCast(b);
            return @reduce(.And, vec_a == vec_b);
        }
    }.bitEqual;
}

test eqFn {
    const MyStruct = packed struct {
        integer: u64 = 0,
        float: f32 = 0,
        not_float: f16 = 0,
        padding: u16 = 0,
        dividible: u32 = 0,

        pub const eq = eqFn(@This(), .{
            // comparing integers by value
            .integer = .valueEqual,
            // comparing floating points by relative error
            .float = .approxEqualRelative,
            // this isn't a float, these are bits
            .not_float = .bitEqual,
            // padding doesn't matter
            .padding = true,
            // two dividibles are equivalent if they have the same number of dividers
            .dividible = equivalentFn(u32, u8, struct {
                fn numberOfDividers(number: u32) u8 {
                    // dividersOf(0) == .{}
                    // dividersOf(1) == .{1}
                    // dividersOf(2) == .{1, 2}

                    if (number <= 2)
                        return @intCast(number);

                    const as_float: f32 = @floatFromInt(number);
                    const sqrt = @sqrt(as_float);
                    const ceil_sqrt = @ceil(sqrt);
                    const int_sqrt: usize = @intFromFloat(ceil_sqrt);

                    // already counting 1 and the number itself
                    var number_of_dividers: u8 = 2;
                    for (2..int_sqrt + 1) |divider| {
                        if (number % divider == 0) number_of_dividers += 1;
                    }

                    return number_of_dividers;
                }
            }.numberOfDividers),
        });
    };

    const zero = MyStruct{};
    const modified_integer = MyStruct{ .integer = 1 };
    const modified_padding = MyStruct{ .padding = 100 };

    try std.testing.expect(zero.eq(zero));
    try std.testing.expect(!zero.eq(modified_integer));
    try std.testing.expect(zero.eq(modified_padding));

    try std.testing.expect(!modified_integer.eq(zero));
    try std.testing.expect(modified_integer.eq(modified_integer));
    try std.testing.expect(!modified_integer.eq(modified_padding));

    try std.testing.expect(modified_padding.eq(zero));
    try std.testing.expect(!modified_padding.eq(modified_integer));
    try std.testing.expect(modified_padding.eq(modified_padding));

    const float_is_1000_000 = MyStruct{ .float = 1000_000 };
    const float_is_almost_1000_000 = MyStruct{ .float = 1000_001 };

    try std.testing.expect(float_is_1000_000.eq(float_is_almost_1000_000));
    // had we used this strategy, it wouldn't be the same!
    try std.testing.expect(!approxEqualAbsoluteFn(f32, 0.5)(
        float_is_1000_000.float,
        float_is_almost_1000_000.float,
    ));

    const float_is_nan = MyStruct{ .float = std.math.nan(f32) };
    // nan is never equal to anything, even nan
    try std.testing.expect(!float_is_nan.eq(float_is_nan));

    const not_float_is_nan = MyStruct{ .not_float = std.math.nan(f16) };
    // but here, nan is compared by bits, not as a float
    try std.testing.expect(not_float_is_nan.eq(not_float_is_nan));

    const dividible_0 = MyStruct{};
    const dividible_1 = MyStruct{ .dividible = 1 };
    const dividible_2 = MyStruct{ .dividible = 2 };
    const dividible_3 = MyStruct{ .dividible = 3 };
    const dividible_4 = MyStruct{ .dividible = 4 };
    const dividible_9 = MyStruct{ .dividible = 9 };

    // zero has zero dividers, it's in it's own league
    try std.testing.expect(dividible_0.eq(dividible_0));
    try std.testing.expect(!dividible_0.eq(dividible_1));
    try std.testing.expect(!dividible_0.eq(dividible_2));
    try std.testing.expect(!dividible_0.eq(dividible_3));
    try std.testing.expect(!dividible_0.eq(dividible_4));
    try std.testing.expect(!dividible_0.eq(dividible_9));

    // one has only one divider, it's in it's own league too
    try std.testing.expect(!dividible_1.eq(dividible_0));
    try std.testing.expect(dividible_1.eq(dividible_1));
    try std.testing.expect(!dividible_1.eq(dividible_2));
    try std.testing.expect(!dividible_1.eq(dividible_3));
    try std.testing.expect(!dividible_1.eq(dividible_4));
    try std.testing.expect(!dividible_1.eq(dividible_9));

    // two and three are prime numbers
    try std.testing.expect(!dividible_2.eq(dividible_0));
    try std.testing.expect(!dividible_2.eq(dividible_1));
    try std.testing.expect(dividible_2.eq(dividible_2));
    try std.testing.expect(dividible_2.eq(dividible_3));
    try std.testing.expect(!dividible_2.eq(dividible_4));
    try std.testing.expect(!dividible_2.eq(dividible_9));

    try std.testing.expect(!dividible_3.eq(dividible_0));
    try std.testing.expect(!dividible_3.eq(dividible_1));
    try std.testing.expect(dividible_3.eq(dividible_2));
    try std.testing.expect(dividible_3.eq(dividible_3));
    try std.testing.expect(!dividible_3.eq(dividible_4));
    try std.testing.expect(!dividible_3.eq(dividible_9));

    // four and nine have three dividers: 1, 2 and 4, and 1, 3 and 9
    try std.testing.expect(!dividible_4.eq(dividible_0));
    try std.testing.expect(!dividible_4.eq(dividible_1));
    try std.testing.expect(!dividible_4.eq(dividible_2));
    try std.testing.expect(!dividible_4.eq(dividible_3));
    try std.testing.expect(dividible_4.eq(dividible_4));
    try std.testing.expect(dividible_4.eq(dividible_9));

    try std.testing.expect(!dividible_9.eq(dividible_0));
    try std.testing.expect(!dividible_9.eq(dividible_1));
    try std.testing.expect(!dividible_9.eq(dividible_2));
    try std.testing.expect(!dividible_9.eq(dividible_3));
    try std.testing.expect(dividible_9.eq(dividible_4));
    try std.testing.expect(dividible_9.eq(dividible_9));
}
