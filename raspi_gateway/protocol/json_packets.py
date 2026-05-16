"""
JSON 包构建 — 设备发现、传感器数据、命令响应
"""

import json
import time

from config import GATEWAY_ID
from protocol.checksum import compute_checksum


def build_discovery_packet(device_id=GATEWAY_ID, name="客厅网关",
                           dtype="gateway", tcp_port=9999, fw="1.0.0") -> str:
    pkt = {
        "type": "device_discovery",
        "device_id": device_id,
        "device_name": name,
        "device_type": dtype,
        "tcp_port": tcp_port,
        "firmware_version": fw,
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_sensor_packet(device_id=GATEWAY_ID, temperature=0.0, humidity=0.0,
                        light=0.0, rain=0.0, smoke=0.0, lpg=0.0,
                        air_quality=0.0, pressure=0.0) -> str:
    pkt = {
        "type": "sensor_data",
        "device_id": device_id,
        "temperature": temperature,
        "humidity": humidity,
        "light": light,
        "rain": rain,
        "smoke": smoke,
        "lpg": lpg,
        "air_quality": air_quality,
        "pressure": pressure,
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_sensor_update_packet(device_id: str, field: str, value: float, version: int = 0) -> str:
    pkt = {
        "type": "sensor_update",
        "device_id": device_id,
        "field": field,
        "value": value,
    }
    if version > 0:
        pkt["version"] = version
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_cmd_response(command_id: str, success: bool = True,
                       msg: str = "ok", device_id: str = "",
                       device_state: str = "",
                       version: int = 0) -> str:
    pkt = {
        "type": "command_response",
        "commandId": command_id,
        "status": "success" if success else "failed",
        "message": msg,
    }
    if device_id:
        pkt["device_id"] = device_id
    if device_state:
        pkt["device_state"] = device_state
    if version > 0:
        pkt["version"] = version
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_heartbeat_ack() -> str:
    pkt = {
        "type": "heartbeat_ack",
        "timestamp": int(time.time() * 1000),
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_voice_text_ack(text: str = "") -> str:
    pkt = {
        "type": "voice_text_ack",
        "text": text,
        "timestamp": int(time.time() * 1000),
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_scene_ack(scene_id: str = "", success: bool = True) -> str:
    pkt = {
        "type": "scene_ack",
        "sceneId": scene_id,
        "status": "success" if success else "failed",
        "timestamp": int(time.time() * 1000),
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_schedule_ack(schedule_id: str = "", success: bool = True) -> str:
    pkt = {
        "type": "schedule_ack",
        "scheduleId": schedule_id,
        "status": "success" if success else "failed",
        "timestamp": int(time.time() * 1000),
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)


def build_firmware_ack(chunk: int = -1, status: str = "ok") -> str:
    pkt = {
        "type": "firmware_ack",
        "status": status,
        "chunk": chunk,
        "timestamp": int(time.time() * 1000),
    }
    pkt["checksum"] = compute_checksum(pkt)
    return json.dumps(pkt, separators=(",", ":"), ensure_ascii=False)

