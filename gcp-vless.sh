#!/bin/bash

# Script: GCP V2Ray Deployer with Telegram Bot
# Author: Assistant  
# Version: 2.0 - VLESS Version

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
SERVICE_NAME="vless-proxy"
REGION="us-central1"
PORT="8080"

# Generate UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
PATH_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)

# Functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
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

# Get Telegram info from user
get_telegram_info() {
    echo ""
    print_info "إعدادات بوت Telegram"
    echo "======================"
    
    while true; do
        read -p "أدخل رمز بوت Telegram (BOT_TOKEN): " TELEGRAM_BOT_TOKEN
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            break
        else
            print_error "يجب إدخال رمز البوت"
        fi
    done
    
    while true; do
        read -p "أدخل معرف الدردشة (CHAT_ID): " TELEGRAM_CHAT_ID
        if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            break
        else
            print_error "يجب إدخال معرف الدردشة"
        fi
    done
}

# Get project and region
get_project_info() {
    echo ""
    print_info "إعدادات Google Cloud"
    echo "====================="
    
    # Get current project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -n "$CURRENT_PROJECT" ]]; then
        print_info "المشروع الحالي: $CURRENT_PROJECT"
        read -p "هل تريد استخدام هذا المشروع؟ (y/n): " use_current
        if [[ $use_current == "y" || $use_current == "Y" ]]; then
            PROJECT_ID=$CURRENT_PROJECT
        else
            list_projects
        fi
    else
        list_projects
    fi
    
    # Get region
    echo ""
    print_info "المناطق المتاحة:"
    echo "1. us-central1 (الولايات المتحدة)"
    echo "2. europe-west1 (أوروبا)" 
    echo "3. asia-east1 (آسيا)"
    echo "4. me-west1 (الشرق الأوسط)"
    read -p "اختر المنطقة (1-4) [افتراضي: 1]: " region_choice
    
    case $region_choice in
        2) REGION="europe-west1" ;;
        3) REGION="asia-east1" ;;
        4) REGION="me-west1" ;;
        *) REGION="us-central1" ;;
    esac
    
    # Get service name
    echo ""
    read -p "أدخل اسم الخدمة [افتراضي: $SERVICE_NAME]: " input_name
    if [[ -n "$input_name" ]]; then
        SERVICE_NAME="$input_name"
    fi
}

list_projects() {
    print_info "جاري جلب قائمة المشاريع..."
    gcloud projects list --format="table(projectId,name)" --sort-by=projectId
    
    echo ""
    while true; do
        read -p "أدخل معرف المشروع (Project ID): " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            # Verify project exists
            if gcloud projects describe $PROJECT_ID &>/dev/null; then
                gcloud config set project $PROJECT_ID
                break
            else
                print_error "المشروع غير موجود أو لا يمكن الوصول إليه"
            fi
        fi
    done
}

# Send message to Telegram
send_telegram_message() {
    local message="$1"
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$message" \
        -d "parse_mode=HTML" > /dev/null; then
        print_success "تم إرسال الرسالة إلى Telegram"
    else
        print_warning "فشل إرسال الرسالة إلى Telegram"
    fi
}

# Create Dockerfile with Xray (supports VLESS)
create_dockerfile() {
    cat > Dockerfile << EOF
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip

# Install Xray (supports VLESS)
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.11/Xray-linux-64.zip -o xray.zip && \\
    unzip xray.zip && \\
    mv xray /usr/bin/ && \\
    chmod +x /usr/bin/xray && \\
    rm xray.zip geoip.dat geosite.dat

# Create Xray config directory
RUN mkdir -p /etc/xray

# Create V2Ray config
COPY config.json /etc/xray/

EXPOSE $PORT

CMD ["xray", "run", "-config", "/etc/xray/config.json"]
EOF

    # Create Xray config file with VLESS
    cat > config.json << EOF
{
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h3", "h2", "http/1.1"],
                    "fingerprint": "randomized"
                },
                "wsSettings": {
                    "path": "/tg-$PATH_SUFFIX"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
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
}

# Deploy to Cloud Run
deploy_service() {
    print_info "جاري النشر على Google Cloud Run..."
    
    # Enable required services
    print_info "تفعيل الخدمات المطلوبة..."
    gcloud services enable run.googleapis.com containerregistry.googleapis.com --quiet
    
    # Build and deploy
    print_info "جاري بناء الصورة (قد يستغرق عدة دقائق)..."
    gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME --quiet
    
    print_info "جاري نشر الخدمة..."
    gcloud run deploy $SERVICE_NAME \
        --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
        --platform managed \
        --region $REGION \
        --allow-unauthenticated \
        --port $PORT \
        --cpu=1 \
        --memory=512Mi \
        --min-instances=0 \
        --max-instances=3 \
        --quiet
}

# Get service URL
get_service_url() {
    gcloud run services describe $SERVICE_NAME \
        --platform managed \
        --region $REGION \
        --format="value(status.url)" 2>/dev/null
}

# Generate VLESS configuration
generate_vless_config() {
    local service_url=$1
    local domain=$(echo $service_url | sed 's|https://||')
    
    # Create VLESS link like your example
    local vless_link="vless://${UUID}@${domain}:443?path=%2Ftg-${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
    
    echo "$vless_link"
}

# Test the service
test_service() {
    local service_url=$1
    print_info "جاري اختبار الخدمة..."
    
    if curl -s --retry 3 --retry-delay 2 "$service_url" > /dev/null; then
        print_success "الخدمة تعمل بشكل صحيح"
        return 0
    else
        print_warning "الخدمة قد تحتاج بعض الوقت لتفعيل TLS"
        return 1
    fi
}

# Main function
main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════╗
║      GCP VLESS Deployer Script      ║
║         Google Cloud Run            ║
║           VLESS + WS + TLS          ║
╚══════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Check dependencies
    check_dependencies
    
    # Check Google Cloud login
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "يجب تسجيل الدخول إلى Google Cloud أولاً"
        gcloud auth login --no-launch-browser

fi
    
    # Get project and Telegram info
    get_project_info
    get_telegram_info
    
    # Display configuration summary
    echo ""
    print_info "ملخص الإعدادات:"
    echo "────────────────"
    echo "• المشروع: $PROJECT_ID"
    echo "• الخدمة: $SERVICE_NAME" 
    echo "• المنطقة: $REGION"
    echo "• UUID: $UUID"
    echo "• المسار: /tg-$PATH_SUFFIX"
    echo ""
    
    read -p "هل تريد متابعة النشر؟ (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        print_info "تم الإلغاء"
        exit 0
    fi
    
    # Create Docker configuration
    print_info "جاري إنشاء ملفات التكوين..."
    create_dockerfile
    
    # Deploy service
    deploy_service
    
    # Get service URL
    print_info "جاري الحصول على رابط الخدمة..."
    SERVICE_URL=$(get_service_url)
    
    if [[ -z "$SERVICE_URL" ]]; then
        print_error "فشل في الحصول على رابط الخدمة"
        exit 1
    fi
    
    # Wait a bit for service to be ready
    sleep 10
    
    # Test service
    test_service "$SERVICE_URL"
    
    # Generate VLESS link
    VLESS_LINK=$(generate_vless_config "$SERVICE_URL")
    
    # Display results
    echo ""
    print_success "✅ تم النشر بنجاح!"
    echo ""
    echo -e "${GREEN}معلومات الخدمة:${NC}"
    echo "📦 اسم الخدمة: $SERVICE_NAME"
    echo "🌐 رابط الخدمة: $SERVICE_URL"
    echo "📍 المنطقة: $REGION"
    echo ""
    echo -e "${GREEN}معلومات VLESS:${NC}"
    echo "🔑 UUID: $UUID"
    echo "🛣️ المسار: /tg-$PATH_SUFFIX"
    echo "🔒 الأمان: TLS + WS"
    echo ""
    echo -e "${CYAN}🔗 رابط VLESS:${NC}"
    echo "$VLESS_LINK"
    echo ""
    
    # Send to Telegram
    print_info "جاري إرسال النتائج إلى Telegram..."
    local telegram_message="🚀 <b>تم نشر VLESS بنجاح على Google Cloud Run</b>

📦 <b>معلومات الخدمة:</b>
• 🔗 <b>الرابط:</b> <code>$SERVICE_URL</code>
• 📍 <b>المنطقة:</b> $REGION
• ⚡ <b>النظام:</b> Cloud Run

🔑 <b>معلومات VLESS:</b>
• 🆔 <b>UUID:</b> <code>$UUID</code>
• 🛣️ <b>المسار:</b> <code>/tg-$PATH_SUFFIX</code>
• 🌐 <b>البروتوكول:</b> VLESS + WebSocket + TLS
• 🔒 <b>الأمان:</b> TLS 1.3
• 🛡️ <b>Fingerprint:</b> Randomized

🔗 <b>رابط VLESS:</b>
<code>$VLESS_LINK</code>

📝 <b>ملاحظة:</b> الرابط جاهز للاستخدام في تطبيقات V2Ray/Xray"

    # Send main message
    send_telegram_message "$telegram_message"
    
    # Also send the VLESS link separately for easy copying
    send_telegram_message "🔗 <b>رابط VLESS للنسخ:</b>\n<code>$VLESS_LINK</code>"
    
    # Cleanup
    rm -f Dockerfile config.json
    
    echo ""
    print_info "يمكنك الآن استخدام رابط VLESS في تطبيقات V2Ray/Xray"
    echo ""
    print_warning "لإيقاف الخدمة استخدم:"
    echo "gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
    echo ""
    print_success "تم الانتهاء بنجاح! 🎉"
}

# Handle script interruption
cleanup() {
    echo ""
    print_warning "تم إيقاف السكريبت"
    rm -f Dockerfile config.json
    exit 1
}

trap cleanup SIGINT

# Run main function
main "$@"
