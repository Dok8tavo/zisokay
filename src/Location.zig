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

string: []const u8,
line: usize = 0,
column: usize = 0,
index: usize = 0,

const Location = @This();

const backspace = 0x08;
const horizontal_tab = 0x09;
const line_feed = 0x0A;
const vertical_tab = 0x0B;
const form_feed = 0x0C;
const carriage_return = 0x0D;

pub fn maxLine(string: []const u8) usize {
    var max_line: usize = 0;
    var line: usize = 0;
    for (string) |b| switch (b) {
        line_feed => line += 1,
        vertical_tab => line += 1,
        form_feed => {
            max_line = @max(max_line, line);
            line = 0;
        },
        else => {},
    };

    return @max(max_line, line);
}
