#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

echo "--- Phase 2: Installing Telegram Notifier ---"

# 1. Update .env with Telegram Variables
cat <<EOF >> /main/.env
TELEGRAM_TOKEN=
TELEGRAM_CHAT_ID=
EOF

# 2. Create Notifier Directories
mkdir -p /main/{clips,notifier}

# 3. Create requirements.txt
cat <<EOF > /main/notifier/requirements.txt
paho-mqtt
requests
python-telegram-bot
EOF

# 4. Create frigate_notifier.py
cat <<'EOF' > /main/notifier/frigate_notifier.py
import time, json, os, requests, asyncio
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

async def handle_review_clip(camera, start, end, review_id, severity):
    url = f"{FRIGATE_URL}/api/{camera}/start/{start}/end/{end}/clip.mp4"
    path = os.path.join(SAVE_FOLDER, f"{review_id}.mp4")
    try:
        res = requests.get(url, stream=True, timeout=60)
        if res.status_code == 200:
            with open(path, 'wb') as f:
                for chunk in res.iter_content(1024): f.write(chunk)
            caption = f"🎬 **NEW {severity.upper()}**\n📷 Camera: {camera}"
            with open(path, 'rb') as v:
                await bot.send_video(chat_id=TELEGRAM_CHAT_ID, video=v, caption=caption, parse_mode='Markdown')
    except Exception as e:
        print(f"Error: {e}")

def on_message(client, userdata, msg):
    from datetime import datetime
    data = json.loads(msg.payload.decode())
    if data.get("type") == "end":
        val = data["after"]
        asyncio.run_coroutine_threadsafe(
            handle_review_clip(val["camera"], val["start_time"]-5, val["end_time"]+5, 
                               datetime.now().strftime('%Y%m%d-%H%M%S'), val["severity"]), loop
        )

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    client = mqtt.Client()
    if MQTT_USER: client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_message = on_message
    client.connect(MQTT_HOST, MQTT_PORT, 60)
    client.subscribe("frigate/reviews")
    client.loop_start()
    loop.run_forever()
EOF

# 5. Append Notifier to compose.yml
cat <<EOF >> /main/compose.yml

  frigate-notifier:
    image: python:3.11-slim
    container_name: frigate-notifier
    restart: always
    depends_on:
      - frigate
    volumes:
      - /main/notifier:/app
      - /main/clips:/app/frigate_clips
    working_dir: /app
    environment:
      - FRIGATE_URL=\${FRIGATE_URL}
      - MQTT_HOST=\${MQTT_HOST}
      - MQTT_PORT=\${MQTT_PORT}
      - MQTT_USER=\${MQTT_USER}
      - MQTT_PASS=\${MQTT_PASS}
      - TELEGRAM_TOKEN=\${TELEGRAM_TOKEN}
      - TELEGRAM_CHAT_ID=\${TELEGRAM_CHAT_ID}
    command: >
      sh -c "pip install --no-cache-dir -r requirements.txt && python frigate_notifier.py"
EOF

chown -R $SUDO_USER:$SUDO_USER /main
echo "--- Notifier Added. Update /main/.env and run 'docker compose up -d' ---"
