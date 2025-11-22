#!/bin/bash

set -euo pipefail

# =========================
# ZORO MULTI-PROTOCOL CLOUD RUN DEPLOYER
# Author: @zoro_40_khanchlyyy
# =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ===== VALIDATIONS =====
validate_uuid() { [[ $1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { error "Invalid UUID: $1"; return 1; }; }
validate_bot_token() { [[ $1 =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35,}$ ]] || { error "Invalid Telegram Bot Token"; return 1; }; }
validate_chat_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Chat ID: $1"; return 1; }; }

# ===== CONFIG SELECTION =====
select_cpu() {
    echo; info "=== CPU ==="
    echo "1)1 2)2 3)4 4)8"
    while true; do read -p "CPU (1-4): " c; case $c in 1) CPU=1; break;;2) CPU=2; break;;3) CPU=4; break;;4) CPU=8; break;;*) echo "1-4";; esac; done
}

select_memory() {
    echo; info "=== Memory ==="
    echo "1)512Mi 2)1Gi 3)2Gi 4)4Gi 5)8Gi 6)16Gi"
    while true; do read -p "Memory (1-6): " m; case $m in 1) MEMORY="512Mi"; break;;2) MEMORY="1Gi"; break;;3) MEMORY="2Gi"; break;;4) MEMORY="4Gi"; break;;5) MEMORY="8Gi"; break;;6) MEMORY="16Gi"; break;;*) echo "1-6";; esac; done
}

select_region() {
    echo; info "=== Region ==="
    echo "1)us-central1 2)us-west1 3)us-east1 4)europe-west1 5)asia-southeast1 6)asia-northeast1 7)asia-east1"
    while true; do read -p "Region (1-7): " r; case $r in 1) REGION="us-central1"; break;;2) REGION="us-west1"; break;;3) REGION="us-east1"; break;;4) REGION="europe-west1"; break;;5) REGION="asia-southeast1"; break;;6) REGION="asia-northeast1"; break;;7) REGION="asia-east1"; break;;*) echo "1-7";; esac; done
}

select_telegram() {
    echo; info "=== Telegram ==="
    echo "1) Channel 2) Bot 3) Both 4) None"
    while true; do read -p "Select (1-4): " t; case $t in 1) TELE_DEST="channel"; break;;2) TELE_DEST="bot"; break;;3) TELE_DEST="both"; break;;4) TELE_DEST="none"; break;;*) echo "1-4";; esac; done
}

get_telegram_info() {
    if [[ "$TELE_DEST" != "none" ]]; then
        while true; do read -p "Bot Token: " TG_BOT_TOKEN; validate_bot_token "$TG_BOT_TOKEN" && break; done
        [[ "$TELE_DEST" == "bot" || "$TELE_DEST" == "both" ]] && { while true; do read -p "Chat ID: " TELE_CHAT_ID; validate_chat_id "$TELE_CHAT_ID" && break; done; }
        [[ "$TELE_DEST" == "channel" || "$TELE_DEST" == "both" ]] && { while true; do read -p "Channel ID: " TELE_CHANNEL_ID; validate_chat_id "$TELE_CHANNEL_ID" && break; done; }
    fi
}

send_telegram() { local chat="$1"; local msg="$2"; curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" -d chat_id="$chat" -d text="$msg" -d parse_mode="Markdown"; }

select_protocols() {
    echo; info "=== Protocols ==="
    echo "1) V2Ray VMess 2) VLESS WS 3) Trojan-Go WS 4) Shadowsocks2022 WS"
    echo "Enter numbers separated by space"
    while true; do read -p "Choice: " proto_choices; [[ -n "$proto_choices" ]] && break; done
}

# ===== GENERATE CONFIGS & LINKS =====
generate_configs() {
    mkdir -p build && cd build
    > ../deployment-info.txt
    DOMAIN="m.googleapis.com"
    for p in $proto_choices; do
        UUID=$(cat /proc/sys/kernel/random/uuid)
        case $p in
            1) NAME="zoro-vmess"; LINK="vmess://${UUID}@${DOMAIN}:443?type=ws&security=tls&host=${DOMAIN}#${NAME}";;
            2) NAME="zoro-vless"; LINK="vless://${UUID}@${DOMAIN}:443?type=ws&security=tls&host=${DOMAIN}#${NAME}";;
            3) NAME="zoro-trojan"; LINK="trojan://${UUID}@${DOMAIN}:443?type=ws&security=tls&host=${DOMAIN}#${NAME}";;
            4) NAME="zoro-ss2022"; LINK="ss://${UUID}@${DOMAIN}:443?type=ws&security=tls&host=${DOMAIN}#${NAME}";;
            *) continue;;
        esac
        echo "$LINK" >> ../deployment-info.txt
        cat <<EOF > ${NAME}-config.json
# $NAME config
UUID: $UUID
Domain: $DOMAIN
Port: 443
EOF
    done
    cd ..
}

# ===== DEPLOY TO CLOUD RUN =====
deploy_all() {
    PROJECT_ID=$(gcloud config get-value project)
    cd build
    for p in $proto_choices; do
        case $p in
            1) NAME="zoro-vmess";;
            2) NAME="zoro-vless";;
            3) NAME="zoro-trojan";;
            4) NAME="zoro-ss2022";;
            *) continue;;
        esac
        log "Building image $NAME..."
        gcloud builds submit --tag gcr.io/${PROJECT_ID}/${NAME} --quiet
        log "Deploying $NAME..."
        gcloud run deploy $NAME --image gcr.io/${PROJECT_ID}/${NAME} --platform managed \
            --region $REGION --allow-unauthenticated --cpu $CPU --memory $MEMORY --quiet
        URL=$(gcloud run services describe $NAME --region $REGION --format="value(status.url)")
        echo "$NAME URL: $URL" >> ../deployment-info.txt
    done
    cd ..
}

# ===== MAIN =====
main() {
    info "=== ZORO MULTI-PROTOCOL DEPLOYER ==="
    select_region
    select_cpu
    select_memory
    select_telegram
    get_telegram_info
    select_protocols
    generate_configs
    deploy_all
    info "✅ Deployment finished!"
    cat deployment-info.txt
    [[ "$TELE_DEST" != "none" ]] && send_telegram "${TELE_CHAT_ID:-$TELE_CHANNEL_ID}" "$(cat deployment-info.txt)"
}

main "$@"
