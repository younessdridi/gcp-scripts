#!/bin/bash
set -euo pipefail

# ------------- User editable defaults -------------
DEFAULT_REGION="us-central1"
SERVICE_NAME="zoro"
WEB_SERVICE_NAME="zoro-web"
IMAGE_NAME="gcr.io/$(gcloud config get-value project --quiet)/${SERVICE_NAME}-image"
WEB_IMAGE_NAME="gcr.io/$(gcloud config get-value project --quiet)/${WEB_SERVICE_NAME}-image"
CPU="1"
MEMORY="512Mi"
LISTEN_PORT=8080
WS_PATH="/tg-@ZORO_40"   # <-- requested path (keep exact)
ENCODED_WS_PATH="%2Ftg-%40ZORO_40"
# --------------------------------------------------

# Helpers
log(){ printf "\e[32m[%s]\e[0m %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"; }
err(){ printf "\e[31m[ERROR]\e[0m %s\n" "$1"; }
warn(){ printf "\e[33m[WARN]\e[0m %s\n" "$1"; }

# Check prerequisites
if ! command -v gcloud &>/dev/null; then err "gcloud CLI not found. Install Google Cloud SDK."; exit 1; fi
if ! command -v git &>/dev/null; then err "git not found. Install git."; exit 1; fi

PROJECT_ID=$(gcloud config get-value project --quiet 2>/dev/null || true)
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  err "gcloud project not configured. Run: gcloud config set project PROJECT_ID"
  exit 1
fi

# Ask for optional values
read -p "Enter region [${DEFAULT_REGION}]: " REGION
REGION=${REGION:-$DEFAULT_REGION}

read -p "Enter service name [${SERVICE_NAME}]: " tmp; SERVICE_NAME=${tmp:-$SERVICE_NAME}
read -p "Enter web service name [${WEB_SERVICE_NAME}]: " tmp; WEB_SERVICE_NAME=${tmp:-$WEB_SERVICE_NAME}

# UUID
if command -v uuidgen &>/dev/null; then
  UUID=$(uuidgen)
else
  UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 || printf "ba0e3984-ccc9-48a3-8074-b2f507f41ce8")
fi

read -p "Enter UUID [auto-generated]: " Utmp
UUID=${Utmp:-$UUID}

# Telegram (optional)
echo
log "If you want deployment info sent to Telegram, enter bot token and chat/channel id now."
read -p "Telegram Bot Token (or leave empty to skip): " TELEGRAM_BOT_TOKEN
if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  read -p "Telegram Chat ID or Channel ID (e.g. -1001234567890 or 123456789): " TELEGRAM_DEST_ID
fi

# Create build dir
WORKDIR="$(pwd)/gcp-zoro-deploy-$(date +%s)"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

log "Creating V2Ray (VLESS) service files..."

# 1) Create v2ray config.json tuned for Cloud Run WS path
cat > config.json <<EOF
{
  "log": {
    "access": "/dev/stdout",
    "error": "/dev/stderr",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "",
            "level": 0,
            "email": "zoro@server"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 2) Dockerfile for v2ray service
cat > Dockerfile <<'EOF'
FROM v2fly/v2fly-core:latest
COPY config.json /etc/v2ray/config.json
EXPOSE 8080
CMD ["/usr/bin/v2ray", "-config", "/etc/v2ray/config.json"]
EOF

# 3) Build & submit image to Google Container Registry via Cloud Build
log "Submitting build for ${SERVICE_NAME}..."
gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}-image" --quiet

log "Deploying ${SERVICE_NAME} to Cloud Run (this may take a minute)..."
gcloud run deploy "${SERVICE_NAME}" \
  --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}-image" \
  --platform managed \
  --region "${REGION}" \
  --allow-unauthenticated \
  --port ${LISTEN_PORT} \
  --cpu ${CPU} \
  --memory ${MEMORY} \
  --quiet

# Get service URL and domain
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" --platform managed --region "${REGION}" --format 'value(status.url)' --quiet)
DOMAIN=$(echo "${SERVICE_URL}" | sed -E 's|https?://||; s|/||g')

log "Service deployed: ${SERVICE_URL}"

# 4) Create simple static web page (zoro-web)
log "Creating web page service files..."
mkdir -p web
cat > web/index.html <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>ZORO - Welcome</title>
  <style>
    body{font-family:Inter,system-ui,Segoe UI,Arial;background:#0b1020;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
    .card{max-width:720px;padding:30px;border-radius:14px;background:linear-gradient(135deg, rgba(255,255,255,0.03), rgba(255,255,255,0.02));box-shadow:0 10px 30px rgba(0,0,0,0.4)}
    h1{margin:0 0 10px;font-size:32px}
    p{margin:0 0 15px;color:#cdd6e0}
    a.btn{display:inline-block;padding:10px 16px;border-radius:10px;background:#ff5b5b;color:#fff;text-decoration:none}
  </style>
</head>
<body>
  <div class="card">
    <h1>Welcome to ZORO Server 🔥</h1>
    <p>Service: <strong>${SERVICE_NAME}</strong></p>
    <p>VLESS WS path: <strong>${WS_PATH}</strong></p>
    <p>UUID: <strong>${UUID}</strong></p>
    <a class="btn" href="https://t.me/zoro_40_khanchlyyy" target="_blank">Telegram Channel</a>
  </div>
</body>
</html>
HTML

# Dockerfile for web
cat > web/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir gunicorn
EXPOSE 8080
CMD ["gunicorn", "-b", "0.0.0.0:8080", "index:app"]
EOF

# tiny WSGI server file (index.py)
cat > web/index.py <<'PY'
from wsgiref.simple_server import make_server
from pathlib import Path

html = Path("index.html").read_text()

def app(environ, start_response):
    start_response('200 OK', [('Content-type','text/html; charset=utf-8')])
    return [html.encode('utf-8')]
PY

# Build & deploy web image
log "Building static web image and deploying as ${WEB_SERVICE_NAME}..."
cd web
gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${WEB_SERVICE_NAME}-image" --quiet
gcloud run deploy "${WEB_SERVICE_NAME}" \
  --image "gcr.io/${PROJECT_ID}/${WEB_SERVICE_NAME}-image" \
  --platform managed \
  --region "${REGION}" \
  --allow-unauthenticated \
  --port 8080 \
  --cpu 1 \
  --memory 128Mi \
  --quiet

WEB_URL=$(gcloud run services describe "${WEB_SERVICE_NAME}" --platform managed --region "${REGION}" --format 'value(status.url)' --quiet)
log "Web page deployed: ${WEB_URL}"
cd ..

# 5) Build VLESS share link (URL-encoded path)
# Use m.googleapis.com as host domain so clients accept the Cloud Run domain as SNI/host parameter
VLESS_LINK="vless://${UUID}@${DOMAIN}:443?path=${ENCODED_WS_PATH}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#zoro"

# Save info to file
cat > deployment-info.txt <<EOT
GCP VLESS Deployment (zoro)
----------------------------
Project: ${PROJECT_ID}
Region:  ${REGION}
Service: ${SERVICE_NAME}
Service URL: ${SERVICE_URL}
Web URL: ${WEB_URL}
UUID: ${UUID}
WS Path: ${WS_PATH}
VLESS Link:
${VLESS_LINK}

Notes:
- Cloud Run terminates TLS automatically (HTTPS). WebSocket path is ${WS_PATH}.
- If you change the path in the VLESS link, ensure config.json wsSettings.path matches it.
EOT

log "Deployment info saved to deployment-info.txt"
log "----"
cat deployment-info.txt
log "----"

# 6) Send to Telegram if requested
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_DEST_ID:-}" ]]; then
  MSG="*ZORO Deployment Complete ✅*
• Project: \`${PROJECT_ID}\`
• Service: \`${SERVICE_NAME}\`
• Region: \`${REGION}\`
• URL: \`${SERVICE_URL}\`
• Web: \`${WEB_URL}\`
• UUID: \`${UUID}\`

VLESS:
\`\`\`
${VLESS_LINK}
\`\`\`"

  # Use Telegram sendMessage
  send_payload=$(jq -nc --arg chat "${TELEGRAM_DEST_ID}" --arg text "${MSG}" '{chat_id:$chat, text:$text, parse_mode:"Markdown", disable_web_page_preview:true}')
  resp=$(curl -s -w "%{http_code}" -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -H 'Content-Type: application/json' -d "${send_payload}")
  http_code="${resp: -3}"
  if [[ "$http_code" == "200" ]]; then
    log "Telegram notification sent."
  else
    warn "Failed to send Telegram notification. Response: ${resp}"
  fi
else
  log "Telegram not configured - skipping notification."
fi

log "All done. Deployment directory: ${WORKDIR}"
