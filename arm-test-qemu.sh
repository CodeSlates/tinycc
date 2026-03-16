#!/bin/bash
set -e

# Cross-compile TCC for ARM64 on an x86_64 host, then verify it can
# link and produce working ARM64 binaries under QEMU emulation.

ARM_SYS_PATH="/usr/aarch64-linux-gnu"
BUILD_OUTPUT="$(pwd)/arm_build_output"

# ---------------------------------------------------------------
# 1. Host setup
# ---------------------------------------------------------------
echo "=== Installing host tools ==="
sudo rm -f /etc/apt/sources.list.d/yarn.list 2>/dev/null || true
sudo apt-get update -qq
sudo apt-get install -y -qq gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu qemu-user-static make

# ---------------------------------------------------------------
# 2. Clean workspace
# ---------------------------------------------------------------
echo "=== Cleaning workspace ==="
make clean || true
rm -f c2str.exe tccdefs_.h tcc_real.bin config.mak config.h

# ---------------------------------------------------------------
# 3. Build host-native c2str helper
# ---------------------------------------------------------------
echo "=== Building host-native c2str ==="
gcc -O2 -DC2STR conftest.c -o c2str.exe || gcc -O2 c2str.c -o c2str.exe
./c2str.exe include/tccdefs.h tccdefs_.h
touch tccdefs_.h

# ---------------------------------------------------------------
# 4. Configure for ARM64 cross-build
# ---------------------------------------------------------------
echo "=== Configuring for ARM64 ==="
./configure \
    --cross-prefix=aarch64-linux-gnu- \
    --cpu=aarch64 \
    --prefix="$BUILD_OUTPUT" \
    --sysroot="" \
    --crtprefix="$ARM_SYS_PATH/lib" \
    --libpaths="{B}:$ARM_SYS_PATH/lib:/usr/lib/aarch64-linux-gnu" \
    --sysincludepaths="{B}/include:$ARM_SYS_PATH/include:/usr/include" \
    --elfinterp="/lib/ld-linux-aarch64.so.1"

echo "--- config.mak ---"
cat config.mak
echo "------------------"

# ---------------------------------------------------------------
# 5. Build TCC compiler binary (ARM64 ELF, cross-compiled by
#    aarch64-linux-gnu-gcc)
# ---------------------------------------------------------------
echo "=== Building ARM64 TCC binary ==="
make tcc ONE_SOURCE=1

# ---------------------------------------------------------------
# 6. Create QEMU wrapper so that "make" can transparently invoke
#    the ARM binary for building runtime libs and install targets
# ---------------------------------------------------------------
echo "=== Creating QEMU wrapper ==="
mv tcc tcc_real.bin

cat > tcc <<'WRAPPER'
#!/bin/sh
exec qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    "$(dirname "$0")/tcc_real.bin" "$@"
WRAPPER
chmod +x tcc

# Quick sanity check – can the wrapper invoke tcc?
echo "=== TCC version via QEMU ==="
./tcc -v || echo "(tcc -v failed, continuing anyway)"

# ---------------------------------------------------------------
# 7. Build libtcc1.a runtime library
#    CONFIG_BUILD_CROSS is now set by configure, so lib/Makefile
#    will automatically use the cross-gcc (CC in config.mak) to
#    compile libtcc1.a objects instead of trying to run the ARM tcc.
# ---------------------------------------------------------------
echo "=== Building libtcc1.a ==="
make libtcc1.a

# ---------------------------------------------------------------
# 8. Install
# ---------------------------------------------------------------
echo "=== Installing ==="
make install

# ---------------------------------------------------------------
# 9. Verification test
# ---------------------------------------------------------------
echo "=== Running ARM64 linking test ==="
TEST_DIR="tcc_arm_test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/test_lib.c" <<'EOF'
int add(int a, int b) { return a + b; }
EOF

cat > "$TEST_DIR/main.c" <<'EOF'
#include <stdio.h>
extern int add(int a, int b);
int main() {
    int res = add(900, 99);
    printf("\n--- ARM64 CROSS-BUILD SUCCESS ---\n");
    printf("Result from emulated TCC-built binary: %d\n", res);
    return (res == 999) ? 0 : 1;
}
EOF

TCC_FINAL="$BUILD_OUTPUT/bin/tcc"

# Build a shared library with the cross-gcc
aarch64-linux-gnu-gcc -shared -fPIC -o "$TEST_DIR/libtest.so" "$TEST_DIR/test_lib.c"

# Use the installed ARM64 TCC (via QEMU) to compile + link main.c
echo "=== Compiling test with installed TCC ==="
qemu-aarch64-static -L "$ARM_SYS_PATH" "$TCC_FINAL" \
    -I "$ARM_SYS_PATH/include" \
    -L "$TEST_DIR" \
    -ltest \
    "$TEST_DIR/main.c" \
    -o "$TEST_DIR/arm_final_test" \
    -v

# Run the resulting ARM64 binary under QEMU
echo "=== Running test binary ==="
export LD_LIBRARY_PATH="$TEST_DIR:$ARM_SYS_PATH/lib"
qemu-aarch64-static -L "$ARM_SYS_PATH" "$TEST_DIR/arm_final_test"

echo "================================================"
echo "Build and test completed successfully."