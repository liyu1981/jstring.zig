const std = @import("std");
const testing = std.testing;

// target: create a reusable string lib for zig with
//   1. CPU cache efficiency considered (use the technique in bunjs)
//   2. all familiar methods can find in javascript string:
//        https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String

const Storage = struct {
    allocator: std.mem.Allocator = undefined,
    mem: []u8 = undefined,
    capacity: u64 = 0,
    used: u64 = 0,

    pub const Fragment = struct {
        start: u64,
        end: u64,
    };

    // we store every string in our storage in 0-sentitial format

    pub fn init(allocator: std.mem.Allocator, init_capacity: u64) Storage {
        const allocated = allocator.alignedAlloc(u8, null, init_capacity) catch unreachable;

        // set the first byte to be zero, so that later all empty string can point to beginning of mem
        allocated[0] = 0;

        return Storage{
            .allocator = allocator,
            .mem = allocated,
            .capacity = init_capacity,
            .used = 1, // used = 1 because of the first byte reserved for all empty JString
        };
    }

    pub fn deinit(this: *const Storage) void {
        this.allocator.free(this.mem);
    }

    pub fn addU8Slice(this: *const Storage, str: []const u8) Storage.Fragment {
        // TODO: need to ensure capacity first
        const self: *Storage = @constCast(this);
        const start = self.used;
        const end = start + str.len;
        @memcpy(self.mem[start..end], str);
        @memset(self.mem[end .. end + 1], 0);
        self.used += str.len + 1;
        return Storage.Fragment{
            .start = start,
            .end = end,
        };
    }
};

pub const JString = struct {
    // a string is simply represented as a slice of immutable from the storage
    slice: []const u8 = undefined,

    pub fn len(this: *const JString) usize {
        return this.slice.len;
    }

    pub fn eql(this: *const JString, that: *const JString) bool {
        return std.mem.eql(u8, this.slice, that.slice);
    }
};

pub fn genJStringCreatorWithInitCapacity(comptime allocator: std.mem.Allocator, comptime init_capacity: u64) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        init_capacity: u64,
        storage: Storage,

        pub fn init() Self {
            return Self{
                .allocator = allocator,
                .init_capacity = init_capacity,
                .storage = Storage.init(allocator, init_capacity),
            };
        }

        pub fn deinit(this: *const Self) void {
            this.storage.deinit();
        }

        pub fn newEmpty(this: *const Self) JString {
            return JString{
                .slice = this.storage.mem[0..0],
            };
        }

        pub fn newFrom(this: *const Self, str: []const u8) JString {
            const self: *Self = @constCast(this);
            const fragment = self.storage.addU8Slice(str);
            return JString{
                .slice = this.storage.mem[fragment.start..fragment.end],
            };
        }
    };
}

pub fn genJStringCreator(comptime allocator: std.mem.Allocator) type {
    return genJStringCreatorWithInitCapacity(allocator, 256 * std.mem.page_size);
}

test "both const/var work" {
    const jstring_creator = genJStringCreator(testing.allocator).init();
    defer jstring_creator.deinit();
    var str = jstring_creator.newEmpty();
    try testing.expectEqual(str.len(), 0);

    var jstring_creator2 = genJStringCreator(testing.allocator).init();
    defer jstring_creator2.deinit();
    str = jstring_creator2.newFrom("hello,world");
    try testing.expectEqual(str.len(), 11);
}

test "newEmpty should work" {
    const jstring_creator = genJStringCreator(testing.allocator).init();
    defer jstring_creator.deinit();

    const str1 = jstring_creator.newEmpty();
    try testing.expectEqual(str1.len(), 0);

    const str2 = jstring_creator.newEmpty();
    try testing.expectEqual(str2.len(), 0);

    // their underlying slice should be the same, equal to the beginning of storage.mem
    try testing.expectEqual(str1.slice, str2.slice);
    try testing.expectEqual(str1.slice, jstring_creator.storage.mem[0..0]);

    // and empty JStrings should all eql
    try testing.expect(str1.eql(&str2));
}

test "newFrom should work" {
    const jstring_creator = genJStringCreator(testing.allocator).init();
    defer jstring_creator.deinit();

    const str1 = jstring_creator.newFrom("hello,world!");
    try testing.expectEqual(str1.len(), 12);
}
