#!/bin/sh

# This script automates the testing of TCC's linking capabilities.
# It builds TCC, creates a test library and executable, and then
# attempts to compile and link them with TCC.

# Exit on error
set -e

# 1. Build TCC
echo "Building TCC..."
./configure
make

# 2. Create test directory
echo "Creating test directory..."
rm -rf tcc_link_test
mkdir tcc_link_test

# 3. Create test files
echo "Creating test files..."

cat > tcc_link_test/test_lib.h <<EOF
#ifndef TEST_LIB_H
#define TEST_LIB_H

int add(int a, int b);

#endif // TEST_LIB_H
EOF

cat > tcc_link_test/test_lib.c <<EOF
#include "test_lib.h"

int add(int a, int b) {
    return a + b;
}
EOF

cat > tcc_link_test/main.c <<EOF
#include <stdio.h>
#include "test_lib.h"

int main() {
    int result = add(2, 3);
    printf("Result: %d", result);
    if (result == 5) {
        printf("Test passed!");
        return 0;
    } else {
        printf("Test failed!");
        return 1;
    }
}
EOF

# 4. Compile libraries with GCC
echo "Compiling libraries with GCC..."
gcc -shared -fPIC -o tcc_link_test/libtest.so tcc_link_test/test_lib.c
gcc -c -fPIC -o tcc_link_test/test_lib.o tcc_link_test/test_lib.c
ar rcs tcc_link_test/libtest.a tcc_link_test/test_lib.o

# 5. Run TCC and capture output
echo "Running TCC and capturing output..."
./tcc -vv -B. -Iinclude -L tcc_link_test -ltest tcc_link_test/main.c -o tcc_link_test/main > tcc_link_test/tcc_output.log 2>&1 || true

echo "TCC command finished. Output logged to tcc_output.log"

# 6. Attempt to run the executable if it was created
if [ -f tcc_link_test/main ]; then
    echo "Attempting to run the TCC-compiled executable..."
    LD_LIBRARY_PATH=tcc_link_test ./tcc_link_test/main
else
    echo "TCC failed to create the executable."
fi

echo "Workflow complete."