#!/bin/bash
set -e

echo "🚀 Adding Frigate Notifier..."

# -------------------------
# Directories
# -------------------------
echo "📁 Creating directories..."
sudo mkdir -p /main/{clips,notifier}

# -------------------------
# Requirements
# -------------------------
echo "📝 Creating requirements..."
sudo tee /main/notifier/requirements.txt > /dev/null << 'EOF'
paho-mqtt
requests
python-telegram-bot
EOF

# -------------------------
# Notifier script
# -------------------------
echo "📝 Creating notifier script..."
sudo tee /main/notifier/frigate_notifier.py > /dev/null << 'EOF'
import json, os, requests, asyncio
import paho.mqtt.client as mqtt
from telegram import Bot

FRIGATE_URL = os.getenv("FRIGATE_URL")
MQTT_HOST = os.getenv("MQTT_HOST")
MQTT_PORT = int(os.getenv("MQTT_PORT", 1883))
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASS = os.getenv("MQTT_PASS")
TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

SAVE_FOLDER = "/app/frigate_clips"
bot = Bot(token=TELEGRAM_TOKEN)
os.makedirs(SAVE_FOLDER, exist_ok=True)

async def handle_review_clip(camera, start, end, review_id, severity):
    url = f"{FRIGATE_URL}/api/{camera}/start/{start}/end/{end}/clip.mp4"
    path = os.path.join(SAVE_FOLDER, f"{review_id}.mp4")
    try:
        res = requests.get(url, stream=True, timeout=60)
        if res.status_code == 200:
            with open(path, 'wb') as f:
                for chunk in res.iter_content(1024): f.write(chunk)
            caption = f"🎬 {severity.upper()} | {camera} | {int(end-start)}s"
            with open(path, 'rb') as v:
                await bot.send_video(chat_id=TELEGRAM_CHAT_ID, video=v, caption=caption)
    except Exception as e:
        print(e)

def on_message(client, userdata, msg):
    from datetime import datetime
    data = json.loads(msg.payload.decode())
    if data.get("type") == "end":
        val = data["after"]
        asyncio.run_coroutine_threadsafe(
            handle_review_clip(
                val["camera"],
                val["start_time"]-5,
                val["end_time"]+5,
                datetime.now().strftime('%Y%m%d%H%M%S'),
                val["severity"]
            ), loop
        )

loop = asyncio.new_event_loop()
client = mqtt.Client()
if MQTT_USER:
    client.username_pw_set(MQTT_USER, MQTT_PASS)
client.on_message = on_message
client.connect(MQTT_HOST, MQTT_PORT, 60)
client.subscribe("frigate/reviews")
client.loop_start()
loop.run_forever()
EOF

# -------------------------
# Update .env
# -------------------------
echo "📝 Updating .env..."
sudo tee -a /main/.env > /dev/null << 'EOF'

# Telegram
TELEGRAM_TOKEN=YOUR_TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=YOUR_CHAT_ID
EOF

# -------------------------
# Update compose
# -------------------------
echo "📝 Updating compose..."
sudo tee -a /main/compose.yml > /dev/null << 'EOF'

  frigate-notifier:
    container_name: notifier
    image: python:3.11-slim
    restart: always
    env_file:
      - /main/.env
    volumes:
      - /main/notifier:/app
      - /main/clips:/app/frigate_clips
    working_dir: /app
    command: sh -c "pip install --no-cache-dir -r requirements.txt && python frigate_notifier.py"
EOF

echo ""
echo "✅ NOTIFIER SETUP COMPLETE"
echo "👉 Restart stack:"
echo "docker compose --env-file /main/.env -f /main/compose.yml up -d"
