#!/bin/bash

set -e

# Path to the .htpasswd file inside the shared directory
AUTH_DIR="./auth_files"
HTPASSWD_FILE="$AUTH_DIR/.htpasswd"
USERNAME="admin"

# Check if the environment variable is set
if [ -z "$SQL_PASSWORD" ]; then
  echo "Error: SQL_PASSWORD environment variable is not set."
  exit 1
fi

# Check if htpasswd utility is installed and install if necessary
if ! command -v htpasswd &> /dev/null; then
  echo "htpasswd utility not found. Installing apache2-utils..."
  sudo apt update
  sudo apt install -y apache2-utils
fi

# Create the authentication directory if it doesn't exist
mkdir -p "$AUTH_DIR"

echo "Generating Nginx Basic Auth password file for user '$USERNAME'..."

# Use printf to pipe the raw password to htpasswd for secure hash generation.
# -B: Use bcrypt algorithm (recommended)
# -c: Create the file (since we are creating it fresh each time)
# -s: Use SHA-1 (if -B fails, this is a common fallback)
# Note: When piping the password, the password is read from STDIN, not the command line arguments.
printf '%s' "$SQL_PASSWORD" | htpasswd -Bcs "$HTPASSWD_FILE" "$USERNAME"

echo "✅ Nginx password file created successfully at $HTPASSWD_FILE."