/// jstring.zig
///
/// Author: Yu Li (liyu1981@gmail.com)
///
/// Target: create a reusable string lib for myself with all familiar methods methods can find in javascript string.
///
/// Reason:
///   1. string is important we all know, so a good string lib will be very useful.
///   2. javascript string is (in my opinion) the most battle tested string library out there, strike a good balance
///      between features and complexity.
///
/// The javascript string specs and methods this file use as reference can be found at
///   https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String
///
/// All methods except those marked as deprecated (such as anchor, big, blink etc) are implemented, in zig way.
const enable_arena_allocator: bool = true;
const enable_pcre: bool = true;

// TODOs:
//   * complete tests
//   * arena allocator
//   * benchmark
//   * README + doc

const std = @import("std");
const testing = std.testing;

const pcre = if (enable_pcre) @import("pcre_binding.zig") else undefined;

pub const JStringError = error{
    RegexFetchBeforeMatch,
    RegexBadPattern,
    RegexMatchFailed,
    // Usually reported when use with splitByRegex/replaceByRegex, indicating that the pattern used will result in
    // overlapped matches so that we can determinstically know how to split/replace. The possible reason is the pattern
    // is using named group. Or you can debug your regex with `RegexUnmanaged.matchAll` or use https://regex101.com/
    RegexMatchOverlapped,
};

pub const ArenaAllocator = defineArenaAllocator(enable_arena_allocator);

// managed versions
//   just very thin wrap around unmanaged versions, where has all real implemenats

pub const Regex = defineRegex(enable_pcre);

pub const JString = struct {
    allocator: std.mem.Allocator,
    unmanaged: JStringUnmanaged,

    pub const U8Iterator = JStringUnmanaged.U8Iterator;
    pub const U8ReverseIterator = JStringUnmanaged.U8ReverseIterator;

    pub fn deinit(this: *JString) void {
        this.unmanaged.deinit(this.allocator);
    }

    pub inline fn newEmpty(allocator: std.mem.Allocator) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newEmpty(allocator),
        };
    }

    pub fn newFromSlice(allocator: std.mem.Allocator, string_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromSlice(allocator, string_slice),
        };
    }

    pub fn newFromJString(that: JString) anyerror!JString {
        return JString{
            .allocator = that.allocator,
            .unmanaged = try JStringUnmanaged.newFromJStringUnmanaged(that.allocator, that.unmanaged),
        };
    }

    pub fn newFromFormat(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromFormat(allocator, fmt, args),
        };
    }

    pub fn newFromTuple(allocator: std.mem.Allocator, rest_items: anytype) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromTuple(allocator, rest_items),
        };
    }

    pub inline fn newFromNumber(allocator: std.mem.Allocator, comptime T: type, value: T) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromNumber(allocator, T, value),
        };
    }

    pub inline fn newFromStringify(allocator: std.mem.Allocator, value: anytype) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromStringify(allocator, value),
        };
    }

    pub inline fn newFromStringifyWithOptions(allocator: std.mem.Allocator, value: anytype, options: std.json.StringifyOptions) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromStringifyWithOptions(allocator, value, options),
        };
    }

    pub inline fn newFromFile(allocator: std.mem.Allocator, f: std.fs.File) anyerror!JString {
        return JString{
            .allocator = allocator,
            .unmanaged = try JStringUnmanaged.newFromFile(allocator, f),
        };
    }

    pub inline fn hash(this: *const JString) usize {
        return this.unmanaged.hash();
    }

    pub inline fn format(
        this: *const JString,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try this.unmanaged.format(fmt, options, writer);
    }

    pub inline fn len(this: *const JString) usize {
        return this.unmanaged.len();
    }

    pub inline fn utf8Len(this: *JString) anyerror!usize {
        return this.unmanaged.utf8Len();
    }

    pub inline fn clone(this: *const JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.clone(this.allocator),
        };
    }

    pub inline fn isEmpty(this: *const JString) bool {
        return this.unmanaged.isEmpty();
    }

    pub inline fn eqlSlice(this: *const JString, string_slice: []const u8) bool {
        return this.unmanaged.eqlSlice(string_slice);
    }

    pub inline fn eql(this: *const JString, that: JString) bool {
        return this.eqlSlice(that.unmanaged.str_slice);
    }

    pub inline fn explode(this: *const JString, limit: isize) anyerror![]JString {
        const unmanaged_strings = try this.unmanaged.explode(this.allocator, limit);
        const strings = try this.allocator.alloc(JString, unmanaged_strings.len);
        for (0..unmanaged_strings.len) |i| {
            strings[i] = JString{
                .allocator = this.allocator,
                .unmanaged = unmanaged_strings[i],
            };
        }
        return strings;
    }

    // ** iterator

    pub inline fn iterator(this: *const JString) U8Iterator {
        return this.unmanaged.iterator();
    }

    pub inline fn reverseIterator(this: *const JString) U8ReverseIterator {
        return this.unmanaged.reverseIterator();
    }

    pub inline fn utf8Iterator(this: *JString) anyerror!std.unicode.Utf8Iterator {
        return this.unmanaged.utf8Iterator();
    }

    // ** at

    pub inline fn at(this: *JString, index: isize) anyerror!u21 {
        return this.unmanaged.at(index);
    }

    // ** charAt

    pub inline fn charAt(this: *const JString, index: isize) anyerror!u8 {
        return this.unmanaged.charAt(index);
    }

    // ** charCodeAt

    pub inline fn charCodeAt(this: *const JString, index: isize) anyerror!u21 {
        _ = this;
        _ = index;
        @compileError("charCodeAt does not make sense in zig, please use at or charAt!");
    }

    // ** codePointAt

    pub inline fn codePointAt(this: *const JString, index: isize) anyerror!u21 {
        _ = this;
        _ = index;
        @compileError("codePointAt does not make sense in zig, please use at or charAt!");
    }

    // ** concat

    pub inline fn concat(this: *const JString, other_jstring: JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.concat(this.allocator, other_jstring.unmanaged),
        };
    }

    pub inline fn concatSlice(this: *const JString, other_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.concatSlice(this.allocator, other_slice),
        };
    }

    /// as we can not know len of rest_jstrings in comptime, so this method is a bit of slower than unmanaged version
    /// (or concatManySlices). Preciesly, slower than one allocation/deallocation of
    /// `[rest_jstrings.len]const []const u8` time.
    pub fn concatMany(this: *const JString, rest_jstrings: []const JString) anyerror!JString {
        if (rest_jstrings.len == 0) {
            return this.clone();
        } else {
            const rest_slices = try this.allocator.alloc([]const u8, rest_jstrings.len);
            defer this.allocator.free(rest_slices);
            for (0..rest_slices.len) |i| rest_slices[i] = rest_jstrings[i].unmanaged.str_slice;
            return JString{
                .allocator = this.allocator,
                .unmanaged = try this.unmanaged.concatManySlices(this.allocator, rest_slices),
            };
        }
    }

    pub inline fn concatManySlices(this: *const JString, rest_slices: []const []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.concatManySlices(this.allocator, rest_slices),
        };
    }

    pub inline fn concatFormat(this: *const JString, comptime fmt: []const u8, rest_items: anytype) anyerror!JString {
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
            return this.clone();
        } else {
            var rest_items_unmanaged_jstring = try JStringUnmanaged.newFromFormat(this.allocator, fmt, rest_items);
            defer rest_items_unmanaged_jstring.deinit(this.allocator);
            var rest_items_jstrings = [1]JString{JString{ .allocator = this.allocator, .unmanaged = rest_items_unmanaged_jstring }};
            return this.concat(&rest_items_jstrings);
        }
    }

    pub inline fn concatTuple(this: *const JString, rest_items: anytype) anyerror!JString {
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

        return this.concatFormat(fmt_buf[0..fmt_len], rest_items);
    }

    // ** endsWith

    pub inline fn endsWith(this: *const JString, suffix: JString) bool {
        return this.unmanaged.endsWith(suffix.unmanaged);
    }

    pub inline fn endsWithSlice(this: *const JString, suffix_slice: []const u8) bool {
        return this.unmanaged.endsWithSlice(suffix_slice);
    }

    // ** fromCharCode

    /// zig supports utf-8 natively, use newFromSlice instead.
    pub inline fn fromCharCode() JString {
        @compileError("zig supports utf-8 natively, use newFromSlice instead.");
    }

    // ** fromCodePoint

    /// zig supports utf-8 natively, use newFromSlice instead.
    pub inline fn fromCodePoint() JString {
        @compileError("zig supports utf-8 natively, use newFromSlice instead.");
    }

    // ** includes

    pub inline fn includes(this: *const JString, needle_slice: []const u8, pos: usize) bool {
        return this.unmanaged.includes(needle_slice, pos);
    }

    pub inline fn fastIncludes(this: *const JString, needle_slice: []const u8, pos: usize) bool {
        return this.unmanaged.fastIncludes(this.allocator, needle_slice, pos);
    }

    // ** indexOf

    pub inline fn indexOf(this: *const JString, needle_slice: []const u8, pos: usize) isize {
        return this.unmanaged.indexOf(needle_slice, pos);
    }

    pub inline fn fastIndexOf(this: *const JString, needle_slice: []const u8, pos: usize) anyerror!isize {
        return this.unmanaged.fastsIndexof(this.allocator, needle_slice, pos);
    }

    // ** isWellFormed

    pub fn isWellFormed(this: *const JString) bool {
        return this.unmananged.isWellFormed();
    }

    // ** lastIndexOf

    pub inline fn lastIndexOf(this: *const JString, needle_slice: []const u8, pos: usize) isize {
        return this.unmanaged.lastIndexOf(needle_slice, pos);
    }

    pub inline fn fastLastIndexOf(this: *const JString, needle_slice: []const u8, pos: usize) anyerror!isize {
        return this.unmanaged.fastLastIndexOf(this.allocator, needle_slice, pos);
    }

    // ** localeCompare

    pub inline fn localeCompare(this: *const JString) bool {
        _ = this;
        @compileError("Not implemented! Does localeCompare make sense in zig?");
    }

    // ** match

    pub inline fn match(this: *const JString, pattern: []const u8, offset: usize, fetch_results: bool, regex_options: u32, match_options: u32) anyerror!Regex {
        if (enable_pcre) {
            return Regex{
                .allocator = this.allocator,
                .unmanaged = try this.unmanaged.match(this.allocator, pattern, offset, fetch_results, regex_options, match_options),
            };
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** matchAll

    pub inline fn matchAll(this: *const JString, pattern: []const u8, offset: usize, regex_options: u32, match_options: u32) anyerror!Regex {
        if (enable_pcre) {
            return this.unmanaged.matchAll(this.allocator, pattern, offset, regex_options, match_options);
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** normalize

    pub inline fn normalize(this: *const JString) JString {
        _ = this;
        @compileError("Not implemented! Does normalize make sense in zig?");
    }

    // ** padEnd

    pub inline fn padEnd(this: *const JString, wanted_len: usize, pad_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.padEnd(this.allocator, wanted_len, pad_slice),
        };
    }

    /// JString version of padEnd, accept pad_string (*const JStringUnmanaged) instead of slice.
    pub inline fn padEndJString(this: *const JString, wanted_len: usize, pad_string: *const JString) anyerror!JString {
        return this.padEnd(wanted_len, pad_string.unmanaged.str_slice);
    }

    // ** padStart

    pub inline fn padStart(this: *const JString, wanted_len: usize, pad_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.padStart(this.allocator, wanted_len, pad_slice),
        };
    }

    pub inline fn padStartJString(this: *const JString, wanted_len: usize, pad_string: *const JString) anyerror!JString {
        return this.padStart(wanted_len, pad_string.unmanaged.str_slice);
    }

    // ** raw

    pub inline fn raw() JString {
        @compileError("zig has no template literals like javascript, use newFromSlice/newFromFormat/newFromTuple instead.");
    }

    // ** repeat

    pub inline fn repeat(this: *const JString, count: usize) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.repeat(this.allocator, count),
        };
    }

    // ** replace

    pub inline fn replace(this: *const JString, pattern: []const u8, replacement_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.replace(this.allocator, pattern, replacement_slice),
        };
    }

    pub inline fn replaceByRegex(this: *const JString, pattern: []const u8, replacement_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.replaceByRegex(this.allocator, pattern, replacement_slice),
        };
    }

    // ** replaceAll

    pub inline fn replaceAll(this: *const JString, pattern: []const u8, replacement_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.replaceAll(this.allocator, pattern, replacement_slice),
        };
    }

    pub inline fn replaceAllByRegex(this: *const JString, pattern: []const u8, replacement_slice: []const u8) anyerror!JString {
        return JString{
            .allocator = this.allcator,
            .unmanaged = try this.unmanaged.repalceAllByRegex(this.allocator, pattern, replacement_slice),
        };
    }

    // ** search

    pub inline fn search(this: *const JString, pattern: []const u8, offset: usize) isize {
        return this.unmanaged.search(pattern, offset);
    }

    pub inline fn searchByRegex(this: *const JString, pattern: []const u8, offset: usize) anyerror!isize {
        if (enable_pcre) {
            return this.unmanaged.searchByRegex(this.allocator, pattern, offset);
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** slice

    pub inline fn slice(this: *const JString, index_start: isize, index_end: isize) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.slice(this.allocator, index_start, index_end),
        };
    }

    pub inline fn sliceWithStartOnly(this: *const JString, index_start: isize) anyerror!JString {
        return this.slice(index_start, @as(isize, @intCast(this.len())));
    }

    // ** split

    pub inline fn split(this: *JString, seperator: []const u8, limit: isize) anyerror![]JString {
        const unmanaged_strings = try this.unmanaged.split(this.allocator, seperator, limit);
        const strings = try this.allocator.alloc(JString, unmanaged_strings.len);
        for (0..unmanaged_strings.len) |i| strings[i] = JString{
            .allocator = this.allocator,
            .unmanaged = unmanaged_strings[i],
        };
        return strings;
    }

    pub inline fn splitByWhiteSpace(this: *JString, limit: isize) anyerror![]JString {
        return this.explode(limit);
    }

    pub inline fn splitByRegex(this: *JString, pattern: []const u8, offset: usize, limit: isize) anyerror![]JString {
        if (enable_pcre) {
            const unmanaged_strings = try this.unmanaged.splitByRegex(this.allocator, pattern, offset, limit);
            const strings = try this.allocator.alloc(JString, unmanaged_strings.len);
            for (0..unmanaged_strings.len) |i| strings[i] = JString{
                .allocator = this.allocator,
                .unmanaged = unmanaged_strings[i],
            };
            return strings;
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** startsWith

    pub inline fn startsWith(this: *const JString, prefix: JString) bool {
        return this.startsWithSlice(prefix.unmanaged.str_slice);
    }

    pub fn startsWithSlice(this: *const JString, prefix_slice: []const u8) bool {
        return this.unmanaged.startsWithSlice(prefix_slice);
    }

    // ** toLocaleLowerCase

    pub fn toLocaleLowerCase(this: *const JString) anyerror!JString {
        _ = this;
        @compileError("TODO, not yet implemented!");
    }

    // ** toLocaleUpperCase

    pub fn toLocalUpperCase(this: *const JString) anyerror!JString {
        _ = this;
        @compileError("TODO, not yet implemented!");
    }

    // ** toLowerCase

    pub fn toLowerCase(this: *const JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.toLowerCase(this.allocator),
        };
    }

    // ** toUpperCase

    pub fn toUpperCase(this: *const JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.toUpperCase(this.allocator),
        };
    }

    // ** toWellFormed

    pub fn toWellFormed(this: *const JString) void {
        _ = this;
        @compileError("toWellFormed does not make sense in zig as zig is u8/utf8 based. No need to use this.");
    }

    // ** trim

    pub fn trim(this: *const JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.unmanaged.trim(this.allocator),
        };
    }

    // ** trimEnd

    pub fn trimEnd(this: *const JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.trimEnd(this.allocator),
        };
    }

    // ** trimStart

    pub fn trimStart(this: *const JString) anyerror!JString {
        return JString{
            .allocator = this.allocator,
            .unmanaged = try this.trimStart(this.allocator),
        };
    }

    // ** valueOf

    pub inline fn valueOf(this: *const JString) []const u8 {
        return this.unmanaged.str_slice;
    }
};

// unmanaged versions: the real deal

pub const RegexUnmanaged = defineRegexUnmanaged(enable_pcre);

pub const JStringUnmanaged = struct {
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

    /// Returns a string copied the content of slice. i.e.,
    /// `const s = try JStringUnmanaged.newFromSlice(allocator, "hello,world");`
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

    /// Returns a string from auto formatting a tuple of items. Essentially what it does is to guess the fmt
    /// automatically. The max items of the tuple is 32.
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

    pub inline fn newFromNumber(allocator: std.mem.Allocator, comptime T: type, value: T) anyerror!JStringUnmanaged {
        switch (@typeInfo(T)) {
            .Int => {},
            .Float => {},
            else => @compileError("parseInt can only work on number like types: integer or float (i32/u32/f32...)."),
        }
        return JStringUnmanaged.newFromFormat(allocator, "{d}", .{value});
    }

    pub fn newFromStringify(allocator: std.mem.Allocator, value: anytype) anyerror!JStringUnmanaged {
        const new_slice = try std.json.stringifyAlloc(allocator, value, .{});
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    pub fn newFromStringifyWithOptions(allocator: std.mem.Allocator, value: anytype, options: std.json.StringifyOptions) anyerror!JStringUnmanaged {
        const new_slice = try std.json.stringifyAlloc(allocator, value, options);
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    pub fn newFromFile(allocator: std.mem.Allocator, f: std.fs.File) anyerror!JStringUnmanaged {
        const stat = try f.stat();
        var new_slice = try allocator.alloc(u8, stat.size);
        const read_size = try f.readAll(new_slice);
        if (read_size == stat.size) {
            return JStringUnmanaged{
                .str_slice = new_slice,
            };
        } else {
            return JStringUnmanaged.newFromSlice(allocator, new_slice[0..read_size]);
        }
    }

    // utils

    pub fn hash(this: *const JStringUnmanaged) usize {
        var wyhash = std.hash.Wyhash.init(0);
        wyhash.update(this.str_slice);
        return wyhash.final();
    }

    pub fn format(
        this: *const JStringUnmanaged,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        _ = options;
        _ = fmt;
        try writer.print("{s}", .{this.str_slice});
    }

    /// Simple util to return the underlying slice's len (= this.str_slice.len). Less typing, less errors.
    pub inline fn len(this: *const JStringUnmanaged) usize {
        return this.str_slice.len;
    }

    /// First time call utf8Len will init the utf8_view and calculate len once. After that we will just use the cached
    /// view and len.
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

    fn _cloneAsArray(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror![]JStringUnmanaged {
        var result_jstrings = try allocator.alloc(JStringUnmanaged, 1);
        result_jstrings[0] = try this.clone(allocator);
        return result_jstrings;
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
    pub inline fn eql(this: *const JStringUnmanaged, that: JStringUnmanaged) bool {
        return this.eqlSlice(that.str_slice);
    }

    /// explode this string to small strings sperated by ascii spaces while respects utf8 chars. Limit can be -1 or
    /// positive numbers. When limit is negative means auto calculate how many strings can return; otherwise will return
    /// min(limit, possible max number of strings)
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

    /// different to Javascript's string.at, return unicode char(u21) of index, as prefer utf-8 string. Same to
    /// Javascript, accept index as `i32`: when postive is from beginning; when negative is from ending; when
    /// `index == 0`, return the the first char if not empty.
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
            }
            if (i >= char_pos) {
                break;
            }
        }
        return unicode_char;
    }

    // ** charAt

    /// different to Javascript's string.charAt, return u8 of index, as prefer utf-8 string. Same to Javascript,
    /// accept index as `i32`: when postive is from beginning; when negative is from ending; when `index == 0`, return
    /// the the first char if not empty.
    pub fn charAt(this: *const JStringUnmanaged, index: isize) anyerror!u8 {
        if (index >= this.len()) {
            return error.IndexOutOfBounds;
        }

        if ((-index) > this.len()) {
            return error.IndexOutOfBounds;
        }

        if (index >= 0) {
            return this.str_slice[@intCast(index)];
        } else {
            return this.str_slice[this.len() - @as(usize, @intCast(-index))];
        }
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

    /// Concat jstrings with the other.
    pub fn concat(this: *const JStringUnmanaged, allocator: std.mem.Allocator, other_jstring: JStringUnmanaged) anyerror!JStringUnmanaged {
        return this.concatSlice(allocator, other_jstring.str_slice);
    }

    pub fn concatSlice(this: *const JStringUnmanaged, allocator: std.mem.Allocator, other_slice: []const u8) anyerror!JStringUnmanaged {
        if (other_slice.len == 0) {
            return this.clone(allocator);
        } else {
            const this_len = this.len();
            const other_len = other_slice.len;
            const new_slice = try allocator.alloc(u8, this_len + other_len);
            var new_slice_ptr = new_slice.ptr;
            @memcpy(new_slice_ptr, this.str_slice);
            new_slice_ptr += this.str_slice.len;
            @memcpy(new_slice_ptr, other_slice);
            return JStringUnmanaged{
                .str_slice = new_slice,
            };
        }
    }

    /// Concat jstrings in rest_jstrings in order, return a new allocated jstring. If `rest_jstrings.len == 0`, will
    /// return a copy of this jstring.
    pub fn concatMany(this: *const JStringUnmanaged, allocator: std.mem.Allocator, rest_jstrings: []const JStringUnmanaged) anyerror!JStringUnmanaged {
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

    pub fn concatManySlices(this: *const JStringUnmanaged, allocator: std.mem.Allocator, rest_slices: []const []const u8) anyerror!JStringUnmanaged {
        if (rest_slices.len == 0) {
            return this.clone(allocator);
        } else {
            var rest_sum_len: usize = 0;
            const new_len = this.len() + lenbrk: {
                for (rest_slices) |s| {
                    rest_sum_len += s.len;
                }
                break :lenbrk rest_sum_len;
            };

            const new_slice = try allocator.alloc(u8, new_len);
            var new_slice_ptr = new_slice.ptr;
            @memcpy(new_slice_ptr, this.str_slice);
            new_slice_ptr += this.str_slice.len;
            for (rest_slices) |s| {
                @memcpy(new_slice_ptr, s);
                new_slice_ptr += s.len;
            }
            return JStringUnmanaged{
                .str_slice = new_slice,
            };
        }
    }

    /// Concat jstrings by format with fmt & .{ data }. It is a shortcut for first creating tmp str from
    /// JStringUnmanaged.newFromFormat then second this.concat(tmp str). (or below psudeo code)
    ///
    /// ```
    /// var tmp_jstring = JStringUnmanaged.newFromFormat(allocator, fmt, rest_items);
    /// defer tmp_jstring.deinit(allocator);
    /// const tmp_jstrings = []JStringUnmanaged{ tmp_jstring };
    /// this.concat(allocator, &tmp_jstrings);
    /// ```
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
            return this.concatMany(allocator, &rest_items_jstrings);
        }
    }

    /// Similar to concatFormat, but try to auto gen fmt from rest_items.
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

    /// The indexOf() method searches this string and returns the index of the first occurrence of the specified
    /// substring. It takes an starting position and returns the first occurrence of the specified substring at an index
    /// greater than or equal to the specified number.
    pub inline fn indexOf(this: *const JStringUnmanaged, needle_slice: []const u8, pos: usize) isize {
        return this._naive_indexOf(needle_slice, pos, false);
    }

    /// Fast version of indexOf as it uses KMP algorithm for searching. Will result in O(this.len+needle_slice.len) but
    /// also requires allocator for creating KMP lookup table.
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

        if (this.str_slice.len < needle_slice.len) {
            return -1;
        }

        var occurence: isize = -1;
        const haystack_slice = this.str_slice[pos..];
        var k: usize = 0;
        while (k < haystack_slice.len - needle_slice.len + 1) : (k += 1) {
            if (std.mem.eql(u8, haystack_slice[k .. k + needle_slice.len], needle_slice)) {
                occurence = @as(isize, @intCast(k));
                if (!want_last) {
                    return if (occurence >= 0) @as(isize, @intCast(pos)) + occurence else occurence;
                }
            } else continue;
        }
        return if (occurence >= 0) @as(isize, @intCast(pos)) + occurence else occurence;
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

        const t = try _kmpBuildFailureTable(allocator, needle_slice);
        defer allocator.free(t);

        var j: isize = 0;
        for (0..haystack_slice.len) |i| {
            if (_sliceAt(u8, haystack_slice, @as(isize, @intCast(i))) == _sliceAt(u8, needle_slice, j)) {
                j += 1;
                if (j >= needle_slice.len) {
                    occurence = @as(isize, @intCast(i)) - j + 1;
                    if (!want_last) {
                        return if (occurence >= 0) @as(isize, @intCast(pos)) + occurence else occurence;
                    }
                    j = _sliceAt(isize, t, j);
                }
            } else if (j > 0) {
                j = _sliceAt(isize, t, j);
            }
        }

        return if (occurence >= 0) @as(isize, @intCast(pos)) + occurence else occurence;
    }

    // ** isWellFormed

    /// similar to definition in javascript, but with difference that we are checking utf8.
    pub fn isWellFormed(this: *const JStringUnmanaged) bool {
        switch (this.utf8Len()) {
            .Error => return false,
            else => return true,
        }
    }

    // ** lastIndexOf

    /// The lastIndexOf() method searches this string and returns the index of the last occurrence of the specified
    /// substring. It takes an optional starting position and returns the last occurrence of the specified substring at
    /// an index less than or equal to the specified number.
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

    /// Thin wrap of Regex's match against this.str_slice as search subject. The regex syntax used is pcre2, can read
    /// here: https://pcre2project.github.io/pcre2/doc/html/pcre2pattern.html, or try it here: https://regex101.com/
    pub inline fn match(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, offset: usize, fetch_results: bool, regex_options: u32, match_options: u32) anyerror!RegexUnmanaged {
        if (enable_pcre) {
            var re = try RegexUnmanaged.init(allocator, pattern, regex_options);
            try re.match(allocator, this.str_slice, offset, fetch_results, match_options);
            return re;
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** matchAll

    /// Thin wrap of Regex's matchAll against this.str_slice as search subject. The regex syntax used is pcre2, can read
    /// here: https://pcre2project.github.io/pcre2/doc/html/pcre2pattern.html, or try it here: https://regex101.com/
    pub inline fn matchAll(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, offset: usize, regex_options: u32, match_options: u32) anyerror!RegexUnmanaged {
        if (enable_pcre) {
            var re = try RegexUnmanaged.init(allocator, pattern, regex_options);
            try re.matchAll(allocator, this.str_slice, offset, match_options);
            return re;
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** normalize

    /// Not implemented! Does normalize make sense in zig?
    pub fn normalize(this: *const JStringUnmanaged) JStringUnmanaged {
        _ = this;
        @compileError("Not implemented! Does normalize make sense in zig?");
    }

    // ** padEnd

    /// The padEnd method creates a new string by padding this string with a given slice (repeated, if needed) so that
    /// the resulting string reaches a given length. The padding is applied from the end of this string. If padString is
    /// too long to stay within targetLength, it will be truncated from the beginning.
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

    /// JString version of padEnd, accept pad_string (*const JStringUnmanaged) instead of slice.
    pub inline fn padEndJString(this: *const JStringUnmanaged, allocator: std.mem.Allocator, wanted_len: usize, pad_string: *const JStringUnmanaged) anyerror!JStringUnmanaged {
        return this.padEnd(allocator, wanted_len, pad_string.str_slice);
    }

    // ** padStart

    /// The padStart() method creates a new string by padding this string with another slice (multiple times, if needed)
    /// until the resulting string reaches the given length. The padding is applied from the start of this string. If
    /// pad_slice is too long to stay within the wanted_len, it will be truncated from the end.
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

    /// JString version of padStart, accept pad_string (*const JStringUnmanaged) instead of slice.
    pub inline fn padStartJString(this: *const JStringUnmanaged, allocator: std.mem.Allocator, wanted_len: usize, pad_string: *const JStringUnmanaged) anyerror!JStringUnmanaged {
        return this.padStart(allocator, wanted_len, pad_string.str_slice);
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

    // ** replace

    pub fn replace(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, replacement_slice: []const u8) anyerror!JStringUnmanaged {
        return this._replace(allocator, pattern, replacement_slice, false);
    }

    pub fn replaceByRegex(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, replacement_slice: []const u8) anyerror!JStringUnmanaged {
        return this._replaceByRegex(allocator, pattern, replacement_slice, false);
    }

    // ** replaceAll

    pub fn replaceAll(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, replacement_slice: []const u8) anyerror!JStringUnmanaged {
        return this._replace(allocator, pattern, replacement_slice, true);
    }

    pub fn replaceAllByRegex(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, replacement_slice: []const u8) anyerror!JStringUnmanaged {
        return this._replaceByRegex(allocator, pattern, replacement_slice, true);
    }

    fn _replace(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, replacement_slice: []const u8, comptime match_all: bool) anyerror!JStringUnmanaged {
        const max_gap_count: usize = if (match_all) @divFloor(this.str_slice.len, pattern.len) else 1;
        var gaps = try allocator.alloc(_MatchedGapIterator.Gap, max_gap_count);
        defer allocator.free(gaps);
        var gap_count: usize = 0;
        var search_offset: usize = 0;
        var found: isize = 0;
        if (match_all) {
            while (true) {
                found = this.indexOf(pattern, search_offset);
                if (found >= 0) {
                    gaps[gap_count] = _MatchedGapIterator.Gap{ .start = @as(usize, @intCast(found)), .len = pattern.len };
                    gap_count += 1;
                    search_offset = @as(usize, @intCast(found)) + pattern.len;
                } else break;
            }
        } else {
            found = this.indexOf(pattern, 0);
            if (found >= 0) {
                gaps[gap_count] = _MatchedGapIterator.Gap{ .start = @as(usize, @intCast(found)), .len = pattern.len };
                gap_count += 1;
                search_offset = @as(usize, @intCast(found)) + pattern.len;
            }
        }
        if (gap_count == 0) {
            return this.clone(allocator);
        } else {
            return this._joinGapsWithSlice(allocator, gaps[0..gap_count], replacement_slice);
        }
    }

    fn _replaceByRegex(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, replacement_slice: []const u8, comptime match_all: bool) anyerror!JStringUnmanaged {
        if (enable_pcre) {
            var re = try RegexUnmanaged.init(allocator, pattern, RegexUnmanaged.DefaultRegexOptions);
            if (match_all) {
                try re.matchAll(allocator, this.str_slice, 0, RegexUnmanaged.DefaultMatchOptions);
            } else {
                try re.match(allocator, this.str_slice, 0, true, RegexUnmanaged.DefaultMatchOptions);
            }
            if (!re.succeed()) {
                return JStringError.RegexMatchFailed;
            }
            if (re.matchSucceed()) {
                var first_gap_start_from_zero = false;
                var last_gap_end_in_end = false;
                const gap_count = brk: {
                    // stupid method, scan once to know how many gaps we have
                    // but since this helps us to avoid allocation (just mem access)
                    // probably it is also fast enough
                    var gap_it = _MatchedGapIterator.init(&re, this.str_slice);
                    var count: usize = 0;
                    while (try gap_it.nextGap()) |g| {
                        if (g.start == 0) {
                            // gap is not overlapping, so simply check every one,
                            // there must be one at most start at 0
                            first_gap_start_from_zero = true;
                        }
                        if (g.start + g.len == this.str_slice.len) {
                            // same idea, must be at most one end at the end
                            last_gap_end_in_end = true;
                        }
                        count += 1;
                    }
                    break :brk count;
                };
                var gaps = try allocator.alloc(_MatchedGapIterator.Gap, gap_count);
                defer allocator.free(gaps);
                var gap_it = _MatchedGapIterator.init(&re, this.str_slice);
                var count: usize = 0;
                while (try gap_it.nextGap()) |g| {
                    gaps[count] = _MatchedGapIterator.Gap{ .start = g.start, .len = g.len };
                    count += 1;
                }
                return this._joinGapsWithSlice(allocator, gaps, replacement_slice);
            } else return JStringError.RegexMatchFailed;
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    fn _joinGapsWithSlice(this: *const JStringUnmanaged, allocator: std.mem.Allocator, gaps: []_MatchedGapIterator.Gap, replacement_slice: []const u8) anyerror!JStringUnmanaged {
        var first_gap_start_from_zero = false;
        var last_gap_end_in_end = false;
        var total_gap_len: usize = 0;
        for (gaps) |g| {
            if (g.start == 0) {
                // gap is not overlapping, so simply check every one,
                // there must be one at most start at 0
                first_gap_start_from_zero = true;
            }
            if (g.start + g.len == this.str_slice.len) {
                // same idea, must be at most one end at the end
                last_gap_end_in_end = true;
            }
            total_gap_len += g.len;
        }
        const new_slice_len = this.str_slice.len - total_gap_len + replacement_slice.len * gaps.len;
        var new_slice = try allocator.alloc(u8, new_slice_len);
        var copy_offset: usize = 0;
        var copy_len: usize = 0;
        var origin_offset: usize = 0;
        for (gaps) |g| {
            // |<gap>..<gap>..|, |..<gap>..<gap>| or |..<gap>..<gap>..<gap>..|
            copy_len = g.start - origin_offset;
            @memcpy(new_slice[copy_offset .. copy_offset + copy_len], this.str_slice[origin_offset .. origin_offset + copy_len]);
            copy_offset += copy_len;
            origin_offset += copy_len;

            copy_len = replacement_slice.len;
            @memcpy(new_slice[copy_offset .. copy_offset + copy_len], replacement_slice);
            copy_offset += copy_len;
            origin_offset += g.len;
        }
        if (!last_gap_end_in_end) {
            // |<gap>..<gap>..| or |..<gap>..<gap>..<gap>..|
            @memcpy(new_slice[copy_offset..], this.str_slice[origin_offset..]);
        }
        return JStringUnmanaged{
            .str_slice = new_slice,
        };
    }

    // ** search

    /// simple search algorithm is alias of indexOf
    pub inline fn search(this: *const JStringUnmanaged, pattern: []const u8, offset: usize) isize {
        return this.indexOf(pattern, offset);
    }

    /// This function is searching by regex so it requires allocator. If the pattern is valid, will return first matched
    /// start or -1 (when there is no match). Buf if the pattern itself has problem, will return
    /// `JStringError.RegexMatchFailed`.
    pub fn searchByRegex(this: *const JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, offset: usize) anyerror!isize {
        if (enable_pcre) {
            var re = try RegexUnmanaged.init(allocator, pattern, RegexUnmanaged.DefaultRegexOptions);
            try re.match(allocator, this.str_slice, offset, true, RegexUnmanaged.DefaultMatchOptions);
            defer re.deinit(allocator);
            if (!re.succeed()) {
                // This usually means there is a problem in the pattern, so we reports back instead of returning -1
                return JStringError.RegexMatchFailed;
            }
            if (re.matchSucceed()) {
                const maybe_results = re.getResults();
                if (maybe_results) |results| {
                    return @as(isize, @intCast(results[0].start));
                } else unreachable;
            } else {
                return -1;
            }
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
    }

    // ** slice

    /// Slice part of current string and return a new copy with content `[index_start, index_end)`. Both `index_start`
    /// and `index_end` can be positive or negative numbers. When is positive, means the forward location from string
    /// beginning; when is negative, means the backward location from string ending. Example: if `s` contains `"hello"`,
    /// `s.slice(allocator, 1, -1)` will return a new string with content `"ell"`.
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
    fn _splitToUtf8Chars(this: *JStringUnmanaged, allocator: std.mem.Allocator, limit: usize, comptime with_spaces: bool) anyerror![]JStringUnmanaged {
        if (limit == 0) {
            return try allocator.alloc(JStringUnmanaged, 0);
        }

        var result_count: usize = 0;
        const utf8_len = try this.utf8Len(); // force for a utf8_view
        const real_limit = if (limit < utf8_len) limit else utf8_len;
        var result_jstrings = try allocator.alloc(JStringUnmanaged, real_limit);
        var it = try this.utf8Iterator();
        while (it.nextCodepoint()) |code_point| {
            if (with_spaces) {
                result_jstrings[result_count] = try JStringUnmanaged.newFromFormat(allocator, "{u}", .{code_point});
                result_count += 1;
                if (result_count >= real_limit) {
                    break;
                }
            } else {
                switch (code_point) {
                    ' ', '\t', '\n', '\r' => continue,
                    else => {
                        result_jstrings[result_count] = try JStringUnmanaged.newFromFormat(allocator, "{u}", .{code_point});
                        result_count += 1;
                        if (result_count >= real_limit) {
                            break;
                        }
                    },
                }
            }
        }

        if (result_count == real_limit) {
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

    /// split by simple seperator([]const u8). If you need to split by white spaces, use `splitByWhiteSpace`, or
    /// even more advanced `splitByRegex` (need to enable pcre support). Given limit negative value to split any many
    /// as possible.
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
            return this._splitToUtf8Chars(allocator, if (real_limit < this.str_slice.len) real_limit else this.str_slice.len, true);
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

    /// Split based on regex matching. With greate power comes great responsibility.
    pub fn splitByRegex(this: *JStringUnmanaged, allocator: std.mem.Allocator, pattern: []const u8, offset: usize, limit: isize) anyerror![]JStringUnmanaged {
        if (enable_pcre) {
            const real_limit = brk: {
                if (limit < 0) {
                    // most will be +1, like "hello".split(/./) => (6) ['', '', '', '', '', '']
                    break :brk this.str_slice.len + 1;
                } else {
                    break :brk @as(usize, @intCast(limit));
                }
            };
            if (real_limit == 0) {
                return this._cloneAsArray(allocator);
            }

            var re = try RegexUnmanaged.init(allocator, pattern, RegexUnmanaged.DefaultRegexOptions);
            try re.matchAll(allocator, this.str_slice, offset, RegexUnmanaged.DefaultMatchOptions);
            if (re.succeed() and re.matchSucceed()) {
                var first_gap_start_from_zero = false;
                var last_gap_end_in_end = false;
                const gap_count = brk: {
                    // stupid method, scan once to know how many gaps we have
                    // but since this helps us to avoid allocation (just mem access)
                    // probably it is also fast enough
                    var gap_it = _MatchedGapIterator.init(&re, this.str_slice);
                    var count: usize = 0;
                    while (try gap_it.nextGap()) |g| {
                        if (g.start == 0) {
                            // gap is not overlapping, so simply check every one,
                            // there must be one at most start at 0
                            first_gap_start_from_zero = true;
                        }
                        if (g.start + g.len == this.str_slice.len) {
                            // same idea, must be at most one end at the end
                            last_gap_end_in_end = true;
                        }
                        count += 1;
                    }
                    break :brk count;
                };
                const jstrings_count = brk2: {
                    const count_by_gap = brk: {
                        if (first_gap_start_from_zero and last_gap_end_in_end) {
                            // |<gap>..<gap>..<gap>|
                            break :brk gap_count + 1;
                        } else if (first_gap_start_from_zero) {
                            // |<gap>..<gap>..|
                            break :brk gap_count + 1;
                        } else if (last_gap_end_in_end) {
                            // |..<gap>..<gap>|
                            break :brk gap_count;
                        } else {
                            // |..<gap>..<gap>..<gap>..|
                            break :brk gap_count + 1;
                        }
                    };
                    break :brk2 if (real_limit < count_by_gap) real_limit else count_by_gap;
                };
                var result_jstrings = try allocator.alloc(JStringUnmanaged, jstrings_count);
                var count: usize = 0;
                var slice_offset: usize = 0;
                var gap_it = _MatchedGapIterator.init(&re, this.str_slice);
                while (try gap_it.nextGap()) |g| {
                    if (count >= jstrings_count) {
                        break;
                    }
                    // |<gap>..<gap>..| or
                    // |..<gap>..<gap>| or |..<gap>..<gap>..<gap>..|
                    // no matter what, we can do this
                    result_jstrings[count] = try JStringUnmanaged.newFromSlice(allocator, this.str_slice[slice_offset..g.start]);
                    slice_offset = g.start + g.len;
                    count += 1;
                }
                if (count < jstrings_count) {
                    // |<gap>| or |..<gap>..<gap>..<gap>..| or |<gap>..<gap>..|
                    // still missing one so get the last piece done
                    result_jstrings[count] = try JStringUnmanaged.newFromSlice(allocator, this.str_slice[slice_offset..]);
                }
                return result_jstrings;
            } else return JStringError.RegexMatchFailed;
        } else {
            @compileError("disabled by comptime var `enable_pcre`, set it true to enable.");
        }
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
            return JStringUnmanaged.newEmpty(allocator);
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
            return JStringUnmanaged.newEmpty(allocator);
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

    /// essentially =trimStart(trimEnd()). All temp strings produced in steps are deinited.
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

    /// trim blank chars(' ', '\t', '\n' and '\r') from the end. If there is nothing to trim it will return a clone of
    /// original string.
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

    /// trim blank chars(' ', '\t', '\n' and '\r') from beginning. If there is nothing to trim it will return a clone
    /// of original string.
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

    pub inline fn valueOf(this: *const JStringUnmanaged) []const u8 {
        return this.str_slice;
    }
};

// util functions

pub inline fn freeJStringArray(a: []JString) void {
    if (a.len > 0) {
        const allocator = a[0].allocator;
        for (0..a.len) |i| a[i].deinit();
        allocator.free(a);
    }
}

pub fn freeJStringUnmanagedArray(allocator: std.mem.Allocator, a: []JStringUnmanaged) void {
    if (a.len > 0) {
        for (0..a.len) |i| a[i].deinit(allocator);
        allocator.free(a);
    }
}

// optional components

fn defineArenaAllocator(comptime enable: bool) type {
    if (enable) {
        // A copy of zig's std.heap.ArenaAllocator for possibility to optimise for string usage.
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

fn defineRegex(comptime with_pcre: bool) type {
    if (with_pcre) {
        return struct {
            const Self = @This();

            allocator: std.mem.Allocator,
            unmanaged: RegexUnmanaged,

            const MatchedResultsList = RegexUnmanaged.MatchedResultsList;
            const MatchedGroupResultsList = RegexUnmanaged.MatchedGroupResultsList;

            pub const MatchedResultIterator = RegexUnmanaged.MatchedResultIterator;
            pub const MatchedGroupResultIterator = RegexUnmanaged.MatchedGroupResultIterator;
            pub const DefaultRegexOptions = RegexUnmanaged.DefaultRegexOptions;
            pub const DefaultMatchOptions = RegexUnmanaged.DefaultMatchOptions;

            pub fn init(allocator: std.mem.Allocator, pattern: []const u8, regex_options: u32) anyerror!Self {
                return Self{
                    .allocator = allocator,
                    .unmanaged = try RegexUnmanaged.init(allocator, pattern, regex_options),
                };
            }

            pub inline fn matchSucceed(this: *const Self) bool {
                return this.unmanaged.matchSucceed();
            }

            pub inline fn succeed(this: *const Self) bool {
                return this.unmanaged.succeed();
            }

            pub inline fn errorNumber(this: *const Self) usize {
                return this.unmanaged.errorNumber();
            }

            pub inline fn errorOffset(this: *const Self) usize {
                return this.unmanaged.errorOffset();
            }

            pub inline fn errorMessage(this: *const Self) []const u8 {
                return this.unmanaged.errorMessage();
            }

            pub inline fn getResults(this: *const Self) ?[]pcre.RegexMatchResult {
                return this.unmanaged.getResults();
            }

            pub inline fn getResultsIterator(this: *Self, subject: []const u8) MatchedResultIterator {
                return this.unmanaged.getResultsIterator(subject);
            }

            pub inline fn getGroupResults(this: *const Self) ?[]pcre.RegexGroupResult {
                return this.unmanaged.getGroupResults();
            }

            pub inline fn getGroupResultByName(this: *const Self, name: []const u8) ?pcre.RegexGroupResult {
                return this.unmanaged.getGroupResultByName(name);
            }

            pub inline fn getGroupResultsIterator(this: *Self, subject: []const u8) MatchedGroupResultIterator {
                return this.unmanaged.getGroupResultsIterator(subject);
            }

            pub inline fn deinit(this: *Self) void {
                this.unmanaged.deinit(this.allocator);
            }

            pub inline fn reset(this: *Self) anyerror!void {
                return this.unmanaged.reset(this.allocator);
            }

            pub inline fn match(this: *Self, subject_slice: []const u8, offset_pos: usize, fetch_results: bool, match_options: u32) anyerror!void {
                return this.unmanaged.match(this.allocator, subject_slice, offset_pos, fetch_results, match_options);
            }

            pub inline fn getNextOffset(this: *Self, subject_slice: []const u8) anyerror!usize {
                return this.unmanaged.getNextOffset(subject_slice);
            }

            pub inline fn fetchResults(this: *Self) anyerror!void {
                this.unmanaged.fetchResults();
            }

            pub inline fn matchAll(this: *Self, subject_slice: []const u8, offset_pos: usize, match_options: u32) anyerror!void {
                this.unmanaged.matchAll(subject_slice, offset_pos, match_options);
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

fn defineRegexUnmanaged(comptime with_pcre: bool) type {
    if (with_pcre) {
        // The RegexUnmanaged is THE struct used for regex matching. It integrates with PCRE2 (if enabled). The regex
        // syntax used is pcre2, can read here: https://pcre2project.github.io/pcre2/doc/html/pcre2pattern.html, or
        // try it here: https://regex101.com/
        return struct {
            const Self = @This();
            const MatchedResultsList = std.SinglyLinkedList([]pcre.RegexMatchResult);
            const MatchedGroupResultsList = std.SinglyLinkedList([]pcre.RegexGroupResult);

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

                maybe_group_results: ?[]pcre.RegexGroupResult,
                cur_pos: usize = 0,
                subject_slice: []const u8,

                pub fn init(regex: *Self, subject: []const u8) MatchedGroupResultIterator {
                    return MatchedGroupResultIterator{
                        .maybe_group_results = regex.getGroupResults(),
                        .subject_slice = subject,
                    };
                }

                pub fn nextResult(this: *MatchedGroupResultIterator) ?Result {
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

            matched_results: []pcre.RegexMatchResult = undefined,
            matched_group_results: []pcre.RegexGroupResult = undefined,

            /// This just means the pcre2 match action has not gone wrong. If want to be sure that there are results,
            /// combine it with `matchSucceed`.
            pub inline fn succeed(this: *const Self) bool {
                // PCRE error code 100 == success
                return this.context_.error_number == 100;
            }

            pub inline fn matchSucceed(this: *const Self) bool {
                return this.context_.rc > 0 or this.total_matched_results > 0;
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
                if (this.total_matched_results > 0) {
                    return this.matched_results;
                } else return null;
            }

            pub inline fn getResultsIterator(this: *Self, subject: []const u8) MatchedResultIterator {
                return MatchedResultIterator.init(this, subject);
            }

            pub inline fn getGroupResults(this: *const Self) ?[]pcre.RegexGroupResult {
                if (this.total_matched_group_results > 0) {
                    return this.matched_group_results;
                } else return null;
            }

            pub inline fn getGroupResultsIterator(this: *Self, subject: []const u8) MatchedGroupResultIterator {
                return MatchedGroupResultIterator.init(this, subject);
            }

            pub fn getGroupResultByIndex(this: *const Self, index: usize) ?pcre.RegexGroupResult {
                if (this.total_matched_group_results > 0) {
                    const c = @as(usize, @intCast(this.context_.matched_group_count));
                    for (this.context_.matched_group_results[0..c]) |gr| {
                        if (gr.index == index) {
                            return gr;
                        }
                    }
                    return null;
                } else return null;
            }

            pub fn getGroupResultByName(this: *const Self, name: []const u8) ?pcre.RegexGroupResult {
                if (this.total_matched_group_results > 0) {
                    const c = @as(usize, @intCast(this.context_.matched_group_count));
                    for (this.context_.matched_group_results[0..c]) |gr| {
                        if (std.mem.eql(u8, gr.name[0..gr.name_len], name)) {
                            return gr;
                        }
                    }
                    return null;
                } else return null;
            }

            pub fn init(allocator: std.mem.Allocator, pattern: []const u8, regex_options: u32) anyerror!Self {
                if (pattern.len == 0) {
                    return JStringError.RegexBadPattern;
                }
                var context_ = try allocator.create(pcre.RegexContext);
                context_.regex_options = regex_options;
                const result = pcre.compile(context_, pattern[0..].ptr);
                if (result == 0) {
                    pcre.get_last_error_message(context_);
                } else {
                    if (context_.matched_group_capacity > 0) {
                        var mgrs = try allocator.alloc(pcre.RegexGroupResult, @as(usize, @intCast(context_.matched_group_capacity)));
                        context_.matched_group_results = mgrs[0..].ptr;
                    }
                }
                return Self{
                    .context_ = context_,
                    .matched_results_list = MatchedResultsList{},
                    .matched_group_results_list = MatchedGroupResultsList{},
                };
            }

            pub fn deinit(this: *Self, allocator: std.mem.Allocator) void {
                defer allocator.destroy(this.context_);
                if (this.total_matched_results > 0) {
                    allocator.free(this.matched_results);
                }
                if (this.total_matched_group_results > 0) {
                    allocator.free(this.matched_group_results);
                }
                if (this.context_.matched_group_capacity > 0) {
                    const c = @as(usize, @intCast(this.context_.matched_group_capacity));
                    allocator.free(this.context_.matched_group_results[0..c]);
                }
                // this must be at last as it will reset context_ from c code
                pcre.free_context(this.context_);
            }

            /// reset regex for next new match. This will only reset matched_results & matched_group_results & free
            /// pcre underlying match object.
            pub fn reset(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                if (this.total_matched_results > 0) {
                    allocator.free(this.matched_results);
                    this.total_matched_results = 0;
                }
                if (this.total_matched_group_results > 0) {
                    allocator.free(this.matched_group_results);
                    this.total_matched_group_results = 0;
                }
                // order is important, must do after free matched_results & matched_group_results
                // as pcre.free_for_next_match will reset them
                pcre.free_for_next_match(this.context_);
            }

            /// if not fetch_results, this.context_.next_offset is not set, need to manually do
            /// `this.getNextOffset(subject)` for it. The regex syntax used is pcre2, can read
            /// here: https://pcre2project.github.io/pcre2/doc/html/pcre2pattern.html, or try it here:
            /// https://regex101.com/
            pub fn match(this: *Self, allocator: std.mem.Allocator, subject_slice: []const u8, offset_pos: usize, fetch_results: bool, match_options: u32) anyerror!void {
                this.context_.match_options = match_options;
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
                    if (this.matchSucceed()) {
                        pcre.get_next_offset(this.context_, subject_slice[0..].ptr, subject_slice.len);
                        return this.context_.next_offset;
                    } else {
                        return this.context_.origin_offset;
                    }
                } else {
                    return JStringError.FetchBeforeMatch;
                }
            }

            /// only for single match fetchResults lazily. For matchAll it will always fetch while match.
            pub fn fetchResults(this: *Self, allocator: std.mem.Allocator) anyerror!void {
                if (this.matchSucceed()) {
                    pcre.fetch_match_results(this.context_);
                    if (this.context_.matched_count > 0) {
                        this.matched_results = try allocator.alloc(pcre.RegexMatchResult, this.context_.matched_count);
                        this.matched_results[0] = this.context_.matched_result;
                        this.total_matched_results = 1;
                    }
                    if (this.context_.matched_group_count > 0) {
                        this.matched_group_results = try allocator.alloc(pcre.RegexGroupResult, this.context_.matched_group_count);
                        for (0..this.context_.matched_group_count) |i| {
                            this.matched_group_results[i] = this.context_.matched_group_results[i];
                        }
                        this.total_matched_group_results = this.context_.matched_group_count;
                    }
                }
            }

            /// matchAll will do `fetchResults` in anyway. The regex syntax used is pcre2, can read
            /// here: https://pcre2project.github.io/pcre2/doc/html/pcre2pattern.html, or try it here:
            /// https://regex101.com/.
            pub fn matchAll(this: *Self, allocator: std.mem.Allocator, subject_slice: []const u8, offset_pos: usize, match_options: u32) anyerror!void {
                this.context_.match_options = match_options;
                var m: i64 = 0;
                var offset: usize = offset_pos;
                var matched_result_count: usize = 0;
                var matched_group_result_count: usize = 0;
                while (offset < subject_slice.len) {
                    m = pcre.match(this.context_, subject_slice[0..].ptr, subject_slice.len, offset);
                    if (m > 0) {
                        try this.fetchResults(allocator);
                        if (this.getResults()) |matched_results| {
                            const n = try allocator.create(MatchedResultsList.Node);
                            n.data = matched_results;
                            this.matched_results_list.prepend(n);
                            matched_result_count += matched_results.len;
                            // set total_matched_results = 0 so later in reset it will not be freed
                            this.total_matched_results = 0;
                        }
                        if (this.getGroupResults()) |group_results| {
                            const n = try allocator.create(MatchedGroupResultsList.Node);
                            n.data = group_results;
                            this.matched_group_results_list.prepend(n);
                            matched_group_result_count += group_results.len;
                            // set total_matched_group_results = 0 so later in reset it will not be freed
                            this.total_matched_group_results = 0;
                        }
                        pcre.get_next_offset(this.context_, subject_slice[0..].ptr, subject_slice.len);
                        offset = this.context_.next_offset;
                        try this.reset(allocator);
                    } else break;
                }

                try this._mergeMatchedResults(allocator, matched_result_count);
                try this._mergeMatchedGroupResults(allocator, matched_group_result_count);
            }

            fn _mergeMatchedResults(this: *Self, allocator: std.mem.Allocator, matched_count: usize) anyerror!void {
                if (this.total_matched_results > 0) {
                    @panic("must not enter this function before reset");
                }
                this.total_matched_results = matched_count;
                if (matched_count == 0) {
                    return;
                } else {
                    var merged_matched_results: []pcre.RegexMatchResult = undefined;
                    merged_matched_results = try allocator.alloc(pcre.RegexMatchResult, matched_count);
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
                    this.matched_results = merged_matched_results;
                }
            }

            fn _mergeMatchedGroupResults(this: *Self, allocator: std.mem.Allocator, matched_group_count: usize) anyerror!void {
                if (this.total_matched_group_results > 0) {
                    @panic("must not enter this function before reset");
                }
                this.total_matched_group_results = matched_group_count;
                if (matched_group_count == 0) {
                    return;
                } else {
                    var merged_matched_group_results: []pcre.RegexGroupResult = undefined;
                    merged_matched_group_results = try allocator.alloc(pcre.RegexGroupResult, matched_group_count);
                    var offset: usize = merged_matched_group_results.len - 1;
                    brk: {
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
                    this.matched_group_results = merged_matched_group_results;
                }
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

// take advantage of both matched results and group matched results are sorted based on start when taking out of pcre,
// do a merge algorithm here
const _MatchedGapIterator = struct {
    const Gap = struct {
        start: usize,
        len: usize,
    };

    it: RegexUnmanaged.MatchedResultIterator,
    it_should_fetch: bool = true,
    group_it: RegexUnmanaged.MatchedGroupResultIterator,
    group_it_should_fetch: bool = true,
    maybe_result: ?RegexUnmanaged.MatchedResultIterator.Result = null,
    maybe_group_result: ?RegexUnmanaged.MatchedGroupResultIterator.Result = null,
    last_start: usize = 0,
    last_len: usize = 0,

    pub fn init(re: *RegexUnmanaged, subject_slice: []const u8) _MatchedGapIterator {
        return _MatchedGapIterator{
            .it = re.getResultsIterator(subject_slice),
            .group_it = re.getGroupResultsIterator(subject_slice),
        };
    }

    pub fn nextGap(this: *_MatchedGapIterator) anyerror!?Gap {
        if (this.it_should_fetch) {
            this.maybe_result = this.it.nextResult();
            this.it_should_fetch = false;
        }
        if (this.group_it_should_fetch) {
            this.maybe_group_result = this.group_it.nextResult();
            this.group_it_should_fetch = false;
        }
        if (this.maybe_result) |r| {
            if (this.maybe_group_result) |gr| {
                if (r.start <= gr.start) {
                    return this._nextGapFromIt(r);
                } else {
                    return this._nextGapFromGroupIt(gr);
                }
            } else {
                return this._nextGapFromIt(r);
            }
        }
        if (this.maybe_group_result) |gr| {
            // this.maybe_result must be null if we reach here, no need to check it
            return this._nextGapFromGroupIt(gr);
        }
        return null;
    }

    fn _nextGapFromIt(this: *_MatchedGapIterator, r: RegexUnmanaged.MatchedResultIterator.Result) anyerror!?Gap {
        this.it_should_fetch = true;
        if (this.last_start == r.start and this.last_len == r.len) {
            // can never reach here because we can reach here either
            // 1. in front other other group result
            // 2. or when move to next single match result
            //
            // for case 2, impossible to meet the condition, as match results will not overlap, and next match
            //   result will never overlap last match's group result
            // for case 1, impossible too, because either this is first match result, or we just move from last
            //   match, so reduce to case 2
            //
            // return this.nextGap();
            unreachable;
        } else if (this.last_start + this.last_len > r.start) {
            // see above, this is impossible too.
            //
            // return JStringError.RegexMatchOverlapped;
            unreachable;
        } else {
            this.last_start = r.start;
            this.last_len = r.len;
            return Gap{
                .start = r.start,
                .len = r.len,
            };
        }
    }

    fn _nextGapFromGroupIt(this: *_MatchedGapIterator, gr: RegexUnmanaged.MatchedGroupResultIterator.Result) anyerror!?Gap {
        this.group_it_should_fetch = true;
        if (this.last_start == gr.start and this.last_len == gr.len) {
            return this.nextGap();
        } else if (this.last_start + this.last_len > gr.start) {
            return JStringError.RegexMatchOverlapped;
        } else {
            // originally I wrote down:
            //
            // this.last_start = gr.start;
            // this.last_len = gr.len;
            // return Gap{
            //     .start = gr.start,
            //     .len = gr.len,
            // };
            //
            // but this can never happen, because if we reach here, means we find a group result outside of
            // 1. all match results
            // 2. all other group results
            // where 2. be always true (as groups are not overlapping), but for 1., at least one match result must
            // cover our group (as how pcre works). So, we can never reach here.
            //
            unreachable;
        }
    }
};

/// very unsafe, you have been warned to know what you are doing
fn _sliceAt(comptime T: type, haystack: []const T, index: isize) T {
    if (index >= 0) {
        return haystack[@as(usize, @intCast(index))];
    } else {
        return haystack[@as(usize, @intCast(@as(isize, @intCast(haystack.len)) + index))];
    }
}

fn _kmpBuildFailureTable(allocator: std.mem.Allocator, needle_slice: []const u8) anyerror![]isize {
    const t = try allocator.alloc(isize, (needle_slice.len + 1));
    @memset(t, 0);

    var j: isize = 0;
    for (1..needle_slice.len) |i| {
        j = _sliceAt(isize, t, @as(isize, @intCast(i)));
        while (j > 0 and _sliceAt(u8, needle_slice, @as(isize, @intCast(i))) != _sliceAt(u8, needle_slice, j)) {
            j = _sliceAt(isize, t, j);
        }
        if (j > 0 or _sliceAt(u8, needle_slice, @as(isize, @intCast(i))) == _sliceAt(u8, needle_slice, j)) {
            t[i + 1] = j + 1;
        }
    }

    return t;
}

fn _testCreateErrorUnion(value_or_error: bool, comptime T: type, value: T, err: anyerror) anyerror!T {
    return if (value_or_error) value else err;
}

fn _testIsError(comptime T: type, maybe_value: anyerror!T, expected_error: anyerror) bool {
    if (maybe_value) |_| {
        return false;
    } else |err| {
        return err == expected_error;
    }
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
    {
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
        const str6 = try JStringUnmanaged.newFromNumber(arena.allocator(), i32, -5);
        try testing.expect(str6.eqlSlice("-5"));
        const str7 = try JStringUnmanaged.newFromNumber(arena.allocator(), f32, -5.5);
        try testing.expect(str7.eqlSlice("-5.5"));
        const TestType = struct { a: i32, b: []const u8 };
        const str8 = try JStringUnmanaged.newFromStringify(arena.allocator(), TestType{ .a = 123, .b = "xy" });
        try testing.expect(str8.eqlSlice("{\"a\":123,\"b\":\"xy\"}"));
        const str9 = try JStringUnmanaged.newFromStringifyWithOptions(arena.allocator(), TestType{ .a = 123, .b = "xy" }, .{ .whitespace = .indent_2 });
        const str9value =
            \\{
            \\  "a": 123,
            \\  "b": "xy"
            \\}
        ;
        try testing.expect(str9.eqlSlice(str9value));
    }
    {
        var tmp_dir = std.testing.tmpDir(.{});
        defer tmp_dir.cleanup();
        var tmp_file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
        try tmp_file.writeAll("hello,world");
        try tmp_file.seekTo(0);
        const str10 = try JStringUnmanaged.newFromFile(arena.allocator(), tmp_file);
        try testing.expect(str10.eqlSlice("hello,world"));
        // now file is at the end, so read again should give us 0 len slice
        const str11 = try JStringUnmanaged.newFromFile(arena.allocator(), tmp_file);
        try testing.expect(str11.eqlSlice(""));
    }
}

test "formatter" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    const s = try std.fmt.allocPrint(arena.allocator(), "{}", .{str1});
    try testing.expectEqualSlices(u8, s, "hello,world");
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
        try testing.expect(str2.eql(str3));
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
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), " zig 更好 \t 的c\t💯");
        var wyhash = std.hash.Wyhash.init(0);
        wyhash.update(" zig 更好 \t 的c\t💯");
        const h = wyhash.final();
        try testing.expectEqual(str1.hash(), h);
    }
}

test "concat" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    var str_array_buf: [256]JStringUnmanaged = undefined;
    str_array_buf[0] = str1;
    const str2 = try str1.concatMany(arena.allocator(), str_array_buf[0..1]);
    try testing.expect(str1.eqlSlice("hello,world" ** 1));
    try testing.expect(str2.eqlSlice("hello,world" ** 2));
    str_array_buf[1] = str2;
    const str3 = try str1.concatMany(arena.allocator(), str_array_buf[0..2]);
    try testing.expect(str3.eqlSlice("hello,world" ** 4));
    const str4 = try str1.concatMany(arena.allocator(), str_array_buf[0..0]);
    try testing.expect(str4.eqlSlice("hello,world"));
    try testing.expect(str4.str_slice.ptr != str1.str_slice.ptr);
    const str5 = try str1.concatFormat(arena.allocator(), "{s}", .{" jstring"});
    try testing.expect(str5.eqlSlice("hello,world jstring"));
    const optional_6: ?i32 = 6;
    const error1 = _testCreateErrorUnion(false, i32, 0, error.OutOfMemory);
    const str6 = try str1.concatTuple(arena.allocator(), .{
        " jstring",
        5,
        optional_6,
        error1,
    });
    try testing.expect(str6.eqlSlice("hello,world jstring56error.OutOfMemory"));
    const str7 = try str1.concat(arena.allocator(), str1);
    try testing.expect(str7.eqlSlice("hello,worldhello,world"));
    const str8 = try str1.concatSlice(arena.allocator(), "hello");
    try testing.expect(str8.eqlSlice("hello,worldhello"));
    var some_slices: [1][]const u8 = undefined;
    some_slices[0] = "hello";
    const str9 = try str1.concatManySlices(arena.allocator(), &some_slices);
    try testing.expect(str9.eqlSlice("hello,worldhello"));
    const str10 = try str1.concatSlice(arena.allocator(), "");
    try testing.expect(str10.eqlSlice("hello,world"));
    const str11 = try str1.concatManySlices(arena.allocator(), some_slices[0..0]);
    try testing.expect(str11.eqlSlice("hello,world"));
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
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "  ");
        var str2 = try str1.trim(arena.allocator());
        try testing.expect(str2.isEmpty());
    }
}

test "chartAt/at" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
        const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "abcdefg");
        try testing.expect(_testIsError(u8, str1.charAt(100), error.IndexOutOfBounds));
        try testing.expectEqual(str2.charAt(0), 'a');
        try testing.expectEqual(str2.charAt(2), 'c');
        try testing.expectEqual(str2.charAt(-3), 'e');
        try testing.expectEqual(str2.charAt(-7), 'a');
        try testing.expect(_testIsError(u8, str2.charAt(-100), error.IndexOutOfBounds));
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "zig更好的c💯");
        try testing.expectEqual(str1.at(0), 'z');
        try testing.expectEqual(str1.at(3), '更');
        try testing.expectEqual(str1.at(-1), '💯');
        try testing.expectEqual(str1.at(-8), 'z');
        try testing.expect(_testIsError(u21, str1.at(100), error.IndexOutOfBounds));
        try testing.expect(_testIsError(u21, str1.at(-100), error.IndexOutOfBounds));
    }
    {}
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
        const str4 = try str1.padStart(arena.allocator(), 4, "welcome");
        try testing.expect(str4.eqlSlice("hello"));
    }
    {
        const str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
        const str2 = try str1.padEnd(arena.allocator(), 10, "world");
        try testing.expect(str2.eqlSlice("helloworld"));
        const str3 = try str1.padEnd(arena.allocator(), 13, "world");
        try testing.expect(str3.eqlSlice("helloworldwor"));
        const str4 = try str1.padEnd(arena.allocator(), 4, "welcome");
        try testing.expect(str4.eqlSlice("hello"));
    }
    {
        // zig💯 = 0x7a 0x69 0x67 0xf0 0x9f 0x92 0xaf, 7 bytes
        const raw_bytes = "zig💯";
        const wrong_raw_bytes = raw_bytes[0..6]; // now this is corrupted unicode string
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), wrong_raw_bytes);
        try testing.expect(_testIsError(u21, str1.at(4), error.InvalidUtf8));
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
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "hello", 20), -1);
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "hello", 24), -1);
    }
    {
        // TODO: more kmp test cases
        const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "GATCCATATG");
        try testing.expectEqual(str2.fastIndexOf(arena.allocator(), "ATAT", 0), 5);
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
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "");
        var str2 = try str1.toUpperCase(arena.allocator());
        try testing.expect(str2.isEmpty());
        str2 = try str1.toLowerCase(arena.allocator());
        try testing.expect(str2.isEmpty());
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
        try testing.expectEqual(strings3.len, 15);
        try testing.expect(strings3[0].eqlSlice("\t"));
        try testing.expect(strings3[7].eqlSlice("💯"));
        try testing.expect(strings3[13].eqlSlice("d"));
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
        var strings = try str1.split(arena.allocator(), "", -1);
        try testing.expectEqual(strings.len, 5);
        try testing.expect(strings[0].eqlSlice("h"));
        try testing.expect(strings[1].eqlSlice("e"));
        try testing.expect(strings[2].eqlSlice("l"));
        try testing.expect(strings[3].eqlSlice("l"));
        try testing.expect(strings[4].eqlSlice("o"));
        strings = try str1.split(arena.allocator(), "", 3);
        try testing.expectEqual(strings.len, 3);
        try testing.expect(strings[0].eqlSlice("h"));
        try testing.expect(strings[1].eqlSlice("e"));
        try testing.expect(strings[2].eqlSlice("l"));
        strings = try str1.split(arena.allocator(), "", 0);
        try testing.expectEqual(strings.len, 0);
    }
}

test "RegexUnmanged" {
    if (enable_pcre) {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        {
            const re = RegexUnmanaged.init(arena.allocator(), "", 0);
            try testing.expect(_testIsError(RegexUnmanaged, re, JStringError.RegexBadPattern));
        }
        {
            const re = try RegexUnmanaged.init(arena.allocator(), "(hello", 0);
            try testing.expect(!re.succeed());
            try testing.expectEqual(re.errorNumber(), 114);
            try testing.expectEqual(re.errorOffset(), 6);
            try testing.expectEqualSlices(u8, re.errorMessage(), "PCRE2 compilation failed at offset 6: missing closing parenthesis\n");
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "hel+o", 0);
            try re.match(arena.allocator(), "hello,hello,world", 0, true, 0);
            re.deinit(arena.allocator());
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(?<H>hel+o)", 0);
            try re.matchAll(arena.allocator(), "hello,hello,world", 0, 0);
            re.deinit(arena.allocator());
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "hel+o", 0);
            try testing.expectEqual(re.errorNumber(), 100);
            try re.match(arena.allocator(), "hello,hello,world", 0, true, 0);
            try testing.expect(re.matchSucceed());
            const matched_results = re.getResults();
            try testing.expect(matched_results != null);
            if (matched_results) |mr| {
                try testing.expect(mr[0].start == 0);
                try testing.expect(mr[0].len == 5);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "hel+o", 0);
            try testing.expectEqual(re.errorNumber(), 100);
            try re.matchAll(arena.allocator(), "hello,hello,world", 0, 0);
            try testing.expect(re.matchSucceed());
            const matched_results = re.getResults();
            try testing.expect(matched_results != null);
            if (matched_results) |mr| {
                try testing.expect(mr.len == 2);
                try testing.expect(mr[0].start == 0);
                try testing.expect(mr[0].len == 5);
                try testing.expect(mr[1].start == 6);
                try testing.expect(mr[1].len == 5);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(?<h>hel+o)", 0);
            try testing.expectEqual(re.errorNumber(), 100);
            try re.matchAll(arena.allocator(), "hello,hello,world", 0, 0);
            try testing.expect(re.matchSucceed());
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
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(?<h>hel+o)", 0);
            try re.matchAll(arena.allocator(), "hello,hello,world", 0, 0);
            re.deinit(arena.allocator());
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(hi,)(?<h>hel+o?)", 0);
            try re.match(arena.allocator(), "hi,hello", 0, true, 0);
            const match_results = re.getResults();
            const group_results = re.getGroupResults();
            _ = group_results;
            if (match_results) |mrs| {
                try testing.expectEqual(mrs[0].start, 0);
                try testing.expectEqual(mrs[0].len, 8);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(hi,)(?<h>hel+o?)", 0);
            try re.match(arena.allocator(), "hi,hello", 0, true, 0);
            try re.reset(arena.allocator());
            try re.match(arena.allocator(), "hi,hello", 0, true, 0);
            const match_results = re.getResults();
            const group_results = re.getGroupResults();
            _ = group_results;
            if (match_results) |mrs| {
                try testing.expectEqual(mrs[0].start, 0);
                try testing.expectEqual(mrs[0].len, 8);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(hi,)(?<h>hel+o?)", 0);
            try re.matchAll(arena.allocator(), "hi,hello,hi,hello", 0, 0);
            const match_results = re.getResults();
            const group_results = re.getGroupResults();
            if (match_results) |mrs| {
                try testing.expectEqual(mrs[0].start, 0);
                try testing.expectEqual(mrs[0].len, 8);
                try testing.expectEqual(mrs[1].start, 9);
                try testing.expectEqual(mrs[1].len, 8);
            }
            if (group_results) |grs| {
                try testing.expectEqual(grs[0].start, 0);
                try testing.expectEqual(grs[0].len, 3);
                try testing.expectEqual(grs[1].start, 3);
                try testing.expectEqual(grs[1].len, 5);
                try testing.expectEqual(grs[2].start, 9);
                try testing.expectEqual(grs[2].len, 3);
                try testing.expectEqual(grs[3].start, 12);
                try testing.expectEqual(grs[3].len, 5);
            }
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "(hi,)(?<h>hel+o?)", 0);
            try re.reset(arena.allocator()); // this should works find without error
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
            const maybe_result = it.nextResult();
            if (maybe_result) |r| {
                try testing.expectEqual(r.start, 0);
                try testing.expectEqual(r.len, 5);
                try testing.expectEqualSlices(u8, r.value, "hello");
            }
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            var re = try str1.matchAll(arena.allocator(), "hel+o", 0, RegexUnmanaged.DefaultRegexOptions, RegexUnmanaged.DefaultMatchOptions);
            try testing.expect(re.succeed());
            var it = re.getResultsIterator(str1.str_slice);
            const maybe_result = it.nextResult();
            if (maybe_result) |r| {
                try testing.expectEqual(r.start, 0);
                try testing.expectEqual(r.len, 5);
                try testing.expectEqualSlices(u8, r.value, "hello");
            }
            const maybe_result2 = it.nextResult();
            if (maybe_result2) |r| {
                try testing.expectEqual(r.start, 6);
                try testing.expectEqual(r.len, 5);
                try testing.expectEqualSlices(u8, r.value, "hello");
            }
            const maybe_result3 = it.nextResult();
            try testing.expectEqual(maybe_result3, null);
        }
    }
}

test "searchByRegex" {
    if (enable_pcre) {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            var r = try str1.searchByRegex(arena.allocator(), "hel+o", 0);
            try testing.expectEqual(r, 0);
            r = try str1.searchByRegex(arena.allocator(), "hel+o", 3);
            try testing.expectEqual(r, 6);
            r = try str1.searchByRegex(arena.allocator(), "hel+o", 8);
            try testing.expectEqual(r, -1);
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            const r = try str1.searchByRegex(arena.allocator(), "nonexist", 0);
            try testing.expectEqual(r, -1);
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            try testing.expect(_testIsError(isize, str1.searchByRegex(arena.allocator(), "he(?<L>l+", 0), JStringError.RegexMatchFailed));
        }
    }
}

test "splitByRegex" {
    if (enable_pcre) {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            var results = try str1.splitByRegex(arena.allocator(), "l+", 0, 0);
            try testing.expectEqual(results.len, 1);
            try testing.expect(results[0].eqlSlice("hello,hello,world"));
            results = try str1.splitByRegex(arena.allocator(), "l+", 0, -1);
            try testing.expectEqual(results.len, 4);
            try testing.expect(results[0].eqlSlice("he"));
            try testing.expect(results[1].eqlSlice("o,he"));
            try testing.expect(results[2].eqlSlice("o,wor"));
            try testing.expect(results[3].eqlSlice("d"));
            results = try str1.splitByRegex(arena.allocator(), "he", 0, -1);
            try testing.expectEqual(results.len, 3);
            try testing.expect(results[0].eqlSlice(""));
            try testing.expect(results[1].eqlSlice("llo,"));
            try testing.expect(results[2].eqlSlice("llo,world"));
            results = try str1.splitByRegex(arena.allocator(), "lo|d", 0, -1);
            try testing.expectEqual(results.len, 3);
            try testing.expect(results[0].eqlSlice("hel"));
            try testing.expect(results[1].eqlSlice(",hel"));
            try testing.expect(results[2].eqlSlice(",worl"));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            var results = try str1.splitByRegex(arena.allocator(), "(?<L>l+)", 0, -1);
            try testing.expectEqual(results.len, 4);
            try testing.expect(results[0].eqlSlice("he"));
            try testing.expect(results[1].eqlSlice("o,he"));
            try testing.expect(results[2].eqlSlice("o,wor"));
            try testing.expect(results[3].eqlSlice("d"));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            const r = str1.splitByRegex(arena.allocator(), "he(?<L>l+)", 0, -1);
            try testing.expect(_testIsError([]JStringUnmanaged, r, JStringError.RegexMatchOverlapped));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            // stupid way of splitting every char into string, but should work
            const results = try str1.splitByRegex(arena.allocator(), ".", 0, -1);
            try testing.expectEqual(results.len, 6);
            try testing.expect(results[0].eqlSlice(""));
            try testing.expect(results[1].eqlSlice(""));
            try testing.expect(results[2].eqlSlice(""));
            try testing.expect(results[3].eqlSlice(""));
            try testing.expect(results[4].eqlSlice(""));
            try testing.expect(results[5].eqlSlice(""));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hhoh");
            var results = try str1.splitByRegex(arena.allocator(), "h", 0, -1);
            try testing.expectEqual(results.len, 4);
            try testing.expect(results[0].eqlSlice(""));
            try testing.expect(results[1].eqlSlice(""));
            try testing.expect(results[2].eqlSlice("o"));
            try testing.expect(results[3].eqlSlice(""));
            results = try str1.splitByRegex(arena.allocator(), "h", 0, 2);
            try testing.expectEqual(results.len, 2);
            try testing.expect(results[0].eqlSlice(""));
            try testing.expect(results[1].eqlSlice(""));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            const results = str1.splitByRegex(arena.allocator(), "", 0, -1);
            try testing.expect(_testIsError([]JStringUnmanaged, results, JStringError.RegexBadPattern));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            const results = str1.splitByRegex(arena.allocator(), "noexist", 0, -1);
            try testing.expect(_testIsError([]JStringUnmanaged, results, JStringError.RegexMatchFailed));
        }
    }
}

test "replace/replaceAll/replaceByRegex/replaceAllByRegex" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
        var str2 = try str1.replace(arena.allocator(), "world", "jstring");
        try testing.expect(str2.eqlSlice("hello,hello,jstring"));
        str2 = try str1.replaceAll(arena.allocator(), "hello", "jstring");
        try testing.expect(str2.eqlSlice("jstring,jstring,world"));
        str2 = try str1.replace(arena.allocator(), "noexist", "jstring");
        try testing.expect(str2.eqlSlice("hello,hello,world"));
    }
    if (enable_pcre) {
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            var str2 = try str1.replaceByRegex(arena.allocator(), "wor.d", "jstring");
            try testing.expect(str2.eqlSlice("hello,hello,jstring"));
            str2 = try str1.replaceAllByRegex(arena.allocator(), "hel+o", "jstring");
            try testing.expect(str2.eqlSlice("jstring,jstring,world"));
            const r = str1.replaceByRegex(arena.allocator(), "noexiststring", "jstring");
            try testing.expect(_testIsError(JStringUnmanaged, r, JStringError.RegexMatchFailed));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            const str2 = try str1.replaceAllByRegex(arena.allocator(), "(?<L>l+)", "L");
            try testing.expect(str2.eqlSlice("heLo,heLo,worLd"));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
            const r = str1.replaceAllByRegex(arena.allocator(), "he(?<L>l+)", "");
            try testing.expect(_testIsError(JStringUnmanaged, r, JStringError.RegexMatchOverlapped));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            const r = str1.replaceAllByRegex(arena.allocator(), "", "L");
            try testing.expect(_testIsError(JStringUnmanaged, r, JStringError.RegexBadPattern));
            try testing.expect(_testIsError(JStringUnmanaged, r, JStringError.RegexBadPattern));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            const r = str1.replaceByRegex(arena.allocator(), "helloworld", "");
            try testing.expect(_testIsError(JStringUnmanaged, r, JStringError.RegexMatchFailed));
        }
        {
            var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello");
            try testing.expect(_testIsError(JStringUnmanaged, str1.replaceAllByRegex(arena.allocator(), "he(?<L>l+", ""), JStringError.RegexMatchFailed));
        }
    }
}

test "freeJStringArray/freeJStringUnmanagedArray" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello\nhello\nhello\n");
        const strs = try str1.split(arena.allocator(), "\n", -1);
        freeJStringUnmanagedArray(arena.allocator(), strs);
    }
    {
        var str1 = try JString.newFromSlice(arena.allocator(), "hello\nhello\nhello\n");
        const strs = try str1.split("\n", -1);
        freeJStringArray(strs);
    }
}

test "JString/Regex" {
    // briefly test managed version, to make sure that they follow the the spec designed. Majority functions are tested in unmanaged version.
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JString.newEmpty(arena.allocator());
        const str2 = try JString.newFromSlice(arena.allocator(), "hello,💯world");
        str1 = try str1.repeat(5);
        var jstrings: [1]JString = undefined;
        jstrings[0] = str2;
        var str3 = try str1.concatMany(jstrings[0..1]);
        try testing.expect(str3.eqlSlice("hello,💯world"));
        str3 = try str1.concatMany(jstrings[0..0]);
        try testing.expect(str3.eqlSlice(""));
        str3 = try str1.concat(str2);
        try testing.expect(str3.eqlSlice("hello,💯world"));
        str3 = try str2.clone();
        try testing.expect(str3.eqlSlice("hello,💯world"));
        try testing.expect(!str3.isEmpty());
        try testing.expect(str3.eql(str2));
    }
}

test "forbidden city" {
    // tests listed here are those necessary to better coverage but not supposed to be used if not developing this lib
    // just remember that: in practice if you call this you will be fired (not me), or they are tested here does not
    // mean you should use it.
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
        const gaps = try arena.allocator().alloc(_MatchedGapIterator.Gap, 0);
        const str2 = try str1._joinGapsWithSlice(arena.allocator(), gaps, "");
        try testing.expect(str2.eqlSlice("hello,hello,world"));
    }
    {
        try testing.expectEqual(_sliceAt(u8, "hello", -1), 'o');
        try testing.expect(!_testIsError(u8, 'h', JStringError.RegexMatchFailed));
    }
    {
        var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello 💯world");
        const strs = try str1._splitToUtf8Chars(arena.allocator(), 999, false);
        defer freeJStringUnmanagedArray(arena.allocator(), strs);
        try testing.expectEqual(strs.len, 11);
        try testing.expect(strs[5].eqlSlice("💯"));
    }
    if (enable_pcre) {
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "pattern", 0);
            var it = re.getResultsIterator("something");
            _ = &it;
            try testing.expectEqual(it.nextResult(), null);
        }
        {
            var re = try RegexUnmanaged.init(arena.allocator(), "pattern", 0);
            _ = &re;
            pcre.fetch_match_results(re.context_); // no panic means passed
            const str = "hello";
            pcre.get_next_offset(re.context_, str[0..].ptr, str.len);
        }
        {
            var context_ = try arena.allocator().create(pcre.RegexContext);
            context_.re = std.mem.zeroes(?*anyopaque);
            var re = RegexUnmanaged{ .context_ = context_ };
            _ = &re;
            const str = "hello";
            _ = pcre.match(re.context_, str[0..].ptr, str.len, 0); // no panic means passed
        }
    }
}
