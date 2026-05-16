"""
摄像头 OpenCV 诊断脚本 — 独立测试，不依赖网关其他模块
用法: python test_camera_opencv.py
"""

import time
import os
import glob
import sys

try:
    import cv2
    import numpy as np
    print("[OK] OpenCV + numpy 已安装")
    print(f"     OpenCV 版本: {cv2.__version__}")
except ImportError as e:
    print(f"[FAIL] 缺少依赖: {e}")
    print("     安装: pip install opencv-python-headless numpy")
    sys.exit(1)


def check_video_devices():
    """列出系统上的 /dev/video* 设备"""
    print("\n" + "=" * 60)
    print(" 系统摄像头设备")
    print("=" * 60)

    devices = sorted(glob.glob("/dev/video*"))
    if not devices:
        print(" [WARN] 未找到任何 /dev/video* 设备")
        return

    for d in devices:
        try:
            cap = cv2.VideoCapture(d)
            if cap.isOpened():
                w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
                h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
                fps = cap.get(cv2.CAP_PROP_FPS)
                backend = cap.getBackendName()
                print(f" [OK] {d}: {int(w)}x{int(h)} @ {fps:.1f}fps (backend={backend})")
                cap.release()
            else:
                print(f" [--] {d}: 存在但 OpenCV 无法打开")
                cap.release()
        except Exception as e:
            print(f" [ERR] {d}: {e}")

    if not devices:
        print(" (无 /dev/video* 设备 — 可能是 CSI 摄像头，OpenCV 无法直接访问)")


def try_opencv_camera():
    """尝试用 OpenCV 打开摄像头，支持多索引 + 多后端"""
    print("\n" + "=" * 60)
    print(" OpenCV 摄像头探测")
    print("=" * 60)

    backends = [
        (cv2.CAP_V4L2, "V4L2"),
        (cv2.CAP_ANY, "CAP_ANY"),
        (cv2.CAP_DSHOW, "DSHOW"),
    ]
    if hasattr(cv2, "CAP_GSTREAMER"):
        backends.append((cv2.CAP_GSTREAMER, "GSTREAMER"))

    indices = [0, 1, 2]
    resolutions = [(640, 360), (640, 480), (320, 240)]

    for idx in indices:
        for backend_id, backend_name in backends:
            try:
                cap = cv2.VideoCapture(idx, backend_id)
            except Exception as e:
                print(f"  idx={idx} backend={backend_name}: 构造失败 ({e})")
                continue

            if not cap.isOpened():
                cap.release()
                continue

            actual_backend = cap.getBackendName()
            for w, h in resolutions:
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)

                for attempt in range(5):
                    ret, frame = cap.read()
                    if ret and frame is not None and frame.size > 0:
                        actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                        actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                        shape = frame.shape
                        print(f" [OK] idx={idx} backend={backend_name}"
                              f"({actual_backend}) res={actual_w}x{actual_h}"
                              f" shape={shape}")

                        save_test_image(frame, idx, actual_w, actual_h)
                        cap.release()
                        return True
                    time.sleep(0.1)

            print(f" [--] idx={idx} backend={backend_name}: 能打开但读不到帧")
            cap.release()

    return False


def save_test_image(frame, idx, w, h):
    """保存测试帧到文件"""
    filename = f"test_camera_{idx}_{w}x{h}.jpg"
    cv2.imwrite(filename, frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
    size_kb = os.path.getsize(filename) / 1024
    print(f"     测试截图已保存: {filename} ({size_kb:.1f} KB)")


def check_v4l2_info():
    """用 v4l2-ctl 获取摄像头信息"""
    print("\n" + "=" * 60)
    print(" V4L2 设备信息")
    print("=" * 60)

    import subprocess
    try:
        result = subprocess.run(
            ["v4l2-ctl", "--list-devices"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            print(result.stdout)
        else:
            print(" (无输出)")
    except FileNotFoundError:
        print(" [WARN] v4l2-ctl 未安装，跳过 (sudo apt install v4l-utils)")
    except Exception as e:
        print(f" [ERR] v4l2-ctl 执行失败: {e}")


def check_libcamera():
    """用 libcamera-hello 检测 CSI 摄像头"""
    print("\n" + "=" * 60)
    print(" libcamera / CSI 摄像头检测")
    print("=" * 60)

    import subprocess
    try:
        result = subprocess.run(
            ["libcamera-hello", "--list-cameras"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            print(result.stdout)
        else:
            print(" (无输出)")
    except FileNotFoundError:
        print(" [WARN] libcamera-hello 未安装，跳过")
    except Exception as e:
        print(f" [ERR] libcamera-hello 执行失败: {e}")


def main():
    print("=" * 60)
    print(" 摄像头 OpenCV 诊断工具")
    print("=" * 60)

    check_v4l2_info()
    check_libcamera()
    check_video_devices()

    success = try_opencv_camera()

    print("\n" + "=" * 60)
    if success:
        print(" 诊断结果: 摄像头已成功打开并捕获帧")
    else:
        print(" 诊断结果: 摄像头未能打开")
        print()
        print(" 可能原因:")
        print("   1. CSI 摄像头 (Pi Camera) — OpenCV 无法直接访问")
        print("      → 需用 Picamera2/libcamera，而非 OpenCV VideoCapture")
        print("   2. USB 摄像头未插好或驱动未加载")
        print("      → 检查: ls /dev/video*")
        print("   3. 摄像头被其他进程占用")
        print("      → 检查: sudo fuser /dev/video0")
        print("   4. 权限不足")
        print("      → 检查: groups (确保在 video 组中)")
    print("=" * 60)


if __name__ == "__main__":
    main()