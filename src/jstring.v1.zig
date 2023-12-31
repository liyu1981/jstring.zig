const std = @import("std");
const testing = std.testing;

// target: create a reusable string lib for myself with
//   1. CPU cache efficiency considered (use the technique in bunjs)
//   2. all familiar methods can find in javascript string:
//        https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String

// rules
//   str is created with creator, creator governs memory allocation
//   str can deinit itself, storage then will reuse its memory
//   str is immutable, mutation will return new str
//   when storage changes its own memory layouts, str will not lose its access
//   storage will ensure continous memory layout so it is cache optimised
//   storage will ensure most time strs are continuously layouted too

const INIT_CAPACITY = std.mem.page_size;
const MAX_CAPACITY_INCREMENT = 512 * std.mem.page_size;

const Storage = struct {
    pub const Fragment = struct {
        id: u64,
        start: u64,
        end: u64,
    };
    const StrMap = std.AutoArrayHashMapUnmanaged(u64, Storage.Fragment);

    allocator: std.mem.Allocator = undefined,
    str_map: Storage.StrMap,
    mem: []u8,
    next_id: u64 = 1, // 0 is reserved for empty string
    capacity: u64 = 0,
    used: u64 = 0,

    // we store every string in our storage in 0-sentitial format

    pub fn init(allocator: std.mem.Allocator, init_capacity: u64) Storage {
        const allocated = allocator.alignedAlloc(u8, null, init_capacity) catch unreachable;

        // set the first byte to be zero, so that later all empty string can point to beginning of mem
        allocated[0] = 0;

        return Storage{
            .allocator = allocator,
            .str_map = Storage.StrMap{},
            .mem = allocated,
            .capacity = init_capacity,
            .used = 1, // used = 1 because of the first byte reserved for all empty JString
        };
    }

    pub fn deinit(this: *const Storage) void {
        const self = @constCast(this);
        self.str_map.deinit(this.allocator);
        self.allocator.free(this.mem);
    }

    pub fn getSlice(this: *Storage, str_id: u64) []const u8 {
        if (str_id == 0) {
            return this.mem[0..1];
        } else {
            if (this.str_map.get(str_id)) |fragment| {
                return this.mem[fragment.start..fragment.end];
            } else unreachable;
        }
    }

    fn calculateIncrementNeeded(target_size: u64, init_size: u64, init_next_increment: u64) u64 {
        var sum_size = init_size;
        var next_increment = init_next_increment;
        while (sum_size < target_size) {
            sum_size += next_increment;
            next_increment = if (next_increment * 2 < MAX_CAPACITY_INCREMENT) next_increment * 2 else MAX_CAPACITY_INCREMENT;
            if (sum_size >= target_size) {
                break;
            }
        }
        return sum_size - init_size;
    }

    fn ensureCapacityFit(this: *Storage, ask_size: u64) void {
        if (this.capacity < this.used + ask_size) {
            // try realloc first
            const old_mem = this.mem;
            _ = old_mem;
            const init_next_increment = if (this.capacity < MAX_CAPACITY_INCREMENT) this.capacity else MAX_CAPACITY_INCREMENT;
            const capacity_increment = calculateIncrementNeeded(this.used + ask_size, this.capacity, init_next_increment);
            const new_mem = this.allocator.realloc(this.mem, this.capacity + capacity_increment) catch |err| brk: {
                std.debug.print("error: {any}!\n", .{err});
                break :brk this.mem;
            };
            this.mem = new_mem;
            this.capacity += capacity_increment;
        }
    }

    pub fn addU8Slice(self: *Storage, str: []const u8) Storage.Fragment {
        self.ensureCapacityFit(str.len);

        const id = self.next_id;
        self.next_id += 1;
        const start = self.used;
        const end = start + str.len;
        @memcpy(self.mem[start..end], str);
        @memset(self.mem[end .. end + 1], 0);
        self.used += str.len + 1;
        const fragment = Storage.Fragment{
            .id = id,
            .start = start,
            .end = end,
        };
        self.str_map.put(self.allocator, id, fragment) catch unreachable;
        return fragment;
    }
};

pub const JString = struct {
    id: u64,
    len: u64,
    storage: *Storage,

    pub inline fn len(this: *const JString) usize {
        return this.len;
    }

    pub inline fn getSlice(this: *const JString) []const u8 {
        return this.storage.getSlice(this.id);
    }

    pub fn eql(this: *const JString, that: *const JString) bool {
        const this_slice = this.getSlice();
        const that_slice = that.getSlice();
        return std.mem.eql(u8, this_slice, that_slice);
    }
};

pub fn genJStringCreatorWithInitCapacity(comptime comptime_allocator: std.mem.Allocator, comptime init_capacity: u64) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        init_capacity: u64,
        storage: Storage,

        pub fn init() Self {
            return Self{
                .allocator = comptime_allocator,
                .init_capacity = init_capacity,
                .storage = Storage.init(comptime_allocator, init_capacity),
            };
        }

        pub fn deinit(this: *Self) void {
            this.storage.deinit();
        }

        pub fn newEmpty(this: *Self) JString {
            const self = @constCast(this);
            return JString{
                .id = 0, // empty string will always have id=0,
                .len = 0,
                .storage = &self.storage,
            };
        }

        pub fn newFrom(this: *Self, str: []const u8) JString {
            const self = @constCast(this);
            const fragment = self.storage.addU8Slice(str);
            return JString{
                .id = fragment.id,
                .len = fragment.end - fragment.start,
                .storage = &self.storage,
            };
        }
    };
}

pub fn genJStringCreator(comptime allocator: std.mem.Allocator) type {
    return genJStringCreatorWithInitCapacity(allocator, INIT_CAPACITY);
}

// >>> all your tests belong to me and list in belowing <<<

test "var work, const not" {
    // {
    //     const jstring_creator = genJStringCreator(testing.allocator).init();
    //     defer jstring_creator.deinit();
    //     const str = jstring_creator.newEmpty();
    //     try testing.expectEqual(str.len, 0);
    // }

    {
        var jstring_creator2 = genJStringCreator(testing.allocator).init();
        defer jstring_creator2.deinit();
        const str = jstring_creator2.newFrom("hello,world");
        try testing.expectEqual(str.len, 11);
    }
}

test "newEmpty should work" {
    var jstring_creator = genJStringCreator(testing.allocator).init();
    defer jstring_creator.deinit();

    const str1 = jstring_creator.newEmpty();
    try testing.expectEqual(str1.len, 0);

    const str2 = jstring_creator.newEmpty();
    try testing.expectEqual(str2.len, 0);

    // their underlying slice should be the same, equal to the beginning of storage.mem
    try testing.expectEqual(str1.getSlice(), str2.getSlice());
    try testing.expectEqual(str1.getSlice(), jstring_creator.storage.mem[0..1]);

    // and empty JStrings should all eql
    try testing.expect(str1.eql(&str2));
}

test "newFrom should work" {
    var jstring_creator = genJStringCreator(testing.allocator).init();
    defer jstring_creator.deinit();

    const str1 = jstring_creator.newFrom("hello,world!");
    try testing.expectEqual(str1.len, 12);
    try testing.expect(std.mem.eql(u8, str1.getSlice(), "hello,world!"));
    try testing.expectEqual(jstring_creator.storage.used, 14);
}

test "ensureCapacity should work" {
    {
        var jstring_creator = genJStringCreatorWithInitCapacity(testing.allocator, 16).init();
        defer jstring_creator.deinit();

        const str1 = jstring_creator.newFrom("hello,world"); // 11 bytes
        try testing.expectEqual(str1.len, 11);

        const str2 = jstring_creator.newFrom("this is a string longer than 16 bytes"); // actually 37 bytes
        try testing.expectEqual(str2.len, 37);
        try testing.expect(std.mem.eql(u8, str1.getSlice(), "hello,world"));
        try testing.expect(std.mem.eql(u8, str2.getSlice(), "this is a string longer than 16 bytes"));
        try testing.expectEqual(jstring_creator.storage.used, 51);
        try testing.expectEqual(jstring_creator.storage.capacity, 64);
    }

    const NoReallocTestingAllocator = struct {
        const Self = @This();
        base_allocator: std.mem.Allocator,

        pub fn init(base_allocator: std.mem.Allocator) Self {
            return Self{ .base_allocator = base_allocator };
        }

        pub fn allocator(this: *Self) std.mem.Allocator {
            return .{
                .ptr = this,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            _ = ctx;
            return testing.allocator.rawAlloc(len, ptr_align, ret_addr);
        }

        fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            _ = ret_addr;
            _ = new_len;
            _ = buf_align;
            _ = buf;
            _ = ctx;
            return false;
        }

        fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            _ = ctx;
            testing.allocator.rawFree(buf, buf_align, ret_addr);
        }
    };

    {
        var jstring_creator2 = genJStringCreatorWithInitCapacity(testing.allocator, 16).init();

        // yes following is possible, but do never do it outside of testing
        var noReallocTestingAllocator = NoReallocTestingAllocator.init(testing.allocator);
        const noReallocTestingAllocator_allocator = noReallocTestingAllocator.allocator();
        jstring_creator2.allocator = noReallocTestingAllocator_allocator;
        jstring_creator2.storage.deinit();
        jstring_creator2.storage = Storage.init(noReallocTestingAllocator_allocator, jstring_creator2.init_capacity);

        defer jstring_creator2.deinit();
        const str1 = jstring_creator2.newFrom("hello,world"); // 11 bytes
        try testing.expectEqual(str1.len, 11);

        const str2 = jstring_creator2.newFrom("this is a string longer than 16 bytes"); // actually 37 bytes
        try testing.expectEqual(str2.len, 37);
        try testing.expect(std.mem.eql(u8, str1.getSlice(), "hello,world"));
        try testing.expect(std.mem.eql(u8, str2.getSlice(), "this is a string longer than 16 bytes"));
        try testing.expectEqual(jstring_creator2.storage.used, 51);
        try testing.expectEqual(jstring_creator2.storage.capacity, 64);
    }
}
