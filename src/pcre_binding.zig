pub const RegexMatchResult = extern struct {
    start: usize = @import("std").mem.zeroes(usize),
    len: usize = @import("std").mem.zeroes(usize),
};
pub const RegexNamedGroupResult = extern struct {
    name: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    name_len: usize = @import("std").mem.zeroes(usize),
    start: usize = @import("std").mem.zeroes(usize),
    len: usize = @import("std").mem.zeroes(usize),
};
pub const RegexContext = extern struct {
    error_number: c_int = @import("std").mem.zeroes(c_int),
    error_offset: usize = @import("std").mem.zeroes(usize),
    error_message: [512]u8 = @import("std").mem.zeroes([512]u8),
    error_message_len: usize = @import("std").mem.zeroes(usize),
    regex_options: u32 = @import("std").mem.zeroes(u32),
    match_options: u32 = @import("std").mem.zeroes(u32),
    with_match_result: u8 = @import("std").mem.zeroes(u8),
    named_group_count: u32 = @import("std").mem.zeroes(u32),
    next_offset: usize = @import("std").mem.zeroes(usize),
    origin_offset: usize = @import("std").mem.zeroes(usize),
    rc: i64 = @import("std").mem.zeroes(i64),
    matched_count: i64 = @import("std").mem.zeroes(i64),
    matched_results_capacity: i64 = @import("std").mem.zeroes(i64),
    matched_results: [*c]RegexMatchResult = @import("std").mem.zeroes([*c]RegexMatchResult),
    matched_group_count: i64 = @import("std").mem.zeroes(i64),
    matched_group_results: [*c]RegexNamedGroupResult = @import("std").mem.zeroes([*c]RegexNamedGroupResult),
    re: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    match_data: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
};
pub extern fn get_last_error_message(context: [*c]RegexContext) void;
pub extern fn compile(context: [*c]RegexContext, pattern: [*c]const u8) u8;
pub extern fn free_context(context: [*c]RegexContext) void;
pub extern fn match(context: [*c]RegexContext, subject: [*c]const u8, subject_len: usize, start_offset: usize) i64;
pub extern fn prepare_named_groups(context: [*c]RegexContext) void;
pub extern fn fetch_match_results(context: [*c]RegexContext) void;
pub extern fn get_next_offset(context: [*c]RegexContext, subject: [*c]const u8, subject_len: usize) void;
pub extern fn free_for_next_match(context: [*c]RegexContext) void;

pub const PCRE2_ANCHORED = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x80000000, .hex);
pub const PCRE2_NO_UTF_CHECK = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x40000000, .hex);
pub const PCRE2_ENDANCHORED = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x20000000, .hex);
pub const PCRE2_ALLOW_EMPTY_CLASS = @as(c_uint, 0x00000001);
pub const PCRE2_ALT_BSUX = @as(c_uint, 0x00000002);
pub const PCRE2_AUTO_CALLOUT = @as(c_uint, 0x00000004);
pub const PCRE2_CASELESS = @as(c_uint, 0x00000008);
pub const PCRE2_DOLLAR_ENDONLY = @as(c_uint, 0x00000010);
pub const PCRE2_DOTALL = @as(c_uint, 0x00000020);
pub const PCRE2_DUPNAMES = @as(c_uint, 0x00000040);
pub const PCRE2_EXTENDED = @as(c_uint, 0x00000080);
pub const PCRE2_FIRSTLINE = @as(c_uint, 0x00000100);
pub const PCRE2_MATCH_UNSET_BACKREF = @as(c_uint, 0x00000200);
pub const PCRE2_MULTILINE = @as(c_uint, 0x00000400);
pub const PCRE2_NEVER_UCP = @as(c_uint, 0x00000800);
pub const PCRE2_NEVER_UTF = @as(c_uint, 0x00001000);
pub const PCRE2_NO_AUTO_CAPTURE = @as(c_uint, 0x00002000);
pub const PCRE2_NO_AUTO_POSSESS = @as(c_uint, 0x00004000);
pub const PCRE2_NO_DOTSTAR_ANCHOR = @as(c_uint, 0x00008000);
pub const PCRE2_NO_START_OPTIMIZE = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00010000, .hex);
pub const PCRE2_UCP = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00020000, .hex);
pub const PCRE2_UNGREEDY = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00040000, .hex);
pub const PCRE2_UTF = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00080000, .hex);
pub const PCRE2_NEVER_BACKSLASH_C = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00100000, .hex);
pub const PCRE2_ALT_CIRCUMFLEX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00200000, .hex);
pub const PCRE2_ALT_VERBNAMES = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00400000, .hex);
pub const PCRE2_USE_OFFSET_LIMIT = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00800000, .hex);
pub const PCRE2_EXTENDED_MORE = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x01000000, .hex);
pub const PCRE2_LITERAL = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x02000000, .hex);
pub const PCRE2_MATCH_INVALID_UTF = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x04000000, .hex);
