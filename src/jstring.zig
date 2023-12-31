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

    // eql functions

    pub inline fn eqlSlice(this: *const JStringUnmanaged, string_slice: []const u8) bool {
        return std.mem.eql(u8, this.slice, string_slice);
    }

    pub inline fn eqlJStringUmanaged(this: *const JStringUnmanaged, that: JStringUnmanaged) bool {
        return std.mem.eql(u8, this.slice, that.slice);
    }
};

// >>> all your tests belong to me and list in belowing <<<

test "newFromXXX" {
    var arena = JStringArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
    try testing.expectEqual(str1.len, 0);
    const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    try testing.expectEqual(str2.len, 11);
    const str3 = try JStringUnmanaged.newFromJStringUnmanaged(arena.allocator(), str2);
    try testing.expectEqual(str3.len, 11);
}

test "eqlXXX" {
    var arena = JStringArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const str1 = try JStringUnmanaged.newEmpty(arena.allocator());
    const str2 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,world");
    const str3 = try JStringUnmanaged.newFromJStringUnmanaged(arena.allocator(), str2);
    try testing.expect(str1.eqlSlice(""));
    try testing.expect(str2.eqlJStringUmanaged(str3));
    try testing.expect(str3.eqlSlice("hello,world"));
}
