"""
TCP 服务器 — 命令接收 + 响应 (端口 9999)
JSON 边界检测：括号计数法（兼容缓冲区粘包）
"""

import json
import socket
import threading
import time

from config import TCP_PORT, HEARTBEAT_TIMEOUT
from protocol.json_packets import build_heartbeat_ack
from logs.logger import get_logger

logger = get_logger("tcp")

MAX_RECV_BUF = 1 * 1024 * 1024


class TcpServer:
    """TCP 命令服务器，json_callback(json_obj) → 返回响应 dict/str 或 None"""

    def __init__(self, port=TCP_PORT, on_command=None):
        self.port = port
        self.on_command = on_command  # (dict) → dict|str|None
        self._server_sock = None
        self._client_sock = None
        self._client_addr = None
        self._running = False
        self._thread = None
        self._recv_buf = bytearray()
        self._last_heartbeat = 0.0

    # ---- 生命周期 ------------------------------------------------------

    def start(self):
        self._server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server_sock.bind(("0.0.0.0", self.port))
        self._server_sock.listen(1)
        self._server_sock.settimeout(1.0)
        self._running = True
        self._thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._thread.start()
        logger.info(f"TCP 服务器已启动，端口 {self.port}")

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        self._disconnect_client()
        if self._server_sock:
            self._server_sock.close()
        logger.info("TCP 服务器已停止")

    # ---- 接受连接 ------------------------------------------------------

    def _accept_loop(self):
        while self._running:
            try:
                client, addr = self._server_sock.accept()
                self._disconnect_client()  # 只允许一个客户端
                self._client_sock = client
                self._client_addr = addr
                self._client_sock.settimeout(1.0)
                self._client_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                self._recv_buf.clear()
                self._last_heartbeat = time.time()
                logger.info(f"QT 客户端已连接: {addr}")
                self._on_client_connected()
                self._recv_loop()
            except socket.timeout:
                continue
            except OSError:
                break

    def _disconnect_client(self):
        if self._client_sock:
            try:
                self._client_sock.close()
            except OSError:
                pass
            self._client_sock = None
            self._client_addr = None
            logger.info("客户端已断开")

    # ---- 客户端连接后发送 hello ----------------------------------------

    def _on_client_connected(self):
        """连接后由 main.handle_tcp_command 响应 hello，这里不重复发送"""
        pass

    # ---- 接收循环 ------------------------------------------------------

    def _recv_loop(self):
        while self._running and self._client_sock:
            try:
                data = self._client_sock.recv(4096)
                if not data:
                    self._disconnect_client()
                    break
                self._recv_buf.extend(data)
                if len(self._recv_buf) > MAX_RECV_BUF:
                    logger.warning("接收缓冲区超限，断开客户端")
                    self._disconnect_client()
                    break
                self._process_buffer()
            except socket.timeout:
                # 心跳超时检测
                if time.time() - self._last_heartbeat > HEARTBEAT_TIMEOUT:
                    logger.warning("心跳超时，断开客户端")
                    self._disconnect_client()
                    break
                continue
            except OSError:
                self._disconnect_client()
                break

    # ---- JSON 边界检测（括号计数法） -----------------------------------

    @staticmethod
    def _find_json_boundary(buf: bytes) -> int:
        """查找完整 JSON 对象的结束位置，未找到返回 -1"""
        depth = 0
        in_string = False
        escape = False
        for i, b in enumerate(buf):
            if escape:
                escape = False
                continue
            if in_string:
                if b == 0x5C:  # backslash
                    escape = True
                elif b == 0x22:  # double quote
                    in_string = False
            else:
                if b == 0x22:
                    in_string = True
                elif b == 0x7B:  # '{'
                    depth += 1
                elif b == 0x7D:  # '}'
                    depth -= 1
                    if depth == 0:
                        return i + 1
        return -1

    def _process_buffer(self):
        """从接收缓冲区提取完整 JSON 对象并处理"""
        while True:
            end = self._find_json_boundary(self._recv_buf)
            if end < 0:
                break
            raw = bytes(self._recv_buf[:end])
            del self._recv_buf[:end]
            try:
                obj = json.loads(raw.decode("utf-8"))
                self._handle_message(obj)
            except (json.JSONDecodeError, UnicodeDecodeError) as e:
                logger.warning(f"JSON 解析失败: {e} | raw={raw[:100]}")

    # ---- 消息路由 ------------------------------------------------------

    def _handle_message(self, obj: dict):
        msg_type = obj.get("type", "")
        logger.debug(f"TCP RX type={msg_type}")

        if msg_type == "heartbeat":
            self._last_heartbeat = time.time()
            self._send_raw(build_heartbeat_ack())

        elif self.on_command:
            try:
                result = self.on_command(obj)
                if result is not None:
                    if isinstance(result, dict):
                        self._send_raw(json.dumps(result, separators=(",", ":")))
                    elif isinstance(result, str):
                        self._send_raw(result)
            except Exception as e:
                logger.error(f"命令处理异常: {e}")

    # ---- 发送 ----------------------------------------------------------

    def _send_raw(self, data: str):
        if self._client_sock:
            try:
                self._client_sock.sendall(data.encode("utf-8"))
            except OSError as e:
                logger.error(f"TCP 发送失败: {e}")

    def send_response(self, data: str):
        """外部调用，发送响应字符串到 QT 客户端"""
        self._send_raw(data)

    def is_connected(self) -> bool:
        return self._client_sock is not None
