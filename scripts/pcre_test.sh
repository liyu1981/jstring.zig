./scripts/zig.sh test -L ./zig-out/lib -lpcre_binding $(pkg-config --libs libpcre2-8) $@
