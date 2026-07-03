#!/usr/bin/env python3
import argparse
import base64
import json
import random
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone


def post_json(url, payload=None, headers=None, timeout=10):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return json.loads(body) if body else {}


def register_user(wallet_url):
    response = post_json(f"{wallet_url}/v1/wallet/register", {})
    if not response.get("success"):
        raise RuntimeError(f"register failed: {response}")
    return response["userId"]


def rabbit_publish(rabbit_url, auth_header, event):
    payload = {
        "properties": {
            "content_type": "application/json",
            "headers": {
                "__TypeId__": "com.eap.common.event.OrderSubmittedEvent"
            }
        },
        "routing_key": "order.submitted",
        "payload": json.dumps(event),
        "payload_encoding": "string"
    }
    return post_json(
        f"{rabbit_url}/api/exchanges/%2F/order.exchange/publish",
        payload,
        headers={"Authorization": auth_header},
    )


def build_event(user_ids, duplicate_order_id=None):
    order_id = duplicate_order_id or str(uuid.uuid4())
    return {
        "orderId": order_id,
        "userId": random.choice(user_ids),
        "marketId": "LOAD_TEST",
        "marketSequence": random.randint(1, 10_000_000),
        "price": random.randint(10, 100),
        "amount": random.randint(1, 5),
        "orderType": "BUY",
        "createdAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "")
    }


def main():
    parser = argparse.ArgumentParser(description="Publish OrderSubmittedEvent load to EAP wallet through RabbitMQ.")
    parser.add_argument("--wallet-url", default="http://localhost:8081/eap-wallet")
    parser.add_argument("--rabbit-url", default="http://localhost:15672")
    parser.add_argument("--rabbit-user", default="admin")
    parser.add_argument("--rabbit-pass", default="admin123")
    parser.add_argument("--users", type=int, default=50)
    parser.add_argument("--events", type=int, default=1000)
    parser.add_argument("--tps", type=int, default=50)
    parser.add_argument("--duplicate-ratio", type=float, default=0.1)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    auth = base64.b64encode(f"{args.rabbit_user}:{args.rabbit_pass}".encode("utf-8")).decode("ascii")
    auth_header = f"Basic {auth}"

    print(f"registering {args.users} users through wallet API...")
    user_ids = [register_user(args.wallet_url) for _ in range(args.users)]
    print(f"registered users: {len(user_ids)}")

    unique_events = []
    duplicate_pool = []
    for _ in range(args.events):
        if duplicate_pool and random.random() < args.duplicate_ratio:
            event = build_event(user_ids, duplicate_order_id=random.choice(duplicate_pool))
        else:
            event = build_event(user_ids)
            duplicate_pool.append(event["orderId"])
        unique_events.append(event)

    interval = 1.0 / max(args.tps, 1)
    started = time.time()
    published = 0
    failures = 0

    def publish_one(event):
        response = rabbit_publish(args.rabbit_url, auth_header, event)
        if not response.get("routed"):
            raise RuntimeError(f"message not routed: {response}")

    print(f"publishing {args.events} events at target {args.tps} TPS, duplicate_ratio={args.duplicate_ratio}")
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = []
        next_send_at = time.time()
        for event in unique_events:
            now = time.time()
            if now < next_send_at:
                time.sleep(next_send_at - now)
            futures.append(executor.submit(publish_one, event))
            next_send_at += interval

        for future in as_completed(futures):
            try:
                future.result()
                published += 1
            except (urllib.error.URLError, RuntimeError) as exc:
                failures += 1
                print(f"publish failed: {exc}")

    elapsed = time.time() - started
    print(json.dumps({
        "events": args.events,
        "published": published,
        "failures": failures,
        "elapsedSeconds": round(elapsed, 2),
        "actualTps": round(published / elapsed, 2) if elapsed > 0 else 0
    }, indent=2))


if __name__ == "__main__":
    main()
