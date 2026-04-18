#!/bin/bash

# Health check script for Docker containers
# Monitors container health status and restarts unhealthy containers

echo "---------------------------------------------------------"
echo "         Docker Container Health Check"
echo "---------------------------------------------------------"

# Function to check if a command exists
command_exists() {
  type "$1" &> /dev/null
}

# Pre-checks
if ! command_exists docker; then
    echo "Error: Docker command not found."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running."
    exit 1
fi

echo "Checking container health status..."
echo ""

# Get all containers with their health status
CONTAINERS=$(docker ps --format "{{.ID}}|{{.Names}}|{{.Status}}")

if [ -z "$CONTAINERS" ]; then
    echo "No running containers found."
    exit 0
fi

UNHEALTHY_COUNT=0
HEALTHY_COUNT=0

echo "Container Health Report:"
echo "========================"

while IFS='|' read -r ID NAME STATUS; do
    # Check if container is unhealthy
    if [[ "$STATUS" == *"unhealthy"* ]]; then
        echo "❌ UNHEALTHY: $NAME (ID: $ID)"
        echo "   Status: $STATUS"
        ((UNHEALTHY_COUNT++))
        
        # Auto-restart unhealthy containers in production
        echo "   Restarting container..."
        docker restart "$ID"
        if [ $? -eq 0 ]; then
            echo "   ✅ Container restarted successfully"
        else
            echo "   ⚠️  Failed to restart container"
        fi
        echo ""
    elif [[ "$STATUS" == *"healthy"* ]] || [[ "$STATUS" == *"Up"* ]]; then
        echo "✅ HEALTHY: $NAME"
        ((HEALTHY_COUNT++))
    else
        echo "⚠️  UNKNOWN: $NAME - Status: $STATUS"
    fi
done <<< "$CONTAINERS"

echo ""
echo "Summary:"
echo "--------"
echo "Healthy containers: $HEALTHY_COUNT"
echo "Unhealthy containers: $UNHEALTHY_COUNT"
echo "---------------------------------------------------------"

exit 0
