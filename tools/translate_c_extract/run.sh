FOLDER=translate_c_extract
ZIG="../../scripts/zig.sh"

cd tools/translate_c_extract
${ZIG} build run -- $@
cd - > /dev/null
