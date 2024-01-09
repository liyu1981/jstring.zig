KCOV="../kcov/build/src/kcov"

rm -rf ./cov/*
rm -rf ./zig-out/bin/*.dSYM
${KCOV} ./cov --include-path=$(pwd) --clean $@
