#!/bin/bash

# EAP Application Services Manager (Multi-Repo)
# 用於管理應用服務的啟動、停止和日誌查看

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

LOG_DIR="/tmp/eap-logs"
WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$LOG_DIR"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 啟動單個服務
start_service() {
    local service=$1
    local port=$2
    local log_file="$LOG_DIR/${service}.log"

    print_info "啟動 ${service}..."

    # 檢查端口是否被佔用
    if lsof -Pi :${port} -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        print_warn "端口 ${port} 已被佔用，先關閉舊進程..."
        lsof -ti:${port} | xargs kill -9 2>/dev/null || true
        sleep 2
    fi

    # 啟動服務（cd 到各自的 repo 目錄）
    nohup bash -c "cd ${WORKSPACE_DIR}/${service} && ./gradlew bootRun" > "$log_file" 2>&1 &
    local pid=$!
    echo $pid > "$LOG_DIR/${service}.pid"

    print_info "${service} 已啟動 (PID: $pid, 日誌: $log_file)"
}

# 啟動所有服務
start_all() {
    print_info "啟動所有應用服務（包含 MCP 和 AI）..."

    start_service "eap-wallet" "8081"
    sleep 3
    start_service "eap-order" "8080"
    sleep 3
    start_service "eap-matchEngine" "8082"
    sleep 3
    start_service "eap-mcp" "8083"
    sleep 3
    start_service "eap-ai-client" "8084"

    echo ""
    print_info "所有服務已啟動！"
    print_info "查看日誌："
    echo "  - Wallet:      tail -f $LOG_DIR/eap-wallet.log"
    echo "  - Order:       tail -f $LOG_DIR/eap-order.log"
    echo "  - MatchEngine: tail -f $LOG_DIR/eap-matchEngine.log"
    echo "  - MCP:         tail -f $LOG_DIR/eap-mcp.log"
    echo "  - AI Client:   tail -f $LOG_DIR/eap-ai-client.log"
    echo ""
    print_info "或使用：./app-services.sh logs <service>"
    print_warn "注意：AI 服務需要 Ollama 運行 (ollama serve)"
}

# 停止服務
stop_service() {
    local service=$1
    local pid_file="$LOG_DIR/${service}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p $pid > /dev/null 2>&1; then
            print_info "停止 ${service} (PID: $pid)..."
            kill $pid 2>/dev/null || true
            rm "$pid_file"
        else
            print_warn "${service} 已經停止"
            rm "$pid_file"
        fi
    else
        print_warn "${service} 沒有運行"
    fi
}

# 停止所有服務
stop_all() {
    print_info "停止所有應用服務..."

    stop_service "eap-ai-client"
    stop_service "eap-mcp"
    stop_service "eap-order"
    stop_service "eap-wallet"
    stop_service "eap-matchEngine"

    # 確保端口清空
    lsof -ti:8080,8081,8082,8083,8084 | xargs kill -9 2>/dev/null || true

    print_info "所有服務已停止"
}

# 查看日誌
logs_service() {
    local service=$1
    local log_file="$LOG_DIR/${service}.log"

    if [ -f "$log_file" ]; then
        print_info "查看 ${service} 日誌 (Ctrl+C 退出)..."
        tail -f "$log_file"
    else
        print_error "日誌文件不存在: $log_file"
        exit 1
    fi
}

# 查看所有日誌
logs_all() {
    print_info "查看所有服務日誌..."

    if command -v tmux &> /dev/null; then
        tmux new-session -d -s eap-logs
        tmux split-window -h
        tmux split-window -v
        tmux select-pane -t 0
        tmux split-window -v

        tmux select-pane -t 0
        tmux send-keys "tail -f $LOG_DIR/eap-order.log" C-m
        tmux select-pane -t 1
        tmux send-keys "tail -f $LOG_DIR/eap-wallet.log" C-m
        tmux select-pane -t 2
        tmux send-keys "tail -f $LOG_DIR/eap-matchEngine.log" C-m

        tmux attach-session -t eap-logs
    else
        print_warn "tmux 未安裝，使用基本模式..."
        tail -f "$LOG_DIR"/*.log
    fi
}

# 查看狀態
status_all() {
    print_info "應用服務狀態："
    echo ""

    for service in eap-order eap-wallet eap-matchEngine eap-mcp eap-ai-client; do
        local pid_file="$LOG_DIR/${service}.pid"
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p $pid > /dev/null 2>&1; then
                echo "  ✅ ${service}: 運行中 (PID: $pid)"
            else
                echo "  ❌ ${service}: 已停止 (PID 文件存在但進程不存在)"
            fi
        else
            echo "  ⚪ ${service}: 未啟動"
        fi
    done

    echo ""
    print_info "端口使用情況："
    lsof -i:8080,8081,8082,8083,8084 -sTCP:LISTEN 2>/dev/null || echo "  無應用服務運行"
}

# 主程序
case "$1" in
    start)
        if [ -z "$2" ]; then
            start_all
        else
            case "$2" in
                order)   start_service "eap-order" "8080" ;;
                wallet)  start_service "eap-wallet" "8081" ;;
                match)   start_service "eap-matchEngine" "8082" ;;
                mcp)     start_service "eap-mcp" "8083" ;;
                ai)      start_service "eap-ai-client" "8084" ;;
                *)
                    print_error "未知的服務: $2"
                    echo "可用服務: order, wallet, match, mcp, ai"
                    exit 1
                    ;;
            esac
        fi
        ;;
    stop)
        if [ -z "$2" ]; then
            stop_all
        else
            case "$2" in
                order)   stop_service "eap-order" ;;
                wallet)  stop_service "eap-wallet" ;;
                match)   stop_service "eap-matchEngine" ;;
                mcp)     stop_service "eap-mcp" ;;
                ai)      stop_service "eap-ai-client" ;;
                *)       stop_service "eap-$2" ;;
            esac
        fi
        ;;
    restart)
        stop_all
        sleep 3
        start_all
        ;;
    logs)
        if [ -z "$2" ]; then
            logs_all
        else
            case "$2" in
                order)   logs_service "eap-order" ;;
                wallet)  logs_service "eap-wallet" ;;
                match)   logs_service "eap-matchEngine" ;;
                mcp)     logs_service "eap-mcp" ;;
                ai)      logs_service "eap-ai-client" ;;
                *)       logs_service "eap-$2" ;;
            esac
        fi
        ;;
    status)
        status_all
        ;;
    *)
        echo "EAP Application Services Manager (Multi-Repo)"
        echo ""
        echo "使用方法："
        echo "  $0 start [service]     - 啟動服務 (order|wallet|match|mcp|ai|all)"
        echo "  $0 stop [service]      - 停止服務"
        echo "  $0 restart             - 重啟所有服務"
        echo "  $0 logs [service]      - 查看日誌"
        echo "  $0 status              - 查看狀態"
        exit 1
        ;;
esac
