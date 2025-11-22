#!/bin/bash

# Script: GCP VLESS + Trojan Deployer with Telegram Bot & Internal HTML
# Owner: zoro 👑
# Version: 3.1 - Single file Cloud Run

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
SERVICE_NAME="proxy-service"
REGION="us-central1"
PORT=8080
UUID=$(cat /proc/sys/kernel/random/uuid)
PATH_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)
PASSWORD=$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)
TELEGRAM_CHAT_ID="@zoro_40_khanchlyyy"

# Functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    local deps=("gcloud" "curl" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "$dep غير مثبت. الرجاء تثبيته أولاً."
            exit 1
        fi
    done
    print_success "جميع المتطلبات مثبتة"
}

# Create Dockerfile + config.json + internal HTML
create_dockerfile() {
cat > Dockerfile << EOF
FROM alpine:latest
RUN apk update && apk add --no-cache curl unzip
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.11/Xray-linux-64.zip -o xray.zip && \
    unzip xray.zip && mv xray /usr/bin/ && chmod +x /usr/bin/xray && rm xray.zip geoip.dat geosite.dat
RUN mkdir -p /etc/xray
COPY config.json /etc/xray/
EXPOSE $PORT
CMD ["xray", "run", "-config", "/etc/xray/config.json"]
EOF

cat > config.json << EOF
{
  "inbounds":[
    {"port":$PORT,"protocol":"vless","settings":{"clients":[{"id":"$UUID","flow":"xtls-rprx-vision"}],"decryption":"none"},
    "streamSettings":{"network":"ws","security":"tls","wsSettings":{"path":"/tg-$PATH_SUFFIX"}}},
    {"port":$((PORT+1)),"protocol":"trojan","settings":{"clients":[{"password":"$PASSWORD"}]},
    "streamSettings":{"network":"ws","security":"tls","wsSettings":{"path":"/tr-$PATH_SUFFIX"}}}
  ],
  "outbounds":[{"protocol":"freedom"}]
}
EOF
}

deploy_service() {
    gcloud services enable run.googleapis.com containerregistry.googleapis.com --quiet
    gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME --quiet
    gcloud run deploy $SERVICE_NAME --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
        --platform managed --region $REGION --allow-unauthenticated --port $PORT --quiet
}

get_service_url() {
    gcloud run services describe $SERVICE_NAME --platform managed --region $REGION --format="value(status.url)"
}

generate_links() {
    local domain=$(echo "$1" | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${domain}:443?path=/tg-${PATH_SUFFIX}&type=ws#zoro"
    TROJAN_LINK="trojan://${PASSWORD}@${domain}:443?path=/tr-${PATH_SUFFIX}#zoro"
    HTML_PAGE="https://${domain}/index.html"
}

send_telegram_message() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=HTML" > /dev/null
    print_success "تم إرسال الرسالة إلى تيليجرام"
}

main() {
    clear
    echo -e "${CYAN}==== GCP VLESS + Trojan Deployer ====${NC}"
    check_dependencies

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "سجل دخول Google أولاً"
        gcloud auth login --no-launch-browser
    fi

    read -p "أدخل معرف المشروع (Project ID): " PROJECT_ID
    read -p "اسم الخدمة (افتراضي: $SERVICE_NAME): " input_name
    [[ -n "$input_name" ]] && SERVICE_NAME="$input_name"

    create_dockerfile
    deploy_service

    SERVICE_URL=$(get_service_url)
    sleep 10
    generate_links "$SERVICE_URL"

    echo ""
    print_success "تم النشر بنجاح!"
    echo "👑 المالك: zoro"
    echo "🌐 رابط الخدمة: $SERVICE_URL"
    echo "🔗 VLESS: $VLESS_LINK"
    echo "🔗 Trojan: $TROJAN_LINK"
    echo "📄 HTML: $HTML_PAGE"

    telegram_msg="🚀 تم نشر السيرفر بنجاح

👑 المالك: zoro
🌐 رابط الخدمة: $SERVICE_URL
🔗 VLESS: $VLESS_LINK
🔗 Trojan: $TROJAN_LINK
📄 HTML: $HTML_PAGE
"
    send_telegram_message "$telegram_msg"

    echo ""
    print_info "لإيقاف الخدمة: gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
}

trap "rm -f Dockerfile config.json; exit" SIGINT
main "$@"
