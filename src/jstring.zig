const std = @import("std");
const testing = std.testing;

// target: create a reusable string lib for myself with
//   1. CPU cache efficiency considered (use the technique in bunjs)
//   2. all familiar methods can find in javascript string:
//        https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String

pub const JStringArenaAllocator = struct {
    const Self = @This();

    const Allocation = struct {
        ptr: [*]u8,
        len: usize,
    };
    const AllocatedMap = std.AutoHashMap(u64, Allocation);

    base_allocator: std.mem.Allocator,
    allocated_map: AllocatedMap,
    vtable: std.mem.Allocator.VTable,

    pub fn init(base_allocator: std.mem.Allocator) Self {
        return Self{
            .base_allocator = base_allocator,
            .allocated_map = AllocatedMap.init(base_allocator),
            .vtable = .{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn allocator(this: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = this,
            .vtable = &this.vtable,
        };
    }

    pub fn deinit(this: *Self) void {
        defer this.allocated_map.deinit();
        var it = this.allocated_map.iterator();
        while (it.next()) |record| {
            const allocation = @as(Allocation, record.value_ptr.*);
            this.base_allocator.free(allocation.ptr[0..allocation.len]);
        }
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *JStringArenaAllocator = @ptrFromInt(@intFromPtr(ctx));
        const result = self.base_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |ptr| {
            const key = @intFromPtr(ptr);
            self.allocated_map.put(key, .{ .ptr = ptr, .len = len }) catch unreachable;
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *JStringArenaAllocator = @ptrFromInt(@intFromPtr(ctx));
        const result = self.base_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            const key = @intFromPtr(buf.ptr);
            self.allocated_map.put(key, .{ .ptr = buf.ptr, .len = new_len }) catch unreachable;
        }
        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *JStringArenaAllocator = @ptrFromInt(@intFromPtr(ctx));
        const key = @intFromPtr(buf.ptr);
        _ = self.allocated_map.remove(key);
        self.base_allocator.rawFree(buf, buf_align, ret_addr);
    }
};

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

    pub fn newEmpty(allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        const new_slice = try allocator.alloc(u8, 0);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    pub fn newFromSlice(allocator: std.mem.Allocator, string_slice: []const u8) anyerror!JStringUnmanaged {
        const new_slice = try allocator.alloc(u8, string_slice.len);
        @memcpy(new_slice, string_slice);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    pub fn newFromJStringUnmanaged(allocator: std.mem.Allocator, that: JStringUnmanaged) anyerror!JStringUnmanaged {
        const new_slice = try allocator.alloc(u8, that.len());
        @memcpy(new_slice, that.str_slice);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    pub fn newFromFormat(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) anyerror!JStringUnmanaged {
        const new_slice = try std.fmt.allocPrint(allocator, fmt, args);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

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

    // utils

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

    pub inline fn clone(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        return JStringUnmanaged.newFromJStringUnmanaged(allocator, this.*);
    }

    pub inline fn isEmpty(this: *const JStringUnmanaged) bool {
        return this.len() == 0;
    }

    pub inline fn eqlSlice(this: *const JStringUnmanaged, string_slice: []const u8) bool {
        return std.mem.eql(u8, this.str_slice, string_slice);
    }

    pub inline fn eqlJStringUmanaged(this: *const JStringUnmanaged, that: JStringUnmanaged) bool {
        return std.mem.eql(u8, this.str_slice, that.str_slice);
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

    pub fn fromCharCode() JStringUnmanaged {
        @compileError("zig supports utf-8 natively, use newFromSlice instead.");
    }

    // ** fromCodePoint

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

    pub fn localeCompare(this: *const JStringUnmanaged) bool {
        _ = this;
        @compileError("Not implemented! Does this method make sense in zig?");
    }

    // TODO match
    // TODO matchAll

    // ** normalize

    pub fn normalize(this: *const JStringUnmanaged) JStringUnmanaged {
        _ = this;
        @compileError("Oops, normalize function is not supported!");
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

    pub fn raw() JStringUnmanaged {
        @compileError("zig has no template literals like javascript, use newFromSlice/newFromFormat/newFromTuple instead.");
    }

    // ** repeat

    pub fn repeat(this: *const JStringUnmanaged, allocator: std.mem.Allocator, count: usize) anyerror!JStringUnmanaged {
        if (count == 0) {
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
    // TODO search

    // ** slice

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

    // TODO split

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

// >>> all your tests belong to me and list in belowing <<<

test "constructors" {
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
}

test "concat" {
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
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
    var arena = JStringArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hEllO,💯woRld");
        const str2 = try str1.toUpperCase(arena.allocator());
        try testing.expect(str2.eqlSlice("HELLO,💯WORLD"));
        const str3 = try str1.toLowerCase(arena.allocator());
        try testing.expect(str3.eqlSlice("hello,💯world"));
    }
}
