FOLDER=pcre
ENTRY=pcre_binding
CFLAGS="$(pkg-config --cflags libpcre2-8) -std=c17"
DEBUG=-g
ZIG=./scripts/zig.sh

mkdir -p zig-out/lib
echo "build src/${ENTRY}.c..."
${ZIG} cc ${CFLAGS} -c ${DEBUG} src/${FOLDER}/${ENTRY}.c -o zig-out/lib/${ENTRY}.o
${ZIG} ar cr zig-out/lib/lib${ENTRY}.a zig-out/lib/${ENTRY}.o
echo "translate src/${ENTRY}.h..."
${ZIG} translate-c src/${FOLDER}/${ENTRY}.h > src/${FOLDER}/${ENTRY}.autogen.zig
echo "extract translated src/${ENTRY}.h..."
./tools/translate_c_extract/run.sh $(pwd)/src/${FOLDER}/${ENTRY}.h $(pwd)/src/${FOLDER}/${ENTRY}.autogen.zig >src/${ENTRY}.zig.new
cp src/${ENTRY}.zig.new src/${ENTRY}.zig
rm src/${ENTRY}.zig.new
