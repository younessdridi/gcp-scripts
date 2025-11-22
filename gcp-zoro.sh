#!/bin/bash

set -euo pipefail

# =========================
# Colors for output
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
info()   { echo -e "${BLUE}[INFO]${NC} $1"; }

# =========================
# Validation functions
# =========================
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $uuid_pattern ]] || { error "Invalid UUID format: $1"; return 1; }
}

validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    [[ $1 =~ $token_pattern ]] || { error "Invalid Telegram Bot Token"; return 1; }
}

validate_channel_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Channel ID"; return 1; }; }
validate_chat_id()    { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Chat ID"; return 1; }; }

# =========================
# Resource selection
# =========================
select_cpu() {
    info "=== CPU Configuration ==="
    echo "1. 1 Core (Default)"; echo "2. 2 Cores"; echo "3. 4 Cores"; echo "4. 8 Cores"
    while true; do
        read -p "Select CPU (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU=1; break ;;
            2) CPU=2; break ;;
            3) CPU=4; break ;;
            4) CPU=8; break ;;
            *) echo "Invalid selection";;
        esac
    done
    info "CPU selected: $CPU core(s)"
}

select_memory() {
    info "=== Memory Configuration ==="
    declare -A MEM_OPTIONS=( [1]=512 [2]=1024 [3]=2048 [4]=4096 [5]=8192 [6]=16384 )
    echo "1. 512Mi 2. 1Gi 3. 2Gi 4. 4Gi 5. 8Gi 6. 16Gi"
    while true; do
        read -p "Select Memory (1-6): " mem_choice
        [[ ${MEM_OPTIONS[$mem_choice]+_} ]] && { MEMORY="${MEM_OPTIONS[$mem_choice]}Mi"; break; }
        echo "Invalid selection"
    done
    info "Memory selected: $MEMORY"
}

select_region() {
    info "=== Region Selection ==="
    declare -A REGIONS=(
        [1]="us-central1"
        [2]="us-west1"
        [3]="us-east1"
        [4]="europe-west1"
        [5]="asia-southeast1"
        [6]="asia-northeast1"
        [7]="asia-east1"
    )
    for i in "${!REGIONS[@]}"; do echo "$i. ${REGIONS[$i]}"; done
    while true; do
        read -p "Select region (1-7): " r
        [[ ${REGIONS[$r]+_} ]] && { REGION="${REGIONS[$r]}"; break; }
        echo "Invalid selection"
    done
    info "Region selected: $REGION"
}

# =========================
# Telegram configuration
# =========================
select_telegram_destination() {
    info "=== Telegram Destination ==="
    echo "1. Channel only 2. Bot only 3. Both 4. None"
    while true; do
        read -p "Select (1-4): " choice
        case $choice in
            1) TELEGRAM_DESTINATION="channel"
               while read -p "Channel ID: " id; do validate_channel_id "$id" && { TELEGRAM_CHANNEL_ID="$id"; break; }; done ;;
            2) TELEGRAM_DESTINATION="bot"
               while read -p "Chat ID: " id; do validate_chat_id "$id" && { TELEGRAM_CHAT_ID="$id"; break; }; done ;;
            3) TELEGRAM_DESTINATION="both"
               while read -p "Channel ID: " id; do validate_channel_id "$id" && { TELEGRAM_CHANNEL_ID="$id"; break; }; done
               while read -p "Chat ID: " id; do validate_chat_id "$id" && { TELEGRAM_CHAT_ID="$id"; break; }; done ;;
            4) TELEGRAM_DESTINATION="none";;
            *) echo "Invalid selection"; continue;;
        esac
        break
    done
}

# =========================
# User input
# =========================
get_user_input() {
    read -p "Service Name: " SERVICE_NAME
    read -p "UUID [default: ba0e3984-ccc9-48a3-8074-b2f507f41ce8]: " UUID
    UUID=${UUID:-ba0e3984-ccc9-48a3-8074-b2f507f41ce8}
    validate_uuid "$UUID"

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while read -p "Telegram Bot Token: " token; do validate_bot_token "$token" && { TELEGRAM_BOT_TOKEN="$token"; break; }; done
    fi

    read -p "Host Domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-m.googleapis.com}
}

# =========================
# Telegram send function
# =========================
send_to_telegram() {
    local chat_id="$1"
    local msg="$2"
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$chat_id\",\"text\":\"$msg\",\"parse_mode\":\"Markdown\"}" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage > /dev/null
}

# =========================
# Deployment
# =========================
main() {
    info "=== Zoro Cloud Run Deployment ==="
    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input

    PROJECT_ID=$(gcloud config get-value project)
    info "Project: $PROJECT_ID"

    # Enable APIs
    gcloud services enable cloudbuild.googleapis.com run.googleapis.com iam.googleapis.com --quiet

    # Clone repo
    [[ -d gcp-v2ray ]] && rm -rf gcp-v2ray
    git clone https://github.com/nyeinkokoaung404/gcp-v2ray.git
    cd gcp-v2ray

    # Build and deploy
    gcloud builds submit --tag gcr.io/${PROJECT_ID}/zoro-v2ray-image --quiet
    gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/zoro-v2ray-image \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --quiet

    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} --region ${REGION} --format 'value(status.url)')
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')

    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftg-%40zoro&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"

    echo -e "${GREEN}Deployment successful!${NC}"
    echo "Service URL: $SERVICE_URL"
    echo "V2Ray Link: $VLESS_LINK"

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        send_to_telegram "${TELEGRAM_CHANNEL_ID:-$TELEGRAM_CHAT_ID}" "*Zoro Cloud Run Deployment Successful*\nURL: $SERVICE_URL\nV2Ray Link:\n$VLESS_LINK"
    fi
}

main "$@"
