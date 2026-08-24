# EAP 本機開發與壓測指南

EAP 是多 repository 專案。日常開發與容量壓測使用不同的 Docker 拓樸，不能混用資料庫位址或把開發環境結果當成壓測證據。

## Repository 配置

```text
eap-workspace/       eap-infra：compose、壓測、公開文件
eap-order/           Order Service，8080 /eap-order
eap-wallet/          Wallet Service，8081 /eap-wallet
eap-matchEngine/     MatchEngine，8082 /match-engine
eap-common/          共用 Java 契約
eap-mcp/             選用控制面，8083
eap-ai-client/       選用本機 AI client，8084
eap-trigger/         Go 實驗模組，尚未接入現行 TradeExecuted 事件
```

## 日常開發環境

`docker-compose.yml` 提供共用 PostgreSQL、RabbitMQ 與 Redis。三個核心服務使用不同 schema，但開發時連到同一個 `eapdb`。

```bash
make dev-env
make dev-up
make run-all
```

常用命令：

```bash
make dev-status
make dev-logs
make build
make test
make app-status
make app-stop
make dev-down
```

只啟動單一服務：

```bash
make run-order
make run-wallet
make run-match
make run-mcp
make run-ai
```

服務也可以在各 repository 直接執行：

```bash
cd eap-order && ./gradlew bootRun
cd eap-wallet && ./gradlew bootRun
cd eap-matchEngine && ./gradlew bootRun
```

## 日常開發拓樸

| 元件 | 位址 | 容器 |
| --- | --- | --- |
| PostgreSQL | `localhost:5432/eapdb` | `eap-postgres` |
| RabbitMQ | `localhost:5672` | `eap-rabbitmq` |
| RabbitMQ UI | `http://localhost:15672` | `eap-rabbitmq` |
| Redis | `localhost:6379` | `eap-redis` |

開發 Redis 使用 AOF 與 `noeviction`，因為任意淘汰 order-book key 會破壞訂單簿一致性。

## 測試

```bash
make test
make test-trigger
```

各 Java repository 也能個別執行：

```bash
GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle \
  ./gradlew --no-daemon test
```

需要 PostgreSQL、Redis 或 RabbitMQ 的整合測試，必須依該 repository 的測試 profile 與 Testcontainers／本機服務要求執行；不要把未實際執行的測試報告為通過。

## 容量壓測環境

容量壓測使用 `docker-compose.loadtest.yml`，不是日常開發 compose：

| 服務資料庫 | 位址 | 容器 |
| --- | --- | --- |
| Order PostgreSQL | `localhost:15432/eap_order_db` | `eap-order-postgres-loadtest` |
| Wallet PostgreSQL | `localhost:15433/eap_wallet_db` | `eap-wallet-postgres-loadtest` |
| MatchEngine PostgreSQL | `localhost:15434/eap_match_db` | `eap-match-postgres-loadtest` |
| RabbitMQ | `localhost:5672` | `eap-rabbitmq-loadtest` |
| Redis | `localhost:6379` | `eap-redis-loadtest` |

公開 runner 會啟動 `loadtest` profile、檢查環境、重設狀態並在結束時停止自己啟動的服務。不要同時啟動日常 RabbitMQ/Redis 與壓測容器占用相同埠號。

主要入口：

```bash
# 隨機混合 HTTP 階梯測試
START_ORDER_TPS=700 END_ORDER_TPS=1100 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=30 STAGE_DURATION_SECONDS=60 \
WORKLOAD_SEED=20260807 DIAGNOSTICS_LEVEL=light \
bash scripts/load-test/run-http-matched-staircase.sh

# 30 分鐘隨機混合 HTTP 穩態測試
TARGET_ORDER_TPS=300 WARMUP_SECONDS=60 DURATION_SECONDS=1800 \
WORKLOAD_SEED=20260807 DIAGNOSTICS_LEVEL=light \
bash scripts/load-test/run-http-matched-steady-state.sh

# 已確認訂單後端診斷，不包含 HTTP admission
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
DIAGNOSTICS_LEVEL=none \
bash scripts/load-test/run-matched-trade-completion-10k.sh
```

完整 HTTP 容量 runner 固定使用 CDA 隨機混合 BUY/SELL 與各服務自己的 `application-loadtest.yml`。使用者數以各 side 的實際送出順序輪替，避免製造不合理的單一使用者瞬間突發。買賣 phase 順序、worker 數與 runtime profile 不再是公開容量開關；這些 runner 不驗證 TDA。

## 診斷層級

| 層級 | 用途 |
| --- | --- |
| `none` | 最低觀測負擔的容量或重複測試 |
| `light` | queue、HTTP、完成量與基本主機指標 |
| `deep` | PostgreSQL、WAL、pool、應用計時器與 durable lag 歸因 |

Deep 會在同機產生 observer effect。deep 結果可以定位瓶頸，但不能直接取代低觀測容量結果。

壓測 runner 的原始輸出位於 `build/load-test-reports/`。`build/` 是可重建、
Git ignored 的本機工作區，不是 BMAD 文件目錄，也不能成為正式宣稱的唯一
證據來源。需要保留的最小結果、samples、診斷與 provenance 應審查後提升到
`docs/benchmarks/results/YYYY-MM-DD-topic/`，再由 dated campaign report 說明
決策與限制；只有符合資格的結果才更新 canonical
[效能報告](docs/performance-report.md)。完整規則見[文件地圖](docs/README.md)、
[benchmark evidence guide](docs/benchmarks/README.md) 與
[壓測分類](docs/benchmarks/load-test-taxonomy.md)。

## 清理與故障排除

```bash
make dev-down
bash scripts/load-test/stop-loadtest-services.sh
docker compose -f docker-compose.loadtest.yml ps
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:8081 -sTCP:LISTEN
lsof -nP -iTCP:8082 -sTCP:LISTEN
```

`make dev-clean` 會要求確認並刪除日常開發 volume。Runner 產生的
`build/load-test-reports/` 可以依空間需求清理；已提升到
`docs/benchmarks/results/` 的證據與 `docs/archive/` 的 frozen history 不得當成
暫存輸出刪除。
