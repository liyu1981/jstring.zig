const std = @import("std");
const jstring = @import("jstring");

const JString = jstring.JString;

pub fn main() !void {
    var arena = jstring.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const out = std.io.getStdOut().writer();
    const s = JString.newFromSlice(arena.allocator(), "hello");
    try out.print("{any} world!\n", .{s});
}
