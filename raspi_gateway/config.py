"""
树莓派网关配置 — 端口、串口参数、设备注册表
设备与传感器配置从 JSON 文件加载，支持运行时热更新
"""

import json
import os

_CONFIG_DIR = os.path.dirname(os.path.abspath(__file__))


def _load_json(filename: str) -> dict:
    path = os.path.join(_CONFIG_DIR, filename)
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"配置文件不存在: {path}")
    except json.JSONDecodeError as e:
        raise RuntimeError(f"配置文件格式错误 {path}: {e}")


def _parse_hex(obj):
    if isinstance(obj, str) and obj.startswith("0x") or obj.startswith("0X"):
        return int(obj, 16)
    return obj


def _load_devices() -> tuple:
    """从 devices.json 加载设备注册表和动作值映射"""
    cfg = _load_json("devices.json")
    registry = {}
    for dev_id, dev in cfg.get("devices", {}).items():
        entry = {}
        for key in ("zone", "dev_type", "dev_index", "zone2", "dev_type2", "dev_index2"):
            if key in dev:
                entry[key] = _parse_hex(dev[key])
        entry["name"] = dev.get("name", dev_id)
        entry["category"] = dev.get("category", "unknown")
        if dev.get("dual_frame"):
            entry["dual_frame"] = True
        if "actions" in dev:
            entry["actions"] = dev["actions"]
        if "brightness_range" in dev:
            entry["brightness_range"] = dev["brightness_range"]
        registry[dev_id] = entry

    raw_action_map = cfg.get("action_value_map", {})
    action_map = {}
    for category, actions in raw_action_map.items():
        parsed = {}
        for action, value in actions.items():
            if isinstance(value, str) and value.startswith("param:"):
                parsed[action] = value
            elif isinstance(value, str):
                parsed[action] = _parse_hex(value)
            else:
                parsed[action] = value
        action_map[category] = parsed

    return registry, action_map


def _load_sensors() -> tuple:
    """从 sensors.json 加载传感器配置"""
    cfg = _load_json("sensors.json")

    type_map = {}
    for k, v in cfg.get("sensor_type_map", {}).items():
        type_map[_parse_hex(k)] = v

    divide_set = set()
    for k in cfg.get("sensor_divide_by_1000", []):
        divide_set.add(_parse_hex(k))

    direct_set = set()
    for k in cfg.get("sensor_direct", []):
        direct_set.add(_parse_hex(k))

    device_map = cfg.get("sensor_device_map", {})

    return type_map, divide_set, direct_set, device_map


# ---- 网络端口 ----
UDP_PORT = 8888
TCP_PORT = 9999
VIDEO_PORT = 9998

# ---- 串口参数 ----
SERIAL_PORT = "/dev/ttyAMA0"
SENSOR_SERIAL_PORT = "/dev/ttyAMA2"
SERIAL_BAUDRATE = 9600
SERIAL_TIMEOUT = 0.1

# ---- 心跳与超时 ----
DISCOVERY_INTERVAL = 20
HEARTBEAT_TIMEOUT = 45

# ---- 网关身份 ----
GATEWAY_ID = "raspi_gateway_01"
GATEWAY_NAME = "客厅网关"
GATEWAY_TYPE = "gateway"
FIRMWARE_VERSION = "1.0.0"

# ---- 串口帧格式 ----
FRAME_HEAD = 0xFF
FRAME_TAIL = 0xFE

# ---- 从 JSON 文件加载 ----
DEVICE_REGISTRY, ACTION_VALUE_MAP = _load_devices()
SENSOR_TYPE_MAP, SENSOR_DIVIDE_BY_1000, SENSOR_DIRECT, SENSOR_DEVICE_MAP = _load_sensors()


def reload_config():
    """运行时热更新配置（不重启网关）"""
    global DEVICE_REGISTRY, ACTION_VALUE_MAP
    global SENSOR_TYPE_MAP, SENSOR_DIVIDE_BY_1000, SENSOR_DIRECT, SENSOR_DEVICE_MAP
    DEVICE_REGISTRY, ACTION_VALUE_MAP = _load_devices()
    SENSOR_TYPE_MAP, SENSOR_DIVIDE_BY_1000, SENSOR_DIRECT, SENSOR_DEVICE_MAP = _load_sensors()