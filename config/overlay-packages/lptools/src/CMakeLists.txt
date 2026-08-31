cmake_minimum_required(VERSION 3.10)
project(lptools)

set(CMAKE_CXX_STANDARD 20)

# Add include directories from android-tools
include_directories(
    ${TERMUX_PREFIX}/include/android-tools/base
    ${TERMUX_PREFIX}/include/android-tools/lp
    ${TERMUX_PREFIX}/include/android-tools/sparse
    ${TERMUX_PREFIX}/include/android-tools/log
    ${TERMUX_PREFIX}/include/android-tools/crypto_utils
    ${TERMUX_PREFIX}/include/android-tools/cutils
    ${TERMUX_PREFIX}/include/android-tools/utils
    ${TERMUX_PREFIX}/include/android-tools/ext4_utils
)

add_executable(lptools lptools.cc)

# Link against android-tools static libraries
target_link_libraries(lptools
    -L${TERMUX_PREFIX}/lib
    android-lp
    android-sparse
    android-base
    android-log
    android-crypto_utils
    android-cutils
    android-utils
    android-ext4_utils
    z
)

install(TARGETS lptools DESTINATION bin)
