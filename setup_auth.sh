#!/bin/bash

if ! command -v htpasswd &> /dev/null; then
  echo "htpasswd command not found, installing apache2-utils..."
  sudo apt update
  sudo apt install -y apache2-utils || {
    echo "Error: Failed to install apache2-utils. Cannot create .htpasswd file."
    exit 1
  }
else
  echo "htpasswd is already installed."
fi

AUTH_DIR="./auth_files"
HTPASSWD_FILE="$AUTH_DIR/.htpasswd"
DEFAULT_USER="admin"

mkdir -p "$AUTH_DIR"

if [ -z "$SQL_PASSWORD" ]; then
  echo "Error: The SQL_PASSWORD variable is required in your .env file to set up Nginx Basic Auth."
  exit 1
fi

echo "Generating Nginx Basic Auth password file for user '$DEFAULT_USER'..."

echo "$DEFAULT_USER:$(openssl passwd -stdin -n -salt $(openssl rand -base64 8) <<< "$SQL_PASSWORD")" > "$HTPASSWD_FILE"

if [ -f "$HTPASSWD_FILE" ]; then
  echo "✅ Nginx password file created successfully at $HTPASSWD_FILE"
else
  echo "❌ Failed to create password file."
  exit 1
fi