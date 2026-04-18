#!/bin/bash

# This script stops and removes all Docker containers, and then
# removes all Docker images.
# USE WITH EXTREME CAUTION IN PRODUCTION ENVIRONMENTS!
# This script will permanently delete all your Docker containers and images.

echo "---------------------------------------------------------"
echo "         Docker Cleanup Script"
echo "---------------------------------------------------------"
echo "WARNING: This script will delete ALL Docker containers and images."
echo "         Ensure you have backed up any necessary data."
echo "---------------------------------------------------------"

# Function to check if a command exists
command_exists () {
  type "$1" &> /dev/null ;
}

# --- Pre-checks ---
if ! command_exists docker; then
    echo "Error: Docker command not found. Please ensure Docker is installed and in your PATH."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running or you do not have permission to access it."
    echo "       Please start Docker or check your user's permissions (e.g., add user to 'docker' group)."
    exit 1
fi

echo "--- Step 1: Stopping and Removing All Running Containers ---"

# Get a list of all running container IDs
RUNNING_CONTAINERS=$(docker ps -aq)

if [ -z "$RUNNING_CONTAINERS" ]; then
    echo "No running Docker containers found."
else
    echo "The following containers are currently running or stopped:"
    docker ps -a --format "{{.ID}}\t{{.Names}}\t{{.Status}}"

    read -p "Are you sure you want to STOP and REMOVE ALL Docker containers listed above? (Y/n):" -n 1 -r REPLY_CONTAINERS
    echo # (optional) move to a new line
    if [[ $REPLY_CONTAINERS =~ ^[Nn]$ ]]; then
        echo "Skipping container removal."
    else
        echo "Stopping all running containers..."
        docker stop $(docker ps -aq)
        if [ $? -eq 0 ]; then
            echo "All running containers stopped successfully."
        else
            echo "Warning: Some containers might not have stopped successfully."
        fi

        echo "Removing all containers..."
        docker rm $(docker ps -aq)
        if [ $? -eq 0 ]; then
            echo "All containers removed successfully."
        else
            echo "Warning: Some containers might not have been removed successfully."
        fi
    fi
fi

echo "---------------------------------------------------------"
echo "--- Step 2: Removing All Docker Images ---"

# Get a list of all image IDs
ALL_IMAGES=$(docker images -aq)

if [ -z "$ALL_IMAGES" ]; then
    echo "No Docker images found."
else
    echo "The following Docker images will be removed:"
    docker images --format "{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}"

    read -p "Are you sure you want to REMOVE ALL Docker images listed above? (Y/n):" -n 1 -r REPLY_IMAGES
    echo # (optional) move to a new line
    if [[ $REPLY_IMAGES =~ ^[Nn]$ ]]; then
        echo "Skipping image removal."
    else
        echo "Removing all images..."
        # Use -f (force) to ensure removal even if tags are shared or images are dangling
        docker rmi -f $(docker images -aq)
        if [ $? -eq 0 ]; then
            echo "All Docker images removed successfully."
        else
            echo "Warning: Some images might not have been removed successfully."
        fi
    fi
fi

echo "---------------------------------------------------------"
echo "--- Step 3: Pruning Docker System (Optional) ---"
echo "This will remove all unused Docker objects (containers, images, volumes, networks)."
echo "This is generally safer as it only removes truly unused/dangling items."
read -p "Do you want to run 'docker system prune -a' to remove all unused Docker data? (Y/n): " -n 1 -r REPLY_PRUNE
echo # (optional) move to a new line
if [[ $REPLY_PRUNE =~ ^[Nn]$ ]]; then
    echo "Skipping 'docker system prune'."
else
    echo "Running 'docker system prune -a'..."
    docker system prune -a --volumes
    echo "Docker system pruned."
fi

echo "---------------------------------------------------------"
echo "Docker cleanup script finished."
echo "You can verify the state by running 'docker ps -a' and 'docker images'."
echo "---------------------------------------------------------"