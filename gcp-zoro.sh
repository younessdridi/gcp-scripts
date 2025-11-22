#!/bin/bash

set -euo pipefail

# ==============================
#        COLORS
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
info()   { echo -e "${BLUE}[INFO]${NC} $1"; }

# ==============================
#      VALIDATION FUNCTIONS
# ==============================
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $uuid_pattern ]] || { error "Invalid UUID format: $1"; return 1; }
}

validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    [[ $1 =~ $token_pattern ]] || { error "Invalid Telegram Bot Token format"; return 1; }
}

validate_channel_id() {
    [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Channel ID format"; return 1; }
}

validate_chat_id() {
    [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Chat ID format"; return 1; }
}

# ==============================
#      CPU & MEMORY
# ==============================
select_cpu() {
    echo
    info "=== CPU Configuration ==="
    echo "1. 1 CPU Core (Default)"
    echo "2. 2 CPU Cores"
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores"
    echo
    while true; do
        read -p "Select CPU cores (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
    info "Selected CPU: $CPU core(s)"
}

select_memory() {
    echo
    info "=== Memory Configuration ==="
    echo "Memory Options:"
    echo "1. 512Mi"
    echo "2. 1Gi"
    echo "3. 2Gi"
    echo "4. 4Gi"
    echo "5. 8Gi"
    echo "6. 16Gi"
    echo
    while true; do
        read -p "Select memory (1-6): " memory_choice
        case $memory_choice in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-6." ;;
        esac
    done
    info "Selected Memory: $MEMORY"
}

# ==============================
#      REGION SELECTION
# ==============================
select_region() {
    echo
    info "=== Region Selection ==="
    echo "1. us-central1 (Iowa, USA)"
    echo "2. us-west1 (Oregon, USA)"
    echo "3. us-east1 (South Carolina, USA)"
    echo "4. europe-west1 (Belgium)"
    echo "5. asia-southeast1 (Singapore)"
    echo "6. asia-northeast1 (Tokyo, Japan)"
    echo "7. asia-east1 (Taiwan)"
    echo
    while true; do
        read -p "Select region (1-7): " region_choice
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="asia-southeast1"; break ;;
            6) REGION="asia-northeast1"; break ;;
            7) REGION="asia-east1"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-7." ;;
        esac
    done
    info "Selected region: $REGION"
}

# ==============================
#   TELEGRAM DESTINATION
# ==============================
select_telegram_destination() {
    echo
    info "=== Telegram Destination ==="
    echo "1. Channel only"
    echo "2. Bot private message only"
    echo "3. Both Channel & Bot"
    echo "4. None"
    echo
    while true; do
        read -p "Select destination (1-4): " telegram_choice
        case $telegram_choice in
            1) TELEGRAM_DESTINATION="channel"
               read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
               validate_channel_id "$TELEGRAM_CHANNEL_ID"; break ;;
            2) TELEGRAM_DESTINATION="bot"
               read -p "Enter Chat ID: " TELEGRAM_CHAT_ID
               validate_chat_id "$TELEGRAM_CHAT_ID"; break ;;
            3) TELEGRAM_DESTINATION="both"
               read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
               validate_channel_id "$TELEGRAM_CHANNEL_ID"
               read -p "Enter Chat ID: " TELEGRAM_CHAT_ID
               validate_chat_id "$TELEGRAM_CHAT_ID"; break ;;
            4) TELEGRAM_DESTINATION="none"; break ;;
            *) echo "Invalid selection. Please enter 1-4." ;;
        esac
    done
}

# ==============================
#      USER INPUT
# ==============================
get_user_input() {
    echo
    info "=== Service Configuration ==="
    # Select protocol
    echo "Select Protocol:"
    echo "1. VLESS-WS"
    echo "2. VMESS-WS"
    echo "3. TROJAN-WS"
    echo "4. Shadowsocks-2022"
    echo "5. REALITY"
    while true; do
        read -p "Choice (1-5): " proto_choice
        case $proto_choice in
            1) PROTOCOL="VLESS-WS"; break ;;
            2) PROTOCOL="VMESS-WS"; break ;;
            3) PROTOCOL="TROJAN-WS"; break ;;
            4) PROTOCOL="Shadowsocks-2022"; break ;;
            5) PROTOCOL="REALITY"; break ;;
            *) echo "Invalid selection. Choose 1-5." ;;
        esac
    done
    
    # Service Name
    read -p "Enter Service Name: " SERVICE_NAME
    
    # UUID
    UUID_DEFAULT=$(cat /proc/sys/kernel/random/uuid)
    read -p "Enter UUID [default: $UUID_DEFAULT]: " UUID
    UUID=${UUID:-$UUID_DEFAULT}
    validate_uuid "$UUID"
    
    # Host domain
    read -p "Enter Host Domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
    
    # Telegram Bot Token
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        validate_bot_token "$TELEGRAM_BOT_TOKEN"
    fi
}

# ==============================
#      TELEGRAM SEND FUNCTION
# ==============================
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    curl -s -X POST \
         -H "Content-Type: application/json" \
         -d "{\"chat_id\":\"$chat_id\",\"text\":\"$message\",\"parse_mode\":\"MARKDOWN\"}" \
         "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" > /dev/null
}

send_deployment_notification() {
    MESSAGE="$1"
    case $TELEGRAM_DESTINATION in
        channel) send_to_telegram "$TELEGRAM_CHANNEL_ID" "$MESSAGE" ;;
        bot) send_to_telegram "$TELEGRAM_CHAT_ID" "$MESSAGE" ;;
        both)
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$MESSAGE"
            send_to_telegram "$TELEGRAM_CHAT_ID" "$MESSAGE"
            ;;
        none) log "Skipping Telegram notification" ;;
    esac
}

# ==============================
#      MAIN DEPLOY FUNCTION
# ==============================
deploy_service() {
    PROJECT_ID=$(gcloud config get-value project)
    log "Starting deployment..."
    
    # Enable APIs
    gcloud services enable cloudbuild.googleapis.com run.googleapis.com iam.googleapis.com --quiet
    
    # Clone repo
    rm -rf gcp-v2ray
    git clone https://github.com/nyeinkokoaung404/gcp-v2ray.git
    cd gcp-v2ray
    
    # Build image
    gcloud builds submit --tag gcr.io/${PROJECT_ID}/${SERVICE_NAME}-image --quiet
    
    # Deploy to Cloud Run
    gcloud run deploy "$SERVICE_NAME" \
        --image gcr.io/${PROJECT_ID}/${SERVICE_NAME}-image \
        --platform managed \
        --region $REGION \
        --allow-unauthenticated \
        --cpu $CPU \
        --memory $MEMORY \
        --quiet
    
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --region $REGION --format 'value(status.url)' --quiet)
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')
    
    # Generate share link
    SHARE_LINK="${PROTOCOL,,}://${UUID}@${HOST_DOMAIN}:443?path=%2Ftg-%40zoro&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
    
    # Compose message
    MESSAGE="*Cloud Run Deployment → Successful ✅*
━━━━━━━━━━━━━━
• Project: \`${PROJECT_ID}\`
• Service: \`${SERVICE_NAME}\`
• Protocol: \`${PROTOCOL}\`
• Region: \`${REGION}\`
• CPU: \`${CPU}\`
• Memory: \`${MEMORY}\`
• Domain: \`${DOMAIN}\`

🔗 Share Link:
\`\`\`
${SHARE_LINK}
\`\`\`
━━━━━━━━━━━━━━"
    
    echo "$MESSAGE" > ../deployment-info.txt
    log "Deployment info saved to deployment-info.txt"
    echo
    info "=== Deployment Info ==="
    echo "$MESSAGE"
    
    # Send to Telegram
    send_deployment_notification "$MESSAGE"
    
    log "Deployment completed!"
    cd ..
}

# ==============================
#        MAIN SCRIPT
# ==============================
main() {
    info "=== Multi Protocol Cloud Run Deployment (zoro) ==="
    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input
    deploy_service
}

main "$@"
