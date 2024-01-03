./scripts/zig.sh cc -I/opt/homebrew/include -std=c17 -c -g src/pcre_binding.c -o zig-out/lib/pcre_binding.o
./scripts/zig.sh ar cr zig-out/lib/libpcre_binding.a zig-out/lib/pcre_binding.o
