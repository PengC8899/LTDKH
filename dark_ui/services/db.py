from __future__ import annotations

import asyncio
import logging
from datetime import datetime
import os
import zoneinfo
from typing import Optional, List, Dict, Any

from sqlalchemy import BigInteger, Integer, String, Text, TIMESTAMP, Boolean, func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncAttrs, AsyncSession, create_async_engine, async_sessionmaker
from urllib.parse import urlparse
from sqlalchemy.orm import Mapped, mapped_column, sessionmaker, DeclarativeBase


logger = logging.getLogger(__name__)


TIMEZONE = os.getenv("TIMEZONE", "Asia/Shanghai")
try:
    TZ = zoneinfo.ZoneInfo(TIMEZONE)
except Exception:
    TZ = zoneinfo.ZoneInfo("Asia/Shanghai")


class Base(AsyncAttrs, DeclarativeBase):
    pass


class Hit(Base):
    __tablename__ = "hits"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[Optional[str]] = mapped_column(Text, index=True, nullable=True)
    user_id: Mapped[Optional[int]] = mapped_column(BigInteger, index=True, nullable=True)
    keyword: Mapped[str] = mapped_column(String(16), index=True)
    amount: Mapped[int] = mapped_column(Integer, index=True)
    chat_id: Mapped[Optional[int]] = mapped_column(BigInteger, index=True, nullable=True)
    chat_title: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    hit_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=False), index=True)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=False), server_default=func.now(), index=True
    )


class Group(Base):
    __tablename__ = "groups"

    # Telegram 群/超级群/频道的唯一 id（注意：频道我们这里可标记，但默认不监听）
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    title: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    username: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_megagroup: Mapped[bool] = mapped_column(Boolean, default=False)
    is_broadcast: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=False), server_default=func.now(), onupdate=func.now())
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=False), server_default=func.now())


class Database:
    def __init__(self, database_url: str) -> None:
        # 若 .env 为 docker 主机名 postgres，本地直跑时可通过环境覆盖或使用 docker compose
        self.database_url = database_url
        self.engine = create_async_engine(database_url, future=True, echo=False)
        # 使用 async_sessionmaker，确保类型正确（AsyncEngine -> AsyncSession）
        self.async_session_factory = async_sessionmaker(
            bind=self.engine, expire_on_commit=False
        )

    async def init_models(self) -> None:
        async with self.engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        logger.info("数据库表结构检查完成（如不存在则自动创建）。")

    def get_session(self) -> AsyncSession:
        return self.async_session_factory()

    async def insert_hit(self, data: Dict[str, Any]) -> int:
        async with self.get_session() as session:
            # 让 created_at 与业务命中时间保持一致，避免视觉上“时间/创建时间”不一致
            hit_time = data["hit_at"]
            hit = Hit(
                username=data.get("username"),
                user_id=data.get("user_id"),
                keyword=data["keyword"],
                amount=int(data["amount"]),
                chat_id=data.get("chat_id"),
                chat_title=data.get("chat_title"),
                hit_at=hit_time,
                created_at=hit_time,
            )
            session.add(hit)
            await session.commit()
            await session.refresh(hit)
            return hit.id

    async def upsert_groups(self, groups: List[Dict[str, Any]]) -> None:
        if not groups:
            return
        async with self.get_session() as session:
            stmt = pg_insert(Group).values(groups)
            stmt = stmt.on_conflict_do_update(
                index_elements=[Group.id],
                set_=dict(
                    title=stmt.excluded.title,
                    username=stmt.excluded.username,
                    is_megagroup=stmt.excluded.is_megagroup,
                    is_broadcast=stmt.excluded.is_broadcast,
                    updated_at=func.now(),
                ),
            )
            await session.execute(stmt)
            await session.commit()

    async def query_groups(
        self,
        page: int = 1,
        page_size: int = 20,
        q: Optional[str] = None,
        is_megagroup: Optional[bool] = None,
        is_broadcast: Optional[bool] = None,
    ) -> Dict[str, Any]:
        async with self.get_session() as session:
            from sqlalchemy import select, and_, or_, desc

            conditions = []
            if q:
                like = f"%{q}%"
                conditions.append(or_(Group.title.ilike(like), Group.username.ilike(like)))
            if is_megagroup is not None:
                conditions.append(Group.is_megagroup.is_(is_megagroup))
            if is_broadcast is not None:
                conditions.append(Group.is_broadcast.is_(is_broadcast))

            where_clause = and_(*conditions) if conditions else None

            total_stmt = select(func.count(Group.id))
            if where_clause is not None:
                total_stmt = total_stmt.where(where_clause)
            total = (await session.execute(total_stmt)).scalar_one()

            stmt = select(Group).order_by(desc(Group.updated_at)).offset((page - 1) * page_size).limit(page_size)
            if where_clause is not None:
                stmt = stmt.where(where_clause)
            rows = (await session.execute(stmt)).scalars().all()

            # 追加每群的去重触发用户数
            uniq_map = { (row["chat_id"]): row["unique_users"] for row in await self.query_group_unique_user_counts() }
            items = []
            for r in rows:
                items.append({
                    "id": r.id,
                    "title": r.title,
                    "username": r.username,
                    "is_megagroup": r.is_megagroup,
                    "is_broadcast": r.is_broadcast,
                    "updated_at": r.updated_at.isoformat(sep=" ", timespec="seconds") if r.updated_at else None,
                    "created_at": r.created_at.isoformat(sep=" ", timespec="seconds") if r.created_at else None,
                    "unique_users": int(uniq_map.get(r.id, 0)),
                })

            return {"total": total, "page": page, "page_size": page_size, "items": items}

    async def query_history(
        self,
        page: int = 1,
        page_size: int = 20,
        username: Optional[str] = None,
        keyword: Optional[str] = None,
        chat_id: Optional[int] = None,
        chat_title: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        min_amount: Optional[int] = None,
        exclude_bots: bool = True,
    ) -> Dict[str, Any]:
        async with self.get_session() as session:
            from sqlalchemy import select, and_, desc, not_, or_

            conditions = []
            if username:
                conditions.append(Hit.username == username)
            if keyword:
                conditions.append(Hit.keyword == keyword)
            if chat_id:
                conditions.append(Hit.chat_id == chat_id)
            if chat_title:
                conditions.append(Hit.chat_title == chat_title)
            if start_time:
                conditions.append(Hit.hit_at >= start_time)
            if end_time:
                conditions.append(Hit.hit_at <= end_time)
            if min_amount is not None:
                conditions.append(Hit.amount >= int(min_amount))
            if exclude_bots:
                # 排除任意包含 "bot" 的用户名（大小写不敏感）
                conditions.append(not_(func.lower(Hit.username).like("%bot%")))

            where_clause = and_(*conditions) if conditions else None

            total_stmt = select(func.count(Hit.id))
            if where_clause is not None:
                total_stmt = total_stmt.where(where_clause)

            total = (await session.execute(total_stmt)).scalar_one()

            stmt = select(Hit).order_by(desc(Hit.hit_at)).offset((page - 1) * page_size).limit(page_size)
            if where_clause is not None:
                stmt = stmt.where(where_clause)

            rows = (await session.execute(stmt)).scalars().all()

            items = [
                {
                    "id": r.id,
                    "username": r.username,
                    "user_id": r.user_id,
                    "keyword": r.keyword,
                    "amount": r.amount,
                    "chat_id": r.chat_id,
                    "chat_title": r.chat_title,
                    "hit_at": r.hit_at.isoformat(sep=" ", timespec="seconds"),
                    "created_at": r.created_at.isoformat(sep=" ", timespec="seconds"),
                }
                for r in rows
            ]

            return {"total": total, "page": page, "page_size": page_size, "items": items}

    async def query_stats(self, exclude_bots: bool = True) -> Dict[str, Any]:
        async with self.get_session() as session:
            from sqlalchemy import select, not_

            # 关键词统计
            kw_stmt = select(Hit.keyword, func.count(Hit.id)).group_by(Hit.keyword)
            kw_rows = (await session.execute(kw_stmt)).all()
            keyword_counts = {k: int(c) for k, c in kw_rows}

            # 用户 TOP
            user_stmt = select(Hit.username, func.count(Hit.id)).group_by(Hit.username).order_by(func.count(Hit.id).desc()).limit(20)
            if exclude_bots:
                user_stmt = user_stmt.where(not_(func.lower(Hit.username).like("%bot%")))
            user_rows = (await session.execute(user_stmt)).all()
            top_users = [{"username": u, "count": int(c)} for u, c in user_rows]

            # 金额分布（按 1000 档）
            bucket_stmt = select(((Hit.amount / 1000) * 1000).label("bucket"), func.count(Hit.id)).group_by("bucket").order_by("bucket")
            bucket_rows = (await session.execute(bucket_stmt)).all()
            amount_buckets = [{"bucket": int(b), "count": int(c)} for b, c in bucket_rows]

            return {
                "keywords": keyword_counts,
                "top_users": top_users,
                "amount_buckets": amount_buckets,
            }

    async def query_group_unique_user_counts(self, exclude_bots: bool = True) -> List[Dict[str, Any]]:
        async with self.get_session() as session:
            from sqlalchemy import select, func, not_

            stmt = select(
                Hit.chat_id,
                Hit.chat_title,
                func.count(func.distinct(Hit.username))
            ).where(Hit.chat_id.is_not(None), Hit.username.is_not(None))
            if exclude_bots:
                stmt = stmt.where(not_(func.lower(Hit.username).like("%bot%")))
            stmt = stmt.group_by(Hit.chat_id, Hit.chat_title).order_by(func.count(func.distinct(Hit.username)).desc())

            rows = (await session.execute(stmt)).all()
            return [
                {"chat_id": int(cid) if cid is not None else None, "chat_title": title, "unique_users": int(cnt)}
                for cid, title, cnt in rows
            ]

    async def query_top_users_dual(self, limit: int = 50, exclude_bots: bool = True) -> Dict[str, List[Dict[str, Any]]]:
        async with self.get_session() as session:
            from sqlalchemy import select, func, not_

            base = select(Hit.username, func.count(Hit.id).label("cnt"), func.sum(Hit.amount).label("sum_amt")).where(Hit.username.is_not(None))
            if exclude_bots:
                base = base.where(not_(func.lower(Hit.username).like("%bot%")))
            base = base.group_by(Hit.username)

            rows_cnt = (await session.execute(base.order_by(func.count(Hit.id).desc()).limit(limit))).all()
            rows_amt = (await session.execute(base.order_by(func.sum(Hit.amount).desc()).limit(limit))).all()

            return {
                "by_count": [{"username": u, "count": int(c), "amount": int(a or 0)} for u, c, a in rows_cnt],
                "by_amount": [{"username": u, "count": int(c), "amount": int(a or 0)} for u, c, a in rows_amt],
            }

    async def query_unique_usernames(
        self,
        username: Optional[str] = None,
        keyword: Optional[str] = None,
        chat_id: Optional[int] = None,
        chat_title: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        min_amount: Optional[int] = None,
        exclude_bots: bool = True,
    ) -> List[str]:
        async with self.get_session() as session:
            from sqlalchemy import select, and_, not_, func

            from typing import Any as _Any
            conditions: List[_Any] = [Hit.username.is_not(None)]
            if username:
                conditions.append(Hit.username == username)
            if keyword:
                conditions.append(Hit.keyword == keyword)
            if chat_id:
                conditions.append(Hit.chat_id == chat_id)
            if chat_title:
                conditions.append(Hit.chat_title == chat_title)
            if start_time:
                conditions.append(Hit.hit_at >= start_time)
            if end_time:
                conditions.append(Hit.hit_at <= end_time)
            if min_amount is not None:
                conditions.append(Hit.amount >= int(min_amount))
            if exclude_bots:
                conditions.append(not_(func.lower(Hit.username).like("%bot%")))

            where_clause = and_(*conditions)
            stmt = select(func.distinct(Hit.username)).where(where_clause)
            rows = (await session.execute(stmt)).all()
            return [r[0] for r in rows if r[0]]


