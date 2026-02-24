#!/bin/bash

# Define the content to be added
content='export INFINI_ROOT="$HOME/.infini"
export LD_LIBRARY_PATH="$INFINI_ROOT/lib:$LD_LIBRARY_PATH"'

# Check if bashrc file exists
bashrc_file="$HOME/.bashrc"

if [ ! -f "$bashrc_file" ]; then
    echo "Creating $bashrc_file file"
    touch "$bashrc_file"
fi

# Check if the content already exists
if grep -q "export INFINI_ROOT=" "$bashrc_file"; then
    echo "INFINI_ROOT configuration already exists in $bashrc_file"
else
    echo "Adding configuration to $bashrc_file"
    echo "$content" >> "$bashrc_file"
    echo "Configuration added successfully"
fi

# Reload bashrc
echo "Reloading $bashrc_file"
source "$bashrc_file"

echo "Done! INFINI_ROOT and LD_LIBRARY_PATH have been set"
