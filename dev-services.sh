#!/bin/bash

# EAP Development Services Manager
# 用於快速啟動和停止開發環境所需的服務

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函數：打印彩色訊息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 函數：啟動服務
start_services() {
    print_info "啟動 EAP 開發服務 (PostgreSQL, RabbitMQ, Redis)..."
    docker-compose up -d
    
    print_info "等待服務健康檢查..."
    sleep 5
    
    print_info "服務狀態："
    docker-compose ps
    
    echo ""
    print_info "服務 URL："
    echo "  - PostgreSQL: localhost:5432 (user: admin, password: admin123, db: eapdb)"
    echo "  - RabbitMQ:   localhost:5672 (AMQP)"
    echo "  - RabbitMQ UI: http://localhost:15672 (user: admin, password: admin123)"
    echo "  - Redis:      localhost:6379"
}

# 函數：停止服務
stop_services() {
    print_info "停止 EAP 開發服務..."
    docker-compose down
    print_info "服務已停止"
}

# 函數：重啟服務
restart_services() {
    print_info "重啟 EAP 開發服務..."
    docker-compose restart
    print_info "服務已重啟"
}

# 函數：查看日誌
logs_services() {
    print_info "查看服務日誌 (Ctrl+C 退出)..."
    docker-compose logs -f
}

# 函數：查看狀態
status_services() {
    print_info "服務狀態："
    docker-compose ps
    
    echo ""
    print_info "資源使用情況："
    docker stats --no-stream eap-postgres eap-rabbitmq eap-redis 2>/dev/null || print_warn "無法獲取資源使用情況"
}

# 函數：清理數據
clean_services() {
    print_warn "這將刪除所有數據（PostgreSQL、Redis、RabbitMQ）"
    read -p "確定要繼續嗎？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "停止並清理服務..."
        docker-compose down -v
        print_info "數據已清理"
    else
        print_info "已取消"
    fi
}

# 函數：進入容器
shell_services() {
    local service=$1
    if [ -z "$service" ]; then
        print_error "請指定服務名稱: postgres, rabbitmq, redis"
        exit 1
    fi
    
    case $service in
        postgres)
            print_info "連接到 PostgreSQL..."
            docker exec -it eap-postgres psql -U admin -d eapdb
            ;;
        rabbitmq)
            print_info "連接到 RabbitMQ..."
            docker exec -it eap-rabbitmq bash
            ;;
        redis)
            print_info "連接到 Redis CLI..."
            docker exec -it eap-redis redis-cli
            ;;
        *)
            print_error "未知的服務: $service"
            print_error "可用的服務: postgres, rabbitmq, redis"
            exit 1
            ;;
    esac
}

# 主程序
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        status_services
        ;;
    logs)
        logs_services
        ;;
    clean)
        clean_services
        ;;
    shell)
        shell_services "$2"
        ;;
    *)
        echo "EAP Development Services Manager"
        echo ""
        echo "使用方法："
        echo "  $0 start              - 啟動所有服務"
        echo "  $0 stop               - 停止所有服務"
        echo "  $0 restart            - 重啟所有服務"
        echo "  $0 status             - 查看服務狀態和資源使用"
        echo "  $0 logs               - 查看服務日誌"
        echo "  $0 clean              - 停止服務並清理所有數據"
        echo "  $0 shell <service>    - 進入服務容器 (postgres|rabbitmq|redis)"
        echo ""
        echo "範例："
        echo "  $0 start              # 啟動服務"
        echo "  $0 shell postgres     # 連接到 PostgreSQL"
        echo "  $0 shell redis        # 連接到 Redis CLI"
        exit 1
        ;;
esac
