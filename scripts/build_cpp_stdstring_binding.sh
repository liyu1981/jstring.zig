mkdir -p zig-out/lib
echo "build src/benchmark/cpp_stdstring_binding.c..."
./scripts/zig.sh c++ -std=c++20 -stdlib=c++20 -c -g src/benchmark/cpp_stdstring_binding.cpp -o zig-out/lib/cpp_stdstring_binding.o
./scripts/zig.sh ar cr zig-out/lib/libcpp_stdstring_binding.a zig-out/lib/cpp_stdstring_binding.o
echo "translate src/benchmark/cpp_stdstring_binding.h..."
./scripts/zig.sh translate-c src/benchmark/cpp_stdstring_binding.h > src/benchmark/cpp_stdstring_binding.zig
