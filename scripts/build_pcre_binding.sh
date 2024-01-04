mkdir -p zig-out/lib
echo "build src/pcre_binding.c..."
./scripts/zig.sh cc $(pkg-config --cflags libpcre2-8) -std=c17 -c -g src/pcre_binding.c -o zig-out/lib/pcre_binding.o
./scripts/zig.sh ar cr zig-out/lib/libpcre_binding.a zig-out/lib/pcre_binding.o
echo "translate src/pcre_binding.h..."
./scripts/zig.sh translate-c src/pcre_binding.h > src/pcre_binding.zig
