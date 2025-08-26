from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List

from aiogram import Bot
from aiogram.client.session.aiohttp import AiohttpSession
from dotenv import load_dotenv
from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi import Request
from fastapi.responses import StreamingResponse
from telethon import TelegramClient, events
from telethon.sessions import StringSession

from services.db import Database
from services.redis_client import RedisClient
from services.filters import parse_message
from services.scheduler import AggregationScheduler, AGG_PREFIX


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("tg-watchdog")

# 加载 .env
load_dotenv()


def get_env(name: str, default: Optional[str] = None) -> str:
    v = os.getenv(name, default)
    if v is None:
        raise RuntimeError(f"缺少必要环境变量：{name}")
    return v


BOT_TOKEN = os.getenv("BOT_TOKEN", "")
TARGET_CHAT_ID = int(os.getenv("TARGET_CHAT_ID", "0") or 0)
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/tg_watchdog")
TIMEZONE = os.getenv("TIMEZONE", "Asia/Shanghai")

import zoneinfo
TZ = zoneinfo.ZoneInfo(TIMEZONE)


def list_account_envs() -> List[Dict[str, Any]]:
    accounts = []
    for i in (1, 2, 3):
        api_id = os.getenv(f"ACCOUNT{i}_API_ID")
        api_hash = os.getenv(f"ACCOUNT{i}_API_HASH")
        username = os.getenv(f"ACCOUNT{i}_USERNAME")
        user_id = os.getenv(f"ACCOUNT{i}_USER_ID")
        phone = os.getenv(f"ACCOUNT{i}_PHONE")
        if api_id and api_hash:
            accounts.append(
                {
                    "name": f"account{i}",
                    "api_id": int(api_id),
                    "api_hash": api_hash,
                    "username": username,
                    "user_id": int(user_id) if user_id else None,
                    "phone": phone,
                }
            )
    return accounts


templates = Jinja2Templates(directory="templates")
# 全局控制模板空白，避免列表中出现空白 #text 节点
templates.env.trim_blocks = True
templates.env.lstrip_blocks = True
app = FastAPI(title="tg-watchdog")


db = Database(DATABASE_URL)
redis_client = RedisClient(REDIS_URL)
bot: Optional[Bot] = None
scheduler: Optional[AggregationScheduler] = None
clients: List[TelegramClient] = []

# 挂载静态资源
app.mount("/static", StaticFiles(directory="static"), name="static")


def normalize_username(username: str) -> str:
    u = (username or "").strip()
    if not u:
        return ""
    if u.startswith("@"):  # 始终保留 @ 前缀，内容统一为小写
        return "@" + u[1:].lower()
    return "@" + u.lower()


def agg_key_for_username(username: str) -> str:
    # 使用标准化用户名作为 Redis 键，确保同一用户只占用一个窗口键
    return f"{AGG_PREFIX}{normalize_username(username)}"


async def ensure_redis_and_db() -> None:
    await redis_client.connect()
    await db.init_models()


async def init_bot() -> Bot:
    session = AiohttpSession()
    b = Bot(token=BOT_TOKEN, session=session)
    # 简单自检
    me = await b.get_me()
    logger.info("Aiogram Bot 已就绪：@%s", me.username)
    return b


async def start_scheduler() -> AggregationScheduler:
    global scheduler
    assert bot is not None
    # 通过闭包包装刷新函数，供 APScheduler 调度
    async def _refresh():
        await refresh_groups_catalog(clients)

    scheduler = AggregationScheduler(redis_client, db, bot, TARGET_CHAT_ID, TZ, refresh_groups_cb=_refresh)
    await scheduler.start()
    return scheduler


async def build_telethon_clients() -> List[TelegramClient]:
    base_dir = os.path.abspath("./sessions")
    os.makedirs(base_dir, exist_ok=True)
    cls: List[TelegramClient] = []
    for acc in list_account_envs():
        session_path = os.path.join(base_dir, f"{acc['name']}.session")
        client = TelegramClient(session_path, acc["api_id"], acc["api_hash"])
        await client.connect()  # 仅连接，不触发交互式登录
        try:
            authorized = await client.is_user_authorized()
        except Exception:
            authorized = False
        if not authorized:
            logger.warning(
                "Telethon 会话未授权：%s（%s）。请在主机执行 `python main.py --init-sessions` 后再启动容器。",
                acc.get("name"), acc.get("username"),
            )
            await client.disconnect()  # type: ignore  # 避免占用连接
            continue
        cls.append(client)
    return cls


async def on_message(event) -> None:
    try:
        message = event.message
        if not message:
            return
        if not message.message:
            return

        # 直接跳过：通过机器人内联（via_bot）或由机器人转发（fwd_from）
        try:
            if getattr(message, "via_bot_id", None):
                return
            fwd = getattr(message, "fwd_from", None)
            if fwd is not None:
                from_name = getattr(fwd, "from_name", "") or ""
                if str(from_name).strip().lower().endswith("bot"):
                    return
                # 若能解析出原始发送者 id，进一步判定是否为机器人
                from_id = getattr(fwd, "from_id", None)
                if from_id is not None:
                    try:
                        entity = await event.client.get_entity(from_id)  # type: ignore
                        if getattr(entity, "bot", False):
                            return
                        uname = str(getattr(entity, "username", "") or "").lower()
                        if uname.endswith("bot"):
                            return
                    except Exception:
                        # 无法解析实体时不影响其他过滤
                        pass
        except Exception:
            # 任何异常不影响主流程
            pass

        # 仅监听群组（包含超级群），忽略频道与私聊
        if not event.is_group:
            return

        # 忽略无 @username 的消息
        sender = await event.get_sender()
        username = None
        user_id = None
        if sender and getattr(sender, "username", None):
            username = f"@{sender.username}"
            user_id = sender.id
        else:
            return

        # 严格要求为普通用户实体
        try:
            from telethon.tl.types import User
            if not isinstance(sender, User):
                return
        except Exception:
            pass

        # 忽略由群/频道身份发布的消息（例如匿名群管理员、频道身份）
        try:
            from telethon.tl.types import Channel, Chat
            if isinstance(sender, (Channel, Chat)):
                return
        except Exception:
            pass

        # 仅监听普通用户：跳过机器人、群主、管理员
        if getattr(sender, "bot", False):
            return

        # 额外保险：Telegram 机器人用户名必须以 "bot" 结尾，全部忽略
        if username:
            uname = username.lstrip("@").lower()
            # 更激进：包含 bot 子串也忽略（如 xbotx、bbpc20bot 等）
            if uname.endswith("bot") or uname.endswith("_bot") or ("bot" in uname):
                return
        try:
            perms = await event.client.get_permissions(event.chat_id, sender)  # type: ignore
            if getattr(perms, "is_admin", False) or getattr(perms, "is_creator", False):
                return
        except Exception:
            # 无法获取权限信息时，不影响普通流程
            pass

        match = parse_message(message.message)
        if not match:
            return

        chat = await event.get_chat()
        chat_title = getattr(chat, "title", "") or getattr(chat, "username", "") or ""
        chat_id = getattr(chat, "id", None)

        key = agg_key_for_username(username)
        now_ts = int(datetime.now(tz=TZ).timestamp())
        finalize_at = now_ts + 600  # 10 分钟窗口

        # 使用 Redis Hash 存储聚合结果：保存最大金额、最早时间
        exists = await redis_client.client.exists(key)  # type: ignore
        if not exists:
            await redis_client.client.hset(  # type: ignore
                key,
                mapping={
                    "username": username,
                    "user_id": user_id or 0,
                    "keyword": match.keyword,
                    "amount": match.amount,
                    "original_amount_text": match.original_amount_text,
                    "chat_id": chat_id or 0,
                    "chat_title": chat_title,
                    "hit_at_ts": now_ts,
                    "finalize_at": finalize_at,
                    "sent": 0,
                },
            )
            # 设置 12 分钟 TTL，窗口结束由调度器发送
            await redis_client.client.expire(key, 12 * 60)  # type: ignore
            return

        # 已存在，择优：金额更大优先；金额相同则保留最早的 hit_at_ts
        current = await redis_client.client.hgetall(key)  # type: ignore
        cur_amount = int(current.get("amount", 0))
        cur_ts = int(current.get("hit_at_ts", now_ts))
        new_amount = match.amount
        new_ts = cur_ts  # 默认保留原来的（更早）
        new_keyword = current.get("keyword")
        new_original_text = current.get("original_amount_text")

        if new_amount > cur_amount:
            new_keyword = match.keyword
            new_original_text = match.original_amount_text
        else:
            new_amount = cur_amount

        # 更新时间窗口的结束时间（始终保持首次窗口的 finalize_at，不延长）
        await redis_client.client.hset(  # type: ignore
            key,
            mapping={
                "keyword": new_keyword,
                "amount": new_amount,
                "original_amount_text": new_original_text,
                "chat_id": chat_id or current.get("chat_id", 0),
                "chat_title": chat_title or current.get("chat_title", ""),
                "hit_at_ts": new_ts,
            },
        )
    except Exception as e:
        logger.exception("处理消息异常：%s", e)


async def register_handlers(clients: List[TelegramClient]) -> None:
    for client in clients:
        @client.on(events.NewMessage())
        async def handler(event):  # noqa: WPS430
            await on_message(event)


@app.get("/health")
async def health() -> Dict[str, Any]:
    return {"status": "ok"}


@app.get("/history")
async def api_history(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    username: Optional[str] = None,
    keyword: Optional[str] = None,
    chat_id: Optional[int] = None,
    chat_title: Optional[str] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    min_amount: Optional[int] = None,
    exclude_bots: bool = Query(True, description="是否排除包含 bot 的用户名"),
):
    def parse_dt(s):
        if not s:
            return None
        return datetime.fromisoformat(s)

    # 统一用户名：大小写不敏感，强制带 @
    norm_username = normalize_username(username) if username else None

    data = await db.query_history(
        page=page,
        page_size=page_size,
        username=norm_username,
        keyword=keyword,
        chat_id=chat_id,
        chat_title=chat_title,
        start_time=parse_dt(start_time),
        end_time=parse_dt(end_time),
        min_amount=min_amount,
        exclude_bots=exclude_bots,
    )
    return JSONResponse(data)


@app.get("/stats")
async def api_stats():
    return JSONResponse(await db.query_stats(exclude_bots=True))


@app.get("/groups")
async def api_groups(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    q: Optional[str] = None,
    is_megagroup: Optional[bool] = None,
    is_broadcast: Optional[bool] = None,
):
    data = await db.query_groups(
        page=page,
        page_size=page_size,
        q=q,
        is_megagroup=is_megagroup,
        is_broadcast=is_broadcast,
    )
    return JSONResponse(data)


@app.get("/", response_class=HTMLResponse)
async def index(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    username: Optional[str] = None,
    keyword: Optional[str] = None,
    chat_title: Optional[str] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    min_amount: Optional[int] = None,
):
    norm_username = normalize_username(username) if username else None
    data = await db.query_history(
        page=page,
        page_size=page_size,
        username=norm_username,
        keyword=keyword,
        chat_id=None,
        chat_title=chat_title,
        start_time=datetime.fromisoformat(start_time) if start_time else None,
        end_time=datetime.fromisoformat(end_time) if end_time else None,
        min_amount=min_amount,
        exclude_bots=True,
    )
    stats = await db.query_stats()
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "title": "tg-watchdog 后台",
            "items": data["items"],
            "total": data["total"],
            "page": data["page"],
            "page_size": data["page_size"],
            "stats": stats,
            "q": {
                "username": username,
                "keyword": keyword,
                "chat_title": chat_title,
                "start_time": start_time,
                "end_time": end_time,
                "min_amount": min_amount,
                "exclude_bots": True,
            },
        },
    )


@app.get("/ui/groups", response_class=HTMLResponse)
async def ui_groups(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    q: Optional[str] = None,
    type: Optional[str] = None,
):
    is_megagroup = True if type == "megagroup" else None
    is_broadcast = True if type == "broadcast" else None
    data = await db.query_groups(
        page=page,
        page_size=page_size,
        q=q,
        is_megagroup=is_megagroup,
        is_broadcast=is_broadcast,
    )
    return templates.TemplateResponse(
        "groups.html",
        {
            "request": request,
            "items": data["items"],
            "total": data["total"],
            "page": data["page"],
            "page_size": data["page_size"],
            "q": q,
            "type": type,
        },
    )


@app.get("/ui/top-users", response_class=HTMLResponse)
async def ui_top_users(request: Request):
    stats = await db.query_top_users_dual()
    return templates.TemplateResponse(
        "top_users.html",
        {
            "request": request,
            "items": stats,
        },
    )

@app.get("/export.csv")
async def export_csv(
    username: Optional[str] = None,
    keyword: Optional[str] = None,
    chat_title: Optional[str] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    min_amount: Optional[str] = None,
    exclude_bots: bool = True,
):
    # 重用查询逻辑
    norm_username = normalize_username(username) if username else None
    def parse_int(s):
        if not s:
            return None
        try:
            return int(s)
        except Exception:
            return None
    data = await db.query_history(
        page=1, page_size=10000,
        username=norm_username,
        keyword=keyword,
        chat_id=None,
        chat_title=chat_title,
        start_time=datetime.fromisoformat(start_time) if start_time else None,
        end_time=datetime.fromisoformat(end_time) if end_time else None,
        min_amount=parse_int(min_amount),
        exclude_bots=exclude_bots,
    )
    import csv
    import io
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["id","username","user_id","keyword","amount","chat_id","chat_title","hit_at","created_at"])
    for item in data["items"]:
        writer.writerow([
            item["id"], item["username"], item["user_id"], item["keyword"], item["amount"],
            item["chat_id"], item["chat_title"], item["hit_at"], item["created_at"],
        ])
    return StreamingResponse(iter([buf.getvalue()]), media_type="text/csv", headers={
        "Content-Disposition": "attachment; filename=history_export.csv"
    })


@app.get("/export_usernames.csv")
async def export_usernames(
    username: Optional[str] = None,
    keyword: Optional[str] = None,
    chat_title: Optional[str] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    min_amount: Optional[str] = None,
    exclude_bots: bool = True,
):
    norm_username = normalize_username(username) if username else None
    def parse_int(s):
        if not s:
            return None
        try:
            return int(s)
        except Exception:
            return None
    names = await db.query_unique_usernames(
        username=norm_username,
        keyword=keyword,
        chat_id=None,
        chat_title=chat_title,
        start_time=datetime.fromisoformat(start_time) if start_time else None,
        end_time=datetime.fromisoformat(end_time) if end_time else None,
        min_amount=parse_int(min_amount),
        exclude_bots=exclude_bots,
    )
    import io, csv
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["username"])  # 表头
    for n in names:
        writer.writerow([n])
    return StreamingResponse(iter([buf.getvalue()]), media_type="text/csv", headers={
        "Content-Disposition": "attachment; filename=usernames_unique.csv"
    })


async def startup_all() -> None:
    global bot, clients
    await ensure_redis_and_db()
    bot = await init_bot()
    await start_scheduler()
    clients = await build_telethon_clients()
    # 启动时刷新一次群组目录
    await refresh_groups_catalog(clients)
    await register_handlers(clients)
    for c in clients:
        await c.connect()  # type: ignore
        session_repr = getattr(getattr(c, "session", None), "filename", None) or str(getattr(c, "session", None))
        logger.info("Telethon 客户端已连接：%s", session_repr)


async def shutdown_all() -> None:
    if scheduler:
        await scheduler.shutdown()
    if bot:
        await bot.session.close()
    for c in clients:
        await c.disconnect()  # type: ignore
    await redis_client.close()


@app.on_event("startup")
async def on_startup():
    await startup_all()


@app.on_event("shutdown")
async def on_shutdown():
    await shutdown_all()


def main():
    parser = argparse.ArgumentParser(description="tg-watchdog")
    parser.add_argument("--init-sessions", action="store_true", help="仅初始化 Telethon 登录会话")
    args = parser.parse_args()

    if args.init_sessions:
        # 同步执行 Telethon 登录流程
        accounts = list_account_envs()
        base_dir = os.path.abspath("./sessions")
        os.makedirs(base_dir, exist_ok=True)
        async def _init():
            for acc in accounts:
                session_path = os.path.join(base_dir, f"{acc['name']}.session")
                client = TelegramClient(session_path, acc["api_id"], acc["api_hash"])
                phone = acc.get("phone") or ""
                await client.start(phone=phone)  # type: ignore
                me = await client.get_me()  # type: ignore
                user_id = getattr(me, "id", None)
                logger.info("账号 %s 登录成功：@%s (%s)", acc["name"], getattr(me, "username", None), user_id)
                await client.disconnect()  # type: ignore
        asyncio.run(_init())
        return

    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)


async def refresh_groups_catalog(clients: List[TelegramClient]) -> None:
    """扫描所有 Telethon 客户端加入的群组，并保存到数据库。
    仅保存群/超级群，频道也会被标识但默认不监听。
    """
    try:
        from telethon.tl.types import Channel, Chat
        groups: List[Dict[str, Any]] = []
        seen_ids = set()  # 用于去重
        for client in clients:
            try:
                dialogs = await client.get_dialogs()  # type: ignore
            except Exception as e:
                logger.exception("获取会话失败：%s", e)
                continue
            for d in dialogs:
                entity = d.entity
                gid = getattr(entity, "id", None)
                title = getattr(entity, "title", None) or getattr(entity, "username", None)
                username = getattr(entity, "username", None)
                is_megagroup = bool(getattr(entity, "megagroup", False))
                is_broadcast = bool(getattr(entity, "broadcast", False))
                if gid is None:
                    continue
                # 仅记录群/超级群/频道，并去重
                if isinstance(entity, (Channel, Chat)) and int(gid) not in seen_ids:
                    seen_ids.add(int(gid))
                    groups.append(
                        {
                            "id": int(gid),
                            "title": title,
                            "username": username,
                            "is_megagroup": is_megagroup,
                            "is_broadcast": is_broadcast,
                        }
                    )
        await db.upsert_groups(groups)
        logger.info("群组目录刷新完成：%s 条", len(groups))
    except Exception as e:
        logger.exception("刷新群组目录失败：%s", e)


if __name__ == "__main__":
    main()


