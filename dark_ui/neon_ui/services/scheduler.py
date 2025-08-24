from __future__ import annotations

import asyncio
import json
import logging
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from apscheduler.schedulers.asyncio import AsyncIOScheduler


logger = logging.getLogger(__name__)


AGG_PREFIX = "wd:agg:"
FORWARD_QUEUE_KEY = "wd:fwd:q"
LAST_SENT_PREFIX = "wd:last_sent:"


class AggregationScheduler:
    """
    负责周期扫描 Redis 聚合键，到期后进行一次性转发与入库。
    """

    def __init__(self, redis_client, db, bot, target_chat_id: int, tzinfo, refresh_groups_cb=None):
        self.redis = redis_client
        self.db = db
        self.bot = bot
        self.target_chat_id = target_chat_id
        self.tzinfo = tzinfo
        self.scheduler = AsyncIOScheduler(timezone=str(tzinfo))
        self.refresh_groups_cb = refresh_groups_cb

    async def start(self) -> None:
        # 每 10 秒扫描一次
        self.scheduler.add_job(self.process_due_aggregations, "interval", seconds=10, id="scan_aggregations", replace_existing=True)
        # 每小时清理一次老旧键
        self.scheduler.add_job(self.cleanup_old_keys, "interval", minutes=60, id="cleanup_keys", replace_existing=True)
        # 每 2 秒消费一次转发队列
        self.scheduler.add_job(self.process_forward_queue, "interval", seconds=2, id="forward_queue", replace_existing=True)
        # 每小时刷新一次群组目录（如果提供了回调）
        if self.refresh_groups_cb is not None:
            self.scheduler.add_job(self.refresh_groups_cb, "interval", hours=1, id="refresh_groups", replace_existing=True)
        self.scheduler.start()
        logger.info("APScheduler 已启动")

    async def shutdown(self) -> None:
        self.scheduler.shutdown(wait=False)
        logger.info("APScheduler 已停止")

    async def process_due_aggregations(self) -> None:
        now = int(time.time())
        pattern = AGG_PREFIX + "*"
        async for key in self.redis.client.scan_iter(match=pattern, count=500):
            data = await self.redis.client.hgetall(key)
            if not data:
                continue
            finalize_at = int(data.get("finalize_at", 0))
            if int(data.get("sent", 0)):
                continue
            if now < finalize_at:
                continue

            # 使用 Lua 原子检查并抢占发送（sent 从 0 -> 1），避免并发重复
            lua = """
            if redis.call('HEXISTS', KEYS[1], 'sent') == 0 then return 0 end
            local s = tonumber(redis.call('HGET', KEYS[1], 'sent') or '0')
            if s ~= 0 then return 0 end
            redis.call('HSET', KEYS[1], 'sent', 1)
            return 1
            """
            try:
                claimed = await self.redis.client.eval(lua, 1, key)
            except Exception:
                claimed = 0
            if not claimed:
                continue

            try:
                await self._finalize_one(key, data)
            except Exception as e:
                logger.exception("聚合发送失败 %s: %s", key, e)

    async def _finalize_one(self, key: str, data: Dict[str, Any]) -> None:
        """聚合完成后写入转发队列，由专门消费者做去重与转发。"""
        username_raw = str(data.get("username") or "")
        uname = username_raw.lstrip("@").lower()
        # 兜底跳过机器人
        if uname.endswith("bot") or uname.endswith("_bot"):
            await self.redis.client.hset(key, mapping={"sent": 1})
            await self.redis.client.expire(key, 600)
            logger.info("跳过机器人用户名聚合：%s", username_raw)
            return

        payload = {
            "username_raw": username_raw,
            "keyword": data.get("keyword"),
            "amount": int(data.get("amount", 0)),
            "original_amount_text": data.get("original_amount_text"),
            "chat_id": int(data.get("chat_id", 0)) if data.get("chat_id") else None,
            "chat_title_raw": str(data.get("chat_title") or ""),
            "user_id": int(data.get("user_id", 0)) if data.get("user_id") else None,
            "hit_at_ts": int(data.get("hit_at_ts", 0)),
            "enqueued_ts": int(time.time()),
        }
        await self.redis.client.rpush(FORWARD_QUEUE_KEY, json.dumps(payload))
        await self.redis.client.hset(key, mapping={"sent": 1})
        await self.redis.client.expire(key, 600)
        logger.info("聚合已入队：%s", username_raw)

    def _normalize_username(self, username: str) -> str:
        u = (username or "").strip()
        if not u:
            return ""
        if u.startswith("@"):  # 保留 @，内容小写
            return "@" + u[1:].lower()
        return "@" + u.lower()

    async def process_forward_queue(self) -> None:
        from .filters import escape_html, format_amount_with_thousands
        # 每次最多处理 100 条
        for _ in range(100):
            item = await self.redis.client.lpop(FORWARD_QUEUE_KEY)
            if not item:
                break
            try:
                data = json.loads(item)
            except Exception:
                continue

            username_raw = str(data.get("username_raw") or "")
            uname = self._normalize_username(username_raw).lstrip("@").lower()
            if uname.endswith("bot") or uname.endswith("_bot") or ("bot" in uname):
                continue

            # 10 分钟唯一：SET NX EX
            last_key = LAST_SENT_PREFIX + self._normalize_username(username_raw)
            ok = await self.redis.client.set(last_key, str(int(time.time())), ex=600, nx=True)
            if not ok:
                continue

            amount = int(data.get("amount", 0))
            user_id = int(data.get("user_id", 0)) if data.get("user_id") else None
            chat_id = int(data.get("chat_id", 0)) if data.get("chat_id") else None
            hit_at_ts = int(data.get("hit_at_ts", 0))
            keyword = data.get("keyword")
            chat_title_raw = str(data.get("chat_title_raw") or "")

            username_html = escape_html(self._normalize_username(username_raw))
            chat_title_html = escape_html(chat_title_raw)
            hit_dt = datetime.fromtimestamp(hit_at_ts, tz=self.tzinfo)
            ts_str = hit_dt.strftime("%Y-%m-%d %H:%M:%S")

            await self.bot.send_message(chat_id=self.target_chat_id, text=f"⏰ 时间：{ts_str}", parse_mode="HTML")
            formatted_amount = format_amount_with_thousands(amount)
            trigger_text = escape_html(f"{str(keyword or '')} {formatted_amount} ({amount})")
            card = (
                "🔔 新消息通知\n\n"
                f"👤 目标用户：{username_html}\n"
                f"🆔 用户 ID：{user_id}\n"
                f"💬 触发消息：{trigger_text}\n"
                f"👥 所在群组：{chat_title_html}（{chat_id}）\n"
                f"🕒 时间：{ts_str}"
            )
            await self.bot.send_message(chat_id=self.target_chat_id, text=card, parse_mode="HTML")

            # 入库
            await self.db.insert_hit(
                {
                    "username": username_html,
                    "user_id": user_id,
                    "keyword": keyword,
                    "amount": amount,
                    "chat_id": chat_id,
                    "chat_title": chat_title_html,
                    "hit_at": hit_dt.replace(tzinfo=None),
                }
            )

    async def cleanup_old_keys(self) -> None:
        # 兜底清理：删除 finalize_at 超过 1 天的过期键
        now = int(time.time())
        pattern = AGG_PREFIX + "*"
        async for key in self.redis.client.scan_iter(match=pattern, count=1000):
            data = await self.redis.client.hgetall(key)
            if not data:
                await self.redis.client.delete(key)
                continue
            finalize_at = int(data.get("finalize_at", 0))
            if finalize_at and now - finalize_at > 86400:
                await self.redis.client.delete(key)


