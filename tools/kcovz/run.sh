FOLDER="kcovz"
ZIG="../../scripts/zig.sh"
ENTRY="kcovz"

cd tools/${FOLDER}
${ZIG} build
cd - > /dev/null
tools/${FOLDER}/zig-out/bin/${ENTRY} $@
