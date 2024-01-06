FOLDER=pcre
ENTRY=pcre_binding
CFLAGS="$(pkg-config --cflags libpcre2-8) -std=c17"
DEBUG=-g
ZIG=./scripts/zig.sh

mkdir -p zig-out/lib
echo "build src/${ENTRY}.c..."
${ZIG} cc ${CFLAGS} -c ${DEBUG} src/${FOLDER}/${ENTRY}.c -o zig-out/lib/${ENTRY}.o
${ZIG} ar cr zig-out/lib/lib${ENTRY}.a zig-out/lib/${ENTRY}.o
echo "translate src/pcre_binding.h..."
${ZIG} translate-c src/${FOLDER}/${ENTRY}.h > src/${FOLDER}/${ENTRY}.autogen.zig
