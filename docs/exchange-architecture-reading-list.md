# 交易所架構閱讀清單

> 建立日期：2026-06-03  
> 用途：整理 EAP 後續架構學習資料，重點放在 matching engine、sequencing、price-time priority、market data feed 與高吞吐交易系統設計。

## 核心閱讀

### Coinbase Exchange Matching Engine

- 連結：https://coinbase-cloud.mintlify.app/exchange/concepts/matching-engine
- 重點：
  - continuous first-come, first-serve order book
  - price-time priority
  - self-trade prevention
  - taker order 與 resting order 的成交價格規則
- 對 EAP 的價值：
  - 可用來對照目前 `eap-matchEngine` 是否真的做到 price-time priority
  - 特別適合補強「同價位 FIFO」與「self-trade prevention」設計

### LMAX Architecture

- 連結：https://www.martinfowler.com/articles/lmax.html
- 重點：
  - single-threaded business logic processor
  - 以 event pipeline 支撐高吞吐，而不是在核心交易邏輯到處加 lock
  - deterministic processing 與低延遲交易系統設計
- 對 EAP 的價值：
  - 幫助理解為什麼交易核心常採單 writer / 單 sequencer 模型
  - 可對照 EAP 目前的 RabbitMQ + Redis Lua 架構，思考 sequencer 放在哪裡

### LMAX Disruptor

- 連結：https://lmax-exchange.github.io/disruptor/disruptor.html
- 重點：
  - ring buffer
  - sequencer
  - batching
  - lock-free / low-contention event handoff
- 對 EAP 的價值：
  - 不一定要直接使用 Disruptor，但要理解高吞吐交易系統如何處理 event sequencing
  - 可作為未來 `per-market sequencer` 的設計參考

### Databento ITCH Protocol Guide

- 連結：https://databento.com/microstructure/itch
- 重點：
  - ITCH 作為 order-by-order market data feed
  - order book update event
  - order reference number
  - full order book reconstruction
- 對 EAP 的價值：
  - 可對照 EAP 的 audit trail / replay / WebSocket market data
  - 幫助理解 market data feed 為什麼需要 sequence 與 gap recovery

### CME Globex Matching Algorithm Steps

- 連結：https://cmegroupclientsite.atlassian.net/wiki/display/EPICSANDBOX/CME%2BGlobex%2BMatching%2BAlgorithm%2BSteps
- 重點：
  - 不同商品可使用不同 matching algorithm
  - FIFO、pro-rata、display quantity 等 allocation rules
  - order modification 可能失去 timestamp priority
- 對 EAP 的價值：
  - EAP 已有 CDA 與 Timed Double Auction，可參考 CME 對不同產品套用不同撮合規則的思路
  - 對 pro-rata 與 price-time priority 的面試說法有幫助

### Nasdaq Matching Engines Overview

- 連結：https://www.nasdaq.com/solutions/fintech/marketplace-technology/about-matching-engines
- 重點：
  - matching engine 依 price、quantity、time 等參數撮合
  - 交易所技術供應商如何描述 matching engine 價值
- 對 EAP 的價值：
  - 可作為高層次產品/架構語言參考
  - 適合整理 README 或面試簡報中的非程式碼敘事

## 對 EAP 的暫定架構結論

目前 EAP 不應宣稱已具備 production-grade exchange ordering。比較準確的說法：

> EAP 目前保證 wallet 一致性與 Redis 操作原子性，但尚未保證 per-market price-time priority。若要接近真交易所架構，下一步應加入 per-market sequencer，讓同一 market 的所有 order 取得單調遞增 sequence，order book 排序改為 price + sequence。水平擴充時以 market / product / trading pair 作為 shard 邊界，而不是讓同一 order book 被多個 consumer 並行寫入。

## 之後可以回頭檢查的問題

- EAP 的 `OrderSubmittedEvent` 是否需要新增 `marketId` / `instrumentId`
- EAP 是否需要 `marketSequence`
- Redis ZSET score 是否應從單純 price 改成可表達 price + sequence 的排序模型
- 同價位 FIFO 是否要用 price-level queue 取代單一 ZSET
- market data feed 是否要帶 sequence number
- WebSocket consumer 是否需要 gap detection / snapshot recovery
- 熱門單一 market 的吞吐上限要用 batching、co-location、低延遲資料結構，還是改變撮合規則
