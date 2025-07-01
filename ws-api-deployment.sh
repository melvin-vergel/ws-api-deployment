#!/bin/sh

# Path to the .env file
ENV_FILE="/root/.env"

# Check if the .env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file $ENV_FILE not found. Please create it with the required variables."
  exit 1
fi

# Load environment variables from the .env file
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Ensure required environment variables are set
if [ -z "$DEFAULT_EMAIL" ] || [ -z "$VIRTUAL_HOST" ] || [ -z "$LETSENCRYPT_HOST" ] || [ -z "$TOKEN" ]; then
  echo "One or more required environment variables are missing. Please ensure $ENV_FILE contains DEFAULT_EMAIL, VIRTUAL_HOST, LETSENCRYPT_HOST, and TOKEN."
  exit 1
fi

# Update the system
sudo apt update

# Check if Docker is installed, and install if it is not
if ! command -v docker &> /dev/null; then
  echo "Docker not found, installing..."
  sudo apt install -y docker.io

  # Start and enable Docker service
  sudo systemctl start docker
  sudo systemctl enable docker
else
  echo "Docker is already installed"
fi

# If the script is already in the repository, just pull the latest changes
REPO_URL="https://melvin-vergel:$GITHUB_TOKEN@github.com/melvin-vergel/whatsapp-api.git"
CURRENT_DIR=$(basename "$PWD")

# Log the REPO_URL for debugging
echo "Using repository URL: $REPO_URL"

if [ "$CURRENT_DIR" = "whatsapp-api" ]; then
  echo "Repository detected. Pulling the latest changes..."
  git reset --hard
  git clean -fd
  git pull "$REPO_URL" feature/stand-alone || {
    echo "Failed to pull the latest changes. Please check the repository and network connection."
    exit 1
  }
else
  echo "Cloning the repository..."
  git clone -b feature/stand-alone "$REPO_URL" whatsapp-api || {
    echo "Failed to clone the repository. Please check your token and network connection."
    exit 1
  }
  cd whatsapp-api
fi


# Function to check and create a Docker volume if it doesn't exist
create_volume_if_missing() {
  if ! docker volume inspect "$1" > /dev/null 2>&1; then
    echo "Creating Docker volume: $1"
    docker volume create "$1"
  else
    echo "Docker volume $1 already exists"
  fi
}

# Ensure Docker volumes are created
create_volume_if_missing html
create_volume_if_missing certs
create_volume_if_missing acme
create_volume_if_missing ws-db

# Function to stop and remove a Docker container if it exists
remove_container_if_exists() {
  if [ "$(docker ps -q -f name=$1)" ]; then
    echo "Stopping and removing existing container: $1"
    docker stop "$1"
    docker rm "$1"
  fi
}

# Run the nginx-proxy container
remove_container_if_exists nginx-proxy
docker run -d \
  --name nginx-proxy \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v html:/usr/share/nginx/html \
  -v certs:/etc/nginx/certs:ro \
  -v /var/run/docker.sock:/tmp/docker.sock:ro \
  --network bridge \
  nginxproxy/nginx-proxy

# Run the acme-companion container
remove_container_if_exists nginx-proxy-acme
docker run -d \
  --name nginx-proxy-acme \
  --restart unless-stopped \
  --env DEFAULT_EMAIL="$DEFAULT_EMAIL" \
  --volumes-from nginx-proxy \
  -v certs:/etc/nginx/certs:rw \
  -v acme:/etc/acme.sh \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --network bridge \
  nginxproxy/acme-companion

# Build the ws-api image
docker build -t ws-api -f ./"$REPO_DIR"/app/Dockerfile ./"$REPO_DIR"/app

# Run the ws-api container
remove_container_if_exists ws-api
docker run -d \
  --name ws-api \
  --restart unless-stopped \
  --cpus=0.9 \
  --memory=900m \
  --env VIRTUAL_HOST="$VIRTUAL_HOST" \
  --env LETSENCRYPT_HOST="$LETSENCRYPT_HOST" \
  --env NODE_ENV=production \
  --env TOKEN="$TOKEN" \
  --env TZ=America/Santiago \
  --env PORT=80 \
  --env WHATSAPP_VERSION="$$WS_VERSION" \
  --expose 80 \
  -v ws-db:/app/persist \
  --network bridge \
  ws-api
# Notify the user
echo "Docker containers have been set up successfully."