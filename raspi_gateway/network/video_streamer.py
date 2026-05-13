"""
摄像头视频流 — JPEG 推流 (端口 9998)
二进制帧格式: Magic(4B) + JPEG_Length(4B LE) + JPEG_Data(NB)
"""

import select
import socket
import struct
import threading
import time
from typing import Optional

try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False

from config import VIDEO_PORT
from logs.logger import get_logger

logger = get_logger("video")

MAGIC = b"\xAA\xBB\xCC\xDD"
CAMERA_WIDTH = 640
CAMERA_HEIGHT = 360
TARGET_FPS = 12


class VideoStreamer:
    """摄像头 JPEG 推流服务器"""

    def __init__(self, port=VIDEO_PORT):
        self.port = port
        self._server_sock = None
        self._client_sock = None
        self._running = False
        self._thread = None
        self._camera = None
        self._camera_type = ""

    # ---- 生命周期 ------------------------------------------------------

    def start(self):
        self._server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server_sock.bind(("0.0.0.0", self.port))
        self._server_sock.listen(1)
        self._server_sock.settimeout(1.0)
        self._running = True
        self._init_camera()
        self._thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._thread.start()
        logger.info(f"视频流已启动，端口 {self.port}")

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        self._disconnect_client()
        if self._server_sock:
            self._server_sock.close()
        if self._camera:
            try:
                if self._camera_type == "picamera2":
                    self._camera.stop()
                self._camera.close()
            except Exception:
                pass
        logger.info("视频流已停止")

    def is_camera_available(self) -> bool:
        return self._camera is not None

    def _init_camera(self):
        """初始化摄像头（先试 Picamera2，失败则回退 OpenCV）"""

        # 尝试 Picamera2（CSI/USB 均可，libcamera 驱动）
        try:
            from picamera2 import Picamera2
            self._camera = Picamera2()
            config = self._camera.create_video_configuration(
                main={"size": (CAMERA_WIDTH, CAMERA_HEIGHT), "format": "MJPEG"},
                buffer_count=4,
            )
            self._camera.configure(config)
            self._camera.start()
            self._camera_type = "picamera2"
            logger.info(f"摄像头: Picamera2 MJPEG {CAMERA_WIDTH}x{CAMERA_HEIGHT}")
            return
        except ImportError:
            pass
        except Exception as e:
            logger.warning(f"Picamera2 初始化失败 ({e})，尝试 OpenCV...")

        # 回退 OpenCV（USB 摄像头通用方案）
        if HAS_CV2:
            try:
                self._camera = cv2.VideoCapture(0)
                self._camera.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
                self._camera.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
                self._camera.set(cv2.CAP_PROP_FPS, 25)
                self._camera_type = "opencv"
                logger.info(f"摄像头: OpenCV {CAMERA_WIDTH}x{CAMERA_HEIGHT}")
                return
            except Exception as e:
                logger.error(f"OpenCV 初始化失败: {e}")
        else:
            logger.warning("OpenCV 未安装，摄像头不可用")

        self._camera = None

    # ---- 接受连接 ------------------------------------------------------

    def _accept_loop(self):
        while self._running:
            try:
                client, addr = self._server_sock.accept()
                self._disconnect_client()
                self._client_sock = client
                self._client_sock.settimeout(1.0)
                self._client_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                self._client_sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 256 * 1024)
                logger.info(f"视频客户端已连接: {addr}")
                self._stream_loop()
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

    # ---- 推流循环 ------------------------------------------------------

    def _stream_loop(self):
        frame_interval = 1.0 / TARGET_FPS
        next_frame_time = time.monotonic()
        dropped = 0
        sent = 0

        while self._running and self._client_sock and self._camera:
            now = time.monotonic()
            wait = next_frame_time - now
            if wait > 0.001:
                time.sleep(min(wait, 0.01))
                continue

            jpeg_bytes = self._capture_frame()
            if not jpeg_bytes or len(jpeg_bytes) <= 100:
                time.sleep(0.002)
                continue

            header = MAGIC + struct.pack("<I", len(jpeg_bytes))
            data = header + jpeg_bytes

            _, writable, _ = select.select([], [self._client_sock], [], 0)
            if writable:
                try:
                    self._client_sock.sendall(data)
                    sent += 1
                    if dropped > 0:
                        dropped = 0
                except (OSError, BrokenPipeError):
                    self._disconnect_client()
                    break
                except socket.timeout:
                    dropped += 1
            else:
                dropped += 1
                time.sleep(0.002)

            next_frame_time += frame_interval
            if next_frame_time < time.monotonic():
                next_frame_time = time.monotonic() + frame_interval

    def _capture_frame(self) -> Optional[bytes]:
        try:
            if self._camera_type == "picamera2":
                request = None
                try:
                    request = self._camera.capture_request()
                    buf = request.make_buffer("main")
                    if buf is None or not hasattr(buf, "planes"):
                        return None
                    data = buf.planes[0]
                    return bytes(data)
                finally:
                    if request is not None:
                        request.release()
            elif self._camera_type == "opencv":
                ret, frame = self._camera.read()
                if ret:
                    _, jpeg = cv2.imencode(".jpg", frame,
                                           [cv2.IMWRITE_JPEG_QUALITY, 40])
                    return jpeg.tobytes()
        except Exception as e:
            logger.warning(f"帧捕获异常: {e}")
        return None