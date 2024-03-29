const std = @import("std");
const jstring = @import("jstring");
const cpp = @import("cpp_stdstring.zig");

const JString = jstring.JString;

var stdout: std.fs.File.Writer = undefined;
var stdout_color_config: std.io.tty.Config = undefined;

const ThisError = error{TestResultsNotFound};

fn stdoutPrintColor(comptime color: std.io.tty.Color, comptime fmt: []const u8, items: anytype) anyerror!void {
    try stdout_color_config.setColor(stdout, color);
    try stdout.print(fmt, items);
}

inline fn stdoutPrintRed(comptime fmt: []const u8, items: anytype) anyerror!void {
    try stdoutPrintColor(std.io.tty.Color.red, fmt, items);
}

inline fn stdoutPrintGreen(comptime fmt: []const u8, items: anytype) anyerror!void {
    try stdoutPrintColor(std.io.tty.Color.green, fmt, items);
}

inline fn stdoutPrintReset(comptime fmt: []const u8, items: anytype) anyerror!void {
    try stdoutPrintColor(std.io.tty.Color.reset, fmt, items);
}

const MAX_TEST = 5;

const TestResultType = enum { success, fail };

const TestResult = union(TestResultType) {
    success: u128,
    fail: anyerror,
};

const TestResults = [MAX_TEST]TestResult;

const TestResultMap = std.StringArrayHashMap(TestResults);
const TestFunc = *const fn () anyerror!void;

pub fn main() !void {
    var ga = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer ga.deinit();
    const gaa = ga.allocator();

    const stdout_file = std.io.getStdOut();
    stdout = stdout_file.writer();
    stdout_color_config = std.io.tty.detectConfig(stdout_file);

    var test_result_map = TestResultMap.init(gaa);
    _ = &test_result_map;

    try runTest("zig create/release", testCreateReleaseZig, gaa, &test_result_map);
    try runTest("cpp create/release", testCreateReleaseCpp, gaa, &test_result_map);

    try printTestResults(test_result_map);
}

fn printTestResults(test_result_map: TestResultMap) anyerror!void {
    var it = test_result_map.iterator();
    var retMap: [MAX_TEST]u8 = undefined;
    var times: [MAX_TEST]u128 = undefined;
    var time_count: usize = 0;

    while (it.next()) |entry| {
        const test_name = entry.key_ptr.*;
        const results = entry.value_ptr.*;
        time_count = 0;
        for (0..results.len) |i| switch (results[i]) {
            .success => |time| {
                retMap[i] = 'o';
                times[i] = time;
                time_count += 1;
            },
            .fail => |_| retMap[i] = 'x',
        };

        try stdoutPrintGreen("|{s}: | ", .{test_name});
        try stdoutPrintReset("[{s}] | ", .{retMap});

        const min = std.mem.min(u128, times[0..time_count]);
        const max = std.mem.max(u128, times[0..time_count]);
        const avg = brk: {
            var sum: u128 = 0;
            for (times[0..time_count]) |t| {
                sum += t;
            }
            break :brk sum / time_count;
        };
        try stdoutPrintReset("avg={d:12}ns | min={d:12}ns | max={d:12}ns |\n", .{ avg, min, max });
    }
}

fn update_test_result(test_result_map_: *TestResultMap, comptime name: []const u8, index: usize, result: TestResult) anyerror!void {
    var maybe_test_results: ?TestResults = test_result_map_.get(name);
    _ = &maybe_test_results;
    if (maybe_test_results) |test_results| {
        var new_test_results: TestResults = test_results;
        new_test_results[index] = result;
        try test_result_map_.put(name, new_test_results);
    } else {
        return ThisError.TestResultsNotFound;
    }
}

fn runTest(comptime name: []const u8, comptime test_func: TestFunc, allocator: std.mem.Allocator, test_result_map_: *TestResultMap) anyerror!void {
    var start: i128 = undefined;
    var end: i128 = undefined;
    var test_results_: *TestResults = try allocator.create(TestResults);
    _ = &test_results_;
    // omit destroy this test_results, hopefully it will be released by arena allocator (or just release when exit)
    try test_result_map_.put(name, test_results_.*);
    for (0..MAX_TEST) |i| {
        start = std.time.nanoTimestamp();
        test_func.*() catch |err| {
            try update_test_result(test_result_map_, name, i, TestResult{ .fail = err });
            continue;
        };
        end = std.time.nanoTimestamp();
        try update_test_result(test_result_map_, name, i, TestResult{ .success = @as(u128, @intCast(end - start)) });
    }
}

// all tests below

const create_release_data = [_][]const u8{
    "This was a triumph.",
    "I'm making a note here:",
    "huge success.",
    "It's hard to overstate",
    "My satisfaction.",
    "Aperture Science.",
    "We do what we must",
    "Because we can.",
    "For the good of all of us.",
    "Except the ones who are dead.",
    "But there's no sense crying Over every mistake. You just keep on trying Till you run out of cake. And the Science gets done. And you make a neat gun. For the people who are Still alive.",
    "I'm not even angry.",
    "I'm being so sincere right now.",
    "Even though you broke my heart.",
    "And killed me.",
    "And tore me to pieces. And threw every piece into a fire. As they burned it hurt because I was so happy for you! Now these points of data Make a beautiful line. And we're out of beta. We're releasing on time. So I'm GLaD. I got burned. Think of all the things we learned For the people who are Still alive. Go ahead and leave me. I think I prefer to stay inside. Maybe you'll find someone else To help you. Maybe Black Mesa... THAT WAS A JOKE, HA HA, FAT CHANCE. Anyway this cake is great It's so delicious and moist Look at me still talking when there's science to do When I look out there It makes me GLaD I'm not you. I've experiments to run There is research to be done On the people who are Still alive. And believe me I am still alive I'm doing science and I'm still alive I feel FANTASTIC and I'm still alive While you're dying I'll be still alive And when you're dead I will be still alive Still alive Still alive.",
};

fn testCreateReleaseZig() anyerror!void {
    var arena = jstring.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var rng_src = std.rand.DefaultPrng.init(0);
    var random = rng_src.random();
    for (0..1_000_000) |_| {
        const r = random.intRangeAtMost(usize, 0, create_release_data.len - 1);
        var s = try JString.newFromSlice(arena.allocator(), create_release_data[r]);
        s.deinit();
    }
}

fn testCreateReleaseCpp() anyerror!void {
    var rng_src = std.rand.DefaultPrng.init(0);
    var random = rng_src.random();
    for (0..1_000_000) |_| {
        const r = random.intRangeAtMost(usize, 0, create_release_data.len - 1);
        const s_ptr = cpp.new_string(create_release_data[r].ptr, create_release_data[r].len);
        cpp.free_string(s_ptr);
    }
}
