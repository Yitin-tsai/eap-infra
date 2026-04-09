# EAP 開發環境快速指南

## 🚀 快速開始（最簡單的方式）

```bash
# 1. 啟動所有開發服務（PostgreSQL, RabbitMQ, Redis）
make dev-up

# 2. 啟動應用
make run-all

# 3. 停止服務（完成開發後）
make dev-down
```

---
## 📦 方式 1: 使用 Makefile（推薦）

### 開發服務管理
```bash
make dev-up         # 啟動開發服務
make dev-down       # 停止開發服務
make dev-status     # 查看狀態和資源使用
make dev-logs       # 查看日誌
make dev-restart    # 重啟服務
make dev-clean      # 清理所有數據
```

### 應用管理
```bash
make run-all        # 啟動所有應用
make run-order      # 只啟動 Order Service
make run-wallet     # 只啟動 Wallet Service
make run-match      # 只啟動 MatchEngine
```

---

## 🛠️ 方式 2: 使用腳本

```bash
# 基本命令
./dev-services.sh start       # 啟動服務
./dev-services.sh stop        # 停止服務
./dev-services.sh status      # 查看狀態
./dev-services.sh logs        # 查看日誌

# 進入容器
./dev-services.sh shell postgres    # 進入 PostgreSQL
./dev-services.sh shell redis       # 進入 Redis CLI
./dev-services.sh shell rabbitmq    # 進入 RabbitMQ
```

---

## 🐳 方式 3: 直接使用 Docker Compose

```bash
# 啟動服務
docker-compose up -d

# 停止服務
docker-compose down

# 查看狀態
docker-compose ps

# 查看日誌
docker-compose logs -f

# 查看資源使用
docker stats eap-postgres eap-rabbitmq eap-redis
```

---

## 💡 優化說明

### 為什麼不會那麼燙了？

1. **使用 Alpine 映像** - 體積減少 50%+
   - `postgres:15` → `postgres:15-alpine`
   - `rabbitmq:3-management` → `rabbitmq:3-management-alpine`
   - `redis:7` → `redis:7-alpine`

2. **資源限制**
   - PostgreSQL: 最多 0.5 CPU, 512MB 記憶體
   - RabbitMQ: 最多 0.5 CPU, 512MB 記憶體
   - Redis: 最多 0.25 CPU, 256MB 記憶體（總共約 200MB）

3. **記憶體優化**
   - Redis: `maxmemory 200mb` + LRU 淘汰策略
   - RabbitMQ: `VM_MEMORY_HIGH_WATERMARK: 256MB`
   - PostgreSQL: `SHARED_BUFFERS: 128MB`, `MAX_CONNECTIONS: 20`

4. **重啟策略**
   - 改為 `unless-stopped`（不需要時可完全停止）

---

## 🔍 常用操作

### 連接資料庫
```bash
# PostgreSQL
./dev-services.sh shell postgres
# 或
docker exec -it eap-postgres psql -U admin -d eapdb
```

### 連接 Redis
```bash
# Redis CLI
./dev-services.sh shell redis
# 或
docker exec -it eap-redis redis-cli

# 查看所有 keys
redis-cli keys '*'

# 查看 matchId 序列
redis-cli GET match:id:sequence
```

### 查看 RabbitMQ
```bash
# Web UI
open http://localhost:15672
# 用戶名: admin, 密碼: admin123

# 命令行
./dev-services.sh shell rabbitmq
rabbitmqctl list_queues
```

---

## 🧪 測試流程

```bash
# 1. 啟動開發服務
make dev-up

# 2. 確認服務健康
make dev-status

# 3. 運行測試
make test

# 4. 啟動應用並手動測試
make run-all

# 5. 測試完成後停止
make dev-down
```

---

## 📊 監控資源使用

```bash
# 實時監控
docker stats eap-postgres eap-rabbitmq eap-redis

# 查看記憶體使用
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

---

## 🔧 故障排除

### 服務無法啟動
```bash
# 查看日誌
docker-compose logs postgres
docker-compose logs rabbitmq
docker-compose logs redis

# 重新創建容器
docker-compose down
docker-compose up -d
```

### 埠號衝突
```bash
# 查看哪個程序佔用了埠號
lsof -i :5432  # PostgreSQL
lsof -i :6379  # Redis
lsof -i :5672  # RabbitMQ

# 停止衝突的服務
kill -9 <PID>
```

### 清理所有數據重新開始
```bash
make dev-clean
make dev-up
```

---

## 💻 Colima 優化（針對 Mac）

如果你使用 Colima，可以限制它的資源使用：

```bash
# 停止當前的 Colima
colima stop

# 重新啟動並限制資源
colima start --cpu 2 --memory 4 --disk 20

# 查看狀態
colima status
```

---

## 🎯 最佳實踐

1. **開發時**
   - 使用 `make dev-up` 啟動服務
   - 開發完成後使用 `make dev-down` 停止
   - 不需要時不要讓服務持續運行

2. **測試時**
   - 考慮使用嵌入式服務（H2、嵌入式 Redis）
   - 只在集成測試時啟動完整環境

3. **資源管理**
   - 定期使用 `make dev-clean` 清理不需要的數據
   - 監控資源使用：`make dev-status`

---

## 📝 服務連接資訊

| 服務 | 連接地址 | 用戶名 | 密碼 | 備註 |
|------|---------|--------|------|------|
| PostgreSQL | localhost:5432 | admin | admin123 | 資料庫: eapdb |
| RabbitMQ | localhost:5672 | admin | admin123 | AMQP |
| RabbitMQ UI | http://localhost:15672 | admin | admin123 | 管理界面 |
| Redis | localhost:6379 | - | - | 無密碼 |

---

## ❓ 常見問題

**Q: 為什麼還是有點燙？**
A: 可以進一步減少資源限制，或考慮使用遠程服務（見下方「方案 2」）

**Q: 可以只啟動部分服務嗎？**
A: 可以，使用：
```bash
docker-compose up -d postgres redis  # 只啟動 PostgreSQL 和 Redis
```

**Q: 如何完全停止 Docker？**
A: 
```bash
make dev-down          # 停止服務
colima stop            # 停止 Colima（Mac）
```
