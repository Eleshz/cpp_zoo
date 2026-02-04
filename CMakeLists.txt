cmake_minimum_required(VERSION 3.20)
project(zoo VERSION 0.1.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Determine build mode (fast or full)
option(BUILD_FULL "Enable full build mode with linting and static analysis" OFF)

# Find required packages
find_package(Threads REQUIRED)

# Include Catch2
add_subdirectory(lib/Catch2)

# Define source and header directories
set(HEADER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(TEST_DIR ${CMAKE_CURRENT_SOURCE_DIR}/test)
set(DIST_DIR ${CMAKE_CURRENT_SOURCE_DIR}/dist)
set(COMMON_HEADER ${HEADER_DIR}/common.hpp)

# Create dist directory
file(MAKE_DIRECTORY ${DIST_DIR})

# Find all header files in src directory, excluding common.hpp
file(GLOB_RECURSE HEADER_FILES "${HEADER_DIR}/*.hpp" "${HEADER_DIR}/*.h")
list(FILTER HEADER_FILES EXCLUDE REGEX "common\\.hpp$")

# Find all test files
file(GLOB TEST_FILES "${TEST_DIR}/*.cpp" "${TEST_DIR}/*.hpp")

# Custom command to generate headers in dist directory using amalgamation script
foreach(header_file ${HEADER_FILES})
    get_filename_component(header_name ${header_file} NAME)
    set(generated_header ${DIST_DIR}/${header_name})

    # Use the amalgamation script to combine all included headers into a single file
    # Run from the source directory so the script can find included files properly
    add_custom_command(
        OUTPUT ${generated_header}
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/amalgamate.sh ${CMAKE_CURRENT_SOURCE_DIR}/src/${header_name} ${generated_header}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        DEPENDS ${header_file} ${CMAKE_CURRENT_SOURCE_DIR}/amalgamate.sh
        COMMENT "Amalgamating ${header_name} using amalgamation script"
    )

    list(APPEND GENERATED_HEADERS ${generated_header})
endforeach()

# Create a custom target for header generation
add_custom_target(generate_headers ALL
    DEPENDS ${GENERATED_HEADERS}
)

# Add test executable
add_executable(test_runner ${TEST_DIR}/test.cpp)
target_link_libraries(test_runner PRIVATE Catch2::Catch2WithMain Threads::Threads)

# Include directories for test
target_include_directories(test_runner PRIVATE
    ${HEADER_DIR}
    ${DIST_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/lib/Catch2/src
)

# Compiler-specific settings for GCC
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    # Basic warning flags for both modes
    # Apply to target instead of globally to avoid third-party warnings
    target_compile_options(test_runner PRIVATE
        -Wall -Wextra -Wpedantic
    )

    if(BUILD_FULL)
        # Additional flags for full mode
        target_compile_options(test_runner PRIVATE
            -Wconversion
            -Wsign-conversion
            -Wcast-align
            -Wcast-qual
            -Wctor-dtor-privacy
            -Wdisabled-optimization
            -Wformat=2
            -Winit-self
            -Wlogical-op
            -Wmissing-declarations
            -Wmissing-include-dirs
            -Wnoexcept
            -Wold-style-cast
            -Woverloaded-virtual
            -Wredundant-decls
            -Wshadow
            -Wstrict-null-sentinel
            -Wstrict-overflow=5
            -Wswitch-default
            -Wundef
            -Wno-unused
            -Wnon-virtual-dtor
            -Wdelete-non-virtual-dtor
        )

        # Sanitizers for full mode
        target_compile_options(test_runner PRIVATE
            -fsanitize=address
            -fsanitize=undefined
            -fstack-protector-strong
        )
        target_link_libraries(test_runner PRIVATE
            -fsanitize=address
            -fsanitize=undefined
            -fstack-protector-strong
        )
    endif()
endif()

# Enable testing
enable_testing()

# Add test
add_test(NAME zoo_tests COMMAND test_runner)

# Add custom target for running tests
add_custom_target(check
    COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure
    DEPENDS test_runner
    COMMENT "Running all tests"
)

# Full mode targets (linting, static analysis)
if(BUILD_FULL)
    # Find clang-tidy if available
    find_program(CLANG_TIDY_EXE NAMES clang-tidy)
    if(CLANG_TIDY_EXE)
        # Configure clang-tidy to exclude third-party code
        set(CMAKE_CXX_CLANG_TIDY
            "${CLANG_TIDY_EXE};--warnings-as-errors=*;"
            "--extra-arg=-I${HEADER_DIR};"
            "--extra-arg=-I${DIST_DIR};"
            "--extra-arg-before=-isystem;--extra-arg-before=${CMAKE_CURRENT_SOURCE_DIR}/lib;"
            "--extra-arg-before=-isystem;--extra-arg-before=${CMAKE_CURRENT_BINARY_DIR}/_deps;"
        )
        message(STATUS "Using clang-tidy: ${CLANG_TIDY_EXE}")
    else()
        message(WARNING "clang-tidy not found, skipping")
    endif()

    # Find cppcheck if available
    find_program(CPPCHECK_EXE NAMES cppcheck)
    if(CPPCHECK_EXE)
        add_custom_target(cppcheck
            COMMAND ${CPPCHECK_EXE}
                --enable=all
                --std=c++17
                --verbose
                --xml
                --xml-version=2
                --suppress=missingIncludeSystem
                --inconclusive
                --suppress-dir=${CMAKE_CURRENT_SOURCE_DIR}/lib/*
                --suppress-dir=${CMAKE_CURRENT_BINARY_DIR}/*
                ${HEADER_DIR} ${TEST_DIR}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            COMMENT "Running cppcheck static analysis on user code only"
        )
        add_dependencies(check cppcheck)
    else()
        message(WARNING "cppcheck not found, skipping")
    endif()

    # Add a target for comprehensive checking
    add_custom_target(full_check
        COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure
        DEPENDS test_runner
        COMMENT "Running full check (tests + static analysis)"
    )

    if(CPPCHECK_EXE)
        add_dependencies(full_check cppcheck)
    endif()
endif()

# Installation rules
install(DIRECTORY ${DIST_DIR}/
    DESTINATION include/zoo
    FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp"
)

# Print build mode info
if(BUILD_FULL)
    message(STATUS "Build mode: FULL (with linting and static analysis)")
else()
    message(STATUS "Build mode: FAST (basic build and test only)")
endif()