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
function process(filename) {
    while ((getline line < filename) > 0) {
        # Check for local includes: #include "filename"
        if (match(line, /^#include "(.+)"/, arr)) {
            # Build the full path (assuming relative to src_dir)
            target_file = src_dir "/" arr[1]

            # Prevent infinite loops (basic check)
            if (seen[target_file] != 1) {
                seen[target_file] = 1
                print "// BEGIN INCLUDE: " arr[1] > "'"$OUTPUT_FILE"'"
                process(target_file)
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
    # Add header guards
    guard = "GENERATED_" toupper(ARGV[2])
    gsub(/[^A-Z0-9_]/, "_", guard)
    
    print "#ifndef " guard > "'"$OUTPUT_FILE"'"
    print "#define " guard > "'"$OUTPUT_FILE"'"
    print "" > "'"$OUTPUT_FILE"'"
    
    # Start processing the main file
    process(ARGV[1])
    
    print "" > "'"$OUTPUT_FILE"'"
    print "#endif // " guard > "'"$OUTPUT_FILE"'"
}
' "$INPUT_FILE"