const std = @import("std");
const jstring = @import("jstring");

const JString = jstring.JString;
const Regex = jstring.Regex;

const usage =
    \\usage:
    \\    tools/translate_c_extract/run.sh <path-to>/<source_header>.h <path-to>/<generated>.autogen.zig
    \\
    \\    [processed file will be printed to stdout]
    \\
;

var stdout: std.fs.File.Writer = undefined;
var stderr: std.fs.File.Writer = undefined;
var stderr_color_config: std.io.tty.Config = undefined;

const ThisError = error{
    FileOpenError,
    RegexMatchFailed,
    HeaderSyntaxError,
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
    if (args.len == 0 or args.len > 2) {
        try stdErrPrintRed("expect 2 arg, but got {d}.\n", .{args.len});
        try stdErrPrintReset("\n{s}", .{usage});
        return 1;
    }

    var maybe_header_file_path = try JString.newFromSlice(ja, args[0]);
    if (!maybe_header_file_path.endsWithSlice(".h")) {
        try stdErrPrintRed("support .h file only, but got {s}\n", .{maybe_header_file_path});
        try stdErrPrintReset("\n{s}", .{usage});
        return 1;
    }

    var maybe_autogen_file_path = try JString.newFromSlice(ja, args[1]);
    if (!maybe_autogen_file_path.endsWithSlice(".autogen.zig")) {
        try stdErrPrintRed("support .autogen.zig file only, but got {s}\n", .{maybe_autogen_file_path});
        try stdErrPrintReset("\n{s}", .{usage});
        return 1;
    }

    var header_file = try openFile(ja, &maybe_header_file_path);
    defer header_file.close();
    try stderr.print("file: {s} opened.\n", .{maybe_header_file_path});
    var header_parser = try parseHeader(ja, header_file, maybe_header_file_path);
    defer header_parser.deinit();

    var it = header_parser.header_provides.iterator();
    while (it.next()) |entry| {
        try stdErrPrintReset("found tk: {s}\n", .{entry.value_ptr.*});
    }

    var autogen_file = try openFile(ja, &maybe_autogen_file_path);
    defer autogen_file.close();
    try stderr.print("file: {s} opened.\n", .{maybe_autogen_file_path});
    const autogen_chunks = try parseAutogen(ja, autogen_file);
    defer jstring.freeJStringArray(autogen_chunks);

    try stdErrPrintReset("found autogen chunks: {d}\n", .{autogen_chunks.len});

    try outputHeader(ja);
    const output_count = try extract(header_parser.header_provides, autogen_chunks, stdout);
    try stdErrPrintColor(std.io.tty.Color.green, "generated {d} lines!\n", .{output_count});

    return 0;
}

fn openFile(allocator: std.mem.Allocator, file_path: *JString) anyerror!std.fs.File {
    return brk: {
        const cwd = std.fs.cwd();
        break :brk cwd.openFile(file_path.valueOf(), .{}) catch {
            const cwd_path = try std.process.getCwdAlloc(allocator);
            defer allocator.free(cwd_path);
            try stdErrPrintRed("can not open file {s} within directory {s}.", .{ file_path, cwd_path });
            try stdErrPrintReset("\n{s}", .{usage});
            return ThisError.FileOpenError;
        };
    };
}

const HeaderParser = struct {
    const State = enum { line, block };
    const ProvideHashMap = std.AutoHashMap(usize, JString);

    file_name: JString = undefined,
    header_provides: ProvideHashMap,
    state: State = State.line,
    last_block_pattern_: *JString = undefined,
    has_last_block_pattern: bool = false,

    re_block_open: Regex,
    re_block_close: Regex,
    re_provide: Regex,

    pub fn init(allocator: std.mem.Allocator, file_name: JString) anyerror!HeaderParser {
        return HeaderParser{
            .file_name = try file_name.clone(),
            .header_provides = ProvideHashMap.init(allocator),
            .re_block_open = try Regex.init(allocator, "translate-c provide-begin:\\s\\/(?<pattern>.+)\\/", 0),
            .re_block_close = try Regex.init(allocator, "translate-c provide-end:\\s\\/(?<pattern>.+)\\/", 0),
            .re_provide = try Regex.init(allocator, "translate-c provide:\\s(?<tk>\\S+)", 0),
        };
    }

    pub fn deinit(this: *HeaderParser) void {
        if (this.has_last_block_pattern) {
            this.last_block_pattern_.*.deinit();
        }
        this.re_provide.deinit();
        this.re_block_open.deinit();
        this.re_block_close.deinit();
        this.header_provides.deinit();
        this.file_name.deinit();
    }

    pub fn parse(this: *HeaderParser, subject_str: *JString) anyerror!void {
        const allocator = subject_str.allocator;
        var lines = try subject_str.split("\n", -1);
        _ = &lines;
        defer jstring.freeJStringArray(lines);
        for (lines, 0..) |line, i| {
            switch (this.state) {
                State.line => {
                    try this.re_provide.match(line.valueOf(), 0, true, Regex.DefaultMatchOptions);
                    defer this.re_provide.reset() catch unreachable;
                    try this.checkMatchFailed("re_provide", &this.re_provide, i);
                    if (this.re_provide.matchSucceed()) {
                        if (this.re_provide.getGroupResultByName("tk")) |gr| {
                            const name = try JString.newFromSlice(allocator, line.valueOf()[gr.start .. gr.start + gr.len]);
                            try this.header_provides.put(name.hash(), name);
                            continue;
                        }
                    }

                    try this.re_block_open.match(line.valueOf(), 0, true, Regex.DefaultMatchOptions);
                    defer this.re_block_open.reset() catch unreachable;
                    try this.checkMatchFailed("re_block_open", &this.re_block_open, i);
                    if (this.re_block_open.matchSucceed()) {
                        if (this.re_block_open.getGroupResultByName("pattern")) |gr| {
                            var pattern = try JString.newFromSlice(allocator, line.valueOf()[gr.start .. gr.start + gr.len]);
                            if (this.has_last_block_pattern) this.last_block_pattern_.*.deinit();
                            this.last_block_pattern_ = &pattern;
                        }
                        this.state = State.block;
                        continue;
                    }

                    try this.re_block_close.match(line.valueOf(), 0, true, Regex.DefaultMatchOptions);
                    defer this.re_block_close.reset() catch unreachable;
                    try this.checkMatchFailed("re_block_close", &this.re_block_close, i);
                    if (this.re_block_close.matchSucceed()) {
                        try stdErrPrintRed("block close interrupted by previous single lien provide, file {s}:L{d}.\n", .{ this.file_name, i });
                        return ThisError.HeaderSyntaxError;
                    }
                },

                State.block => {
                    var block_pattern_re = try line.match(this.last_block_pattern_.*.valueOf(), 0, true, Regex.DefaultRegexOptions, Regex.DefaultMatchOptions);
                    defer block_pattern_re.deinit();
                    try this.checkMatchFailed("block_pattern_re", &block_pattern_re, i);
                    if (block_pattern_re.matchSucceed()) {
                        if (block_pattern_re.getGroupResultByName("tk")) |gr| {
                            const name = try JString.newFromSlice(allocator, line.valueOf()[gr.start .. gr.start + gr.len]);
                            try this.header_provides.put(name.hash(), name);
                            continue;
                        }
                    }

                    try this.re_block_open.match(line.valueOf(), 0, true, Regex.DefaultMatchOptions);
                    defer this.re_block_open.reset() catch unreachable;
                    try this.checkMatchFailed("re_block_open", &this.re_block_open, i);
                    if (this.re_block_open.matchSucceed()) {
                        try stdErrPrintRed("block open before previous block not closed, file {s}:L{d}.\n", .{ this.file_name, i });
                        return ThisError.HeaderSyntaxError;
                    }

                    try this.re_block_close.match(line.valueOf(), 0, true, Regex.DefaultMatchOptions);
                    defer this.re_block_close.reset() catch unreachable;
                    try this.checkMatchFailed("re_block_close", &this.re_block_close, i);
                    if (this.re_block_close.matchSucceed()) {
                        if (this.re_block_close.getGroupResultByName("pattern")) |gr| {
                            const close_pattern_slice = line.valueOf()[gr.start .. gr.start + gr.len];
                            if (!this.last_block_pattern_.*.eqlSlice(close_pattern_slice)) {
                                try stdErrPrintRed(" block close with a different pattern `{s}`(open by `{s}`), file {s}:L{d}.\n", .{ close_pattern_slice, this.last_block_pattern_.*, this.file_name, i });
                                return ThisError.HeaderSyntaxError;
                            }
                        }
                        this.state = State.line;
                        continue;
                    }

                    try this.re_provide.match(line.valueOf(), 0, true, Regex.DefaultMatchOptions);
                    defer this.re_provide.reset() catch unreachable;
                    try this.checkMatchFailed("re_provide", &this.re_provide, i);
                    if (this.re_provide.matchSucceed()) {
                        try stdErrPrintRed("block interrupted single line provide, file {s}:L{d}.\n", .{ this.file_name, i });
                        return ThisError.HeaderSyntaxError;
                    }
                },
            }
        }
    }

    fn checkMatchFailed(this: *HeaderParser, label: []const u8, re: *Regex, line_no: usize) anyerror!void {
        if (!re.succeed()) {
            try stdErrPrintRed("regex {s} match failed: {s}, file {s}:L{d}.\n", .{ label, this.re_block_open.errorMessage(), this.file_name, line_no });
            return ThisError.RegexMatchFailed;
        }
    }
};

fn parseHeader(allocator: std.mem.Allocator, f: std.fs.File, file_name: JString) anyerror!HeaderParser {
    var all_content = try JString.newFromFile(allocator, f);
    defer all_content.deinit();
    var parser = try HeaderParser.init(allocator, file_name);
    try parser.parse(&all_content);
    return parser;
}

fn parseAutogen(allocator: std.mem.Allocator, f: std.fs.File) anyerror![]JString {
    var all_content = try JString.newFromFile(allocator, f);
    return all_content.split(";", -1);
}

fn extract(header_provides: HeaderParser.ProvideHashMap, autogen_chunks: []JString, writer: std.fs.File.Writer) anyerror!usize {
    var count: usize = 0;
    for (0..autogen_chunks.len) |i| {
        var chunk = autogen_chunks[i];
        // split by space/parenthesis, so variable name or function name will be seperated
        const tokens = try chunk.splitByRegex("[\\s\\(\\)]", 0, -1);
        defer jstring.freeJStringArray(tokens);
        // very naive algorithm, just check whether there is any token is provided from header
        for (tokens) |token| {
            const hash = token.hash();
            if (header_provides.contains(hash)) {
                try writer.print("{s};\n", .{chunk});
                count += 1;
                break;
            }
        }
    }
    return count;
}

fn outputHeader(allocator: std.mem.Allocator) anyerror!void {
    var it = std.process.args();
    try stdout.print("// generated by: ` ", .{});
    var cwd_buf: [4096]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buf);
    while (it.next()) |arg| {
        const relative_arg = try std.fs.path.relative(allocator, cwd, arg);
        defer allocator.free(relative_arg);
        try stdout.print("{s} ", .{relative_arg});
    }
    try stdout.print("`\n", .{});
    try stdout.print("// timestamp: {d}\n", .{std.time.microTimestamp()});
}
