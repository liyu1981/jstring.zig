# `jstring.zig`

## Target: create a reusable string lib for myself with all familiar methods methods can find in javascript string.

## Reason:

1.  string is important we all know, so a good string lib will be very useful.
2.  javascript string is (in my opinion) the most battle tested string library out there, strike a good balance
    between features and complexity.

The javascript string specs and methods this file use as reference can be found at
https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String

All methods except those marked as deprecated (such as anchor, big, blink etc) are implemented, in zig way.

# integration with PCRE2 regex

One highlight of `jstring.zig` is that it integrates with [PCRE2](https://www.pcre.org/) to provide `match`, `match_all` and more just like the familar feeling of javascript string.

here are some examples of how regex can be used

```zig
var str1 = try JStringUnmanaged.newFromSlice(arena.allocator(), "hello,hello,world");
var results = try str1.splitByRegex(arena.allocator(), "l+", 0, 0);
try testing.expectEqual(results.len, 1);
try testing.expect(results[0].eqlSlice("hello,hello,world"));
results = try str1.splitByRegex(arena.allocator(), "l+", 0, -1);
try testing.expectEqual(results.len, 4);
try testing.expect(results[0].eqlSlice("he"));
try testing.expect(results[1].eqlSlice("o,he"));
try testing.expect(results[2].eqlSlice("o,wor"));
try testing.expect(results[3].eqlSlice("d"));
```

# usage

```bash
zig fetch --save https://github.com/liyu1981/jstring.zig/archive/refs/tags/0.1.0.tar.gz
```

check `example` folder for a sample project

```zig
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
```

in order to run this example from the `git clone` repo, you will need

```bash
cd <jstirng_repo>/examples
zig fetch --save ../ # to update your local zig cache about jstring
zig build run
```

# `build.zig`

when use `jstring.zig` in your project, as it integrates with `PCRE2`, will need to link your project to `libpcre-8`. `jstring.zig` provide a build time function to easy this process.

```zig
// in your build.zig
const jstring_build = @import("jstring");
...
const jstring_dep = b.dependency("jstring", .{});
exe.addModule("jstring", jstring_dep.module("jstring"));
jstring_build.linkPCRE(exe, jstring_dep);
```

again, check `example` folder for the usage

# performance

`jstring.zig` is built with performance in mind. Though `benchmark` is still in developing, but the initial result of allocate/free 1M random size of strings shows a _~70%_ advantage comparing to c++/20's `std::string`.

```bash
benchmark % ./zig-out/bin/benchmark
|zig create/release: | [ooooo] | avg=    16464000ns | min=    14400000ns | max=    20975000ns |
|cpp create/release: | [ooooo] | avg=    56735400ns | min=    56137000ns | max=    57090000ns |
```

(`jstring.zig` is built with `-Doptimize=ReleaseFast`, and `cpp` is built with `-std=c++20 -O2`)

check current benchmark method [here](https://github.com/liyu1981/jstring.zig/blob/main/tools/benchmark/main.zig)

# docs

check the auto generated zig docs [here](https://liyu1981.github.io/jstring.zig)

# tests

`jstring` is rigorously tested.

```bash
./script/pcre_test.sh src/jstring.zig
```

to run all tests.

or check kcov report [here](https://liyu1981.github.io/jstring.zig/cov/index.html): the current level is 100%.

# license

MIT License :)
