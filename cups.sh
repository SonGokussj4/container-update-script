#!/bin/bash

# Default tags and services for filtering
DEFAULT_TAGS="latest|release|stable"
SPECIFIC_SERVICES=""

# File to store the output of 'cup check' command
INPUT_FILE="/tmp/results.txt"

# Function to check if a command exists
check_for_command() {
    local cmd=$1
    local url=$2
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' command not found. Please install it from $url"
        exit 1
    fi
}

# Function to display help
show_help() {
    cat << EOF
Usage: update_containers [options]

Options:
  --tags <tags>       Specify tags to filter (comma-separated, e.g., 'latest,release,stable').
  --services <names>  Specify services to update (comma-separated, e.g., 'deluge,radarr').
  --check             Check for available updates without performing any actions.
  --help              Display this help message.
EOF
    exit 0
}

# Parse arguments
TAGS="$DEFAULT_TAGS"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --tags)
            TAGS="${2//,/|}"
            shift 2
            ;;
        --services)
            SPECIFIC_SERVICES=${2//,/ }
            shift 2
            ;;
        --check)
            check_for_command "cup" "https://sergi0g.github.io/cup/docs/installation/binary"
            cup check > "$INPUT_FILE"
            grep 'Update available' "$INPUT_FILE"
            exit 0
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Check for required commands
check_for_command "cup" "https://sergi0g.github.io/cup/docs/installation/binary"
check_for_command "jq" "https://jqlang.github.io/jq/download/"

# Run the 'cup check' command and save the output to a file for further processing
cup check > "$INPUT_FILE"

# Filter lines that match the specified criteria
mapfile -t update_lines < <(grep 'Update available' "$INPUT_FILE" | grep -E "$TAGS")

# Get a list of all Docker Compose projects and their directories
mapfile -t compose_projects < <(docker compose ls --format json | jq -r '.[] | "\(.Name) \(.ConfigFiles)"')

# Flag to indicate if any updates were performed
updated_any=false

# Iterate over the list of Docker Compose projects
for line in "${update_lines[@]}"; do
    # Extract the image name (e.g., apache/tika:latest)
    image=$(echo "$line" | awk '{print $1}')

    # Extract the service name from the image (e.g., tika for apache/tika:latest)
    service_name=$(basename "$(echo "$image" | cut -d':' -f1)")

    # Skip if specific services are defined and this service is not in the list
    if [[ -n "$SPECIFIC_SERVICES" ]] && ! [[ " $SPECIFIC_SERVICES " =~ " $service_name " ]]; then
        continue
    fi

    echo "------------------------------------------------------------------------------------"
    echo "IMAGE: $image --> $service_name"

    # Find the corresponding Docker Compose project
    for project in "${compose_projects[@]}"; do
        project_name=$(echo "$project" | awk '{print $1}')
        compose_file=$(echo "$project" | awk '{print $2}')
        project_dir=$(dirname "$compose_file")

        # Check if the service is part of this project
        if grep -q "$service_name" "$compose_file"; then
            echo "PROJECT: $project"
            echo "Updating service '$service_name' in project '$project_name'..."

            # Navigate to the project directory
            cd "$project_dir" || continue

            # Pull the latest image
            docker compose pull

            # Recreate and start the service
            docker compose up -d

            # Navigate back to the original directory
            cd - || exit

            updated_any=true
        fi
    done

    echo "------------------------------------------------------------------------------------"

    # Check if any updates were performed
    if ! $updated_any; then
        echo "No updates were performed."
        if grep -q 'Update available' "$INPUT_FILE"; then
            echo "Here's the list of all 'Update available' items:"
            grep 'Update available' "$INPUT_FILE"
        else
            echo "And no updates available at the moment."
        fi
    fi

done
