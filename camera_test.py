#!/usr/bin/env python3
import time
import cv2
import os
from datetime import datetime

# 依赖检查与自动提示
def check_dependencies():
    print("=" * 60)
    print("  树莓派5 摄像头全能测试工具")
    print("=" * 60)
    
    dependencies_ok = True
    
    # 检查picamera2（CSI摄像头必备）
    try:
        from picamera2 import Picamera2
        print("[OK] picamera2 库已安装 (CSI摄像头支持)")
    except ImportError:
        print("[WARN] picamera2 库未安装")
        print("     安装命令: sudo apt install python3-picamera2")
        dependencies_ok = False
    
    # 检查OpenCV（USB摄像头必备）
    try:
        import cv2
        print(f"[OK] OpenCV 库已安装 (USB摄像头支持) 版本: {cv2.__version__}")
    except ImportError:
        print("[WARN] OpenCV 库未安装")
        print("     安装命令: pip3 install opencv-python-headless")
        dependencies_ok = False
    
    if not dependencies_ok:
        print("\n[提示] 请先安装缺少的依赖，然后重新运行脚本")
        exit(1)
    
    print("\n[提示] 按 Q 键退出预览，按 S 键保存截图")
    print("=" * 60 + "\n")

# CSI摄像头测试（使用官方picamera2，性能最优）
def test_csi_camera(resolution=(640, 480), fps=30):
    from picamera2 import Picamera2
    
    print("🔍 正在检测CSI摄像头...")
    try:
        picam2 = Picamera2()
        cameras = picam2.global_camera_info()
        
        if not cameras:
            print("[--] 未检测到CSI摄像头")
            picam2.close()
            return False
        
        print(f"[OK] 检测到 {len(cameras)} 个CSI摄像头")
        for i, cam in enumerate(cameras):
            print(f"     摄像头 {i}: {cam['Model']}")
        
        # 配置摄像头
        config = picam2.create_preview_configuration(
            main={"format": "XRGB8888", "size": resolution}
        )
        picam2.configure(config)
        picam2.start()
        time.sleep(0.5)  # 等待摄像头预热
        
        print(f"\n[开始] CSI摄像头测试 分辨率:{resolution[0]}x{resolution[1]} @ {fps}fps")
        return run_preview_loop(
            capture_func=lambda: picam2.capture_array(),
            camera_type="CSI",
            resolution=resolution
        )
        
    except Exception as e:
        print(f"[ERR] CSI摄像头测试失败: {e}")
        if "Permission denied" in str(e):
            print("     解决方法: sudo usermod -aG video $USER (执行后重新登录)")
        return False
    finally:
        try:
            picam2.stop()
            picam2.close()
        except:
            pass

# USB摄像头测试（使用OpenCV）
def test_usb_camera(device_index=0, resolution=(640, 480), fps=30):
    print(f"\n🔍 正在检测USB摄像头 (设备索引: {device_index})...")
    
    # 尝试不同后端
    backends = [
        (cv2.CAP_V4L2, "V4L2"),
        (cv2.CAP_ANY, "自动检测")
    ]
    
    for backend_id, backend_name in backends:
        try:
            cap = cv2.VideoCapture(device_index, backend_id)
            if cap.isOpened():
                print(f"[OK] USB摄像头已打开 (后端: {backend_name})")
                break
        except:
            continue
    else:
        print("[--] 未检测到可用的USB摄像头")
        return False
    
    # 设置分辨率和帧率
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, resolution[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, resolution[1])
    cap.set(cv2.CAP_PROP_FPS, fps)
    
    # 获取实际参数
    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = cap.get(cv2.CAP_PROP_FPS)
    
    print(f"[信息] 实际参数: {actual_w}x{actual_h} @ {actual_fps:.1f}fps")
    
    try:
        return run_preview_loop(
            capture_func=lambda: cap.read(),
            camera_type="USB",
            resolution=(actual_w, actual_h)
        )
    finally:
        cap.release()

# 通用预览循环（帧率计算+截图+退出控制）
def run_preview_loop(capture_func, camera_type, resolution):
    frame_count = 0
    start_time = time.time()
    cv2.namedWindow(f"{camera_type}摄像头预览", cv2.WINDOW_NORMAL)
    cv2.resizeWindow(f"{camera_type}摄像头预览", resolution[0], resolution[1])
    
    print("\n[预览中] 按 Q 退出 | 按 S 保存截图")
    
    while True:
        # 捕获帧
        if camera_type == "CSI":
            frame = capture_func()
            ret = True
        else:  # USB
            ret, frame = capture_func()
        
        if not ret or frame is None:
            print("[ERR] 无法读取帧")
            break
        
        # 计算帧率
        frame_count += 1
        elapsed = time.time() - start_time
        if elapsed > 1:
            current_fps = frame_count / elapsed
            # 在画面上显示信息
            cv2.putText(frame, f"FPS: {current_fps:.1f}", (10, 30), 
                       cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
            cv2.putText(frame, f"Res: {resolution[0]}x{resolution[1]}", (10, 70), 
                       cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        
        # 显示画面
        cv2.imshow(f"{camera_type}摄像头预览", frame)
        
        # 按键处理
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            print("\n[退出] 用户终止测试")
            break
        elif key == ord('s'):
            # 保存截图
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{camera_type}_camera_{timestamp}.jpg"
            cv2.imwrite(filename, frame)
            file_size = os.path.getsize(filename) / 1024
            print(f"[截图] 已保存: {filename} ({file_size:.1f} KB)")
    
    # 计算平均帧率
    total_time = time.time() - start_time
    avg_fps = frame_count / total_time if total_time > 0 else 0
    print(f"\n[测试完成] 总帧数: {frame_count} | 平均帧率: {avg_fps:.1f}fps")
    
    cv2.destroyAllWindows()
    return True

# 主函数
def main():
    check_dependencies()
    
    # 先测试CSI摄像头（树莓派优先）
    csi_success = test_csi_camera(resolution=(640, 480), fps=30)
    
    # 如果CSI失败，自动测试USB摄像头
    if not csi_success:
        print("\n" + "-" * 60)
        usb_success = test_usb_camera(device_index=0, resolution=(640, 480), fps=30)
        
        # 尝试第二个USB摄像头
        if not usb_success:
            test_usb_camera(device_index=1, resolution=(640, 480), fps=30)
    
    print("\n" + "=" * 60)
    print("  测试结束")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n[退出] 用户中断")
        cv2.destroyAllWindows()