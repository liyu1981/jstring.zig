BIN_ENTRY=pcre_test
LFLAGS="-lpcre_binding $(pkg-config --libs libpcre2-8)"
ZIG=./scripts/zig.sh

${ZIG} test -L ./zig-out/lib ${LFLAGS} -femit-bin=./zig-out/bin/${BIN_ENTRY} $@
