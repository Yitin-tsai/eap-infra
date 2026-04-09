.PHONY: help dev-up dev-down dev-restart dev-status dev-logs dev-clean build test run-all quick-test api-docs

SERVICES = eap-order eap-wallet eap-matchEngine eap-mcp eap-ai-client

help:
	@echo "EAP Project (Multi-Repo) - 可用命令："
	@echo ""
	@echo "開發環境服務："
	@echo "  make dev-up        - 啟動開發服務 (PostgreSQL, RabbitMQ, Redis)"
	@echo "  make dev-down      - 停止開發服務"
	@echo "  make dev-restart   - 重啟開發服務"
	@echo "  make dev-status    - 查看服務狀態"
	@echo "  make dev-logs      - 查看服務日誌"
	@echo "  make dev-clean     - 清理所有數據"
	@echo ""
	@echo "應用服務："
	@echo "  make run-all       - 啟動所有應用服務 (需先 make dev-up)"
	@echo "  make run-order     - 啟動 Order Service (8080)"
	@echo "  make run-wallet    - 啟動 Wallet Service (8081)"
	@echo "  make run-match     - 啟動 MatchEngine Service (8082)"
	@echo "  make run-mcp       - 啟動 MCP Server (8083)"
	@echo "  make run-ai        - 啟動 AI Client (8084)"
	@echo ""
	@echo "AI 服務："
	@echo "  make ai-start      - 啟動 AI 相關服務 (MCP + AI Client)"
	@echo "  make ai-test       - 測試 AI 聊天功能"
	@echo ""
	@echo "建置與測試："
	@echo "  make build         - 構建所有服務"
	@echo "  make test          - 運行所有測試"
	@echo "  make quick-test    - 快速測試交易流程"
	@echo ""
	@echo "文件："
	@echo "  make api-docs      - 匯出 OpenAPI 規格到 docs/api/ (需服務啟動)"
	@echo ""
	@echo "快速開始："
	@echo "  1. make dev-up     # 啟動開發服務"
	@echo "  2. make run-all    # 啟動應用"
	@echo "  3. make ai-start   # 啟動 AI 服務 (需要 Ollama)"

# 啟動開發服務
dev-up:
	@echo "🚀 啟動開發服務..."
	@docker-compose up -d
	@echo "✅ 服務已啟動"
	@make dev-status

# 停止開發服務
dev-down:
	@echo "🛑 停止開發服務..."
	@docker-compose down
	@echo "✅ 服務已停止"

# 重啟開發服務
dev-restart:
	@echo "🔄 重啟開發服務..."
	@docker-compose restart
	@echo "✅ 服務已重啟"

# 查看服務狀態
dev-status:
	@echo "📊 服務狀態："
	@docker-compose ps
	@echo ""
	@echo "💻 資源使用："
	@docker stats --no-stream eap-postgres eap-rabbitmq eap-redis 2>/dev/null || echo "無法獲取資源使用情況"

# 查看日誌
dev-logs:
	@docker-compose logs -f

# 清理數據
dev-clean:
	@echo "⚠️  警告：這將刪除所有數據"
	@read -p "確定繼續嗎？(y/N): " confirm && [ "$$confirm" = "y" ] && docker-compose down -v || echo "已取消"

# 構建所有服務
build:
	@echo "🔨 構建所有服務..."
	@for svc in $(SERVICES); do \
		echo "  Building $$svc..." && \
		(cd $$svc && ./gradlew build -x test) || exit 1; \
	done
	@echo "✅ 全部構建完成"

# 運行所有測試
test:
	@echo "🧪 運行所有測試..."
	@for svc in $(SERVICES); do \
		echo "  Testing $$svc..." && \
		(cd $$svc && ./gradlew test) || exit 1; \
	done
	@echo "✅ 全部測試完成"

# 啟動所有應用服務（背景模式）
run-all:
	@echo "🚀 啟動所有應用服務..."
	@./app-services.sh start
	@echo ""
	@echo "📝 查看日誌: make logs-order, make logs-wallet, make logs-match, make logs-mcp, make logs-ai"

# 啟動單個服務
run-order:
	@echo "🚀 啟動 Order Service..."
	@cd eap-order && ./gradlew bootRun

run-wallet:
	@echo "🚀 啟動 Wallet Service..."
	@cd eap-wallet && ./gradlew bootRun

run-match:
	@echo "🚀 啟動 MatchEngine..."
	@cd eap-matchEngine && ./gradlew bootRun

run-mcp:
	@echo "🚀 啟動 MCP Server..."
	@cd eap-mcp && ./gradlew bootRun

run-ai:
	@echo "🚀 啟動 AI Client..."
	@cd eap-ai-client && ./gradlew bootRun

# 應用服務管理
app-start:
	@./app-services.sh start

app-stop:
	@./app-services.sh stop

app-restart:
	@./app-services.sh restart

app-status:
	@./app-services.sh status

app-logs:
	@./app-services.sh logs

# 查看單個服務日誌
logs-order:
	@./app-services.sh logs order

logs-wallet:
	@./app-services.sh logs wallet

logs-match:
	@./app-services.sh logs match

logs-mcp:
	@./app-services.sh logs mcp

logs-ai:
	@./app-services.sh logs ai

# AI 服務管理
ai-start:
	@echo "🤖 啟動 AI 相關服務..."
	@echo "⚠️  請確保 Ollama 已啟動並載入模型 (ollama serve + ollama pull llama3.1)"
	@echo ""
	@./app-services.sh start mcp
	@sleep 5
	@./app-services.sh start ai
	@echo ""
	@echo "✅ AI 服務已啟動"
	@echo "   - MCP Server: http://localhost:8083"
	@echo "   - AI Client:  http://localhost:8084"
	@echo ""
	@echo "📝 測試 AI 聊天: make ai-test"

ai-stop:
	@echo "🛑 停止 AI 服務..."
	@./app-services.sh stop ai
	@./app-services.sh stop mcp

# AI 聊天測試
ai-test:
	@echo "🤖 測試 AI 聊天功能..."
	@echo ""
	@echo "1. 測試市場指標查詢..."
	@curl -s -X POST http://localhost:8084/api/chat \
		-H "Content-Type: application/json" \
		-d '{"message": "查詢目前的市場指標"}' | jq .
	@echo ""
	@echo "2. 測試訂單簿查詢..."
	@curl -s -X POST http://localhost:8084/api/chat \
		-H "Content-Type: application/json" \
		-d '{"message": "顯示訂單簿前5檔"}' | jq .
	@echo ""
	@echo "✅ AI 測試完成"

# 快速測試
quick-test:
	@echo "🧪 快速測試交易流程..."
	@echo "1. 註冊用戶..."
	@curl -s -X POST http://localhost:8081/eap-wallet/register \
		-H "Content-Type: application/json" \
		-d '{"userId": "550e8400-e29b-41d4-a716-446655440001"}' | jq .
	@curl -s -X POST http://localhost:8081/eap-wallet/register \
		-H "Content-Type: application/json" \
		-d '{"userId": "550e8400-e29b-41d4-a716-446655440002"}' | jq .
	@echo ""
	@echo "2. 買方下單..."
	@curl -s -X POST http://localhost:8080/eap-order/bid/buy \
		-H "Content-Type: application/json" \
		-d '{"bidder": "550e8400-e29b-41d4-a716-446655440000", "bidPrice": 100, "amount": 10}' | jq .
	@echo ""
	@echo "3. 等待 Outbox Poller 發布事件..."
	@sleep 2
	@echo ""
	@echo "4. 賣方下單（將觸發撮合）..."
	@curl -s -X POST http://localhost:8080/eap-order/bid/sell \
		-H "Content-Type: application/json" \
		-d '{"seller": "450e8400-e29b-41d4-a716-446655440001", "sellPrice": 100, "amount": 10}' | jq .
	@echo ""
	@sleep 2
	@echo "✅ 測試完成！檢查結果："
	@echo ""
	@echo "--- Outbox 表 ---"
	@docker exec eap-postgres psql -U admin -d eapdb -c "SELECT id, event_type, status FROM wallet_service.outbox ORDER BY id;"
	@echo ""
	@echo "--- Orders 備份表 ---"
	@docker exec eap-postgres psql -U admin -d eapdb -c "SELECT order_id, order_type, status FROM order_service.orders;"
	@echo ""
	@echo "--- 成交記錄 ---"
	@docker exec eap-postgres psql -U admin -d eapdb -c "SELECT match_id, price, amount, order_type FROM order_service.match_history ORDER BY id DESC LIMIT 5;"

# 完整測試流程（包含 AI）
full-test: quick-test ai-test
	@echo ""
	@echo "✅ 完整測試流程完成"

# 匯出 OpenAPI 規格（需要服務已啟動）
api-docs:
	@echo "📄 匯出 OpenAPI 規格到 docs/api/ ..."
	@mkdir -p docs/api
	@curl -sf http://localhost:8080/eap-order/v3/api-docs | python3 -m json.tool > docs/api/order-service.json && echo "  ✅ order-service.json" || echo "  ❌ Order Service 未啟動"
	@curl -sf http://localhost:8081/eap-wallet/v3/api-docs | python3 -m json.tool > docs/api/wallet-service.json && echo "  ✅ wallet-service.json" || echo "  ❌ Wallet Service 未啟動"
	@curl -sf http://localhost:8082/match-engine/v3/api-docs | python3 -m json.tool > docs/api/match-engine.json && echo "  ✅ match-engine.json" || echo "  ❌ MatchEngine 未啟動"
	@echo ""
	@echo "📝 規格檔已存到 docs/api/"
