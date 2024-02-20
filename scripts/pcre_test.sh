BIN_ENTRY=pcre_test
LFLAGS="-lpcre_binding $(pkg-config --libs libpcre2-8) -lc"
ZIG=./scripts/zig.sh

mkdir -p ./zig-out/bin
${ZIG} test -L ./zig-out/lib ${LFLAGS} -femit-bin=./zig-out/bin/${BIN_ENTRY} $@
