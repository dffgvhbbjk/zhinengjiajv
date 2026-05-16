"""
串口管理器 — 支持独立 TX/RX 端口
负责串口帧的收发，传感器数据缓存，串口自动重连
"""

from queue import Queue
import threading
import time

from config import SERIAL_PORT, SERIAL_BAUDRATE, SERIAL_TIMEOUT
from uart.serial_parser import SerialParser
from logs.logger import get_logger

logger = get_logger("serial")

RECONNECT_INTERVAL = 5.0


class SerialManager:
    """管理一个物理串口的收发（可用作控制端口或传感器端口）"""

    def __init__(self, port=SERIAL_PORT, baudrate=SERIAL_BAUDRATE,
                 on_sensor_data=None, on_cmd_response=None):
        self.port_name = port
        self.baudrate = baudrate
        self.on_sensor_data = on_sensor_data
        self.on_cmd_response = on_cmd_response
        self.ser = None
        self.parser = SerialParser()
        self._send_queue = Queue()
        self._running = False
        self._sensor_cache = {}
        self._cache_lock = threading.Lock()
        self._last_reconnect_attempt = 0.0

    # ---- 生命周期 ------------------------------------------------------

    def open(self):
        try:
            import serial
            self.ser = serial.Serial(
                port=self.port_name,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=SERIAL_TIMEOUT,
            )
            logger.info(f"串口已打开: {self.port_name} @ {self.baudrate}")
        except Exception as e:
            logger.error(f"串口打开失败: {e}")
            self.ser = None
            return False
        self._running = True
        return True

    def close(self):
        self._running = False
        if self.ser and self.ser.is_open:
            self.ser.close()
            logger.info("串口已关闭")

    def is_open(self) -> bool:
        return self.ser is not None and self.ser.is_open

    # ---- 发送 ----------------------------------------------------------

    def send_frame(self, frame: bytes):
        """发送一帧到 STM32（串口打开时同步写入，否则入队等待重连后发送）"""
        if self.ser and self.ser.is_open:
            try:
                self.ser.write(frame)
                logger.debug(f"TX: {frame.hex(' ').upper()}")
                return
            except Exception as e:
                logger.error(f"串口写入失败: {e}, 将尝试重连")
                self._close_port()
                raise
        self._send_queue.put(frame)

    # ---- 收发轮询（主循环中调用） ---------------------------------------

    def poll(self):
        """处理发送队列 + 接收缓冲区，串口断开时自动重连"""
        if not self.is_open() and self._running:
            self._try_reconnect()
            return

        # 发送
        while not self._send_queue.empty():
            frame = self._send_queue.get_nowait()
            if self.ser and self.ser.is_open:
                try:
                    self.ser.write(frame)
                    logger.debug(f"TX: {frame.hex(' ').upper()}")
                except Exception as e:
                    logger.error(f"串口写入失败: {e}, 将尝试重连")
                    self._close_port()
                    return

        # 接收
        if self.ser and self.ser.is_open:
            try:
                waiting = self.ser.in_waiting
                if waiting > 0:
                    data = self.ser.read(waiting)
                    frames = self.parser.feed(data)
                    for frame in frames:
                        logger.debug(f"RX: {frame.hex(' ').upper()}")
                        self._handle_frame(frame)
            except Exception as e:
                logger.error(f"串口读取失败: {e}, 将尝试重连")
                self._close_port()

    # ---- 自动重连 --------------------------------------------------------

    def _close_port(self):
        """关闭串口（不改变 _running 状态，以便后续重连）"""
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None

    def _try_reconnect(self):
        """每隔 RECONNECT_INTERVAL 秒尝试重新打开串口"""
        now = time.monotonic()
        if now - self._last_reconnect_attempt < RECONNECT_INTERVAL:
            return
        self._last_reconnect_attempt = now
        try:
            import serial
            self.ser = serial.Serial(
                port=self.port_name,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=SERIAL_TIMEOUT,
            )
            logger.info(f"串口已重连: {self.port_name} @ {self.baudrate}")
        except Exception as e:
            logger.warning(f"串口重连失败 ({self.port_name}): {e}")

    # ---- 帧路由 --------------------------------------------------------

    def _handle_frame(self, frame: bytes):
        """根据 Byte 1 区分传感器帧/控制帧"""
        if SerialParser.is_sensor_frame(frame):
            try:
                parsed = SerialParser.parse_sensor_frame(frame)
                with self._cache_lock:
                    self._sensor_cache[parsed["field"]] = parsed["value"]
                logger.info(f"SENSOR {parsed['field']}={parsed['value']:.3f}")
                if self.on_sensor_data:
                    self.on_sensor_data(parsed["field"], parsed["value"])
            except ValueError as e:
                logger.warning(f"传感器帧解析失败: {e}")
        elif SerialParser.is_control_frame(frame):
            try:
                parsed = SerialParser.parse_control_frame(frame)
                logger.info(f"CTRL_RSP zone={parsed['zone']:#04x} "
                            f"dev={parsed['dev_type']:#04x} "
                            f"idx={parsed['dev_index']:#04x} "
                            f"val={parsed['value']:#04x}")
                if self.on_cmd_response:
                    self.on_cmd_response(parsed)
            except ValueError as e:
                logger.warning(f"控制帧解析失败: {e}")
        else:
            logger.debug(f"未知帧类型: {frame.hex(' ').upper()}")

    # ---- 传感器缓存 ----------------------------------------------------

    def get_sensor_cache(self) -> dict:
        with self._cache_lock:
            return dict(self._sensor_cache)
