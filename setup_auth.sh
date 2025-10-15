#!/bin/bash

set -e

AUTH_DIR="./auth_files"
HTPASSWD_FILE="$AUTH_DIR/.htpasswd"
USERNAME="admin"

if [ -z "$SQL_PASSWORD" ]; then
  echo "Error: SQL_PASSWORD environment variable is not set. Please set it in your .env file."
  exit 1
fi

if ! command -v htpasswd &> /dev/null; then
  echo "htpasswd utility not found. Installing apache2-utils..."
  sudo apt update
  sudo apt install -y apache2-utils
fi

mkdir -p "$AUTH_DIR"

echo "Generating Nginx Basic Auth password file for user '$USERNAME' using environment variable..."

htpasswd -Bbc "$HTPASSWD_FILE" "$USERNAME" "$SQL_PASSWORD"

echo "✅ Nginx password file created successfully at $HTPASSWD_FILE."
