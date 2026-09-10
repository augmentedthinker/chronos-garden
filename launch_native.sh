#!/bin/bash
# Launch Persistent Garden inside native Godot 4.3 engine on Linux
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Starting Persistent Garden in Godot 4.3..."
godot --path "$DIR"
