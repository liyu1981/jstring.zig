const std = @import("std");
const jstring = @import("jstring");

pub fn main() !u8 {
    var your_name = brk: {
        var jstr = try jstring.JString.newFromSlice(std.heap.page_allocator, "name is: zig");
        defer jstr.deinit();
        const m = try jstr.match("name is: (?<name>.+)", 0, true, 0, 0);
        if (m.matchSucceed()) {
            const r = m.getGroupResultByName("name");
            break :brk try jstr.slice(
                @as(isize, @intCast(r.?.start)),
                @as(isize, @intCast(r.?.start + r.?.len)),
            );
        }
        unreachable;
    };
    defer your_name.deinit();

    try std.io.getStdOut().writer().print("\nhello, {s}\n", .{your_name});
    return 0;
}
