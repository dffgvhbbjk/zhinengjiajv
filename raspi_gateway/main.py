"""
树莓派智能家居网关 — 主入口

职责：
  1. 串口控制 (/dev/ttyAMA0, 9600) ↔ STM32 控制帧收发
  2. 串口传感器 (/dev/ttyAMA3, 9600) ← STM32 传感器数据单向接收
  3. TCP Server (9999) ↔ QT6 客户端 命令/响应
  4. UDP Broadcaster (8888) ↔ QT6 客户端 设备发现/传感器广播
  5. TCP Video Stream (9998) ↔ QT6 客户端 摄像头 JPEG 推流

启动方式:
  python main.py
"""

from collections import deque
from typing import Optional

import json
import signal
import sys
import time
import threading

from config import DEVICE_REGISTRY, GATEWAY_ID, SERIAL_PORT, SENSOR_SERIAL_PORT, SERIAL_BAUDRATE
from config import SENSOR_DEVICE_MAP
from uart.serial_manager import SerialManager
from uart.serial_dispatcher import SerialDispatcher
from network.udp_broadcaster import UdpBroadcaster
from network.tcp_server import TcpServer
from network.video_streamer import VideoStreamer
from protocol.json_packets import (build_cmd_response, build_sensor_packet,
                                  build_sensor_update_packet,
                                  build_voice_text_ack, build_scene_ack,
                                  build_schedule_ack, build_firmware_ack)
from logs.logger import get_logger

logger = get_logger("main")

SERIAL_RESPONSE_TIMEOUT = 5.0

_REVERSE_ACTIONS = {
    "on": "off", "off": "on",
    "open": "close", "close": "open",
    "start": "stop", "stop": "start",
}

# ---- 全局组件 ----------------------------------------------------------
cmd_serial: Optional[SerialManager] = None
sensor_serial: Optional[SerialManager] = None
dispatcher: SerialDispatcher = None
udp: UdpBroadcaster = None
tcp: TcpServer = None
video: VideoStreamer = None
_pending_command_ids = deque(maxlen=200)
_command_id_lock = threading.Lock()
_REVERSE_LOOKUP = {}
_last_timeout_check = 0.0


def _build_reverse_lookup() -> dict:
    rev = {}
    for dev_id, dev in DEVICE_REGISTRY.items():
        rev[(dev.get("zone"), dev.get("dev_type"), dev.get("dev_index"))] = dev_id
        if dev.get("dual_frame"):
            rev[(dev.get("zone2"), dev.get("dev_type2"), dev.get("dev_index2"))] = dev_id
    return rev


def _build_sensor_refresh_pkt() -> str:
    """构建传感器数据 JSON 包（供 UDP data_refresh_request 使用）"""
    cache = sensor_serial.get_sensor_cache() if sensor_serial else {}
    return build_sensor_packet(
        temperature=cache.get("temperature", 0.0),
        humidity=cache.get("humidity", 0.0),
        light=cache.get("light", 0.0),
        rain=cache.get("rain", 0.0),
        smoke=cache.get("smoke", 0.0),
        lpg=cache.get("lpg", 0.0),
        air_quality=cache.get("air_quality", 0.0),
        pressure=cache.get("pressure", 0.0),
    )


# ============================================================
# 初始化
# ============================================================

def init():
    global cmd_serial, sensor_serial, dispatcher, udp, tcp, video, _REVERSE_LOOKUP

    _REVERSE_LOOKUP = _build_reverse_lookup()

    # 1. 控制串口 — ttyAMA0（发控制帧 + 收控制响应）
    cmd_serial = SerialManager(
        port=SERIAL_PORT, baudrate=SERIAL_BAUDRATE,
        on_cmd_response=handle_cmd_response,
    )
    if not cmd_serial.open():
        logger.warning("控制串口不可用，将以无硬件模式运行")

    # 2. 传感器串口 — ttyAMA3（只收传感器帧）
    sensor_serial = SerialManager(
        port=SENSOR_SERIAL_PORT, baudrate=SERIAL_BAUDRATE,
        on_sensor_data=handle_sensor_data,
    )
    if not sensor_serial.open():
        logger.warning("传感器串口不可用，传感器数据将缺失")

    # 3. 串口指令分发器
    dispatcher = SerialDispatcher(DEVICE_REGISTRY)

    # 4. UDP 广播器（含接收 + sensor_provider）
    udp = UdpBroadcaster(sensor_provider=_build_sensor_refresh_pkt)
    try:
        udp.start()
    except OSError as e:
        logger.error(f"UDP 广播器启动失败 (端口 {udp.port}): {e}")

    # 5. TCP 命令服务器
    tcp = TcpServer(on_command=handle_tcp_command)
    try:
        tcp.start()
    except OSError as e:
        logger.error(f"TCP 服务器启动失败 (端口 {tcp.port}): {e}")

    # 6. 视频流
    video = VideoStreamer()
    try:
        video.start()
    except OSError as e:
        logger.error(f"视频流启动失败 (端口 {video.port}): {e}")


# ============================================================
# 清理
# ============================================================

def cleanup():
    logger.info("正在关闭...")
    for comp, name in [(video, "视频流"), (tcp, "TCP"),
                       (udp, "UDP"), (cmd_serial, "控制串口"),
                       (sensor_serial, "传感器串口")]:
        if comp:
            try:
                comp.stop()
            except Exception as e:
                logger.warning(f"{name}关闭异常: {e}")
    logger.info("网关已停止")


def signal_handler(sig, frame):
    logger.info(f"收到信号 {sig}")
    cleanup()
    sys.exit(0)


# ============================================================
# TCP JSON 命令 → 串口帧
# ============================================================

def handle_tcp_command(json_cmd: dict):
    """按 type 路由到对应处理器，返回响应 dict/str 或 None"""
    msg_type = json_cmd.get("type", "")

    if msg_type == "control":
        return _handle_control(json_cmd)

    elif msg_type == "scene":
        result = _handle_scene(json_cmd)
        if result is not None:
            return result
        return None

    elif msg_type == "data_refresh_request":
        return _handle_data_refresh()

    elif msg_type == "hello":
        return _handle_hello()

    elif msg_type == "voice_text":
        tcp.send_response(build_voice_text_ack(
            json_cmd.get("text", "")))
        text = json_cmd.get("text", "")
        is_cmd = json_cmd.get("is_command", False)
        logger.info(f"VOICE: {'[CMD]' if is_cmd else '[TXT]'} {text}")
        return None

    elif msg_type == "schedule":
        command_id = json_cmd.get("commandId", "")
        tcp.send_response(build_schedule_ack(command_id))
        logger.info(f"SCHEDULE: {json_cmd.get('data', '')[:50]}...")
        return None

    elif msg_type == "alert_command":
        logger.info(f"ALERT_CMD: {json_cmd.get('action', '')}")
        return None

    elif msg_type == "firmware_init":
        total = json_cmd.get("totalChunks", 0)
        logger.info(f"FW_INIT: {total} chunks, {json_cmd.get('fileName', '')}")
        tcp.send_response(build_firmware_ack(chunk=-1, status="ok"))
        return None

    elif msg_type == "firmware_chunk":
        chunk = json_cmd.get("chunk", -1)
        tcp.send_response(build_firmware_ack(chunk=chunk, status="ok"))
        return None

    else:
        logger.warning(f"未知消息类型: {msg_type}")
        return None


def _handle_control(json_cmd: dict):
    if cmd_serial is None or not cmd_serial.is_open():
        return build_cmd_response(
            json_cmd.get("commandId", ""), success=False, msg="控制串口不可用")

    try:
        frames = dispatcher.dispatch(json_cmd)
        cmd_id = json_cmd.get("commandId", "")
        dev_id = json_cmd.get("device", "")
        now = time.monotonic()
        for frame in frames:
            cmd_serial.send_frame(frame)
        with _command_id_lock:
            for i in range(len(frames)):
                _pending_command_ids.append({
                    "commandId": cmd_id,
                    "device_id": dev_id,
                    "is_last_frame": i == len(frames) - 1,
                    "timestamp": now,
                })
        logger.info(f"CTRL → {json_cmd['device']}.{json_cmd['action']} "
                    f"({len(frames)} 帧)")
        return None
    except Exception as e:
        logger.error(f"控制命令失败: {e}")
        return build_cmd_response(
            json_cmd.get("commandId", ""), success=False, msg=str(e))


def _parse_action_list(json_cmd: dict, key: str = "actions"):
    """解析 actions/actionDevices 字段：支持 JSON 数组 或 逗号分隔字符串（兼容旧格式）"""
    raw = json_cmd.get(key)
    if raw is None:
        return []
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str):
        raw_str = raw.strip()
        if raw_str == "":
            return []
        if raw_str.startswith("["):
            try:
                return json.loads(raw_str)
            except json.JSONDecodeError:
                pass
        return [a.strip() for a in raw_str.split(",") if a.strip()]
    return []


def _handle_scene(json_cmd: dict):
    if cmd_serial is None or not cmd_serial.is_open():
        return build_cmd_response(
            json_cmd.get("commandId", ""), success=False, msg="控制串口不可用")

    try:
        actions = _parse_action_list(json_cmd)
        devices = _parse_action_list(json_cmd, key="actionDevices")

        if len(actions) != len(devices):
            return build_cmd_response(
                json_cmd.get("commandId", ""), success=False,
                msg="actions/actionDevices length mismatch")

        all_frames = []
        for dev_id, action in zip(devices, actions):
            sub_cmd = {"device": dev_id.strip(), "action": action.strip()}
            frames = dispatcher.dispatch(sub_cmd)
            for frame in frames:
                all_frames.append((frame, dev_id.strip(), action.strip()))

        frame_count = len(all_frames)
        logger.info(f"SCENE: {json_cmd.get('sceneName', '')} "
                    f"({len(devices)} 设备, {frame_count} 帧)")

        scene_cmd_id = json_cmd.get("commandId", "")
        now = time.monotonic()

        with _command_id_lock:
            for i, (frame, dev_id, _action) in enumerate(all_frames):
                _pending_command_ids.append({
                    "commandId": scene_cmd_id,
                    "device_id": dev_id,
                    "is_last_frame": i == len(all_frames) - 1,
                    "timestamp": now,
                })

        succeeded = []
        for i, (frame, dev_id, action) in enumerate(all_frames):
            try:
                cmd_serial.send_frame(frame)
                succeeded.append((dev_id, action))
            except Exception as send_err:
                logger.error(f"SCENE 帧发送失败 (第{i + 1}/{frame_count}帧, "
                             f"设备={dev_id}, 动作={action}): {send_err}")
                _rollback_scene_frames(succeeded)
                return build_cmd_response(
                    scene_cmd_id, success=False,
                    msg=f"场景部分失败: 已执行{len(succeeded)}/{frame_count}帧, "
                        f"第{i + 1}帧发送失败({send_err})，已回滚已执行帧")

        return None
    except Exception as e:
        logger.error(f"场景执行失败: {e}")
        return build_cmd_response(
            json_cmd.get("commandId", ""), success=False, msg=str(e))


def _rollback_scene_frames(succeeded: list):
    """回滚已发送的场景帧，发送反向命令"""
    if not succeeded:
        return
    logger.warning(f"SCENE_ROLLBACK: 正在回滚 {len(succeeded)} 个已执行操作...")
    rolled_back = 0
    for dev_id, action in succeeded:
        reverse_action = _REVERSE_ACTIONS.get(action)
        if reverse_action is None:
            logger.warning(f"SCENE_ROLLBACK: 设备={dev_id} 动作={action} 无反向映射，跳过回滚")
            continue
        try:
            sub_cmd = {"device": dev_id, "action": reverse_action}
            frames = dispatcher.dispatch(sub_cmd)
            for frame in frames:
                cmd_serial.send_frame(frame)
            rolled_back += 1
            logger.info(f"SCENE_ROLLBACK: 设备={dev_id} {action}→{reverse_action} 已回滚")
        except Exception as e:
            logger.error(f"SCENE_ROLLBACK: 设备={dev_id} 回滚失败 ({action}→{reverse_action}): {e}")
    logger.warning(f"SCENE_ROLLBACK: 回滚完成 ({rolled_back}/{len(succeeded)} 成功)")


def _handle_data_refresh():
    cache = sensor_serial.get_sensor_cache() if sensor_serial else {}
    if not cache:
        return None
    pkt = build_sensor_packet(
        temperature=cache.get("temperature", 0.0),
        humidity=cache.get("humidity", 0.0),
        light=cache.get("light", 0.0),
        rain=cache.get("rain", 0.0),
        smoke=cache.get("smoke", 0.0),
        lpg=cache.get("lpg", 0.0),
        air_quality=cache.get("air_quality", 0.0),
        pressure=cache.get("pressure", 0.0),
    )
    udp.broadcast_raw(pkt)
    logger.debug("DATA_REFRESH → UDP")
    return None


def _handle_hello():
    """Hello 握手响应"""
    from protocol.checksum import compute_checksum
    camera_available = video is not None and video.is_camera_available()
    resp = {
        "type": "command_response",
        "commandId": "hello",
        "status": "success",
        "message": "connected",
        "camera": camera_available,
        "videoPort": 9998,
    }
    resp["checksum"] = compute_checksum(resp)
    return json.dumps(resp, separators=(",", ":"), ensure_ascii=False)


# ============================================================
# 串口帧 → JSON
# ============================================================

def handle_sensor_data(field: str, value: float):
    sensor_device_id = SENSOR_DEVICE_MAP.get(field, GATEWAY_ID)
    pkt = build_sensor_update_packet(device_id=sensor_device_id, field=field, value=value)
    udp.broadcast_raw(pkt)


def handle_cmd_response(parsed: dict):
    zone = parsed.get("zone")
    dev_type = parsed.get("dev_type")
    dev_index = parsed.get("dev_index")
    frame_dev_id = _REVERSE_LOOKUP.get((zone, dev_type, dev_index))

    with _command_id_lock:
        entry = _match_and_pop_pending(frame_dev_id)

    if entry is None:
        logger.warning(f"CMD_RSP 收到孤立响应: zone={zone:#04x} dev_type={dev_type:#04x} dev_index={dev_index:#04x}")
        return

    cid = entry.get("commandId", "")
    expected_dev = entry.get("device_id", "")
    is_last = entry.get("is_last_frame", True)

    if frame_dev_id and expected_dev and frame_dev_id != expected_dev:
        logger.warning(f"CMD_RSP 设备不匹配: 期望={expected_dev} 实际={frame_dev_id} zone={zone:#04x}")

    if cid and tcp.is_connected():
        if is_last:
            resp = build_cmd_response(cid, success=True)
            tcp.send_response(resp)
            logger.info(f"CMD_RSP → TCP commandId={cid} device={frame_dev_id or expected_dev} (final)")
        else:
            logger.info(f"CMD_RSP device={frame_dev_id or expected_dev} (intermediate, waiting for more)")


def _match_and_pop_pending(frame_dev_id: Optional[str]) -> Optional[dict]:
    """按 device_id 匹配并移除待响应条目，无匹配时回退到队列首"""
    if not _pending_command_ids:
        return None

    if frame_dev_id is None:
        return _pending_command_ids.popleft()

    for i, entry in enumerate(_pending_command_ids):
        if entry.get("device_id") == frame_dev_id:
            del _pending_command_ids[i]
            return entry

    # 未精确匹配时，回退到队列首（兼容场景：响应不带 device_id 映射的情况）
    logger.warning(f"CMD_RSP 无法精确匹配 device_id={frame_dev_id}，回退到队列首")
    return _pending_command_ids.popleft()


def _check_command_timeouts():
    global _last_timeout_check
    now = time.monotonic()
    if now - _last_timeout_check < 1.0:
        return
    _last_timeout_check = now

    expired = []
    with _command_id_lock:
        while _pending_command_ids:
            entry = _pending_command_ids[0]
            if now - entry.get("timestamp", 0) > SERIAL_RESPONSE_TIMEOUT:
                expired.append(_pending_command_ids.popleft())
            else:
                break

    for entry in expired:
        cid = entry.get("commandId", "")
        if cid and tcp and tcp.is_connected():
            resp = build_cmd_response(cid, success=False, msg="串口响应超时")
            tcp.send_response(resp)
            logger.warning(f"CMD_TIMEOUT commandId={cid} device={entry.get('device_id', '')}")


# ============================================================
# 主入口
# ============================================================

def main():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("===== 树莓派智能家居网关 启动 =====")
    logger.info(f"控制串口: {SERIAL_PORT} | 传感器串口: {SENSOR_SERIAL_PORT} @ {SERIAL_BAUDRATE}")
    logger.info(f"TCP: 9999 (命令) | UDP: 8888 (发现/传感器) | TCP: 9998 (视频)")
    logger.info(f"已注册 {len(DEVICE_REGISTRY)} 个设备")

    init()

    try:
        last_bulk_sensor_time = 0.0
        while True:
            if cmd_serial:
                try:
                    cmd_serial.poll()
                except Exception as e:
                    logger.error(f"控制串口异常: {e}", exc_info=True)
            if sensor_serial:
                try:
                    sensor_serial.poll()
                except Exception as e:
                    logger.error(f"传感器串口异常: {e}", exc_info=True)

            now = time.monotonic()
            if now - last_bulk_sensor_time >= 2.0:
                if tcp and tcp.is_connected():
                    _handle_data_refresh()
                last_bulk_sensor_time = now

            _check_command_timeouts()

            time.sleep(0.05)
    except KeyboardInterrupt:
        pass
    finally:
        cleanup()


if __name__ == "__main__":
    main()
