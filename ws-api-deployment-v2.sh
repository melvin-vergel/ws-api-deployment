#!/bin/bash

# Path to the .env file
ENV_FILE="./.env"

# Check if the .env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file $ENV_FILE not found. Please create it with the required variables."
  exit 1
fi

set -o allexport
source "$ENV_FILE"
set +o allexport

# Ensure required environment variables are set
if [ -z "$DEFAULT_EMAIL" ] || [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ] || \
   [ -z "$REPO_URL_API" ] || [ -z "$REPO_BRANCH_API" ] || [ -z "$VIRTUAL_HOST_API" ] || [ -z "$LETSENCRYPT_HOST_API" ] || \
   [ -z "$REPO_URL_SITE" ] || [ -z "$REPO_BRANCH_SITE" ] || [ -z "$VIRTUAL_HOST_SITE" ] || [ -z "$LETSENCRYPT_HOST_SITE" ] || \
   [ -z "$TOKEN" ] || [ -z "$WS_VERSION" ] || [ -z "$TZ" ] || [ -z "$API_URL" ] || [ -z "$APPLY_EXCEL_LINK" ]; then
  echo "One or more required environment variables are missing in $ENV_FILE."
  echo "Please ensure all required variables are set."
  exit 1
fi

# -----------------------------------------------------------------------------
# SYSTEM & DOCKER SETUP
# -----------------------------------------------------------------------------

# Update the system
sudo apt update

# Check if Docker is installed, and install if it is not
if ! command -v docker &> /dev/null; then
  echo "Docker not found, installing..."
  sudo apt install -y docker.io
  sudo systemctl start docker
  sudo systemctl enable docker
else
  echo "Docker is already installed."
fi

# -----------------------------------------------------------------------------
# REPOSITORY MANAGEMENT
# -----------------------------------------------------------------------------

# Function to clone or pull a Git repository
manage_repo() {
  local repo_url=$1
  local repo_dir=$2
  local repo_branch=$3
  # Injects both username and token for authentication
  local authenticated_repo_url=$(echo "$repo_url" | sed "s|://|://$GITHUB_USER:$GITHUB_TOKEN@|")

  echo "--- Managing repository: $repo_dir ---"
  if [ -d "$repo_dir" ]; then
    echo "Directory found. Pulling latest changes from branch '$repo_branch'..."
    (cd "$repo_dir" && git reset --hard && git clean -fd && git pull "$authenticated_repo_url" "$repo_branch") || {
      echo "Error: Failed to pull repository $repo_dir. Check connection, credentials, and branch name."
      exit 1
    }
  else
    echo "Cloning repository from branch '$repo_branch'..."
    git clone -b "$repo_branch" "$authenticated_repo_url" "$repo_dir" || {
      echo "Error: Failed to clone repository. Check URL, credentials, and branch name."
      exit 1
    }
  fi
}

# Clone or pull both repositories
manage_repo "$REPO_URL_API" "whatsapp-api" "$REPO_BRANCH_API"
manage_repo "$REPO_URL_SITE" "ws-site" "$REPO_BRANCH_SITE"

# -----------------------------------------------------------------------------
# DOCKER VOLUME & CONTAINER UTILITIES
# -----------------------------------------------------------------------------

# Function to create a Docker volume if it doesn't exist
create_volume_if_missing() {
  if ! docker volume inspect "$1" > /dev/null 2>&1; then
    echo "Creating Docker volume: $1"
    docker volume create "$1"
  else
    echo "Docker volume $1 already exists."
  fi
}

# Function to stop and remove a Docker container if it exists
remove_container_if_exists() {
  if [ "$(docker ps -q -f name=$1)" ]; then
    echo "Stopping and removing existing container: $1"
    docker stop "$1"
    docker rm "$1"
  fi
}

# -----------------------------------------------------------------------------
# DOCKER SETUP
# -----------------------------------------------------------------------------

# Ensure Docker volumes are created
echo "--- Ensuring Docker volumes exist ---"
create_volume_if_missing html
create_volume_if_missing certs
create_volume_if_missing acme
create_volume_if_missing ws-db-api # Volume for the API data

# Run nginx-proxy and acme-companion containers (shared for all services)
echo "--- Setting up proxy and SSL containers ---"
remove_container_if_exists nginx-proxy
docker run -d \
  --name nginx-proxy --restart unless-stopped \
  -p 80:80 -p 443:443 \
  -v html:/usr/share/nginx/html \
  -v certs:/etc/nginx/certs:ro \
  -v /var/run/docker.sock:/tmp/docker.sock:ro \
   -v ./custom_proxy.conf:/etc/nginx/conf.d/custom_proxy.conf:rw \
  --network bridge \
  nginxproxy/nginx-proxy

remove_container_if_exists nginx-proxy-acme
docker run -d \
  --name nginx-proxy-acme --restart unless-stopped \
  --env DEFAULT_EMAIL="$DEFAULT_EMAIL" \
  --volumes-from nginx-proxy \
  -v certs:/etc/nginx/certs:rw -v acme:/etc/acme.sh \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --network bridge \
  nginxproxy/acme-companion

# -----------------------------------------------------------------------------
# ws-api SERVICE
# -----------------------------------------------------------------------------

echo "--- Building and deploying ws-api ---"
docker build -t ws-api -f ./whatsapp-api/Dockerfile ./whatsapp-api

remove_container_if_exists ws-api
docker run -d \
  --name ws-api --restart unless-stopped \
  --cpus=0.9 --memory=900m \
  --env VIRTUAL_HOST="$VIRTUAL_HOST_API" \
  --env LETSENCRYPT_HOST="$LETSENCRYPT_HOST_API" \
  --env NODE_ENV=production \
  --env TOKEN="$TOKEN" \
  --env TZ="$TZ" \
  --env PORT=80 \
  --env WHATSAPP_VERSION="$WS_VERSION" \
  --env VALID_ORIGIN="https://$VIRTUAL_HOST_SITE" \
  --env CRON_MORNING="$CRON_MORNING" \
  --env CRON_DAY="$CRON_DAY" \
  --env CRON_EVENING="$CRON_EVENING" \
  --env CLIENT_MAX_BODY_SIZE="50m" \
  --expose 80 \
  -v ws-db-api:/app/persist \
  --network bridge \
  ws-api

# -----------------------------------------------------------------------------
# ws-site SERVICE
# -----------------------------------------------------------------------------

echo "--- Building and deploying ws-site ---"
# Assumes the Dockerfile for the site is in the root of its repository
docker build -t ws-site -f ./ws-site/Dockerfile ./ws-site

remove_container_if_exists ws-site
docker run -d \
  --name ws-site --restart unless-stopped \
  --cpus=0.5 --memory=500m \
  --env VIRTUAL_HOST="$VIRTUAL_HOST_SITE" \
  --env LETSENCRYPT_HOST="$LETSENCRYPT_HOST_SITE" \
  --env NODE_ENV=production \
  --env TZ="$TZ" \
  --env API_URL="$API_URL" \
  --env APPLY_EXCEL_LINK="$APPLY_EXCEL_LINK" \
  --expose 80 \
  --network bridge \
  ws-site


echo "Adding Portainer Agent"
remove_container_if_exists portainer_agent
docker run -d \
  -p 9001:9001 \
  --name portainer_agent \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /:/host \
  portainer/agent:2.27.3

echo "Adding sqlite-web (coleifer/sqlite-web)"
remove_container_if_exists sqlite_web
docker run -d \
  --name sqlite_web \
  --restart unless-stopped \
  -e VIRTUAL_HOST="$VIRTUAL_HOST_SQL" \
  -e LETSENCRYPT_HOST="$VIRTUAL_HOST_SQL" \
  -e SQLITE_WEB_PASSWORD="$SQL_PASSWORD" \
  -e TZ="$TZ" \
  -e SQLITE_DATABASE="database.sqllite" \
  -v ws-db-api:/data \
  --network bridge \
  coleifer/sqlite-web
# -----------------------------------------------------------------------------
# FINAL NOTIFICATION
# -----------------------------------------------------------------------------

echo "✅ Docker containers for ws-api and ws-site have been set up successfully."