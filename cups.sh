#!/bin/bash

# Global Variables:
# -----------------
# g_running_compose_projects: Array to hold Docker Compose projects
# g_update_lines: Array to hold lines from the 'cup check' output
# -----------------

# Set the script to exit on any error
set -eou pipefail

# Debug options
VERBOSE=0
DEBUG=1

# Set VERBOSE to 1 to enable debug mode
if [ "$VERBOSE" -eq 1 ]; then
    set -x
fi


# File to store the output of 'cup check' command
INPUT_FILE="/tmp/results.txt"

# Global array for update image names.
# We'll use this to store the list of images for which an update is available.
declare -ag g_update_images

# Global array for Docker Compose projects.
# Each element will hold a line with the project name and the path to its compose file.
declare -ag g_running_compose_projects


# -----------------------------------------------------------------------------
# Function: show_help
# -----------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: cups [options]

Options:
  --check             Only check for updates and display them
  --help              Display this help message.
EOF
    exit 0
}

# -----------------------------------------------------------------------------
# Function: check_for_command
# -----------------------------------------------------------------------------
# This function checks if a command is available in the system.
# If not, it prints an error message and exits the script.
# Arguments:
#   $1: Command name to check
#   $2: URL to the installation instructions or download page
# -----------------------------------------------------------------------------
check_for_command() {
    local cmd=$1
    local url=$2

    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' command not found. Please install it from $url"
        exit 1
    fi

    return 0
}

get_update_images() {
    g_update_images=()

    # Extract update images using jq
    while IFS= read -r image; do
        g_update_images+=("$image")
    done < <(jq -r '.images[] | select(.result.has_update == true) | .reference' "$INPUT_FILE")
    # jq -r '.images[] | select(.result.has_update == true) | [.reference, .result.info.current_version, .result.info.new_version] | join("\t")'

    if [ "$DEBUG" -eq 1 ]; then
        # Print extracted images (for debugging purposes)
        echo "[ DEBUG ] Extracted update images:"
        echo "[ DEBUG ] ============================================================"
        for img in "${g_update_images[@]}"; do
            echo "[ DEBUG ] $img"
        done
    fi
}

# -----------------------------------------------------------------------------
# Function: get_compose_projects
# -----------------------------------------------------------------------------
# This function retrieves the list of Docker Compose projects.
# It uses 'docker compose ls --format json' for structured output and jq to parse it.
# Each project is stored as a string with the project name and its associated compose file.
# -----------------------------------------------------------------------------
get_compose_projects() {
    if ! mapfile -t g_running_compose_projects < <(docker compose ls --format json | jq -r '.[] | "\(.Name) \(.ConfigFiles)"'); then
        echo "Error: Failed to get Docker Compose projects list"
        exit 1
    fi

    if [ ${#g_running_compose_projects[@]} -eq 0 ]; then
        echo "Warning: No Docker Compose projects found"
        exit 1
    fi

    # Print the list of projects (for debugging purposes)
    for project in "${g_running_compose_projects[@]}"; do
        echo "$project"
    done
}


# -----------------------------------------------------------------------------
# Function: build_regex_pattern
# -----------------------------------------------------------------------------
# This function takes the global g_update_images array and builds a single
# regular expression pattern (joined by |) that can be used by grep to test for
# any of the images in one pass.
# -----------------------------------------------------------------------------
build_regex_pattern() {
    local pattern=""
    for image in "${g_update_images[@]}"; do
        # Remove the version (everything after the colon)
        base_image=$(echo "$image" | cut -d':' -f1)
        # Escape regex-special characters in the base image name
        base_image_escaped=$(printf '%s\n' "$base_image" | sed -e 's/[][\/.^$*+?{}|()]/\\&/g')
        pattern+="${base_image_escaped}|"
    done
    # Remove the trailing '|'
    pattern=${pattern%|}
    echo "$pattern"
}



# -----------------------------------------------------------------------------
# Function: update_service
# -----------------------------------------------------------------------------
# Given a project path, this function changes to that directory and updates
# the Docker Compose service by pulling and starting it.
# -----------------------------------------------------------------------------
update_service() {
    local project_path="$1"
    echo "Updating service in: $project_path"
    pushd "$project_path" >/dev/null || { echo "Failed to change directory to $project_path"; return 1; }
    docker compose pull
    docker compose up -d
    popd >/dev/null
}

# -----------------------------------------------------------------------------
# Function: get_max_project_length
# -----------------------------------------------------------------------------
# This function calculates the maximum length of project names in the
# g_running_compose_projects array. It returns the maximum length.
# -----------------------------------------------------------------------------
get_max_project_length() {
    local length=0
    local max=0

    for project in "${g_running_compose_projects[@]}"; do
        project_name=$(echo "$project" | awk '{print $1}')
        length=${#project_name}
        if (( length > max )); then
            max=$length
        fi
    done

    echo "$max"
}

# -----------------------------------------------------------------------------
# Main execution block
# -----------------------------------------------------------------------------
main() {
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --check)
                check_for_command "cup" "https://sergi0g.github.io/cup/docs/installation/binary"
                cup check > "$INPUT_FILE"
                grep -E 'Update available|Patch update|Minor update|Major update' "$INPUT_FILE"
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
    cup check -r > "$INPUT_FILE"

    if [ ! -f "$INPUT_FILE" ]; then
        echo "Error: Update input file '$INPUT_FILE' not found."
        exit 1
    fi

    # Step 1: Parse the update file.
    get_update_images
    if [ ${#g_update_images[@]} -eq 0 ]; then
        echo "No update images found in input file."
        exit 0
    fi

    # Build regex from update images.
    regex_pattern=$(build_regex_pattern)

    # Step 2: Get Docker Compose projects.
    get_compose_projects

    # Declare associative array for available updates (project_name -> project_dir)
    declare -A available_updates
    # Also, an indexed array to preserve ordering.
    declare -a available_update_keys=()

    # For printing the table, get the max length of project names.
    longest_project_length=$(get_max_project_length)

    printf "%-${longest_project_length}s %-20s\n" "Project" "Message"
    printf "%-${longest_project_length}s %-20s\n" $(printf '%*s' "$longest_project_length" | tr ' ' '-') $(printf '%*s' "60" | tr ' ' '-')

    # Check each Docker Compose project.
    for project in "${g_running_compose_projects[@]}"; do
        # Expecting: "project_name compose_file_path"
        project_name=$(echo "$project" | awk '{print $1}')
        compose_file=$(echo "$project" | awk '{print $2}')
        project_dir=$(dirname "$compose_file")

        if [ ! -f "$compose_file" ]; then
            echo "Error: Docker Compose file '$compose_file' not found for project '$project_name'."
            continue
        fi

        # Use grep to search the compose file for any update images.
        if grep -qE "image:\s*.*($regex_pattern)" "$compose_file"; then
            printf "%-${longest_project_length}s %-20s\n" "🔴 $project_name" "Update Available"
            available_updates["$project_name"]="$project_dir"
            available_update_keys+=("$project_name")
        else
            printf "%-${longest_project_length}s %-20s\n" "🟢 $project_name" "Ok"
        fi
    done

    if [ ${#available_update_keys[@]} -eq 0 ]; then
        echo "No Docker Compose projects with available updates."
        exit 0
    fi

    echo
    echo "List of projects with available updates:"

    id_width=4
    proj_width=$longest_project_length
    path_width=60

    # Print table header
    printf "\n%-${id_width}s %-${proj_width}s %-${path_width}s\n" "ID" "Project" "Path"
    printf "%-${id_width}s %-${proj_width}s %-${path_width}s\n" \
        "$(printf '%*s' "$id_width" | tr ' ' '-')" \
        "$(printf '%*s' "$proj_width" | tr ' ' '-')" \
        "$(printf '%*s' "$path_width" | tr ' ' '-')"

    # Print each project row.
    for idx in "${!available_update_keys[@]}"; do
        num=$((idx + 1))
        proj=${available_update_keys[$idx]}
        proj_dir=${available_updates[$proj]}
        printf "%-${id_width}s %-${proj_width}s %-${path_width}s\n" "$num" "$proj" "$proj_dir"
    done

    echo
    echo "Enter the numbers of services to update (space-separated) and press Enter:"
    read -r selection

    echo
    echo "You selected to update:"
    for num in $selection; do
        index=$((num - 1))
        if [[ $index -ge 0 && $index -lt ${#available_update_keys[@]} ]]; then
            proj=${available_update_keys[$index]}
            proj_dir=${available_updates[$proj]}
            printf "%-${proj_width}s : %s\n" "$proj" "$proj_dir"
            update_service "$proj_dir"
        else
            echo "Invalid selection: $num"
        fi
    done
}

main "$@"
