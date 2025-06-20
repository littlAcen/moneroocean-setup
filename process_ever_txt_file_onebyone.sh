#!/bin/bash

# Loop through all .txt files in the current directory
for txt_file in *.txt; do
    # Skip if no .txt files are found
    [[ -e "$txt_file" ]] || continue
    
    echo "Processing file: $txt_file"
    
    # Execute the Python command with the current .txt file
#    python3 "LATEST_ssh25_mitohnealles_WORKING_currently_checked_host_is_shown_port_22_is_always_checked_ssh_format_readable_no_checked_host_file_W0RKING_SERVERS_ARE_REMOVED_WORKING_COPY_flatten_opt_rich_gemini!!!.py" \
     python3 LATEST-TO_USE_ssh25_09-06-25.py \
        -f "$txt_file" \
        -p ssh \
        -t 55
    
    # Wait for the command to finish before proceeding
    wait
    echo "Finished processing: $txt_file"
    echo "---------------------------------"
done

echo "All files processed!"

