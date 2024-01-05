rm -rf ./cov/*
rm -rf ./zig-out/bin/*.dSYM
kcov ./cov --include-path=$(pwd)/src --clean $@
