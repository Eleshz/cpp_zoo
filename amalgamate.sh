#!/bin/bash

# Usage: ./amalgamate.sh input.hpp output.hpp

INPUT_FILE=$1
OUTPUT_FILE=$2
SRC_DIR="src" # The folder where your headers live

# Remove the output file if it exists
rm -f "$OUTPUT_FILE"

# We use AWK to read files recursively
# It looks for #include "..." and pastes the file content instead
awk -v src_dir="$SRC_DIR" '
function collect_std_includes_and_pragmas(filename) {
    while ((getline line < filename) > 0) {
        # Check for standard library includes: #include <filename>
        if (match(line, /^#include <(.+)>/, arr)) {
            # Store standard includes to be printed at the top
            if (!std_includes[arr[1]]) {
                std_includes[arr[1]] = 1
                std_include_order[++std_include_count] = arr[1]
            }
        }
        # Check for pragma once
        else if (match(line, /^[[:space:]]*#[[:space:]]*pragma[[:space:]]+[[:space:]]*once[[:space:]]*$/)) {
            # Mark that we found a pragma once to include at the top
            found_pragma_once = 1
        }
        # Check for local includes: #include "filename"
        else if (match(line, /^#include "(.+)"/, arr)) {
            # Build the full path (assuming relative to src_dir)
            target_file = src_dir "/" arr[1]

            # Prevent infinite loops (basic check)
            if (seen[target_file] != 1) {
                seen[target_file] = 1
                collect_std_includes_and_pragmas(target_file)
            }
        }
    }
    close(filename)
}

function output_content(filename) {
    while ((getline line < filename) > 0) {
        # Skip standard library includes since they are already at the top
        if (match(line, /^#include <(.+)>/, arr)) {
            # Do nothing - skip this line
        }
        # Skip pragma once since it will be placed at the top
        else if (match(line, /^[[:space:]]*#[[:space:]]*pragma[[:space:]]+[[:space:]]*once[[:space:]]*$/)) {
            # Do nothing - skip this line
        }
        # Check for local includes: #include "filename"
        else if (match(line, /^#include "(.+)"/, arr)) {
            # Build the full path (assuming relative to src_dir)
            target_file = src_dir "/" arr[1]

            # Prevent infinite loops (basic check)
            if (output_seen[target_file] != 1) {
                output_seen[target_file] = 1
                print "// BEGIN INCLUDE: " arr[1] > "'"$OUTPUT_FILE"'"
                output_content(target_file)
                print "// END INCLUDE: " arr[1] > "'"$OUTPUT_FILE"'"
            }
        } else {
            # Write normal code to output
            print line > "'"$OUTPUT_FILE"'"
        }
    }
    close(filename)
}

BEGIN {
    # Extract output filename for header guard (get just the basename without path and extension)
    output_file = "'"$OUTPUT_FILE"'"
    sub(/.*\//, "", output_file)  # Remove path
    sub(/\.[^.]*$/, "", output_file)  # Remove extension
    guard = "GENERATED_" toupper(output_file)
    gsub(/[^A-Z0-9_]/, "_", guard)

    # First pass: collect all standard library includes and pragma once
    collect_std_includes_and_pragmas(ARGV[1])

    # Add header guards OR pragma once (prefer header guards as they are more compatible)
    print "#ifndef " guard > "'"$OUTPUT_FILE"'"
    print "#define " guard > "'"$OUTPUT_FILE"'"
    print "" > "'"$OUTPUT_FILE"'"

    # Alternative: if you prefer pragma once instead of header guards, uncomment below:
    # if (found_pragma_once) {
    #     print "#pragma once" > "'"$OUTPUT_FILE"'"
    #     print "" > "'"$OUTPUT_FILE"'"
    # }

    # Print all collected standard library includes at the top
    for (i = 1; i <= std_include_count; i++) {
        print "#include <" std_include_order[i] ">" > "'"$OUTPUT_FILE"'"
    }
    if (std_include_count > 0) {
        print "" > "'"$OUTPUT_FILE"'"
    }

    # Second pass: output the actual content (without std includes and pragma once)
    output_content(ARGV[1])

    print "" > "'"$OUTPUT_FILE"'"
    print "#endif // " guard > "'"$OUTPUT_FILE"'"
}
' "$INPUT_FILE"