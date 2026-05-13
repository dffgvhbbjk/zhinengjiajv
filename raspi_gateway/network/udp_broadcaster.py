"""
UDP 广播器 — 设备发现 + 传感器数据广播 + 接收请求 (端口 8888)
"""

import json
import socket
import threading
import time

from config import UDP_PORT, DISCOVERY_INTERVAL, GATEWAY_ID, GATEWAY_NAME, \
    GATEWAY_TYPE, FIRMWARE_VERSION, TCP_PORT, DEVICE_REGISTRY
from protocol.json_packets import build_discovery_packet
from logs.logger import get_logger

logger = get_logger("udp")


class UdpBroadcaster:
    """定期广播设备存在 + 按需广播传感器数据 + 接收 data_refresh_request"""

    def __init__(self, port=UDP_PORT, sensor_provider=None):
        self.port = port
        self._sock = None
        self._running = False
        self._thread = None
        self._recv_thread = None
        self._stop_event = threading.Event()
        self._sensor_provider = sensor_provider
        self._broadcast_lock = threading.Lock()
        self._burst_done = False

    # ---- 生命周期 ------------------------------------------------------

    def start(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._sock.bind(("0.0.0.0", self.port))
        self._running = True
        self._thread = threading.Thread(target=self._broadcast_loop, daemon=True)
        self._thread.start()
        self._recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self._recv_thread.start()
        threading.Thread(target=self._startup_burst, daemon=True).start()
        logger.info(f"UDP 广播器已启动，端口 {self.port} (收发)")

    def stop(self):
        self._running = False
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=2)
        if self._recv_thread:
            self._recv_thread.join(timeout=2)
        if self._sock:
            self._sock.close()
        logger.info("UDP 广播器已停止")

    # ---- 后台广播线程 --------------------------------------------------

    def _startup_burst(self):
        for i in range(3):
            time.sleep(0.3)
            self._broadcast_once()
            logger.info(f"UDP 启动广播 {i + 1}/3")
        self._burst_done = True

    def _broadcast_once(self):
        with self._broadcast_lock:
            pkt = build_discovery_packet(
                device_id=GATEWAY_ID, name=GATEWAY_NAME,
                dtype=GATEWAY_TYPE, tcp_port=TCP_PORT, fw=FIRMWARE_VERSION,
            )
            self._send(pkt)

            for dev_id, dev in DEVICE_REGISTRY.items():
                sub_pkt = build_discovery_packet(
                    device_id=dev_id, name=dev.get("name", dev_id),
                    dtype=dev.get("category", "device"), tcp_port=TCP_PORT, fw="1.0",
                )
                self._send(sub_pkt)

    def _broadcast_loop(self):
        while self._running:
            try:
                self._broadcast_once()
                logger.info(f"UDP 设备广播 ×{len(DEVICE_REGISTRY) + 1}")
            except Exception as e:
                logger.error(f"UDP 广播失败: {e}")

            self._stop_event.wait(DISCOVERY_INTERVAL)

    def _send(self, data: str):
        if self._sock:
            try:
                self._sock.sendto(data.encode("utf-8"), ("255.255.255.255", self.port))
            except OSError as e:
                logger.error(f"UDP 发送失败: {e}")

    # ---- UDP 接收 ------------------------------------------------------

    def _recv_loop(self):
        self._sock.settimeout(1.0)
        while self._running:
            try:
                data, addr = self._sock.recvfrom(4096)
                raw = data.decode("utf-8")
                if "\"data_refresh_request\"" not in raw:
                    continue
                try:
                    obj = json.loads(raw)
                    msg_type = obj.get("type", "")
                    if msg_type == "data_refresh_request":
                        logger.info(f"UDP RX data_refresh_request from {addr}")
                        if self._sensor_provider:
                            pkt = self._sensor_provider()
                            if pkt:
                                self._send(pkt)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    pass
            except socket.timeout:
                continue
            except OSError:
                break

    def broadcast_raw(self, data: str):
        """直接发送原始字符串（用于已组装好的 JSON 包）"""
        self._send(data)
