FOLDER="translate_c_extract"
ZIG="../../scripts/zig.sh"
ENTRY="translate_c_extract"

cd tools/${FOLDER}
${ZIG} build
cd - > /dev/null
tools/${FOLDER}/zig-out/bin/${ENTRY} $@
