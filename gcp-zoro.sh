#!/bin/bash
set -euo pipefail

# ---------------------------
# Colors
# ---------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
highlight() { echo -e "${CYAN}$1${NC}"; }

# ---------------------------
# Validation
# ---------------------------
validate_uuid() { [[ $1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; }
validate_bot_token() { [[ $1 =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; }
validate_channel_id() { [[ $1 =~ ^-?[0-9]+$ ]]; }
validate_chat_id() { [[ $1 =~ ^-?[0-9]+$ ]]; }

# ---------------------------
# CPU / RAM
# ---------------------------
select_cpu() {
    echo; info "=== CPU Configuration ==="
    echo "1) 1 Core"
    echo "2) 2 Cores"
    echo "3) 4 Cores"
    echo "4) 8 Cores"
    while true; do
        read -p "Select CPU cores (1-4): " cpu
        case $cpu in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            *) echo "Invalid";;
        esac
    done
    info "CPU: $CPU"
}

select_memory() {
    echo; info "=== Memory Configuration ==="
    echo "1)512Mi 2)1Gi 3)2Gi 4)4Gi 5)8Gi 6)16Gi"
    while true; do
        read -p "Select Memory (1-6): " m
        case $m in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid";;
        esac
    done
    info "Memory: $MEMORY"
}

# ---------------------------
# Region
# ---------------------------
select_region() {
    echo; info "=== Region Selection ==="
    echo "1) us-central1 2) us-west1 3) us-east1 4) europe-west1 5) asia-southeast1 6) asia-northeast1 7) asia-east1"
    while true; do
        read -p "Select region (1-7): " r
        case $r in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="asia-southeast1"; break ;;
            6) REGION="asia-northeast1"; break ;;
            7) REGION="asia-east1"; break ;;
            *) echo "Invalid";;
        esac
    done
    info "Region: $REGION"
}

# ---------------------------
# Telegram
# ---------------------------
select_telegram() {
    echo; info "=== Telegram ==="
    echo "1) Channel 2) Bot 3) Both 4) None"
    while true; do
        read -p "Destination (1-4): " t
        case $t in
            1) TELEGRAM_DEST="channel"; read -p "Channel ID: " TELEGRAM_CHANNEL_ID; break ;;
            2) TELEGRAM_DEST="bot"; read -p "Chat ID: " TELEGRAM_CHAT_ID; break ;;
            3) TELEGRAM_DEST="both"; read -p "Channel ID: " TELEGRAM_CHANNEL_ID; read -p "Chat ID: " TELEGRAM_CHAT_ID; break ;;
            4) TELEGRAM_DEST="none"; break ;;
            *) echo "Invalid";;
        esac
    done
}

get_user_input() {
    echo; info "=== Service Setup ==="
    read -p "Service Name Prefix [default: zoro]: " SERVICE_PREFIX
    SERVICE_PREFIX=${SERVICE_PREFIX:-zoro}

    # UUID
    while true; do
        read -p "UUID [random default]: " UUID
        UUID=${UUID:-$(uuidgen)}
        validate_uuid "$UUID" && break
        echo "Invalid UUID"
    done

    # SNI
    while true; do
        read -p "Enter SNI: " SNI
        [[ -n "$SNI" ]] && break
        echo "Cannot be empty"
    done

    read -p "Host domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-m.googleapis.com}

    # Telegram token
    if [[ "$TELEGRAM_DEST" != "none" ]]; then
        while true; do
            read -p "Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            validate_bot_token "$TELEGRAM_BOT_TOKEN" && break
            echo "Invalid token"
        done
    fi
}

# ---------------------------
# Protocol Selection
# ---------------------------
select_protocols() {
    echo; info "=== Select Protocols to Deploy ==="
    echo "1) VLESS 2) Trojan 3) Trojan-Go 4) All"
    while true; do
        read -p "Choice (1-4): " p
        case $p in
            1) PROTOCOLS=("vless"); break ;;
            2) PROTOCOLS=("trojan"); break ;;
            3) PROTOCOLS=("trojango"); break ;;
            4) PROTOCOLS=("vless" "trojan" "trojango"); break ;;
            *) echo "Invalid";;
        esac
    done
}

# ---------------------------
# Telegram send
# ---------------------------
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$chat_id\",\"text\":\"$message\",\"parse_mode\":\"Markdown\"}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
}

# ---------------------------
# Deploy function
# ---------------------------
deploy() {
    local PROTO=$1
    local PATH_PROTO="${SERVICE_PREFIX}-${PROTO}"

    log "Deploying $PROTO..."

    rm -rf gcp-v2ray
    git clone https://github.com/nyeinkokoaung404/gcp-v2ray.git
    cd gcp-v2ray

    IMAGE_NAME="gcr.io/$(gcloud config get-value project)/${SERVICE_PREFIX}-${PROTO}-image"

    gcloud builds submit --tag $IMAGE_NAME --quiet
    gcloud run deploy ${SERVICE_PREFIX}-${PROTO} \
        --image $IMAGE_NAME \
        --platform managed \
        --region $REGION \
        --allow-unauthenticated \
        --cpu $CPU \
        --memory $MEMORY \
        --quiet

    URL=$(gcloud run services describe ${SERVICE_PREFIX}-${PROTO} --region $REGION --format 'value(status.url)')
    DOMAIN=$(echo $URL | sed 's|https://||')

    case $PROTO in
        vless) LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2F${PATH_PROTO}&security=tls&sni=${SNI}&type=ws#${SERVICE_PREFIX}-${PROTO}" ;;
        trojan) LINK="trojan://${UUID}@${HOST_DOMAIN}:443?path=%2F${PATH_PROTO}&sni=${SNI}#${SERVICE_PREFIX}-${PROTO}" ;;
        trojango) LINK="trojan-go://${UUID}@${HOST_DOMAIN}:443?path=%2F${PATH_PROTO}&sni=${SNI}#${SERVICE_PREFIX}-${PROTO}" ;;
    esac

    echo -e "$PROTO Deployment ✅\nURL: $URL\nLink: $LINK" >> ../deployment-info.txt
    cd ..
}

# ---------------------------
# Main
# ---------------------------
main() {
    highlight "=== GCP Cloud Run Multi-Protocol Deploy Panel ==="

    select_protocols
    select_region
    select_cpu
    select_memory
    select_telegram
    get_user_input

    rm -f deployment-info.txt

    for proto in "${PROTOCOLS[@]}"; do
        deploy "$proto"
    done

    highlight "=== Deployment Complete ==="
    cat deployment-info.txt

    # Telegram
    if [[ "$TELEGRAM_DEST" != "none" ]]; then
        MESSAGE=$(cat deployment-info.txt)
        [[ "$TELEGRAM_DEST" == "channel" || "$TELEGRAM_DEST" == "both" ]] && send_to_telegram "$TELEGRAM_CHANNEL_ID" "$MESSAGE"
        [[ "$TELEGRAM_DEST" == "bot" || "$TELEGRAM_DEST" == "both" ]] && send_to_telegram "$TELEGRAM_CHAT_ID" "$MESSAGE"
    fi
}

main "$@"
