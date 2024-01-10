FOLDER="tools/benchmark"
ENTRY=cpp_stdstring
CFLAGS="-std=c++20"
#DEBUG="-g"
DEBUG="-O2"
ZIG=../../scripts/zig.sh

mkdir -p zig-out/lib
echo "build ${ENTRY}.c..."
${ZIG} c++ ${CFLAGS} -c ${DEBUG} ${ENTRY}.cpp -o zig-out/lib/${ENTRY}.o
${ZIG} ar cr zig-out/lib/lib${ENTRY}.a zig-out/lib/${ENTRY}.o
echo "translate ${ENTRY}.h..."
${ZIG} translate-c ${ENTRY}.h > ${ENTRY}.autogen.zig
echo "extract translated ${ENTRY}.h..."
../translate_c_extract/zig-out/bin/translate_c_extract $(pwd)/${ENTRY}.h $(pwd)/${ENTRY}.autogen.zig >${ENTRY}.zig.new
cp ${ENTRY}.zig.new ${ENTRY}.zig
rm ${ENTRY}.zig.new
