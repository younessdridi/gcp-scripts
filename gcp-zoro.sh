#!/bin/bash

# GCP V2Ray VLESS Server Deployer (Telegram Auto-Send Edition)
# Version: 10.0 – Clean + Organized Telegram Output

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ID=""
SERVICE_NAME=""
REGION="us-central1"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
UUID=""
PATH_SUFFIX=""
SERVICE_URL=""
VLESS_LINK=""

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

check_environment() {
    if ! command -v gcloud &> /dev/null; then
        echo "Run inside Google Cloud Shell"
        exit 1
    fi
}

check_auth() {
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter Project ID: " PROJECT_ID
        gcloud config set project "$PROJECT_ID"
    fi
}

get_configuration() {
    read -p "Enter service name [vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}

    read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    read -p "Enter Telegram Chat ID: " TELEGRAM_CHAT_ID

    UUID=$(cat /proc/sys/kernel/random/uuid)
    RAND=$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)

    PATH_SUFFIX="tg-${RAND}-@ZORO40_DZ-@zoro_40_khanchlyyy"
}

create_dockerfile() {

cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl bash unzip

RUN curl -L https://github.com/v2fly/v2ray-core/releases/download/v5.7.0/v2ray-linux-64.zip -o v2ray.zip \
    && unzip v2ray.zip \
    && mv v2ray /usr/bin/ \
    && chmod +x /usr/bin/v2ray \
    && rm -f v2ray.zip geoip.dat geosite.dat \
    && mkdir -p /etc/v2ray

COPY config.json /etc/v2ray/

EXPOSE 8080

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
EOF

cat > config.json << EOF
{
   "log": { "loglevel": "warning" },
   "inbounds": [
      {
         "port": 8080,
         "listen": "0.0.0.0",
         "protocol": "vless",
         "settings": {
            "clients": [ { "id": "$UUID", "level": 0 } ],
            "decryption": "none"
         },
         "streamSettings": {
            "network": "ws",
            "security": "tls",
            "tlsSettings": {
               "alpn": ["h3", "h2", "http/1.1"],
               "fingerprint": "randomized"
            },
            "wsSettings": { "path": "/$PATH_SUFFIX" }
         }
      }
   ],
   "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF
}

enable_services() {
    gcloud services enable run.googleapis.com containerregistry.googleapis.com cloudbuild.googleapis.com --quiet
}

build_and_deploy() {

gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" --quiet

gcloud run deploy "$SERVICE_NAME" \
    --image "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
    --platform managed \
    --region "$REGION" \
    --allow-unauthenticated \
    --port 8080 \
    --cpu 1 \
    --memory "512Mi" \
    --min-instances 1 \
    --max-instances 5 \
    --execution-environment gen2 \
    --quiet
}

get_service_info() {
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)")
}

generate_vless_link() {
    domain=$(echo "$SERVICE_URL" | sed 's|https://||')

VLESS_LINK="vless://${UUID}@${domain}:443?path=%2F${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
}

send_telegram_message() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         --data-urlencode "text=${text}" \
         -d "parse_mode=HTML" >/dev/null
}

send_final_messages() {

domain=$(echo "$SERVICE_URL" | sed 's|https://||')

INFO_MSG="🚀 <b>VLESS SERVER DEPLOYED</b>

🌍 <b>Domain:</b> <code>${domain}</code>
📍 <b>Region:</b> ${REGION}
🆔 <b>Project:</b> ${PROJECT_ID}
🔧 <b>Service:</b> ${SERVICE_NAME}

🔑 <b>UUID:</b>
<code>${UUID}</code>

🛣️ <b>Path:</b>
<code>/${PATH_SUFFIX}</code>

🔐 <b>Security:</b> TLS  
📡 <b>Protocol:</b> VLESS + WS  
⚡ <b>ALPN:</b> h3, h2, http/1.1

📌 <b>Channels:</b>
@ZORO40_DZ  
@zoro_40_khanchlyyy"

send_telegram_message "$INFO_MSG"

sleep 2

LINK_MSG="🔗 <b>VLESS LINK:</b>
<code>${VLESS_LINK}</code>"

send_telegram_message "$LINK_MSG"
}

cleanup() {
    rm -f Dockerfile config.json
}

main() {
    check_environment
    check_auth
    get_configuration
    create_dockerfile
    enable_services
    build_and_deploy
    get_service_info
    generate_vless_link
    send_final_messages
    cleanup

    echo ""
    echo "DONE – Server deployed and sent to Telegram!"
}

main
