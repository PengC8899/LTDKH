import logging
import inspect
from typing import Optional, Any
from urllib.parse import urlparse, urlunparse

try:
    from redis.asyncio import Redis  # type: ignore
except ImportError:
    from redis import Redis  # type: ignore  # 回退到同步版本


logger = logging.getLogger(__name__)


class RedisClient:
    def __init__(self, redis_url: str) -> None:
        self.redis_url = redis_url
        # 兼容异步/同步 Redis 客户端
        self._client: Optional[Any] = None

    async def connect(self) -> None:
        if self._client is None:
            self._client = Redis.from_url(self.redis_url, encoding="utf-8", decode_responses=True)
            try:
                pong = self._client.ping()
                if inspect.isawaitable(pong):
                    await pong
                logger.info("Redis 连接成功：%s", self.redis_url)
                return
            except Exception:
                # 若 .env 指向 docker 主机名 `redis`，本地直跑时尝试回退到 localhost
                try:
                    parsed = urlparse(self.redis_url)
                    if parsed.hostname == "redis":
                        fallback = parsed._replace(netloc=f"localhost:{parsed.port or 6379}")
                        fallback_url = urlunparse(fallback)
                        logger.warning("Redis 连接失败，尝试回退到本地：%s -> %s", self.redis_url, fallback_url)
                        self._client = Redis.from_url(fallback_url, encoding="utf-8", decode_responses=True)
                        pong2 = self._client.ping()
                        if inspect.isawaitable(pong2):
                            await pong2
                        logger.info("Redis 回退连接成功：%s", fallback_url)
                        return
                except Exception as e:
                    logger.exception("Redis 回退连接失败：%s", e)
                raise

    @property
    def client(self) -> Any:
        assert self._client is not None, "Redis 尚未连接"
        return self._client

    async def close(self) -> None:
        if self._client is not None:
            close_fn = getattr(self._client, "close", None) or getattr(self._client, "aclose", None)
            if callable(close_fn):
                try:
                    result = close_fn()
                    if inspect.isawaitable(result):
                        await result
                except Exception:
                    # 忽略关闭异常，避免影响退出流程
                    pass
            self._client = None


