#!/bin/bash

# Removes all unused Docker volumes

unused_vols=$(docker volume ls -qf dangling=true)
if [ -z "$unused_vols" ]; then
  echo "No unused volumes to remove."
else
  echo "Removing unused volumes..."
  docker volume rm $unused_vols
fi 