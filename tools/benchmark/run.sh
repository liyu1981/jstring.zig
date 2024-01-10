FOLDER="benchmark"
ZIG="../../scripts/zig.sh"
ENTRY="benchmark"

cd tools/${FOLDER}
${ZIG} build
cd - > /dev/null
tools/${FOLDER}/zig-out/bin/${ENTRY} $@
