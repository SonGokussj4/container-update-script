# container-update-script (cups)

Check for image updates for running containers using 'cup'

## Description

This script is using the [cup](https://sergi0g.github.io/cup/docs/installation/binary) tool to check for any updates for existing images.
But it will only check for images that are currently running as containers with `docker compose` and update them if necessary.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed with `docker compose` support
- [jq](https://stedolan.github.io/jq/download/) installed
- [cup](https://sergi0g.github.io/cup/docs/installation/binary) installed

## Install for local user

```bash
# Clone the repository
git clone https://github.com/SonGokussj4/container-update-script

# Create a bin directory in your home directory
mkdir -p ~/bin

# Create a symbolic link to the script
ln -s $(pwd)/cups.sh ~/bin/cups
```

## Usage

```bash
# Check for updates, pull new images and deploy them (tags latest, release, stable by default)
cups

# Only check for updates
cups --check

# Specify tags to check for updates
cups --tags latest,develop,1.52.666

# Specify services to check for updates
cups --services immich,plex

# Combine
cups --check --tags latest,develop,1.52.666 --services immich,plex
```

## Example

```bash
$ cups --help
Usage: update_containers [options]

Options:
  --tags <tags>       Specify tags to filter (comma-separated, e.g., 'latest,release,stable').
  --services <names>  Specify services to update (comma-separated, e.g., 'deluge,radarr').
  --check             Check for available updates without performing any actions.
  --help              Display this help message.

$ cups --check
✓ Done!
deluan/navidrome:latest                                         Update available
ghcr.io/homarr-labs/homarr:beta                                 Update available
stonith404/pingvin-share:latest                                 Update available


$ cups --tags latest --services pingvin-share
✓ Done!
------------------------------------------------------------------------------------
IMAGE: stonith404/pingvin-share:latest --> pingvin-share
PROJECT: pingvin-share /var/services/homes/xxx/docker/pingvin-share/docker-compose.yaml
Updating service 'pingvin-share' in project 'pingvin-share'...
[+] Pulling 20/20
   ✔ pingvin-share 19 layers [⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿]      0B/0B      Pulled                                 308.7s
   ✔ 38a8310d387e Already exists                                                                                   0.0s
   ✔ 65052e355180 Already exists                                                                                   0.0s
   ...
   ✔ 9665cb010f1a Pull complete                                                                                    5.6s
   ✔ f268f8ab24c2 Pull complete                                                                                    6.9s
[+] Running 1/1
 ✔ Container pingvin-share-pingvin-share-1  Started                                                              224.6s
```
