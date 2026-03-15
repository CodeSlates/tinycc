#!/bin/bash
set -e

# 1. Host setup
echo "Updating host tools..."
sudo rm -f /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu qemu-user-static make

# 2. Clean Workspace
echo "Cleaning workspace..."
make clean || true
rm -f c2str.exe tccdefs_.h tcc_real.bin

# 3. Build host-native c2str
echo "Building host-native c2str..."
gcc -O2 -DC2STR conftest.c -o c2str.exe || gcc -O2 c2str.c -o c2str.exe
./c2str.exe include/tccdefs.h tccdefs_.h
touch tccdefs_.h

# 4. Configure for ARM64
echo "Configuring for ARM64..."
./configure --cross-prefix=aarch64-linux-gnu- --cpu=aarch64 --prefix=$(pwd)/arm_build_output

# 5. Build JUST the main compiler binary first
echo "Building the base ARM compiler..."
make tcc ONE_SOURCE=1

# 6. THE BAIT-AND-SWITCH (Now with Header Injection!)
echo "Swapping ARM binary with QEMU wrapper script..."
mv tcc tcc_real.bin

export ARM_SYS_PATH="/usr/aarch64-linux-gnu"
cat > tcc << EOF
#!/bin/sh
# Route via QEMU AND force it to use the ARM cross-compiler headers
exec qemu-aarch64-static -L "$ARM_SYS_PATH" "\$(dirname "\$0")/tcc_real.bin" -I"$ARM_SYS_PATH/include" "\$@"
EOF
chmod +x tcc

# 7. Build the Libraries
echo "Building libtcc1.a using the proxy..."
echo "Manually building libtcc1.a for aarch64 using cross-gcc..."

cd lib
rm -f *.o libtcc1.a

# Compile generic + target-specific parts (adjust file list based on ls *.c *.S in lib/)
aarch64-linux-gnu-gcc -c -O2 -Wall libtcc1.c -o libtcc1.o
# If present (runtime helpers)
[ -f alloca.c ] && aarch64-linux-gnu-gcc -c alloca.c -o alloca.o
[ -f arm64.c ] && aarch64-linux-gnu-gcc -c arm64.c -o arm64.o     # or bt-arm64.c, etc.
[ -f arm64-link.c ] && aarch64-linux-gnu-gcc -c arm64-link.c -o arm64-link.o

# Add any other .c/.S files that exist for arm64 (check your lib/ dir)
# Common ones: lib-arm64.c, bt-arm64.c, etc. — compile them similarly

# Archive (include all .o you built)
aarch64-linux-gnu-ar rcs ../libtcc1.a *.o
cd ..

# Make install will pick it up
make install


# 9. Verification Test
echo "Verifying with ARM64 Linking Test..."
TEST_DIR="tcc_arm_test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/test_lib.c" << 'EOF'
int add(int a, int b) { return a + b; }
EOF

cat > "$TEST_DIR/main.c" << 'EOF'
#include <stdio.h>
extern int add(int a, int b);
int main() {
    int res = add(900, 99);
    printf("\n--- ARM64 CROSS-BUILD SUCCESS ---\n");
    printf("Result from emulated TCC-built binary: %d\n", res);
    return (res == 999) ? 0 : 1;
}
EOF

TCC_FINAL="./arm_build_output/bin/tcc"
aarch64-linux-gnu-gcc -shared -fPIC -o "$TEST_DIR/libtest.so" "$TEST_DIR/test_lib.c"

qemu-aarch64-static -L "$ARM_SYS_PATH" "$TCC_FINAL" \
    -I "$ARM_SYS_PATH/include" \
    -L "$TEST_DIR" \
    -ltest \
    "$TEST_DIR/main.c" \
    -o "$TEST_DIR/arm_final_test"

export LD_LIBRARY_PATH="$TEST_DIR:$ARM_SYS_PATH/lib"
qemu-aarch64-static -L "$ARM_SYS_PATH" "$TEST_DIR/arm_final_test"

echo "------------------------------------------------"
echo "Build and test completed successfully."