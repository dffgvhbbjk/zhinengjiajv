"""
MD5 checksum 计算 — 用于 UDP 数据包完整性校验
"""

import hashlib
import json
import math


def compute_checksum(packet_dict: dict) -> str:
    """
    1. 从 dict 中移除 checksum 键（如果存在）
    2. 整数型浮点数转为 int（与 Qt QJsonDocument::Compact 行为一致）
    3. json.dumps 成 Compact 格式（无空格，sort_keys 与 Qt 字母序一致）
    4. MD5 并返回十六进制字符串
    """
    d = {}
    for k, v in packet_dict.items():
        if k == "checksum":
            continue
        if isinstance(v, float) and math.isfinite(v) and v == int(v):
            d[k] = int(v)
        else:
            d[k] = v
    raw = json.dumps(d, separators=(",", ":"), ensure_ascii=False, sort_keys=True)
    return hashlib.md5(raw.encode("utf-8")).hexdigest()