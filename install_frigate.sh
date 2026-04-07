#!/bin/bash
set -euo pipefail

# Ensure script runs as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo)"
  exit 1
fi

BASE_DIR="/main"

echo "🚀 Starting BASE setup (Docker + Frigate)..."

# -------------------------
# Install Docker
# -------------------------
echo "🧹 Removing old Docker..."
apt-get remove -y docker docker-engine docker.io containerd runc || true

echo "🔄 Updating system..."
apt-get update -y

echo "📦 Installing dependencies..."
apt-get install -y ca-certificates curl gnupg lsb-release

echo "🔑 Adding Docker key..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "📁 Adding repo..."
echo \
"deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y

echo "🐳 Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# Add user to docker group (if not root login)
if [ -n "${SUDO_USER:-}" ]; then
  usermod -aG docker "$SUDO_USER" || true
fi

# -------------------------
# Directories
# -------------------------
echo "📁 Creating directories..."
mkdir -p $BASE_DIR/frigate/{config,data}

# -------------------------
# .env
# -------------------------
echo "📝 Creating .env..."
cat > $BASE_DIR/.env << 'EOF'
MQTT_HOST=
MQTT_PORT=
MQTT_USER=
MQTT_PASS=

FRIGATE_URL=http://frigate:5000
EOF

chmod 600 $BASE_DIR/.env

# -------------------------
# Frigate config
# -------------------------
echo "📝 Creating Frigate config..."
cat > $BASE_DIR/frigate/config/config.yml << 'EOF'
# MQTT Setup
mqtt:
  host: 
  port: 
  user: 
  password: 

detectors:
  coral:
    type: edgetpu
    device: usb

ffmpeg:
  hwaccel_args: preset-vaapi

detect:
  width: 2688
  height: 1664
  fps: 4
  enabled: true

objects:
  track:
    - person

review:
  alerts:
    enabled: true
    labels:
      - person
  detections:
    enabled: true
    labels:
      - person

snapshots:
  enabled: true
  clean_copy: true
  bounding_box: true
  retain:
    default: 1
    objects:
      person: 5
  quality: 70

record:
  enabled: true
  expire_interval: 60
  alerts:
    retain:
      days: 1
      mode: motion
    pre_capture: 10
    post_capture: 15
  detections:
    retain:
      days: 1
      mode: motion
    pre_capture: 10
    post_capture: 15
  continuous:
    days: 1
  motion:
    days: 1

go2rtc:
  streams:
    cameraname:
      - rtsp://username:password@camera-ip:554/cam/realmonitor?channel=1&subtype=0

cameras:
  cameraname:
    ffmpeg:
      output_args:
        record: preset-record-generic-audio-copy
      inputs:
        - path: rtsp://127.0.0.1:8554/cameraname
          input_args: preset-rtsp-restream
          roles:
            - detect
            - record
    motion:
      threshold: 50
      contour_area: 20
      improve_contrast: true
 

    detect:
      annotation_offset: 0

semantic_search:
  enabled: false
face_recognition:
  enabled: false
lpr:
  enabled: false
classification:
  bird:
    enabled: false

version: 0.17-0
EOF

# -------------------------
# Docker Compose
# -------------------------
echo "📝 Creating compose..."
cat > $BASE_DIR/compose.yml << 'EOF'
services:
  dozzle:
    container_name: dozzle
    restart: unless-stopped
    image: amir20/dozzle:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - 8080:8080

  frigate:
    container_name: frigate
    privileged: true
    restart: unless-stopped
    image: ghcr.io/blakeblackshear/frigate:stable
    shm_size: "256mb"
    devices:
      - /dev/bus/usb:/dev/bus/usb
      - /dev/dri/renderD128:/dev/dri/renderD128
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /main/frigate/config:/config
      - /main/frigate/data:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000
    ports:
      - "5000:5000"
      - "8971:8971"
      - "8554:8554"
      - "8555:8555/tcp"
      - "8555:8555/udp"
      - "1984:1984"
    environment:
      FRIGATE_RTSP_PASSWORD: "password"
EOF

echo ""
echo "✅ BASE SETUP COMPLETE"
echo "👉 Run:"
echo "docker compose --env-file $BASE_DIR/.env -f $BASE_DIR/compose.yml up -d"
echo ""
echo "⚠️ Re-login required for docker group"
