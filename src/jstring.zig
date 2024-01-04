const enable_arena_allocator: bool = true;
const enable_pcre: bool = true;

const std = @import("std");
const testing = std.testing;

const pcre = if (enable_pcre) @import("pcre_binding.zig") else undefined;

pub const ArenaAllocator = defineArenaAllocator(enable_arena_allocator);

pub const RegexUnmanaged = defineRegexUnmanaged(enable_pcre);

pub const JStringUnmanaged = struct {
    const JStringUnmanagedError = error{
        UnicodeDecodeError,
    };

    pub const U8Iterator = struct {
        const Self = @This();

        jstring_: *const JStringUnmanaged = undefined,
        pos: usize = 0,

        pub fn next(this: *Self) ?u8 {
            if (this.pos >= this.jstring_.*.len()) {
                return null;
            } else {
                const c = this.jstring_.*.charAt(@as(i32, @intCast(this.pos))) catch return null;
                this.pos += 1;
                return c;
            }
        }
    };

    pub const U8ReverseIterator = struct {
        const Self = @This();

        jstring_: *const JStringUnmanaged = undefined,
        pos: isize = -1,

        pub fn next(this: *Self) ?u8 {
            if (this.pos < -@as(isize, @intCast(this.jstring_.*.len()))) {
                return null;
            } else {
                const c = this.jstring_.*.charAt(this.pos) catch return null;
                this.pos -= 1;
                return c;
            }
        }
    };

    str_slice: []const u8,
    utf8_view_inited: bool = false,
    utf8_view: std.unicode.Utf8View = undefined,
    utf8_len: usize = 0,

    pub inline fn deinit(this: *const JStringUnmanaged, allocator: std.mem.Allocator) void {
        allocator.free(this.str_slice);
    }

    // constructors

    /// As the name assumes, it returns an empty string.
    pub fn newEmpty(allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        const new_slice = try allocator.alloc(u8, 0);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    /// Returns a string copied the content of slice.
    /// I.e., `const s = try JStringUnmanaged.newFromSlice(allocator, "hello,world");`
    pub fn newFromSlice(allocator: std.mem.Allocator, string_slice: []const u8) anyerror!JStringUnmanaged {
        const new_slice = try allocator.alloc(u8, string_slice.len);
        @memcpy(new_slice, string_slice);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    /// Returns a string copied the content of the other JStringUnmanaged
    pub fn newFromJStringUnmanaged(allocator: std.mem.Allocator, that: JStringUnmanaged) anyerror!JStringUnmanaged {
        const new_slice = try allocator.alloc(u8, that.len());
        @memcpy(new_slice, that.str_slice);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    /// Returns a string from the result of formatting, i.e., sprintf.
    /// Example: `var s = JStringUnmanaged.newFromFormat(allocator, "{s}{d}", .{ "hello", 5 })`
    pub fn newFromFormat(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) anyerror!JStringUnmanaged {
        const new_slice = try std.fmt.allocPrint(allocator, fmt, args);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    /// Returns a string from auto formatting a tuple of items. Essentially what
    /// it does is to guess the fmt automatically. The max items of the tuple is
    /// 32.
    /// Example: `var s = JStringUnmanaged.newFromFormat(allocator, .{ "hello", 5 })`
    pub fn newFromTuple(allocator: std.mem.Allocator, rest_items: anytype) anyerror!JStringUnmanaged {
        const ArgsType = @TypeOf(rest_items);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
        }

        const fields_info = args_type_info.Struct.fields;
        if (fields_info.len > @typeInfo(u32).Int.bits) {
            @compileError("32 arguments max are supported per format call");
        }

        // max 32 arguments, and each of them will not have long (<8) specifier
        comptime var fmt_buf: [8 * 32]u8 = undefined;
        _ = &fmt_buf;
        comptime var fmt_len: usize = 0;
        comptime {
            var fmt_print_slice: []u8 = fmt_buf[0..];
            for (fields_info) |field_info| {
                _bufPrintFmt(@typeInfo(field_info.type), &fmt_buf, &fmt_len, &fmt_print_slice);
            }
        }
        return JStringUnmanaged.newFromFormat(allocator, fmt_buf[0..fmt_len], rest_items);
    }

    // TODO: parseInt
    // TODO: parseFloat

    // utils

    /// Simple util to return the underlying slice's len (= this.str_slice.len).
    /// Less typing, less errors.
    pub inline fn len(this: *const JStringUnmanaged) usize {
        return this.str_slice.len;
    }

    /// First time call utf8Len will init the utf8_view and calculate len once.
    /// After that we will just use the cached view and len.
    pub fn utf8Len(this: *JStringUnmanaged) anyerror!usize {
        if (!this.utf8_view_inited) {
            this.utf8_view = try std.unicode.Utf8View.init(this.str_slice);
            this.utf8_view_inited = true;
            this.utf8_len = brk: {
                var utf8_len: usize = 0;
                var it = this.utf8_view.iterator();
                while (it.nextCodepoint()) |_| {
                    utf8_len += 1;
                }
                break :brk utf8_len;
            };
        }
        return this.utf8_len;
    }

    /// As the name assumes. Equals to `JStringUnmanaged.newFromJStringUnmanaged(allocator, this)`
    pub inline fn clone(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        return JStringUnmanaged.newFromJStringUnmanaged(allocator, this.*);
    }

    /// Equals to `this.len() == 0` or `this.str_slice.len == 0`
    pub inline fn isEmpty(this: *const JStringUnmanaged) bool {
        return this.len() == 0;
    }

    /// As simple as compare the underlying str_slice to string_slice
    pub inline fn eqlSlice(this: *const JStringUnmanaged, string_slice: []const u8) bool {
        return std.mem.eql(u8, this.str_slice, string_slice);
    }

    /// Equals to `this.eqlSlice(that.str_slice)`
    pub inline fn eqlJStringUmanaged(this: *const JStringUnmanaged, that: JStringUnmanaged) bool {
        return this.eqlSlice(that.str_slice);
    }

    /// explode this string to small strings sperated by ascii spaces while
    /// respects utf8 chars. Limit can be -1 or positive numbers. When limit is
    /// negative means auto calculate how many strings can return; otherwise
    /// will return min(limit, possible max number of strings)
    pub fn explode(this: *const JStringUnmanaged, allocator: std.mem.Allocator, limit: isize) anyerror![]JStringUnmanaged {
        const real_limit = brk: {
            if (limit < 0) {
                break :brk this.str_slice.len;
            } else {
                break :brk @as(usize, @intCast(limit));
            }
        };
        return this._explode(allocator, real_limit);
    }

    fn _explode(this: *const JStringUnmanaged, allocator: std.mem.Allocator, limit: usize) anyerror![]JStringUnmanaged {
        var result_jstrings = try allocator.alloc(JStringUnmanaged, limit);
        var result_count: usize = 0;
        var pos: usize = 0;
        var next_pos: usize = 0;

        while (pos < this.str_slice.len) {
            switch (this.str_slice[pos]) {
                ' ', '\t', '\n', '\r' => {
                    pos += 1;
                    continue;
                },
                else => {
                    next_pos = pos + 1;
                    next_pos = brk: {
                        while (next_pos < this.str_slice.len) : (next_pos += 1) {
                            switch (this.str_slice[next_pos]) {
                                ' ', '\t', '\n', '\r' => break :brk next_pos,
                                else => continue,
                            }
                        }
                        break :brk next_pos;
                    };
                    result_jstrings[result_count] = try JStringUnmanaged.newFromSlice(allocator, this.str_slice[pos..next_pos]);
                    result_count += 1;
                    if (result_count >= limit) {
                        break;
                    }
                    pos = next_pos;
                    continue;
                },
            }
        }

        if (result_count == limit) {
            return result_jstrings;
        } else {
            defer allocator.free(result_jstrings);
            var final_result_jstrings = try allocator.alloc(JStringUnmanaged, result_count);
            _ = &final_result_jstrings;
            if (result_count > 0) {
                @memcpy(final_result_jstrings, result_jstrings[0..result_count]);
            }
            return final_result_jstrings;
        }
    }

    // methods as listed at https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String

    // all methods marked as deprecated (such as anchor, big, blink etc) are omitted.

    // ** iterator

    /// return an iterator can iterate char(u8) by char, from the beginning.
    pub inline fn iterator(this: *const JStringUnmanaged) U8Iterator {
        return U8Iterator{
            .jstring_ = this,
            .pos = 0,
        };
    }

    /// return an interator can iterate char(u8) by char, but from the end.
    pub inline fn reverseIterator(this: *const JStringUnmanaged) U8ReverseIterator {
        return U8ReverseIterator{
            .jstring_ = this,
            .pos = -1,
        };
    }

    /// return std.unicode.Utf8Iterator, which can help to iterate through every
    /// unicode char
    pub inline fn utf8Iterator(this: *JStringUnmanaged) anyerror!std.unicode.Utf8Iterator {
        _ = try this.utf8Len();
        return this.utf8_view.iterator();
    }

    // ** at

    /// different to Javascript's string.at, return unicode char(u21) of index,
    /// as prefer utf-8 string. Same to Javascript, accept index as i32: when
    /// postive is from beginning; when negative is from ending; when
    /// index == 0, return the the first char if not empty.
    pub fn at(this: *JStringUnmanaged, index: isize) anyerror!u21 {
        const utf8_len = try this.utf8Len();
        if (index >= utf8_len) {
            return error.IndexOutOfBounds;
        }

        if ((-index) > utf8_len) {
            return error.IndexOutOfBounds;
        }

        const char_pos: usize = if (index >= 0) @intCast(index) else (utf8_len - @as(usize, @intCast(-index)));

        var it = this.utf8_view.iterator();
        var unicode_char: u21 = undefined;
        for (0..utf8_len) |i| {
            if (it.nextCodepoint()) |uc| {
                unicode_char = uc;
            } else {
                return JStringUnmanagedError.UnicodeDecodeError;
            }
            if (i >= char_pos) {
                break;
            }
        }
        return unicode_char;
    }

    // ** charAt

    /// different to Javascript's string.charAt, return u8 of index, as prefer utf-8
    /// string. Same to Javascript, accept index as i32: when postive is from
    /// beginning; when negative is from ending; when index == 0, return the
    /// the first char if not empty.
    pub fn charAt(this: *const JStringUnmanaged, index: isize) anyerror!u8 {
        if (index >= this.len()) {
            return error.IndexOutOfBounds;
        }

        if ((-index) > this.len()) {
            return error.IndexOutOfBounds;
        }

        if (index >= 0) {
            return this.str_slice[@intCast(index)];
        }

        if (index < 0) {
            return this.str_slice[this.len() - @as(usize, @intCast(-index))];
        }

        unreachable;
    }

    // ** charCodeAt

    /// charCodeAt does not make sense in zig, please use at or charAt!
    pub inline fn charCodeAt(this: *const JStringUnmanaged, index: isize) anyerror!u21 {
        _ = this;
        _ = index;
        @compileError("charCodeAt does not make sense in zig, please use at or charAt!");
    }

    // ** codePointAt

    /// as in zig we use u21 for char, so codePointAt is a trival alias to at().
    pub inline fn codePointAt(this: *const JStringUnmanaged, index: isize) anyerror!u21 {
        _ = this;
        _ = index;
        @compileError("codePointAt does not make sense in zig, please use at or charAt!");
    }

    // ** concat

    /// Concat jstrings in rest_jstrings in order, return a new allocated
    /// jstring. If rest_jstrings.len == 0, will return a copy of this jstring.
    pub fn concat(this: *const JStringUnmanaged, allocator: std.mem.Allocator, rest_jstrings: []const JStringUnmanaged) anyerror!JStringUnmanaged {
        if (rest_jstrings.len == 0) {
            return this.clone(allocator);
        } else {
            var rest_sum_len: usize = 0;
            const new_len = this.len() + lenbrk: {
                for (rest_jstrings) |jstring| {
                    rest_sum_len += jstring.len();
                }
                break :lenbrk rest_sum_len;
            };

            const new_slice = try allocator.alloc(u8, new_len);
            var new_slice_ptr = new_slice.ptr;
            @memcpy(new_slice_ptr, this.str_slice);
            new_slice_ptr += this.str_slice.len;
            for (rest_jstrings) |jstring| {
                @memcpy(new_slice_ptr, jstring.str_slice);
                new_slice_ptr += jstring.len();
            }
            return JStringUnmanaged{
                .str_slice = new_slice,
            };
        }
    }

    /// Concat jstrings by format with fmt & .{ data }. It is a shortcut for
    /// first creating tmp str from JStringUnmanaged.newFromFormat then second
    /// this.concat(tmp str). (or below psudeo code)
    ///
    ///   var tmp_jstring = JStringUnmanaged.newFromFormat(allocator, fmt, rest_items);
    ///   defer tmp_jstring.deinit(allocator);
    ///   const tmp_jstrings = []JStringUnmanaged{ tmp_jstring };
    ///   this.concat(allocator, &tmp_jstrings);
    pub fn concatFormat(this: *const JStringUnmanaged, allocator: std.mem.Allocator, comptime fmt: []const u8, rest_items: anytype) anyerror!JStringUnmanaged {
        const ArgsType = @TypeOf(rest_items);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
        }

        const fields_info = args_type_info.Struct.fields;
        if (fields_info.len > @typeInfo(u32).Int.bits) {
            @compileError("32 arguments max are supported per format call");
        }

        if (rest_items.len == 0) {
            return this.clone(allocator);
        } else {
            var rest_items_jstring = try JStringUnmanaged.newFromFormat(allocator, fmt, rest_items);
            defer rest_items_jstring.deinit(allocator);
            var rest_items_jstrings = [1]JStringUnmanaged{rest_items_jstring};
            return this.concat(allocator, &rest_items_jstrings);
        }
    }

    /// Similar to concatFormat, but try to auto gen fmt from rest_items.
    /// Not support Optional & ErrorUnion in rest_items.
    pub fn concatTuple(this: *const JStringUnmanaged, allocator: std.mem.Allocator, rest_items: anytype) anyerror!JStringUnmanaged {
        const ArgsType = @TypeOf(rest_items);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
        }

        const fields_info = args_type_info.Struct.fields;
        if (fields_info.len > @typeInfo(u32).Int.bits) {
            @compileError("32 arguments max are supported per format call");
        }

        // max 32 arguments, and each of them will not have long (<8) specifier
        comptime var fmt_buf: [8 * 32]u8 = undefined;
        _ = &fmt_buf;
        comptime var fmt_len: usize = 0;
        comptime {
            var fmt_print_slice: []u8 = fmt_buf[0..];
            for (fields_info) |field_info| {
                _bufPrintFmt(@typeInfo(field_info.type), &fmt_buf, &fmt_len, &fmt_print_slice);
            }
        }
        // std.debug.print("\n{s}\n", .{fmt_buf[0..fmt_len]});
        return this.concatFormat(allocator, fmt_buf[0..fmt_len], rest_items);
    }

    // ** endsWith

    pub inline fn endsWith(this: *const JStringUnmanaged, suffix: JStringUnmanaged) bool {
        return this.endsWithSlice(suffix.str_slice);
    }

    pub fn endsWithSlice(this: *const JStringUnmanaged, suffix_slice: []const u8) bool {
        if (this.len() < suffix_slice.len) {
            return false;
        }
        return std.mem.eql(u8, this.str_slice[this.str_slice.len - suffix_slice.len ..], suffix_slice);
    }

    // ** fromCharCode

    /// zig supports utf-8 natively, use newFromSlice instead.
    pub fn fromCharCode() JStringUnmanaged {
        @compileError("zig supports utf-8 natively, use newFromSlice instead.");
    }

    // ** fromCodePoint

    /// zig supports utf-8 natively, use newFromSlice instead.
    pub fn fromCodePoint() JStringUnmanaged {
        @compileError("zig supports utf-8 natively, use newFromSlice instead.");
    }

    // ** includes

    pub inline fn includes(this: *const JStringUnmanaged, needle_slice: []const u8, pos: usize) bool {
        return this._naive_indexOf(needle_slice, pos, false) >= 0;
    }

    pub inline fn fastIncludes(this: *const JStringUnmanaged, allocator: std.mem.Allocator, needle_slice: []const u8, pos: usize) bool {
        const i = this._kmp_indexOf(allocator, needle_slice, pos, false) catch unreachable;
        return i >= 0;
    }

    // ** indexOf

    /// The indexOf() method searches this string and returns the index of the
    /// first occurrence of the specified substring. It takes an starting
    /// position and returns the first occurrence of the specified substring at
    /// an index greater than or equal to the specified number.
    pub inline fn indexOf(this: *const JStringUnmanaged, needle_slice: []const u8, pos: usize) isize {
        return this._naive_indexOf(needle_slice, pos, false);
    }

    /// Fast version of indexOf as it uses KMP algorithm for searching. Will
    /// result in O(this.len+needle_slice.len) but also requires allocator for
    /// creating KMP lookup table.
    pub inline fn fastIndexOf(this: *const JStringUnmanaged, allocator: std.mem.Allocator, needle_slice: []const u8, pos: usize) anyerror!isize {
        return this._kmp_indexOf(allocator, needle_slice, pos, false);
    }

    fn _naive_indexOf(this: *const JStringUnmanaged, needle_slice: []const u8, pos: usize, want_last: bool) isize {
        if (needle_slice.len == 0) {
            if (want_last) {
                return @as(isize, @intCast(this.len() - 1));
            } else {
                return @as(isize, @intCast(pos));
            }
        }

        var occurence: isize = -1;
        const haystack_slice = this.str_slice[pos..];
        var k: usize = 0;
        while (k < haystack_slice.len - needle_slice.len) : (k += 1) {
            if (std.mem.eql(u8, haystack_slice[k .. k + needle_slice.len], needle_slice)) {
                occurence = @as(isize, @intCast(k));
                if (!want_last) {
                    return if (occurence > 0) @as(isize, @intCast(pos)) + occurence else occurence;
                }
            } else continue;
        }
        return if (occurence > 0) @as(isize, @intCast(pos)) + occurence else occurence;
    }

    fn _kmp_indexOf(this: *const JStringUnmanaged, allocator: std.mem.Allocator, needle_slice: []const u8, pos: usize, want_last: bool) anyerror!isize {
        if (needle_slice.len == 0) {
            if (want_last) {
                return @as(isize, @intCast(this.len() - 1));
            } else {
                return @as(isize, @intCast(pos));
            }
        }

        if (pos >= this.len() or pos + needle_slice.len > this.len()) {
            return -1;
        }

        var occurence: isize = -1;
        const haystack_slice = this.str_slice[pos..];

        const t = try _kmp_build_failure_table(allocator, needle_slice);
        defer allocator.free(t);

        var j: isize = 0;
        for (0..haystack_slice.len) |i| {
            if (_slice_at(u8, haystack_slice, @as(isize, @intCast(i))) == _slice_at(u8, needle_slice, j)) {
                j += 1;
                if (j >= needle_slice.len) {
                    occurence = @as(isize, @intCast(i)) - j + 1;
                    if (!want_last) {
                        return if (occurence >= 0) @as(isize, @intCast(pos)) + occurence else occurence;
                    }
                    j = _slice_at(isize, t, j);
                }
            } else if (j > 0) {
                j = _slice_at(isize, t, j);
            }
        }

        return if (occurence >= 0) @as(isize, @intCast(pos)) + occurence else occurence;
    }

    // ** isWellFormed

    /// similar to definition in javascript, but with difference that we are
    /// checking utf8.
    pub fn isWellFormed(this: *const JStringUnmanaged) bool {
        switch (this.utf8Len()) {
            .Error => return false,
            else => return true,
        }
    }

    // ** lastIndexOf

    /// The lastIndexOf() method searches this string and returns the index of
    /// the last occurrence of the specified substring. It takes an optional
    /// starting position and returns the last occurrence of the specified
    /// substring at an index less than or equal to the specified number.
    pub inline fn lastIndexOf(this: *const JStringUnmanaged, needle_slice: []const u8, pos: usize) isize {
        return this._naive_indexOf(needle_slice, pos, true);
    }

    pub inline fn fastLastIndexOf(this: *const JStringUnmanaged, allocator: std.mem.Allocator, needle_slice: []const u8, pos: usize) anyerror!isize {
        return this._kmp_indexOf(allocator, needle_slice, pos, true);
    }

    // ** localeCompare

    /// Not implemented! Does this method make sense in zig?
    pub fn localeCompare(this: *const JStringUnmanaged) bool {
        _ = this;
        @compileError("Not implemented! Does localeCompare make sense in zig?");
    }

    // ** match

    /// thin wrap of Regex's match against this.str_slice as search subject
    pub inline fn match(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, offset: usize, fetch_results: bool, regex_options: u32, match_options: u32) anyerror!RegexUnmanaged {
        var re = try RegexUnmanaged.init(allocator, pattern, regex_options, match_options);
        try re.match(allocator, this.str_slice, offset, fetch_results, match_options);
        return re;
    }

    // ** matchAll

    /// this wrap of Regex's matchAll against this.str_slice as search subject
    pub inline fn matchAll(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, offset: usize, regex_options: u32, match_options: u32) anyerror!RegexUnmanaged {
        var re = try RegexUnmanaged.init(allocator, pattern, regex_options, match_options);
        try re.matchAll(allocator, this.str_slice, offset, match_options);
        return re;
    }

    // ** normalize

    /// Not implemented! Does normalize make sense in zig?
    pub fn normalize(this: *const JStringUnmanaged) JStringUnmanaged {
        _ = this;
        @compileError("Not implemented! Does normalize make sense in zig?");
    }

    // ** padEnd

    /// The padEnd method creates a new string by padding this string with a
    /// given slice (repeated, if needed) so that the resulting string reaches
    /// a given length. The padding is applied from the end of this string. If
    /// padString is too long to stay within targetLength, it will be truncated
    /// from the beginning.
    pub fn padEnd(this: *const JStringUnmanaged, allocator: std.mem.Allocator, wanted_len: usize, pad_slice: []const u8) anyerror!JStringUnmanaged {
        if (this.len() >= wanted_len) {
            return this.clone(allocator);
        }

        var wanted_slice = try allocator.alloc(u8, wanted_len);

        const wanted_pad_len = wanted_len - this.len();
        const count = @divTrunc(wanted_pad_len, pad_slice.len);
        const residual_len = wanted_pad_len % pad_slice.len;
        var target_slice = wanted_slice[0..this.str_slice.len];
        @memcpy(target_slice, this.str_slice);
        target_slice = wanted_slice[wanted_len - residual_len ..];
        @memcpy(target_slice, pad_slice[0..residual_len]);
        for (0..count) |i| {
            target_slice = wanted_slice[this.str_slice.len + i * pad_slice.len .. wanted_len - residual_len];
            @memcpy(target_slice, pad_slice);
        }
        return JStringUnmanaged{
            .str_slice = wanted_slice,
        };
    }

    /// JString version of padEnd, accept pad_string (*const JStringUnmanaged)
    /// instead of slice.
    pub inline fn padEndJString(this: *const JStringUnmanaged, allocator: std.mem.Allocator, wanted_len: usize, pad_string: *const JStringUnmanaged) anyerror!JStringUnmanaged {
        return this.padEnd(allocator, wanted_len, pad_string.slice);
    }

    // ** padStart

    /// The padStart() method creates a new string by padding this string with
    /// another slice (multiple times, if needed) until the resulting string
    /// reaches the given length. The padding is applied from the start of this
    /// string. If pad_slice is too long to stay within the wanted_len, it will
    /// be truncated from the end.
    pub fn padStart(this: *const JStringUnmanaged, allocator: std.mem.Allocator, wanted_len: usize, pad_slice: []const u8) anyerror!JStringUnmanaged {
        if (this.len() >= wanted_len) {
            return this.clone(allocator);
        }

        var wanted_slice = try allocator.alloc(u8, wanted_len);

        const wanted_pad_len = wanted_len - this.len();
        const count = @divTrunc(wanted_pad_len, pad_slice.len);
        const residual_len = wanted_pad_len % pad_slice.len;
        var target_slice = wanted_slice[wanted_pad_len..];
        @memcpy(target_slice, this.str_slice);
        target_slice = wanted_slice[0..residual_len];
        @memcpy(target_slice, pad_slice[pad_slice.len - residual_len ..]);
        for (0..count) |i| {
            target_slice = wanted_slice[residual_len + i * pad_slice.len .. wanted_pad_len];
            @memcpy(target_slice, pad_slice);
        }

        return JStringUnmanaged{
            .str_slice = wanted_slice,
        };
    }

    /// JString version of padStart, accept pad_string (*const JStringUnmanaged)
    /// instead of slice.
    pub inline fn padStartJString(this: *const JStringUnmanaged, allocator: std.mem.Allocator, wanted_len: usize, pad_string: *const JStringUnmanaged) anyerror!JStringUnmanaged {
        return this.padStart(allocator, wanted_len, pad_string.slice);
    }

    // ** raw

    /// zig has no template literals like javascript, use newFromSlice/newFromFormat/newFromTuple instead.
    pub fn raw() JStringUnmanaged {
        @compileError("zig has no template literals like javascript, use newFromSlice/newFromFormat/newFromTuple instead.");
    }

    // ** repeat

    /// repeat current string for `count` times and return as a new string.
    pub fn repeat(this: *const JStringUnmanaged, allocator: std.mem.Allocator, count: usize) anyerror!JStringUnmanaged {
        if (count == 0 or this.len() == 0) {
            return JStringUnmanaged.newEmpty(allocator);
        }

        const new_len = this.len() * count;
        const new_slice = try allocator.alloc(u8, new_len);
        var target_slice: []u8 = undefined;
        for (0..count) |i| {
            target_slice = new_slice[i * this.len() .. (i + 1) * this.len()];
            @memcpy(target_slice, this.str_slice);
        }
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    // TODO replace

    // ** search

    /// This function is searching by regex so it requires allocator. For simple search
    /// use `indexOf`
    pub fn search(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8) anyerror!isize {
        _ = this;
        _ = allocator;
        _ = pattern;
        @compileError("TODO!");
    }

    // ** slice

    /// Slice part of current string and return a new copy with content
    /// [index_start, index_end). Both `index_start` and `index_end` can be
    /// positive or negative numbers. When is positive, means the forward
    /// location from string beginning; when is negative, means the backward
    /// location from string ending. Example: if `s` contains
    /// "hello", `s.slice(allocator, 1, -1)` will return a new string with
    /// content "ell"
    pub fn slice(this: *const JStringUnmanaged, allocator: std.mem.Allocator, index_start: isize, index_end: isize) anyerror!JStringUnmanaged {
        const uindex_start = brk: {
            if (index_start >= 0) {
                break :brk @as(usize, @intCast(index_start));
            } else {
                if (@as(usize, @intCast(-index_start)) > this.len()) {
                    return error.IndexOutOfBounds;
                }
                break :brk this.len() - @as(usize, @intCast(-index_start));
            }
        };
        const uindex_end = brk: {
            if (index_end >= 0) {
                break :brk @as(usize, @intCast(index_end));
            } else {
                if (@as(usize, @intCast(-index_end)) > this.len()) {
                    return error.IndexOutOfBounds;
                }
                break :brk this.len() - @as(usize, @intCast(-index_end));
            }
        };
        return this._slice(allocator, uindex_start, uindex_end);
    }

    pub inline fn sliceWithStartOnly(this: *const JStringUnmanaged, allocator: std.mem.Allocator, index_start: isize) anyerror!JStringUnmanaged {
        return this.slice(allocator, index_start, @as(isize, @intCast(this.len())));
    }

    fn _slice(this: *const JStringUnmanaged, allocator: std.mem.Allocator, index_start: usize, index_end: usize) anyerror!JStringUnmanaged {
        if (index_start >= index_end or index_start >= this.len()) {
            return JStringUnmanaged.newEmpty(allocator);
        }
        const valid_index_end = if (index_end > this.len()) this.len() else index_end;
        return JStringUnmanaged.newFromSlice(allocator, this.str_slice[index_start..valid_index_end]);
    }

    // ** split

    /// pay attention that this function will not consider spaces in non-ascii.
    fn _splitToUtf8Chars(this: *JStringUnmanaged, allocator: std.mem.Allocator, limit: usize) anyerror![]JStringUnmanaged {
        var result_jstrings = try allocator.alloc(JStringUnmanaged, limit);
        var result_count: usize = 0;
        if (limit == 0) {
            return result_jstrings;
        }

        _ = try this.utf8Len(); // force for a utf8_view
        var it = try this.utf8Iterator();
        while (it.nextCodepoint()) |code_point| {
            switch (code_point) {
                ' ', '\t', '\n', '\r' => continue,
                else => {
                    result_jstrings[result_count] = try JStringUnmanaged.newFromFormat(allocator, "{u}", .{code_point});
                    result_count += 1;
                    if (result_count >= limit) {
                        break;
                    }
                },
            }
        }

        if (result_count == limit) {
            return result_jstrings;
        } else {
            defer allocator.free(result_jstrings);
            var final_result_jstrings = try allocator.alloc(JStringUnmanaged, result_count);
            _ = &final_result_jstrings;
            if (result_count > 0) {
                @memcpy(final_result_jstrings, result_jstrings[0..result_count]);
            }
            return final_result_jstrings;
        }
    }

    /// split by simple seperator([]const u8). If you need to split by white spaces, use
    /// `splitByWhiteSpace`, or even more advanced `splitByRegex` (need to enable pcre support)
    pub fn split(this: *JStringUnmanaged, allocator: std.mem.Allocator, seperator: []const u8, limit: isize) anyerror![]JStringUnmanaged {
        const real_limit = brk: {
            if (limit < 0) {
                break :brk this.str_slice.len;
            } else {
                break :brk @as(usize, @intCast(limit));
            }
        };

        if (seperator.len == 0) {
            // Well this is quite stupid, but let us still try to cover it.
            // Essentially it creates a string for each char (utf8) and remove
            // all spaces
            return this._splitToUtf8Chars(allocator, real_limit);
        }

        var result_jstrings = try allocator.alloc(JStringUnmanaged, real_limit);
        var result_count: usize = 0;
        var search_start: usize = 0;
        var pos: isize = -1;
        while (search_start < this.str_slice.len) {
            pos = this.indexOf(seperator, search_start);
            if (pos < 0) {
                if (result_count > 0) {
                    // have found one, the what's left is rest part
                    result_jstrings[result_count] = try JStringUnmanaged.newFromSlice(allocator, this.str_slice[search_start..]);
                    result_count += 1;
                }
                break;
            } else {
                result_jstrings[result_count] = try JStringUnmanaged.newFromSlice(allocator, this.str_slice[search_start..@as(usize, @intCast(pos))]);
                result_count += 1;
                if (result_count >= real_limit) {
                    break;
                }
                search_start = @as(usize, @intCast(pos)) + seperator.len;
                continue;
            }
        }

        if (result_count == real_limit) {
            // save the copy as all buf filled
            return result_jstrings;
        } else {
            defer allocator.free(result_jstrings);
            var final_result_jstrings = try allocator.alloc(JStringUnmanaged, result_count);
            _ = &final_result_jstrings;
            if (result_count > 0) {
                @memcpy(final_result_jstrings, result_jstrings[0..result_count]);
            }
            return final_result_jstrings;
        }
    }

    /// Split by ascii whitespaces (" \t\n\r"), or called explode in languages like PHP (which is the best language! :))
    pub inline fn splitByWhiteSpace(this: *JStringUnmanaged, allocator: std.mem.Allocator, limit: isize) anyerror![]JStringUnmanaged {
        return this.explode(allocator, limit);
    }

    pub fn splitByRegex(this: *JStringUnmanaged, allocator: std.mem.Allocator, regex: anytype, limit: isize) anyerror![]JStringUnmanaged {
        _ = this;
        _ = allocator;
        _ = regex;
        _ = limit;
        @compileError("TODO, not yet implemented!");
    }

    // ** startsWith

    pub inline fn startsWith(this: *const JStringUnmanaged, prefix: JStringUnmanaged) bool {
        return this.startsWithSlice(prefix.str_slice);
    }

    pub fn startsWithSlice(this: *const JStringUnmanaged, prefix_slice: []const u8) bool {
        if (this.len() < prefix_slice.len) {
            return false;
        }
        return std.mem.eql(u8, this.str_slice[0..prefix_slice.len], prefix_slice);
    }

    // ** toLocaleLowerCase

    pub fn toLocaleLowerCase(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        _ = this;
        _ = allocator;
        @compileError("TODO, not yet implemented!");
    }

    // ** toLocaleUpperCase

    pub fn toLocalUpperCase(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        _ = this;
        _ = allocator;
        @compileError("TODO, not yet implemented!");
    }

    // ** toLowerCase

    pub fn toLowerCase(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        if (this.len() == 0) {
            return this.clone(allocator);
        }

        var new_slice = try allocator.alloc(u8, this.str_slice.len);
        @memcpy(new_slice, this.str_slice);
        var i: usize = 0;
        while (i < new_slice.len) {
            const size = try std.unicode.utf8ByteSequenceLength(new_slice[i]);
            if (size == 1) {
                new_slice[i] = std.ascii.toLower(new_slice[i]);
            }
            i += size;
        }
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    // ** toUpperCase

    pub fn toUpperCase(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        if (this.len() == 0) {
            return this.clone(allocator);
        }

        var new_slice = try allocator.alloc(u8, this.str_slice.len);
        @memcpy(new_slice, this.str_slice);
        var i: usize = 0;
        while (i < new_slice.len) {
            const size = try std.unicode.utf8ByteSequenceLength(new_slice[i]);
            if (size == 1) {
                new_slice[i] = std.ascii.toUpper(new_slice[i]);
            }
            i += size;
        }
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    // ** toWellFormed

    /// toWellFormed does not make sense in zig as zig is u8/utf8 based. No need to use this.
    pub fn toWellFormed(this: *const JStringUnmanaged) void {
        _ = this;
        @compileError("toWellFormed does not make sense in zig as zig is u8/utf8 based. No need to use this.");
    }

    // ** trim

    /// essentially =trimStart(trimEnd()). All temp strings produced in steps
    /// are deinited.
    pub fn trim(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        const str1 = try this.trimStart(allocator);
        if (str1.len() == 0) {
            return str1;
        }
        const str2 = try str1.trimEnd(allocator);
        defer str1.deinit(allocator);
        return str2;
    }

    // ** trimEnd

    /// trim blank chars(' ', '\t', '\n' and '\r') from the end. If there is
    /// nothing to trim it will return a clone of original string.
    pub fn trimEnd(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        const first_nonblank = brk: {
            var i = this.str_slice.len - 1;
            while (i >= 0) {
                switch (this.str_slice[i]) {
                    ' ', '\t', '\n', '\r' => {
                        if (i > 0) {
                            i -= 1;
                            continue;
                        } else {
                            break :brk 0;
                        }
                    },
                    else => break :brk i,
                }
            }
            break :brk 0;
        };
        if (first_nonblank == this.str_slice.len - 1) {
            return this.clone(allocator);
        } else if (first_nonblank == 0) {
            return JStringUnmanaged.newEmpty(allocator);
        } else {
            const new_slice = this.str_slice[0 .. first_nonblank + 1];
            return JStringUnmanaged.newFromSlice(allocator, new_slice);
        }
    }

    // ** trimStart

    /// trim blank chars(' ', '\t', '\n' and '\r') from beginning. If there is
    /// nothing to trim it will return a clone of original string.
    pub fn trimStart(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        const first_nonblank = brk: {
            for (this.str_slice, 0..) |char, i| {
                switch (char) {
                    ' ', '\t', '\n', '\r' => continue,
                    else => break :brk i,
                }
            }
            break :brk this.len();
        };
        if (first_nonblank == 0) {
            return this.clone(allocator);
        } else {
            const new_slice = this.str_slice[first_nonblank..];
            return JStringUnmanaged.newFromSlice(allocator, new_slice);
        }
    }

    // ** valueOf

    pub inline fn valueOf(this: *const JStringUnmanaged) []u8 {
        return this.str_slice;
    }
};

// optional components

fn defineArenaAllocator(comptime enable: bool) type {
    if (enable) {
        // A copy of zig's std.heap.ArenaAllocator for possibility to optimise for
        // string usage.
        // This allocator takes an existing allocator, wraps it, and provides an
        // interface where you can allocate without freeing, and then free it all
        // together.
        return struct {
            const Self = @This();

            child_allocator: std.mem.Allocator,
            state: State,

            /// Inner state of ArenaAllocator. Can be stored rather than the entire ArenaAllocator
            /// as a memory-saving optimization.
            pub const State = struct {
                buffer_list: std.SinglyLinkedList(usize) = .{},
                end_index: usize = 0, // the next addr to write in cur_buf

                pub fn promote(self: State, child_allocator: std.mem.Allocator) Self {
                    return .{
                        .child_allocator = child_allocator,
                        .state = self,
                    };
                }
            };

            pub fn allocator(self: *Self) std.mem.Allocator {
                return .{
                    .ptr = self,
                    .vtable = &.{
                        .alloc = alloc,
                        .resize = resize,
                        .free = free,
                    },
                };
            }

            const BufNode = std.SinglyLinkedList(usize).Node;

            pub fn init(child_allocator: std.mem.Allocator) Self {
                return (State{}).promote(child_allocator);
            }

            pub fn deinit(self: *Self) void {
                // NOTE: When changing this, make sure `reset()` is adjusted accordingly!
                var it = self.state.buffer_list.first;
                while (it) |node| {
                    // this has to occur before the free because the free frees node
                    const next_it = node.next;
                    const align_bits = std.math.log2_int(usize, @alignOf(BufNode));
                    const alloc_buf = @as([*]u8, @ptrCast(node))[0..node.data];
                    self.child_allocator.rawFree(alloc_buf, align_bits, @returnAddress());
                    it = next_it;
                }
            }

            pub const ResetMode = union(enum) {
                /// Releases all allocated memory in the arena.
                free_all,
                /// This will pre-heat the arena for future allocations by allocating a
                /// large enough buffer for all previously done allocations.
                /// Preheating will speed up the allocation process by invoking the
                /// backing allocator less often than before. If `reset()` is used in a
                /// loop, this means that after the biggest operation, no memory
                /// allocations are performed anymore.
                retain_capacity,
                /// This is the same as `retain_capacity`, but the memory will be shrunk
                /// to this value if it exceeds the limit.
                retain_with_limit: usize,
            };

            /// Queries the current memory use of this arena.
            /// This will **not** include the storage required for internal keeping.
            pub fn queryCapacity(self: Self) usize {
                var size: usize = 0;
                var it = self.state.buffer_list.first;
                while (it) |node| : (it = node.next) {
                    // Compute the actually allocated size excluding the
                    // linked list node.
                    size += node.data - @sizeOf(BufNode);
                }
                return size;
            }

            /// Resets the arena allocator and frees all allocated memory.
            ///
            /// `mode` defines how the currently allocated memory is handled.
            /// See the variant documentation for `ResetMode` for the effects of each mode.
            ///
            /// The function will return whether the reset operation was successful or not.
            /// If the reallocation  failed `false` is returned. The arena will still be fully
            /// functional in that case, all memory is released. Future allocations just might
            /// be slower.
            ///
            /// NOTE: If `mode` is `free_all`, the function will always return `true`.
            pub fn reset(self: *Self, mode: ResetMode) bool {
                // Some words on the implementation:
                // The reset function can be implemented with two basic approaches:
                // - Counting how much bytes were allocated since the last reset, and storing that
                //   information in State. This will make reset fast and alloc only a teeny tiny bit
                //   slower.

                // - Counting how much bytes were allocated by iterating the chunk linked list. This
                //   will make reset slower, but alloc() keeps the same speed when reset() as if reset()
                //   would not exist.
                //

                // The second variant was chosen for implementation, as with more and more calls to reset(),
                // the function will get faster and faster. At one point, the complexity of the function
                // will drop to amortized O(1), as we're only ever having a single chunk that will not be
                // reallocated, and we're not even touching the backing allocator anymore.
                //

                // Thus, only the first hand full of calls to reset() will actually need to iterate the linked
                // list, all future calls are just taking the first node, and only resetting the `end_index`
                // value.

                const requested_capacity = switch (mode) {
                    .retain_capacity => self.queryCapacity(),
                    .retain_with_limit => |limit| @min(limit, self.queryCapacity()),
                    .free_all => 0,
                };

                if (requested_capacity == 0) {
                    // just reset when we don't have anything to reallocate
                    self.deinit();
                    self.state = State{};
                    return true;
                }

                const total_size = requested_capacity + @sizeOf(BufNode);
                const align_bits = std.math.log2_int(usize, @alignOf(BufNode));
                // Free all nodes except for the last one

                var it = self.state.buffer_list.first;
                const maybe_first_node = while (it) |node| {
                    // this has to occur before the free because the free frees node
                    const next_it = node.next;
                    if (next_it == null)
                        break node;
                    const alloc_buf = @as([*]u8, @ptrCast(node))[0..node.data];
                    self.child_allocator.rawFree(alloc_buf, align_bits, @returnAddress());
                    it = next_it;
                } else null;
                std.debug.assert(maybe_first_node == null or maybe_first_node.?.next == null);
                // reset the state before we try resizing the buffers, so we definitely have reset the arena to 0.

                self.state.end_index = 0;
                if (maybe_first_node) |first_node| {
                    self.state.buffer_list.first = first_node;
                    // perfect, no need to invoke the child_allocator
                    if (first_node.data == total_size)
                        return true;
                    const first_alloc_buf = @as([*]u8, @ptrCast(first_node))[0..first_node.data];
                    if (self.child_allocator.rawResize(first_alloc_buf, align_bits, total_size, @returnAddress())) {
                        // successful resize
                        first_node.data = total_size;
                    } else {
                        // manual realloc
                        const new_ptr = self.child_allocator.rawAlloc(total_size, align_bits, @returnAddress()) orelse {
                            // we failed to preheat the arena properly, signal this to the user.
                            return false;
                        };
                        self.child_allocator.rawFree(first_alloc_buf, align_bits, @returnAddress());
                        const node: *BufNode = @ptrCast(@alignCast(new_ptr));
                        node.* = .{ .data = total_size };
                        self.state.buffer_list.first = node;
                    }
                }
                return true;
            }

            inline fn curAllocBuf(cur_node: *BufNode) []u8 {
                return @as([*]u8, @ptrCast(cur_node))[0..cur_node.data];
            }

            inline fn curBuf(cur_alloc_buf: []u8) []u8 {
                return cur_alloc_buf[@sizeOf(BufNode)..];
            }

            inline fn actualMinSize(minimum_size: usize) usize {
                // seems each node is layed out as
                //    |BufNode struct| data buf (minimum_size)|
                // so calculate size
                return minimum_size + @sizeOf(BufNode);
            }

            fn createNode(self: *Self, prev_len: usize, minimum_size: usize) ?*BufNode {
                const actual_min_size = actualMinSize(minimum_size);
                const len = prev_len + actual_min_size;
                const log2_align = comptime std.math.log2_int(usize, @alignOf(BufNode));
                const ptr = self.child_allocator.rawAlloc(len, log2_align, @returnAddress()) orelse
                    return null;
                const buf_node: *BufNode = @ptrCast(@alignCast(ptr));
                buf_node.* = .{ .data = len };
                self.state.buffer_list.prepend(buf_node);
                self.state.end_index = 0;
                return buf_node;
            }

            fn alloc(ctx: *anyopaque, n: usize, log2_ptr_align: u8, ra: usize) ?[*]u8 {
                const self: *Self = @ptrCast(@alignCast(ctx));
                _ = ra;

                const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
                var cur_node = if (self.state.buffer_list.first) |first_node|
                    first_node
                else
                    (self.createNode(0, n + ptr_align) orelse return null);
                while (true) {
                    const cur_alloc_buf = curAllocBuf(cur_node);
                    const cur_buf = curBuf(cur_alloc_buf);

                    // find new_end_index as follows
                    //    Memory Layout
                    //    |--------------------|-----------------------|------------------->
                    //    ^cur ptr+end_index   ^cur ptr_aligned addr   ^next ptr+end_index (+n)
                    //         ^addr            ^adjusted_addr
                    //         ^----------------^
                    //          ^delta
                    //          so: new_end_index = end_index + delta
                    const addr = @intFromPtr(cur_buf.ptr) + self.state.end_index;
                    const adjusted_addr = std.mem.alignForward(usize, addr, ptr_align);
                    const adjusted_index = self.state.end_index + (adjusted_addr - addr);
                    const new_end_index = adjusted_index + n;

                    if (new_end_index <= cur_buf.len) {
                        const result = cur_buf[adjusted_index..new_end_index];
                        self.state.end_index = new_end_index;
                        return result.ptr;
                    }

                    const bigger_buf_size = actualMinSize(new_end_index);
                    const log2_align = comptime std.math.log2_int(usize, @alignOf(BufNode));
                    if (self.child_allocator.rawResize(cur_alloc_buf, log2_align, bigger_buf_size, @returnAddress())) {
                        cur_node.data = bigger_buf_size;
                    } else {
                        // Allocate a new node if that's not possible
                        cur_node = self.createNode(cur_buf.len, n + ptr_align) orelse return null;
                    }
                }
            }

            fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
                const self: *Self = @ptrCast(@alignCast(ctx));
                _ = log2_buf_align;
                _ = ret_addr;

                const cur_node = self.state.buffer_list.first orelse return false;
                const cur_buf = curBuf(curAllocBuf(cur_node));
                if (@intFromPtr(cur_buf.ptr) + self.state.end_index != @intFromPtr(buf.ptr) + buf.len) {
                    // It's not the most recent allocation, so it cannot be expanded or shrinked
                    return false;
                }

                if (buf.len >= new_len) {
                    self.state.end_index -= buf.len - new_len;
                    return true;
                } else if (cur_buf.len - self.state.end_index >= new_len - buf.len) {
                    self.state.end_index += new_len - buf.len;
                    return true;
                }

                return false;
            }

            fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
                _ = log2_buf_align;
                _ = ret_addr;
                const self: *Self = @ptrCast(@alignCast(ctx));
                const cur_node = self.state.buffer_list.first orelse return;
                const cur_buf = curBuf(curAllocBuf(cur_node));
                if (@intFromPtr(cur_buf.ptr) + self.state.end_index == @intFromPtr(buf.ptr) + buf.len) {
                    // It is the most recent allocation...just shirnk the end_index?
                    self.state.end_index -= buf.len;
                }
            }
        };
    } else {
        return struct {
            const Self = @This();

            pub fn init(child_allocator: std.mem.Allocator) Self {
                _ = child_allocator;
                @compileError("disabled by comptime var `enable_arena_allocator`, set it true to enable.");
            }
        };
    }
}

fn defineRegexUnmanaged(comptime with_pcre: bool) type {
    if (with_pcre) {
        return struct {
            const Self = @This();
            const MatchedResultsList = std.SinglyLinkedList([]pcre.RegexMatchResult);
            const MatchedGroupResultsList = std.SinglyLinkedList([]pcre.RegexNamedGroupResult);
            const RegexError = error{
                FetchBeforeMatch,
            };

            pub const MatchedResultIterator = struct {
                const Result = struct {
                    start: usize,
                    len: usize,
                    value: []const u8,
                };

                maybe_matched_results: ?[]pcre.RegexMatchResult,
                cur_pos: usize = 0,
                subject_slice: []const u8,

                pub fn init(regex: *Self, subject: []const u8) MatchedResultIterator {
                    return MatchedResultIterator{
                        .maybe_matched_results = regex.getResults(),
                        .subject_slice = subject,
                    };
                }

                pub fn nextResult(this: *MatchedResultIterator) ?Result {
                    if (this.maybe_matched_results) |matched_results| {
                        if (this.cur_pos < matched_results.len) {
                            const start = matched_results[this.cur_pos].start;
                            const len = matched_results[this.cur_pos].len;
                            this.cur_pos += 1;
                            return Result{
                                .start = start,
                                .len = len,
                                .value = this.subject_slice[start .. start + len],
                            };
                        } else return null;
                    } else return null;
                }
            };

            pub const MatchedGroupResultIterator = struct {
                const Result = struct {
                    start: usize,
                    len: usize,
                    name: []const u8,
                    value: []const u8,
                };

                maybe_group_results: []pcre.RegexNamedGroupResult,
                cur_pos: usize,
                subject_slice: []const u8,

                pub fn init(regex: *Self, subject: []const u8) MatchedGroupResultIterator {
                    return MatchedGroupResultIterator{
                        .maybe_group_results = regex.getGroupResults(),
                        .subject_slice = subject,
                    };
                }

                pub fn nextResult(this: *MatchedResultIterator) ?Result {
                    if (this.maybe_group_results) |group_results| {
                        if (this.cur_pos < group_results.len) {
                            const start = group_results[this.cur_pos].start;
                            const len = group_results[this.cur_pos].len;
                            const name = group_results[this.cur_pos].name[0..group_results[this.cur_pos].name_len];
                            this.cur_pos += 1;
                            return Result{
                                .start = start,
                                .len = len,
                                .name = name,
                                .value = this.subject_slice[start .. start + len],
                            };
                        } else return null;
                    } else return null;
                }
            };

            pub const DefaultRegexOptions: u32 = 0;
            pub const DefaultMatchOptions: u32 = 0;

            context_: *pcre.RegexContext = undefined,
            matched_results_list: MatchedResultsList = undefined,
            matched_group_results_list: MatchedGroupResultsList = undefined,
            total_matched_results: usize = 0,
            total_matched_group_results: usize = 0,

            pub inline fn succeed(this: *const Self) bool {
                // PCRE error code 100 == success
                return this.context_.error_number == 100;
            }

            pub inline fn errorNumber(this: *const Self) usize {
                return @as(usize, @intCast(this.context_.error_number));
            }

            pub inline fn errorOffset(this: *const Self) usize {
                return this.context_.error_offset;
            }

            pub inline fn errorMessage(this: *const Self) []const u8 {
                return this.context_.error_message[0..this.context_.error_message_len];
            }

            pub inline fn getResults(this: *const Self) ?[]pcre.RegexMatchResult {
                if (this.context_.matched_count > 0) {
                    const c = @as(usize, @intCast(this.context_.matched_count));
                    return this.context_.matched_results[0..c];
                } else return null;
            }

            pub inline fn getResultsIterator(this: *Self, subject: []const u8) MatchedResultIterator {
                return MatchedResultIterator.init(this, subject);
            }

            pub inline fn getGroupResults(this: *const Self) ?[]pcre.RegexNamedGroupResult {
                if (this.context_.matched_group_count > 0) {
                    const c = @as(usize, @intCast(this.context_.matched_group_count));
                    return this.context_.matched_group_results[0..c];
                } else return null;
            }

            pub inline fn getGroupResultsIterator(this: *Self, subject: []const u8) MatchedGroupResultIterator {
                return MatchedGroupResultIterator.init(this, subject);
            }

            pub fn init(allocator: std.mem.Allocator, pattern: []const u8, regex_options: u32, match_options: u32) anyerror!Self {
                var context_ = try allocator.create(pcre.RegexContext);
                context_.regex_options = regex_options;
                context_.match_options = match_options;
                const result = pcre.compile(context_, pattern[0..].ptr);
                if (result == 0) {
                    pcre.get_last_error_message(context_);
                } else {
                    var mgrs = try allocator.alloc(pcre.RegexNamedGroupResult, context_.named_group_count);
                    context_.matched_group_results = mgrs[0..].ptr;
                }
                return Self{
                    .context_ = context_,
                    .matched_results_list = MatchedResultsList{},
                    .matched_group_results_list = MatchedGroupResultsList{},
                };
            }

            pub fn deinit(this: *Self, allocator: std.mem.Allocator) void {
                defer allocator.destroy(this.context_);
                pcre.free_context(this.context_);
                allocator.free(this.context_.matched_results);
                for (this.context_.matched_group_results) |matched_group_result| {
                    allocator.free(matched_group_result.name);
                }
                allocator.free(this.context_.matched_group_results);
            }

            /// reset regex for next new match. This will only reset
            /// matched_results & matched_group_results & free pcre underlying match object
            pub fn reset(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                allocator.free(this.context_.matched_results);
                for (this.context_.matched_group_results) |matched_group_result| {
                    allocator.free(matched_group_result.name);
                }
                allocator.free(this.context_.matched_group_results);
                // order is important, must do after free matched_results & matched_group_results
                // as pcre.free_for_next_match will reset them
                pcre.free_for_next_match(this.context_);
                try this._reset();
            }

            fn _reset(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                this.context_.matched_results = null;
                var mgrs = try allocator.alloc(pcre.RegexNamedGroupResult, this.context_.named_group_count);
                this.context_.matched_group_results = mgrs[0..].ptr;
            }

            /// if not fetch_results, this.context_.next_offset is not set, need to manually
            /// do `this.getNextOffset(subject)` for it
            pub fn match(this: *Self, allocator: std.mem.Allocator, subject_slice: []const u8, offset_pos: usize, fetch_results: bool, match_options: u32) anyerror!void {
                this.context_.match_options &= match_options;
                const m = pcre.match(this.context_, subject_slice[0..].ptr, subject_slice.len, offset_pos);
                if (m > 0) {
                    if (fetch_results) {
                        try this.fetchResults(allocator);
                        pcre.get_next_offset(this.context_, subject_slice[0..].ptr, subject_slice.len);
                    }
                }
            }

            /// must call after successful match, otherwise error
            pub fn getNextOffset(this: *Self, subject_slice: []const u8) anyerror!usize {
                if (this.context_.with_match_result == 1) {
                    if (this.context_.matched_count > 0) {
                        pcre.get_next_offset(this.context_, subject_slice[0..].ptr, subject_slice.len);
                        return this.context_.next_offset;
                    } else {
                        return this.context_.origin_offset;
                    }
                } else {
                    return error.FetchBeforeMatch;
                }
            }

            /// only for single match fetchResults lazily. For matchAll it will always fetch while match.
            pub fn fetchResults(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                if (this.context_.rc > 0) {
                    // will only fetch when rc > 0 (which must equal matched_results_capacity), so this is ... relatively ... safe :)
                    const matched_capacity = @as(usize, @intCast(this.context_.matched_results_capacity));
                    const mrs = try allocator.alloc(pcre.RegexMatchResult, matched_capacity);
                    this.context_.matched_results = mrs.ptr;
                    pcre.prepare_named_groups(this.context_);
                    if (this.context_.named_group_count > 0) {
                        const named_group_count = @as(usize, @intCast(this.context_.named_group_count));
                        for (0..named_group_count) |i| {
                            const name_len = this.context_.matched_group_results[i].name_len;
                            const name_slice = try allocator.alloc(u8, name_len);
                            this.context_.matched_group_results[i].name = name_slice.ptr;
                        }
                    }
                    pcre.fetch_match_results(this.context_);
                }
            }

            /// fetchResults will be done while match.
            pub fn matchAll(this: *Self, allocator: std.mem.Allocator, subject_slice: []const u8, offset_pos: usize, match_options: u32) anyerror!void {
                this.context_.match_options &= match_options;
                var m: i64 = 0;
                var offset: usize = offset_pos;
                while (offset < subject_slice.len) {
                    m = pcre.match(this.context_, subject_slice[0..].ptr, subject_slice.len, offset);
                    if (m > 0) {
                        try this.fetchResults(allocator);
                        if (this.getResults()) |matched_results| {
                            const n = try allocator.create(MatchedResultsList.Node);
                            n.data = matched_results;
                            this.matched_results_list.prepend(n);
                            this.total_matched_results += matched_results.len;
                        }
                        if (this.getGroupResults()) |named_group_results| {
                            const n = try allocator.create(MatchedGroupResultsList.Node);
                            n.data = named_group_results;
                            this.matched_group_results_list.prepend(n);
                            this.total_matched_group_results += named_group_results.len;
                        }
                        pcre.get_next_offset(this.context_, subject_slice[0..].ptr, subject_slice.len);
                        offset = this.context_.next_offset;
                        try this._reset(allocator);
                    } else break;
                }

                try this._mergeMatchedResults(allocator);
                try this._mergeMatchedGroupResults(allocator);
            }

            fn _mergeMatchedResults(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                const total_matched_results: usize = this.total_matched_results;
                var merged_matched_results: []pcre.RegexMatchResult = undefined;

                if (total_matched_results > 0) {
                    merged_matched_results = try allocator.alloc(pcre.RegexMatchResult, total_matched_results);
                    var offset: usize = merged_matched_results.len - 1;
                    brk: {
                        while (this.matched_results_list.popFirst()) |n| {
                            for (1..n.data.len + 1) |i| {
                                merged_matched_results[offset] = n.data[n.data.len - i];
                                if (offset == 0) {
                                    allocator.free(n.data);
                                    allocator.destroy(n);
                                    break :brk;
                                }
                                offset -= 1;
                            }
                            allocator.free(n.data);
                            allocator.destroy(n);
                        }
                    }
                }

                if (this.context_.matched_results_capacity > 0) {
                    const old_matched_results = this.context_.matched_results[0..@as(usize, @intCast(this.context_.matched_results_capacity))];
                    defer allocator.free(old_matched_results);
                }

                this.context_.matched_count = @as(i64, @intCast(total_matched_results));
                this.context_.matched_results_capacity = @as(i64, @intCast(total_matched_results));
                this.context_.matched_results = merged_matched_results.ptr;
            }

            fn _mergeMatchedGroupResults(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                const total_matched_group_results: usize = this.total_matched_group_results;

                var merged_matched_group_results: []pcre.RegexNamedGroupResult = undefined;
                if (total_matched_group_results > 0) {
                    merged_matched_group_results = try allocator.alloc(pcre.RegexNamedGroupResult, total_matched_group_results);
                    var offset: usize = merged_matched_group_results.len - 1;
                    brk: {
                        while (offset > 0) {
                            while (this.matched_group_results_list.popFirst()) |n| {
                                for (1..n.data.len + 1) |i| {
                                    merged_matched_group_results[offset] = n.data[n.data.len - i];
                                    if (offset == 0) {
                                        allocator.free(n.data);
                                        allocator.destroy(n);
                                        break :brk;
                                    }
                                    offset -= 1;
                                }
                                allocator.free(n.data);
                                allocator.destroy(n);
                            }
                        }
                    }
                }

                if (this.context_.named_group_count > 0) {
                    const old_matched_group_results = this.context_.matched_group_results[0..@as(usize, @intCast(this.context_.named_group_count))];
                    defer allocator.free(old_matched_group_results);
                }

                this.context_.matched_group_count = @as(i64, @intCast(total_matched_group_results));
                this.context_.matched_group_results = merged_matched_group_results.ptr;
            }
        };
    } else {
        return struct {
            const Self = @This();

            pub fn init(allocator: std.mem.Allocator, pattern: []const u8, regex_options: u32, match_options: u32) anyerror!Self {
                _ = allocator;
                _ = pattern;
                _ = regex_options;
                _ = match_options;
                @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
            }
        };
    }
}

// >>> internal functions

fn _bufPrintFmt(comptime type_info: std.builtin.Type, comptime fmt_buf: []u8, comptime fmt_len_: *usize, comptime fmt_print_slice_: *[]u8) void {
    var printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "{{", .{});
    fmt_len_.* = fmt_len_.* + printed_fmt.len;
    fmt_print_slice_.* = fmt_buf[fmt_len_.*..];

    _bufPrintSpecifier(type_info, fmt_buf, fmt_len_, fmt_print_slice_);

    printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "}}", .{});
    fmt_len_.* = fmt_len_.* + printed_fmt.len;
    fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
}

fn _bufPrintSpecifier(comptime type_info: std.builtin.Type, comptime fmt_buf: []u8, comptime fmt_len_: *usize, comptime fmt_print_slice_: *[]u8) void {
    var printed_fmt: []u8 = undefined;
    switch (type_info) {
        .Array => {
            printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "any", .{});
            fmt_len_.* = fmt_len_.* + printed_fmt.len;
            fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One, .Many, .C => {
                printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "s", .{});
                fmt_len_.* = fmt_len_.* + printed_fmt.len;
                fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
            },
            .Slice => {
                printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "any", .{});
                fmt_len_.* = fmt_len_.* + printed_fmt.len;
                fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
            },
        },
        .Optional => |info| {
            printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "?", .{});
            fmt_len_.* = fmt_len_.* + printed_fmt.len;
            fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
            _bufPrintSpecifier(@typeInfo(info.child), fmt_buf, fmt_len_, fmt_print_slice_);
        },
        .ErrorUnion => |info| {
            printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "!", .{});
            fmt_len_.* = fmt_len_.* + printed_fmt.len;
            fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
            _bufPrintSpecifier(@typeInfo(info.payload), fmt_buf, fmt_len_, fmt_print_slice_);
        },
        else => {
            printed_fmt = try std.fmt.bufPrint(fmt_print_slice_.*, "", .{});
            fmt_len_.* = fmt_len_.* + printed_fmt.len;
            fmt_print_slice_.* = fmt_buf[fmt_len_.*..];
        },
    }
}

/// very unsafe, you have been warned to know what you are doing
fn _slice_at(comptime T: type, haystack: []const T, index: isize) T {
    if (index >= 0) {
        return haystack[@as(usize, @intCast(index))];
    } else {
        return haystack[@as(usize, @intCast(@as(isize, @intCast(haystack.len)) + index))];
    }
}

fn _kmp_build_failure_table(allocator: std.mem.Allocator, needle_slice: []const u8) anyerror![]isize {
    const t = try allocator.alloc(isize, (needle_slice.len + 1));
    @memset(t, 0);

    var j: isize = 0;
    for (1..needle_slice.len) |i| {
        j = _slice_at(isize, t, @as(isize, @intCast(i)));
        while (j > 0 and _slice_at(u8, needle_slice, @as(isize, @intCast(i))) != _slice_at(u8, needle_slice, j)) {
            j = _slice_at(isize, t, j);
        }
        if (j > 0 or _slice_at(u8, needle_slice, @as(isize, @intCast(i))) == _slice_at(u8, needle_slice, j)) {
            t[i + 1] = j + 1;
        }
    }

    return t;
}

fn _test_return_error_union(value_or_error: bool, value: i32, err: anyerror) !i32 {
    return if (value_or_error) value else err;
}

// >>> all your tests belong to me and list in below <<<

test "ArenaAllocator" {
    if (enable_arena_allocator) {
        {
            var arena_allocator = ArenaAllocator.init(std.testing.allocator);
            defer arena_allocator.deinit();
            // provides some variance in the allocated data

            var rng_src = std.rand.DefaultPrng.init(19930913);
            const random = rng_src.random();
            var rounds: usize = 25;
            while (rounds > 0) {
                rounds -= 1;
                _ = arena_allocator.reset(.retain_capacity);
                var alloced_bytes: usize = 0;
                const total_size: usize = random.intRangeAtMost(usize, 256, 16384);
                while (alloced_bytes < total_size) {
                    const size = random.intRangeAtMost(usize, 16, 256);
                    const alignment = 32;
                    const slice = try arena_allocator.allocator().alignedAlloc(u8, alignment, size);
                    try std.testing.expect(std.mem.isAligned(@intFromPtr(slice.ptr), alignment));
                    try std.testing.expectEqual(size, slice.len);
                    alloced_bytes += slice.len;
                }
            }
        }
        {
            var arena_allocator = ArenaAllocator.init(std.testing.allocator);
            defer arena_allocator.deinit();
            const a = arena_allocator.allocator();

            // Create two internal buffers
            _ = try a.alloc(u8, 1);
            _ = try a.alloc(u8, 1000);

            // Check that we have at least two buffers
            try std.testing.expect(arena_allocator.state.buffer_list.first.?.next != null);

            // This retains the first allocated buffer
            try std.testing.expect(arena_allocator.reset(.{ .retain_with_limit = 1 }));
        }
    }
}

test "constructors" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
    try testing.expectEqual(str1.len(), 0);
    const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    try testing.expectEqual(str2.len(), 11);
    const str3 = try JStringUnmanaged.newFromJStringUnmanaged(arena.allocator(), str2);
    try testing.expectEqual(str3.len(), 11);
    const str4 = try JStringUnmanaged.newFromFormat(arena.allocator(), "{s}", .{"jstring"});
    try testing.expectEqual(str4.len(), 7);
    const str5 = try JStringUnmanaged.newFromTuple(arena.allocator(), .{ "jstring", 5 });
    try testing.expectEqual(str5.len(), 8);
}

test "utils" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
        const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
        const str3 = try JStringUnmanaged.newFromJStringUnmanaged(arena.allocator(), str2);
        try testing.expect(str1.eqlSlice(""));
        try testing.expect(str1.isEmpty());
        try testing.expect(str2.eqlJStringUmanaged(str3));
        try testing.expect(str3.eqlSlice("hello,world"));
        const str4 = try str3.clone(arena.allocator());
        try testing.expect(str4.eqlSlice("hello,world"));
        try testing.expect(str3.str_slice.ptr != str4.str_slice.ptr);
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "zig更好的c💯");
        try testing.expectEqual(str1.utf8Len(), 8);
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), " zig 更好 \t 的c\t💯");
        const strings1 = try str1.explode(arena.allocator(), -1);
        try testing.expectEqual(strings1.len, 4);
        const strings2 = try str1.explode(arena.allocator(), 2);
        try testing.expectEqual(strings2.len, 2);
        try testing.expect(strings2[0].eqlSlice("zig"));
        try testing.expect(strings2[1].eqlSlice("更好"));
    }
}

test "concat" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    var str_array_buf: [256]JStringUnmanaged = undefined;
    str_array_buf[0] = str1;
    const str2 = try str1.concat(arena.allocator(), str_array_buf[0..1]);
    try testing.expect(str1.eqlSlice("hello,world" ** 1));
    try testing.expect(str2.eqlSlice("hello,world" ** 2));
    str_array_buf[1] = str2;
    const str3 = try str1.concat(arena.allocator(), str_array_buf[0..2]);
    try testing.expect(str3.eqlSlice("hello,world" ** 4));
    const str4 = try str1.concat(arena.allocator(), str_array_buf[0..0]);
    try testing.expect(str4.eqlSlice("hello,world"));
    try testing.expect(str4.str_slice.ptr != str1.str_slice.ptr);
    const str5 = try str1.concatFormat(arena.allocator(), "{s}", .{" jstring"});
    try testing.expect(str5.eqlSlice("hello,world jstring"));
    const optional_6: ?i32 = 6;
    const error1 = _test_return_error_union(false, 0, error.OutOfMemory);
    const str6 = try str1.concatTuple(arena.allocator(), .{
        " jstring",
        5,
        optional_6,
        error1,
    });
    // std.debug.print("\n{s}\n", .{str6.slice});
    try testing.expect(str6.eqlSlice("hello,world jstring56error.OutOfMemory"));
}

test "startsWith/endsWith" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
    try testing.expect(str1.startsWith(str2));
    try testing.expect(str1.startsWithSlice(""));
    try testing.expect(str1.startsWithSlice("hello"));
    try testing.expect(!str1.startsWithSlice("hello,world,more"));
    const str3 = try JStringUnmanaged.newFromSlice(arena.allocator(), "world");
    try testing.expect(str1.endsWith(str3));
    try testing.expect(str1.endsWithSlice(""));
    try testing.expect(str1.endsWithSlice("world"));
    try testing.expect(!str1.endsWithSlice("hello,world,more"));
}

test "trim/trimStart/trimEnd" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "  hello,world");
        const str2 = try str1.trimStart(arena.allocator());
        try testing.expect(str2.eqlSlice("hello,world"));
        const str3 = try str2.trimStart(arena.allocator());
        try testing.expect(str3.eqlSlice("hello,world"));
        const str4 = try JStringUnmanaged.newFromSlice(arena.allocator(), "  \t  ");
        const str5 = try str4.trimStart(arena.allocator());
        try testing.expect(str5.eqlSlice(""));
    }
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world  ");
        const str2 = try str1.trimEnd(arena.allocator());
        try testing.expect(str2.eqlSlice("hello,world"));
        const str3 = try str2.trimEnd(arena.allocator());
        try testing.expect(str3.eqlSlice("hello,world"));
        const str4 = try JStringUnmanaged.newFromSlice(arena.allocator(), "  \t  ");
        const str5 = try str4.trimEnd(arena.allocator());
        try testing.expect(str5.eqlSlice(""));
    }
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "  hello,world  ");
        const str2 = try str1.trim(arena.allocator());
        try testing.expect(str2.eqlSlice("hello,world"));
        const str4 = try JStringUnmanaged.newFromSlice(arena.allocator(), "  \t  ");
        const str5 = try str4.trimEnd(arena.allocator());
        try testing.expect(str5.eqlSlice(""));
    }
}

test "chartAt/at" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
        const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "abcdefg");
        try testing.expectEqual(str1.charAt(0), error.IndexOutOfBounds);
        try testing.expectEqual(str2.charAt(0), 'a');
        try testing.expectEqual(str2.charAt(2), 'c');
        try testing.expectEqual(str2.charAt(-3), 'e');
        try testing.expectEqual(str2.charAt(-7), 'a');
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "zig更好的c💯");
        try testing.expectEqual(str1.at(0), 'z');
        try testing.expectEqual(str1.at(3), '更');
        try testing.expectEqual(str1.at(-1), '💯');
        try testing.expectEqual(str1.at(-8), 'z');
    }
}

test "iterator/reverseIterator/utf8Iterator" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
        const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "ab");
        var it1 = str1.iterator();
        try testing.expectEqual(it1.next(), null);
        var it2 = str2.iterator();
        try testing.expectEqual(it2.next(), 'a');
        try testing.expectEqual(it2.next(), 'b');
        try testing.expectEqual(it2.next(), null);
        var it3 = str2.reverseIterator();
        try testing.expectEqual(it3.next(), 'b');
        try testing.expectEqual(it3.next(), 'a');
        try testing.expectEqual(it3.next(), null);
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "zig更好的c💯");
        var it1 = try str1.utf8Iterator();
        try testing.expectEqual(it1.nextCodepoint(), 'z');
    }
}

test "padStart/padEnd" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
        const str2 = try str1.padStart(arena.allocator(), 12, "welcome");
        try testing.expect(str2.eqlSlice("welcomehello"));
        const str3 = try str1.padStart(arena.allocator(), 15, "welcome");
        try testing.expect(str3.eqlSlice("omewelcomehello"));
    }
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
        const str2 = try str1.padEnd(arena.allocator(), 10, "world");
        try testing.expect(str2.eqlSlice("helloworld"));
        const str3 = try str1.padEnd(arena.allocator(), 13, "world");
        try testing.expect(str3.eqlSlice("helloworldwor"));
    }
}

test "indexOf/lastIndexOf/includes" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,worldhello,world");
        try testing.expectEqual(str1.indexOf("hello", 0), 0);
        try testing.expectEqual(str1.lastIndexOf("hello", 0), 11);
        try testing.expectEqual(str1.indexOf("hello", 6), 11);
        try testing.expectEqual(str1.indexOf("nothere", 0), -1);
        try testing.expectEqual(str1.indexOf("", 0), 0);
        try testing.expectEqual(str1.indexOf("", 6), 6);
        try testing.expectEqual(str1.lastIndexOf("", 0), 21);
        try testing.expectEqual(str1.lastIndexOf("", 6), 21);
        try testing.expect(str1.includes("hello", 0));
        try testing.expect(!str1.includes("nothere", 0));
    }
    {
        const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,worldhello,world");
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "hello", 0), 0);
        try testing.expectEqual(str2.fastLastIndexOf(arena.allocator(), "hello", 0), 11);
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "hello", 6), 11);
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "nothere", 0), -1);
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "", 0), 0);
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "", 6), 6);
        try testing.expectEqual(str2.fastLastIndexOf(arena.allocator(), "", 0), 21);
        try testing.expectEqual(str2.fastLastIndexOf(arena.allocator(), "", 6), 21);
        try testing.expect(str2.fastIncludes(arena.allocator(), "hello", 0));
        try testing.expect(!str2.fastIncludes(arena.allocator(), "nothere", 0));
    }
}

test "repeat" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
        const str2 = try str1.repeat(arena.allocator(), 2);
        try testing.expect(str2.eqlSlice("hellohello"));
        const str3 = try str1.repeat(arena.allocator(), 0);
        try testing.expect(str3.eqlSlice(""));
    }
}

test "slice" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
        const str2 = try str1.sliceWithStartOnly(arena.allocator(), 0);
        try testing.expect(str2.eqlSlice("hello,world"));
        const str3 = try str1.sliceWithStartOnly(arena.allocator(), 6);
        try testing.expect(str3.eqlSlice("world"));
        const str4 = try str1.sliceWithStartOnly(arena.allocator(), -5);
        try testing.expect(str4.eqlSlice("world"));
        const str5 = try str1.sliceWithStartOnly(arena.allocator(), -11);
        try testing.expect(str5.eqlSlice("hello,world"));
        var r = str1.sliceWithStartOnly(arena.allocator(), -15);
        try testing.expectEqual(r, error.IndexOutOfBounds);
        r = str1.slice(arena.allocator(), 0, -15);
        try testing.expectEqual(r, error.IndexOutOfBounds);
        const str6 = try str1.slice(arena.allocator(), 15, 7);
        try testing.expect(str6.eqlSlice(""));
        const str7 = try str1.slice(arena.allocator(), 8, 7);
        try testing.expect(str7.eqlSlice(""));
        const str8 = try str1.slice(arena.allocator(), 6, 15);
        try testing.expect(str8.eqlSlice("world"));
        const str9 = try str1.slice(arena.allocator(), 6, 8);
        try testing.expect(str9.eqlSlice("wo"));
        const str10 = try str1.slice(arena.allocator(), 6, -3);
        try testing.expect(str10.eqlSlice("wo"));
    }
}

test "toLowerCase/toUpperCase" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hEllO,💯woRld");
        const str2 = try str1.toUpperCase(arena.allocator());
        try testing.expect(str2.eqlSlice("HELLO,💯WORLD"));
        const str3 = try str1.toLowerCase(arena.allocator());
        try testing.expect(str3.eqlSlice("hello,💯world"));
    }
}

test "split" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,💯world");
        var strings1 = try str1.split(arena.allocator(), ",", -1);
        try testing.expectEqual(strings1.len, 2);
        try testing.expect(strings1[0].eqlSlice("hello"));
        try testing.expect(strings1[1].eqlSlice("💯world"));
        var strings2 = try str1.split(arena.allocator(), ",", 1);
        try testing.expectEqual(strings2.len, 1);
        try testing.expect(strings2[0].eqlSlice("hello"));
        var str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "\thello 💯 world ");
        var strings3 = try str2.split(arena.allocator(), "", -1);
        try testing.expectEqual(strings3.len, 11);
        try testing.expect(strings3[0].eqlSlice("h"));
        try testing.expect(strings3[5].eqlSlice("💯"));
        try testing.expect(strings3[10].eqlSlice("d"));
    }
}

test "RegexUnmanged" {
    if (enable_pcre) {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "hel+o", 0, 0);
            try testing.expectEqual(re.errorNumber(), 100);
            try re.match(arena.allocator(), "hello,hello,world", 0, true, 0);
            try testing.expect(re.succeed());
            const matched_results = re.getResults();
            try testing.expect(matched_results != null);
            if (matched_results) |mr| {
                // std.debug.print("\n{d}\n", .{mr.len});
                try testing.expect(mr[0].start == 0);
                try testing.expect(mr[0].len == 5);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "hel+o", 0, 0);
            try testing.expectEqual(re.errorNumber(), 100);
            try re.matchAll(arena.allocator(), "hello,hello,world", 0, 0);
            try testing.expect(re.succeed());
            const matched_results = re.getResults();
            try testing.expect(matched_results != null);
            if (matched_results) |mr| {
                // std.debug.print("\n{d}\n", .{mr.len});
                try testing.expect(mr.len == 2);
                try testing.expect(mr[0].start == 0);
                try testing.expect(mr[0].len == 5);
                try testing.expect(mr[1].start == 6);
                try testing.expect(mr[1].len == 5);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(?<h>hel+o)", 0, 0);
            try testing.expectEqual(re.errorNumber(), 100);
            try re.matchAll(arena.allocator(), "hello,hello,world", 0, 0);
            try testing.expect(re.succeed());
            const matched_results = re.getResults();
            try testing.expect(matched_results != null);
            if (matched_results) |mr| {
                try testing.expect(mr.len == 2);
                try testing.expect(mr[0].start == 0);
                try testing.expect(mr[0].len == 5);
                try testing.expect(mr[1].start == 6);
                try testing.expect(mr[1].len == 5);
            }
            const matched_group_results = re.getGroupResults();
            try testing.expect(matched_group_results != null);
            if (matched_group_results) |mgr| {
                try testing.expect(mgr.len == 2);
                try testing.expectEqualSlices(u8, mgr[0].name[0..mgr[0].name_len], "h");
                try testing.expect(mgr[0].start == 0);
                try testing.expect(mgr[0].len == 5);
                try testing.expectEqualSlices(u8, mgr[1].name[0..mgr[1].name_len], "h");
                try testing.expect(mgr[1].start == 6);
                try testing.expect(mgr[1].len == 5);
            }
        }
    }
}

test "match/matchAll" {
    if (enable_pcre) {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            var re = try str1.match(arena.allocator(), "hel+o", 0, true, RegexUnmanaged.DefaultRegexOptions, RegexUnmanaged.DefaultMatchOptions);
            try testing.expect(re.succeed());
            var it = re.getResultsIterator(str1.str_slice);
            var maybe_result = it.nextResult();
            if (maybe_result) |r| {
                try testing.expectEqual(r.start, 0);
                try testing.expectEqual(r.len, 5);
                try testing.expectEqualSlices(u8, r.value, "hello");
            }
            maybe_result = it.nextResult();
            if (maybe_result) |r| {
                try testing.expectEqual(r.start, 6);
                try testing.expectEqual(r.len, 5);
                try testing.expectEqualSlices(u8, r.value, "hello");
            }
            maybe_result = it.nextResult();
            try testing.expectEqual(maybe_result, null);
        }
    }
}
