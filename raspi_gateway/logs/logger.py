"""
简易日志模块
"""

import logging
import os

LOG_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(LOG_DIR, "gateway.log")

_initialized = False


def _init_handlers():
    global _initialized
    if _initialized:
        return

    root = logging.getLogger("raspi")
    root.setLevel(logging.DEBUG)

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    ch.setFormatter(fmt)
    root.addHandler(ch)

    try:
        fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(fmt)
        root.addHandler(fh)
    except (PermissionError, OSError):
        pass

    _initialized = True


def get_logger(name: str = "raspi_gateway") -> logging.Logger:
    logger = logging.getLogger(f"raspi.{name}")
    _init_handlers()
    return logger