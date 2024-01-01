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
    slice: []const u8,
    len: usize,

    pub fn deinit(this: *const JStringUnmanaged, allocator: std.mem.Allocator) void {
        allocator.free(this.slice);
    }

    // constructors

    pub fn newEmpty(allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        const slice = try allocator.alloc(u8, 0);
        return JStringUnmanaged{
            .slice = slice,
            .len = 0,
        };
    }

    pub fn newFromSlice(allocator: std.mem.Allocator, string_slice: []const u8) anyerror!JStringUnmanaged {
        const slice = try allocator.alloc(u8, string_slice.len);
        @memcpy(slice, string_slice);
        return JStringUnmanaged{
            .slice = slice,
            .len = string_slice.len,
        };
    }

    pub fn newFromJStringUnmanaged(allocator: std.mem.Allocator, that: JStringUnmanaged) anyerror!JStringUnmanaged {
        const slice = try allocator.alloc(u8, that.len);
        @memcpy(slice, that.slice);
        return JStringUnmanaged{
            .slice = slice,
            .len = that.len,
        };
    }

    pub fn newFromFormat(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) anyerror!JStringUnmanaged {
        const slice = try std.fmt.allocPrint(allocator, fmt, args);
        return JStringUnmanaged{
            .slice = slice,
            .len = slice.len,
        };
    }

    // utils

    pub inline fn clone(this: *const JStringUnmanaged, allocator: std.mem.Allocator) anyerror!JStringUnmanaged {
        return JStringUnmanaged.newFromJStringUnmanaged(allocator, this.*);
    }

    pub inline fn isEmpty(this: *const JStringUnmanaged) bool {
        return this.len == 0;
    }

    pub inline fn eqlSlice(this: *const JStringUnmanaged, string_slice: []const u8) bool {
        return std.mem.eql(u8, this.slice, string_slice);
    }

    pub inline fn eqlJStringUmanaged(this: *const JStringUnmanaged, that: JStringUnmanaged) bool {
        return std.mem.eql(u8, this.slice, that.slice);
    }

    // methods as listed at https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String

    // TODO iterator
    // TODO at
    // TODO charAt
    // TODO charCodeAt
    // TODO codePointAt

    // ** concat

    /// Concat jstrings in rest_jstrings in order, return a new allocated jstring.
    /// If rest_jstrings.len == 0, will return a copy of this jstring
    pub fn concat(this: *const JStringUnmanaged, allocator: std.mem.Allocator, rest_jstrings: []const JStringUnmanaged) anyerror!JStringUnmanaged {
        if (rest_jstrings.len == 0) {
            return this.clone(allocator);
        } else {
            var rest_sum_len: usize = 0;
            const new_len = this.len + lenbrk: {
                for (rest_jstrings) |jstring| {
                    rest_sum_len += jstring.len;
                }
                break :lenbrk rest_sum_len;
            };

            const new_slice = try allocator.alloc(u8, new_len);
            var new_slice_ptr = new_slice.ptr;
            @memcpy(new_slice_ptr, this.slice);
            new_slice_ptr += this.slice.len;
            for (rest_jstrings) |jstring| {
                @memcpy(new_slice_ptr, jstring.slice);
                new_slice_ptr += jstring.len;
            }
            return JStringUnmanaged{
                .slice = new_slice,
                .len = new_len,
            };
        }
    }

    /// Concat jstrings by format with fmt & .{ data }. It is a shortcut for first creating tmp str from
    /// JStringUnmanaged.newFromFormat then second this.concat(tmp str). (or below psudeo code)
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

        comptime var fmt_buf: [24 * 32]u8 = undefined;
        _ = &fmt_buf;
        comptime var fmt_len: usize = 0;
        comptime {
            var fmt_print_slice: []u8 = fmt_buf[0..];
            var printed_fmt: []u8 = undefined;
            for (fields_info) |field_info| {
                switch (@typeInfo(field_info.type)) {
                    .Array => {
                        printed_fmt = try std.fmt.bufPrint(fmt_print_slice, "{{any}}", .{});
                        fmt_len += printed_fmt.len;
                        fmt_print_slice = fmt_buf[fmt_len..];
                    },
                    .Pointer => |ptr_info| switch (ptr_info.size) {
                        .One, .Many, .C => {
                            printed_fmt = try std.fmt.bufPrint(fmt_print_slice, "{{s}}", .{});
                            fmt_len += printed_fmt.len;
                            fmt_print_slice = fmt_buf[fmt_len..];
                        },
                        .Slice => {
                            printed_fmt = try std.fmt.bufPrint(fmt_print_slice, "{{any}}", .{});
                            fmt_len += printed_fmt.len;
                            fmt_print_slice = fmt_buf[fmt_len..];
                        },
                    },
                    .Optional => {
                        @compileError("not support Optional!");
                    },
                    .ErrorUnion => {
                        @compileError("not support ErrorUnion!");
                    },
                    else => {
                        printed_fmt = try std.fmt.bufPrint(fmt_print_slice, "{{}}", .{});
                        fmt_len += printed_fmt.len;
                        fmt_print_slice = fmt_buf[fmt_len..];
                    },
                }
            }
        }
        return this.concatFormat(allocator, fmt_buf[0..fmt_len], rest_items);
    }

    // ** endsWith

    pub inline fn endsWith(this: *const JStringUnmanaged, suffix: JStringUnmanaged) bool {
        return this.endsWithSlice(suffix.slice);
    }

    pub fn endsWithSlice(this: *const JStringUnmanaged, suffix_slice: []const u8) bool {
        if (this.len < suffix_slice.len) {
            return false;
        }
        return std.mem.eql(u8, this.slice[this.slice.len - suffix_slice.len ..], suffix_slice);
    }

    // TODO fromCharCode
    // TODO fromCodePoint
    // TODO includes
    // TODO indexOf
    // TODO isWellFormed
    // TODO lastIndexOf
    // TODO localeCompare
    // TODO match
    // TODO matchAll
    // TODO normalize
    // TODO padEnd
    // TODO padStart
    // TODO raw
    // TODO repeat
    // TODO replace
    // TODO search
    // TODO slice
    // TODO split

    // ** startsWith

    pub inline fn startsWith(this: *const JStringUnmanaged, prefix: JStringUnmanaged) bool {
        return this.startsWithSlice(prefix.slice);
    }

    pub fn startsWithSlice(this: *const JStringUnmanaged, prefix_slice: []const u8) bool {
        if (this.len < prefix_slice.len) {
            return false;
        }
        return std.mem.eql(u8, this.slice[0..prefix_slice.len], prefix_slice);
    }

    // TODO toLocaleLowerCase
    // TODO toLocaleUpperCase
    // TODO toLowerCase
    // TODO toUpperCase
    // TODO toWellFormed
    // TODO trim
    // TODO trimEnd
    // TODO trimStart
    // TODO valueOf
};

// >>> all your tests belong to me and list in belowing <<<

test "constructors" {
    var arena = JStringArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
    try testing.expectEqual(str1.len, 0);
    const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    try testing.expectEqual(str2.len, 11);
    const str3 = try JStringUnmanaged.newFromJStringUnmanaged(arena.allocator(), str2);
    try testing.expectEqual(str3.len, 11);
    const str4 = try JStringUnmanaged.newFromFormat(arena.allocator(), "{s}", .{"jstring"});
    try testing.expectEqual(str4.len, 7);
}

test "utils" {
    var arena = JStringArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
    const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    const str3 = try JStringUnmanaged.newFromJStringUnmanaged(arena.allocator(), str2);
    try testing.expect(str1.eqlSlice(""));
    try testing.expect(str1.isEmpty());
    try testing.expect(str2.eqlJStringUmanaged(str3));
    try testing.expect(str3.eqlSlice("hello,world"));
    const str4 = try str3.clone(arena.allocator());
    try testing.expect(str4.eqlSlice("hello,world"));
    try testing.expect(str3.slice.ptr != str4.slice.ptr);
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
    try testing.expect(str4.slice.ptr != str1.slice.ptr);
    const str5 = try str1.concatFormat(arena.allocator(), "{s}", .{" jstring"});
    try testing.expect(str5.eqlSlice("hello,world jstring"));
    const str6 = try str1.concatTuple(arena.allocator(), .{ " jstring", 5 });
    // std.debug.print("\n{s}\n", .{str6.slice});
    try testing.expect(str6.eqlSlice("hello,world jstring5"));
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
