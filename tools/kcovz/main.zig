const std = @import("std");
const jstring = @import("jstring");

const JString = jstring.JString;
const Regex = jstring.Regex;

const usage =
    \\usage:
    \\    tools/kcovz/run.sh <abs-path-to>/<binary>
    \\
;

var stdout: std.fs.File.Writer = undefined;
var stderr: std.fs.File.Writer = undefined;
var stderr_color_config: std.io.tty.Config = undefined;

const ThisError = error{
    FileOpenError,
    RegexMatchFailed,
    ExeKovFailed,
};

fn stdErrPrintColor(comptime color: std.io.tty.Color, comptime fmt: []const u8, items: anytype) anyerror!void {
    try stderr_color_config.setColor(stderr, color);
    try stderr.print(fmt, items);
}

inline fn stdErrPrintRed(comptime fmt: []const u8, items: anytype) anyerror!void {
    try stdErrPrintColor(std.io.tty.Color.red, fmt, items);
}

inline fn stdErrPrintReset(comptime fmt: []const u8, items: anytype) anyerror!void {
    try stdErrPrintColor(std.io.tty.Color.reset, fmt, items);
}

pub fn main() !u8 {
    var jstring_arena = jstring.ArenaAllocator.init(std.heap.page_allocator);
    defer jstring_arena.deinit();
    const ja = jstring_arena.allocator();

    stdout = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr();
    stderr_color_config = std.io.tty.detectConfig(stderr_file);
    stderr = stderr_file.writer();

    var args = try std.process.argsAlloc(ja);
    args = args[1..];
    if (args.len == 0 or args.len > 1) {
        try stdErrPrintRed("expect 1 arg, but got {d}.\n", .{args.len});
        try stdErrPrintReset("\n{s}", .{usage});
        return 1;
    }

    const cwd_path = try std.process.getCwdAlloc(ja);
    defer ja.free(cwd_path);

    const binary_file_path = try JString.newFromSlice(ja, args[0]);
    const f = std.fs.openFileAbsolute(binary_file_path.valueOf(), .{}) catch {
        try stdErrPrintRed("file {s} not exist. Do you forget to use absolute path? it is easy as `$(pwd)/<relative-path>`\n", .{binary_file_path});
        try stdErrPrintReset("\n{s}", .{usage});
        return 1;
    };
    f.close();

    // try doKov(ja, cwd_path, binary_file_path.valueOf());

    try calibrateKovOutput(ja, cwd_path, binary_file_path);

    return 0;
}

fn doKov(allocator: std.mem.Allocator, cwd: []const u8, binary_file_path: []const u8) anyerror!void {
    var include_s: JString = try JString.newFromFormat(allocator, "--include-path={s}", .{cwd});
    defer include_s.deinit();
    const argv: []const []const u8 = &[_][]const u8{
        "kcov",
        "./cov",
        include_s.valueOf(),
        "--clean",
        binary_file_path,
    };
    try stdout.print("execute kcov: `{s} {s} {s} {s} {s}`...\n", .{ argv[0], argv[1], argv[2], argv[3], argv[4] });
    const run_results = try std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = argv,
    });

    switch (run_results.term) {
        .Exited => |r| {
            if (r == 0) {
                try stdout.print("kcov succeeded!", .{});
                try stdErrPrintReset("====== std out ======\n{s}\n====== std err ======\n{s}\n", .{ run_results.stdout, run_results.stderr });
                return;
            } else {
                try stdErrPrintRed("kcov child process exit with ret {d}\n", .{r});
                try stdErrPrintReset("====== std out ======\n{s}\n====== std err ======\n{s}\n", .{ run_results.stdout, run_results.stderr });
                return ThisError.ExeKovFailed;
            }
        },
        .Signal => |r| {
            try stdErrPrintRed("kcov child process exit with signal {d}\n", .{r});
            return ThisError.ExeKovFailed;
        },
        .Stopped => |r| {
            try stdErrPrintRed("kcov child process stopped with value {d}\n", .{r});
            return ThisError.ExeKovFailed;
        },
        .Unknown => |r| {
            try stdErrPrintRed("kcov child process terminated with unknown reason {d}\n", .{r});
            return ThisError.ExeKovFailed;
        },
    }
}

const KovCoverageFileEntry = struct {
    file: []const u8 = "",
    percent_covered: []const u8 = "",
    covered_lines: []const u8 = "",
    total_lines: []const u8 = "",
};

const KovCoverage = struct {
    files: []KovCoverageFileEntry = undefined,
    percent_covered: []const u8 = "",
    covered_lines: usize = 0,
    total_lines: usize = 0,
    percent_low: f32 = 0.0,
    percent_high: f32 = 0.0,
    command: []const u8 = "",
    date: []const u8 = "",
};

const KovCodecovEntry = std.json.ArrayHashMap([]const u8);

const KovCodecov = struct {
    coverage: std.json.ArrayHashMap(KovCodecovEntry),
};

fn calibrateKovOutput(allocator: std.mem.Allocator, cwd: []const u8, binary_file_path: JString) anyerror!void {
    const binary_file_basename = std.fs.path.basename(binary_file_path.valueOf());
    var coverage_json_path = try JString.newFromFormat(allocator, "{s}/cov/{s}/coverage.json", .{ cwd, binary_file_basename });
    var codecov_json_path = try JString.newFromFormat(allocator, "{s}/cov/{s}/codecov.json", .{ cwd, binary_file_basename });

    defer {
        coverage_json_path.deinit();
        codecov_json_path.deinit();
    }

    var kov_coverage = try loadJson(KovCoverage, allocator, coverage_json_path.valueOf());
    var kov_coverage_v = kov_coverage.value;
    _ = &kov_coverage_v;
    // try stdout.print("{any}", .{v});
    defer kov_coverage.deinit();

    var kov_codecov = try loadJson(KovCodecov, allocator, codecov_json_path.valueOf());
    var kov_codecov_v = kov_codecov.value.coverage;
    // try stdout.print("{any}", .{v2});
    _ = &kov_codecov_v;
    defer kov_codecov.deinit();

    for (kov_coverage_v.files, 0..) |file_entry, index| {
        var found_codecov_entry_key: []const u8 = undefined;
        const found_codecov_entry: ?KovCodecovEntry = brk: {
            var it = kov_codecov_v.map.iterator();
            while (it.next()) |entry| {
                var file_str = try JString.newFromSlice(allocator, file_entry.file);
                defer file_str.deinit();
                if (file_str.endsWithSlice(entry.key_ptr.*)) {
                    found_codecov_entry_key = entry.key_ptr.*;
                    break :brk entry.value_ptr.*;
                }
            }
            break :brk null;
        };
        if (found_codecov_entry) |codecov_entry| {
            try calibrateSingleFile(
                allocator,
                file_entry,
                index,
                codecov_entry,
                found_codecov_entry_key,
                &kov_coverage_v,
                &kov_codecov_v,
            );
        }
    }

    try backupSingleFile(allocator, coverage_json_path);
    try backupSingleFile(allocator, codecov_json_path);
    try writeJson(KovCoverage, allocator, &kov_coverage_v, coverage_json_path);
    var kov_codecov_value = kov_codecov.value;
    try writeJson(KovCodecov, allocator, &kov_codecov_value, codecov_json_path);
}

const MAX_FILE_BYTES: usize = 8 * 1024 * 1024 * 1024; // 8G

fn loadJson(comptime T: type, allocator: std.mem.Allocator, abs_json_path: []const u8) anyerror!std.json.Parsed(T) {
    const f = try std.fs.openFileAbsolute(abs_json_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(allocator, MAX_FILE_BYTES);
    defer allocator.free(content);
    const parsed = try std.json.parseFromSlice(T, allocator, content, std.json.ParseOptions{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    return parsed;
}

fn writeJson(comptime T: type, allocator: std.mem.Allocator, value: *T, file_path: JString) anyerror!void {
    const f = try std.fs.createFileAbsolute(file_path.valueOf(), .{});
    defer f.close();
    const content = try std.json.stringifyAlloc(allocator, value, .{});
    defer allocator.free(content);
    try f.writeAll(content);
}

fn backupSingleFile(allocator: std.mem.Allocator, file_path: JString) anyerror!void {
    const backup_file_path = try file_path.concatSlice(".bak");
    const backup_f = try std.fs.createFileAbsolute(backup_file_path.valueOf(), .{});
    defer backup_f.close();
    const origin_f = try std.fs.openFileAbsolute(file_path.valueOf(), .{});
    defer origin_f.close();
    const content = try origin_f.readToEndAlloc(allocator, MAX_FILE_BYTES);
    defer allocator.free(content);
    try backup_f.writeAll(content);
}

fn calibrateSingleFile(
    allocator: std.mem.Allocator,
    file_entry: KovCoverageFileEntry,
    file_entry_index: usize,
    codecov_entry: KovCodecovEntry,
    codecov_entry_key: []const u8,
    kov_coverage_v: *KovCoverage,
    kov_codecov_v: *std.json.ArrayHashMap(KovCodecovEntry),
) anyerror!void {
    const covered_lines: usize = try std.fmt.parseInt(usize, file_entry.covered_lines, 0);
    var total_lines: usize = try std.fmt.parseInt(usize, file_entry.total_lines, 0);
    var percent_covered: f32 = try std.fmt.parseFloat(f32, file_entry.percent_covered);

    const file_type = try guessFileType(allocator, file_entry.file);

    var f = try std.fs.openFileAbsolute(file_entry.file, .{});
    defer f.close();
    var file_content = try JString.newFromFile(allocator, f);
    defer file_content.deinit();
    const file_lines = try file_content.split("\n", -1);
    defer jstring.freeJStringArray(file_lines);

    // try dumpFileLines(allocator, file_lines, file_entry.file);

    var new_codecov_entry = KovCodecovEntry{
        .map = std.StringArrayHashMapUnmanaged([]const u8){},
    };
    var it = codecov_entry.map.iterator();
    while (it.next()) |entry| {
        const line_no = try std.fmt.parseInt(usize, entry.key_ptr.*, 0) - 1; // kcov line start from 1
        const test_stat = try TestStat.fromSlice(allocator, entry.value_ptr.*);
        if (test_stat.tested == 0) {
            if (line_no < file_lines.len) {
                const line = file_lines[line_no];
                try stdErrPrintColor(std.io.tty.Color.green, "check file:{s} line {d}: ", .{ file_entry.file, line_no });
                try stdErrPrintReset("{s} ", .{line});
                const not_for_cover = isLineNotForCover(line, file_type);
                if (not_for_cover) {
                    total_lines -= 1;
                    kov_coverage_v.total_lines -= 1;
                    try stdErrPrintColor(std.io.tty.Color.green, "not_for_cover, noted!\n", .{});
                    continue;
                } else {
                    try stdErrPrintReset("skipped.\n", .{});
                }
            }
        }
        try new_codecov_entry.map.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
    }

    percent_covered = @as(f32, @floatFromInt(covered_lines)) / @as(f32, @floatFromInt(total_lines));
    try kov_codecov_v.map.put(allocator, codecov_entry_key, new_codecov_entry);
    // following will be very leaky, but we should be fine in govering of arena
    kov_coverage_v.files[file_entry_index].covered_lines = (try JString.newFromFormat(allocator, "{d}", .{covered_lines})).valueOf();
    kov_coverage_v.files[file_entry_index].total_lines = (try JString.newFromFormat(allocator, "{d}", .{total_lines})).valueOf();
    kov_coverage_v.files[file_entry_index].percent_covered = (try JString.newFromFormat(allocator, "{d:.2}", .{percent_covered})).valueOf();
    kov_coverage_v.percent_covered = (try JString.newFromFormat(allocator, "{d}", .{@as(f32, @floatFromInt(kov_coverage_v.covered_lines)) / @as(f32, @floatFromInt(kov_coverage_v.total_lines))})).valueOf();
}

const TestStat = struct {
    tested: usize,
    potential: usize,

    pub fn fromSlice(allocator: std.mem.Allocator, str_slice: []const u8) anyerror!TestStat {
        var jstr = try JString.newFromSlice(allocator, str_slice);
        defer jstr.deinit();
        var re = try jstr.match("(?<tested>\\d+)\\/(?<potential>\\d+?)", 0, true, 0, 0);
        defer re.deinit();
        const tested = brk: {
            const maybe_tested = re.getGroupResultByName("tested");
            if (maybe_tested) |loc| {
                break :brk try std.fmt.parseInt(usize, jstr.valueOf()[loc.start .. loc.start + loc.len], 0);
            } else unreachable;
        };
        const potential = brk: {
            const maybe_potential = re.getGroupResultByName("potential");
            if (maybe_potential) |loc| {
                break :brk try std.fmt.parseInt(usize, jstr.valueOf()[loc.start .. loc.start + loc.len], 0);
            } else unreachable;
        };
        return TestStat{
            .tested = tested,
            .potential = potential,
        };
    }
};

const FileType = enum {
    zig,
    c,
    cpp,
};

fn guessFileType(allocator: std.mem.Allocator, file_path: []const u8) anyerror!FileType {
    var jstr = try JString.newFromSlice(allocator, file_path);
    defer jstr.deinit();
    if (jstr.endsWithSlice(".zig")) {
        return FileType.zig;
    } else if (jstr.endsWithSlice(".c")) {
        return FileType.c;
    } else if (jstr.endsWithSlice(".cpp") or jstr.endsWithSlice(".cc")) {
        return FileType.cpp;
    }
    unreachable;
}

fn isLineNotForCover(line: JString, file_type: FileType) bool {
    switch (file_type) {
        FileType.zig => {
            if (line.indexOf("unreachable", 0) >= 0) {
                return true;
            }
            if (line.indexOf("@panic", 0) >= 0) {
                return true;
            }
            return false;
        },

        FileType.c => {
            if (line.indexOf("/* no-cover */", 0) >= 0) {
                return true;
            }
            return false;
        },

        FileType.cpp => {
            if (line.indexOf("/* no-cover */", 0) >= 0) {
                return true;
            }
            return false;
        },
    }
}

fn dumpFileLines(allocator: std.mem.Allocator, lines: []JString, file_path: []const u8) anyerror!void {
    var dump_path = try JString.newFromFormat(allocator, "{s}_dump.txt", .{file_path});
    defer dump_path.deinit();
    var f = try std.fs.createFileAbsolute(dump_path.valueOf(), .{});
    defer f.close();
    var fwriter = f.writer();
    for (lines) |line| {
        try fwriter.print("{s}\n", .{line});
    }
}
