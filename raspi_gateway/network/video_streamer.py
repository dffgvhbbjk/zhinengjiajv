"""
摄像头视频流 — JPEG 推流 (端口 9998)
二进制帧格式: Magic(4B) + JPEG_Length(4B LE) + JPEG_Data(NB)

CSI 摄像头: Picamera2 preview + XRGB8888 + capture_array (已验证可行)
USB 摄像头: OpenCV VideoCapture
"""

import socket
import struct
import threading
import time
from typing import Optional

try:
    import cv2
    import numpy as np
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
CAMERA_RETRY_INTERVAL = 10.0


def _generate_fallback_frame() -> bytes:
    black = np.zeros((CAMERA_HEIGHT, CAMERA_WIDTH, 3), dtype=np.uint8)
    cv2.putText(black, "No Camera", (CAMERA_WIDTH // 2 - 80, CAMERA_HEIGHT // 2),
                cv2.FONT_HERSHEY_SIMPLEX, 0.9, (200, 200, 200), 2)
    _, jpeg = cv2.imencode(".jpg", black, [cv2.IMWRITE_JPEG_QUALITY, 40])
    return jpeg.tobytes()


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
        self._last_retry_time = 0.0
        self._init_attempts = 0

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

    def _reset_camera(self):
        if self._camera:
            try:
                if self._camera_type == "picamera2":
                    self._camera.stop()
                self._camera.close()
            except Exception:
                pass
            self._camera = None
            self._camera_type = ""

    def _init_camera(self):
        """初始化摄像头（Picamera2 → OpenCV），启动时尝试，失败后支持热重试"""

        self._init_attempts += 1
        now = time.monotonic()

        if self._camera is not None:
            return

        if self._init_attempts > 1:
            if now - self._last_retry_time < CAMERA_RETRY_INTERVAL:
                return
            logger.info(f"尝试重新初始化摄像头 (第 {self._init_attempts} 次)...")

        self._last_retry_time = now

        if self._try_picamera2():
            return

        if HAS_CV2:
            if self._try_opencv_camera():
                return
        else:
            logger.warning("OpenCV 未安装，摄像头不可用")

        self._camera = None
        if self._init_attempts == 1:
            logger.error("所有摄像头方案均失败，视频流将不可用")
        else:
            logger.warning(f"摄像头重试失败 (第 {self._init_attempts} 次)，{CAMERA_RETRY_INTERVAL:.0f}s 后重试")

    def _try_picamera2(self) -> bool:
        """Picamera2 preview + XRGB8888，尝试多个 camera_num"""

        try:
            from picamera2 import Picamera2
        except ImportError:
            return False

        for camera_num in [0, 1]:
            cam = None
            try:
                logger.debug(f"尝试 Picamera2 camera_num={camera_num} ...")
                cam = Picamera2(camera_num=camera_num)
                config = cam.create_preview_configuration(
                    main={"format": "XRGB8888", "size": (CAMERA_WIDTH, CAMERA_HEIGHT)}
                )
                cam.configure(config)
                cam.start()
                time.sleep(0.8)

                test = cam.capture_array()
                if test is None or test.size == 0:
                    raise RuntimeError("capture_array 返回空帧")

                self._camera = cam
                self._camera_type = "picamera2"
                h, w = test.shape[:2]
                logger.info(f"摄像头: Picamera2 camera_num={camera_num} XRGB8888 {w}x{h}")
                return True
            except ImportError:
                return False
            except IndexError as e:
                logger.debug(f"Picamera2 camera_num={camera_num} 不存在或不可用: {e}")
                if cam is not None:
                    try:
                        cam.close()
                    except Exception:
                        pass
                continue
            except Exception as e:
                logger.warning(f"Picamera2 camera_num={camera_num} 初始化失败 ({type(e).__name__}: {e})")
                if cam is not None:
                    try:
                        cam.close()
                    except Exception:
                        pass
                continue

        return False

    def _try_opencv_camera(self) -> bool:
        """尝试用 OpenCV 打开摄像头，支持多索引 + V4L2 后端"""
        camera_indices = [0, 1]

        for idx in camera_indices:
            for backend in [cv2.CAP_V4L2, cv2.CAP_ANY]:
                try:
                    cap = cv2.VideoCapture(idx, backend)
                except Exception:
                    continue

                if not cap.isOpened():
                    cap.release()
                    continue

                cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

                for _ in range(5):
                    ret, frame = cap.read()
                    if ret and frame is not None and frame.size > 0:
                        actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                        actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                        logger.info(f"摄像头: OpenCV idx={idx} backend={backend} "
                                    f"{actual_w}x{actual_h}")
                        self._camera = cap
                        self._camera_type = "opencv"
                        return True
                    time.sleep(0.1)

                logger.warning(f"OpenCV idx={idx} backend={backend} 打开但无法读取帧")
                cap.release()

        return False

    # ---- 接受连接 ------------------------------------------------------

    def _accept_loop(self):
        while self._running:
            try:
                client, addr = self._server_sock.accept()
                self._disconnect_client()
                self._client_sock = client
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
        frame_count = 0
        fail_count = 0
        _consecutive_blocked_captures = 0

        while self._running and self._client_sock:
            now = time.monotonic()
            wait = next_frame_time - now
            if wait > 0:
                time.sleep(min(wait, 0.05))

            capture_start = time.monotonic()

            if self._camera is None:
                self._init_camera()
                if self._camera is None:
                    if not HAS_CV2:
                        time.sleep(0.5)
                        continue
                    if frame_count == 0:
                        logger.info("摄像头不可用，发送占位帧...")
                    jpeg_bytes = _generate_fallback_frame()
                else:
                    jpeg_bytes = self._capture_frame()
                    if not jpeg_bytes or len(jpeg_bytes) <= 100:
                        jpeg_bytes = _generate_fallback_frame()
            else:
                jpeg_bytes = self._capture_frame()

            capture_elapsed = time.monotonic() - capture_start
            if capture_elapsed > 2.0:
                _consecutive_blocked_captures += 1
                logger.warning(f"摄像头读取耗时 {capture_elapsed:.1f}s (第{_consecutive_blocked_captures}次)")
                if _consecutive_blocked_captures >= 3:
                    logger.error(f"摄像头连续{_consecutive_blocked_captures}次阻塞读取，重置摄像头")
                    self._reset_camera()
                    _consecutive_blocked_captures = 0
                    continue
            else:
                _consecutive_blocked_captures = 0

            if not jpeg_bytes or len(jpeg_bytes) <= 100:
                fail_count += 1
                if fail_count == 1:
                    logger.warning("首帧捕获失败，等待摄像头就绪...")
                if fail_count >= 30:
                    logger.error(f"连续 {fail_count} 次帧捕获失败，重置摄像头并断开客户端")
                    self._reset_camera()
                    self._disconnect_client()
                    break
                time.sleep(0.1)
                continue

            fail_count = 0
            frame_count += 1

            header = MAGIC + struct.pack("<I", len(jpeg_bytes))
            data = header + jpeg_bytes

            try:
                self._client_sock.sendall(data)
            except (OSError, BrokenPipeError, ConnectionResetError, TimeoutError):
                logger.info(f"视频客户端已断开 (已发送 {frame_count} 帧)")
                self._disconnect_client()
                break

            if frame_count % 30 == 0:
                logger.debug(f"视频流: 已发送 {frame_count} 帧, "
                              f"JPEG大小: {len(jpeg_bytes)}B")

            next_frame_time += frame_interval
            if next_frame_time < time.monotonic():
                next_frame_time = time.monotonic() + frame_interval

    def _capture_frame(self) -> Optional[bytes]:
        try:
            if self._camera_type == "picamera2":
                frame = self._camera.capture_array()
                if frame is None or frame.size == 0:
                    return None
                if frame.ndim == 3 and frame.shape[2] >= 4:
                    rgb = frame[:, :, 1:4]
                    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
                else:
                    bgr = frame
                _, jpeg = cv2.imencode(".jpg", bgr,
                                       [cv2.IMWRITE_JPEG_QUALITY, 40])
                return jpeg.tobytes()
            elif self._camera_type == "opencv":
                ret, frame = self._camera.read()
                if ret:
                    _, jpeg = cv2.imencode(".jpg", frame,
                                           [cv2.IMWRITE_JPEG_QUALITY, 40])
                    return jpeg.tobytes()
        except Exception as e:
            logger.warning(f"帧捕获异常: {e}")
        return None