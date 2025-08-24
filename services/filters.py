from __future__ import annotations

import html
import re
from dataclasses import dataclass
from typing import Optional, List, Tuple


# 关键词与正则：支持带千分位的数字，至少3位数字
KEYWORDS = ["大单", "大双", "小单", "小双", "大", "小", "单", "双"]

# 金额匹配更严格：
# - 纯数字 >= 3 位，例如 300、12345
# - 或者带标准千分位分隔：1,000、12,345、1,234,567
NUM = r"(?:[1-9]\d{2,}|\d{1,3}(?:,\d{3})+)"
PATTERN = re.compile(rf"(大单|大双|小单|小双|大|小|单|双)\s*({NUM})")


@dataclass
class MatchResult:
    keyword: str
    amount: int
    original_amount_text: str


def parse_message(text: str) -> Optional[MatchResult]:
    """
    从文本中匹配关键词+金额，若有多个匹配取金额最大的；若金额相同取最早出现的。
    仅当金额 >= 300 时有效。
    """
    if not text:
        return None

    candidates: List[Tuple[int, int, str, str]] = []  # (amount, start_index, keyword, original_text)
    for m in PATTERN.finditer(text):
        kw = m.group(1)
        raw_num = m.group(2)
        normalized = int(raw_num.replace(",", ""))
        if normalized < 300:
            continue
        candidates.append((normalized, m.start(), kw, raw_num))

    if not candidates:
        return None

    # 取金额最大的；若相同，取 start 最小（最早）
    candidates.sort(key=lambda t: (-t[0], t[1]))
    amount, _, kw, raw = candidates[0]
    return MatchResult(keyword=kw, amount=amount, original_amount_text=raw)


def format_amount_with_thousands(n: int) -> str:
    return f"{n:,}"


def escape_html(text: Optional[str]) -> str:
    return html.escape(text or "")


