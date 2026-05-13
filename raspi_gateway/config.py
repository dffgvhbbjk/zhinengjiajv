"""
树莓派网关配置 — 端口、串口参数、设备注册表
"""

# ---- 网络端口 ----
UDP_PORT = 8888          # 设备发现 + 传感器广播
TCP_PORT = 9999          # 控制命令
VIDEO_PORT = 9998        # 摄像头视频流

# ---- 串口参数 ----
SERIAL_PORT = "/dev/ttyAMA0"      # 控制 UART（发控制帧 + 收控制响应）
SENSOR_SERIAL_PORT = "/dev/ttyAMA3"  # 传感器 UART（只收传感器帧）
SERIAL_BAUDRATE = 9600
SERIAL_TIMEOUT = 0.1

# ---- 心跳与超时 ----
DISCOVERY_INTERVAL = 20   # UDP 设备发现广播间隔（秒）
HEARTBEAT_TIMEOUT = 45    # 心跳超时（秒），比 Qt 端(30s)宽松

# ---- 网关身份 ----
GATEWAY_ID = "raspi_gateway_01"
GATEWAY_NAME = "客厅网关"
GATEWAY_TYPE = "gateway"
FIRMWARE_VERSION = "1.0.0"

# ---- device_id → 串口帧参数映射 ----
# zone:  0x01=Zone1, 0x02=Zone2
# dev_type: 设备类型码
# dev_index: 设备编号
# dual_frame: 全屋总控需要发送两条帧（Zone1 + Zone2）

DEVICE_REGISTRY = {
    # ---- 门 (Zone=0x01, DevType=0x24) ----
    "door_01": {"zone": 0x01, "dev_type": 0x24, "dev_index": 0x01, "name": "1号门", "category": "door"},
    "door_02": {"zone": 0x01, "dev_type": 0x24, "dev_index": 0x02, "name": "2号门", "category": "door"},
    "door_03": {"zone": 0x01, "dev_type": 0x24, "dev_index": 0x03, "name": "3号门", "category": "door"},

    # ---- 风扇 (Zone=0x01, DevType=0x22) ----
    "fan_01": {"zone": 0x01, "dev_type": 0x22, "dev_index": 0x01, "name": "风扇", "category": "fan"},

    # ---- 加湿器 (Zone=0x01, DevType=0x36) ----
    "humidifier_01": {"zone": 0x01, "dev_type": 0x36, "dev_index": 0x00, "name": "加湿器", "category": "humidifier"},

    # ---- 蜂鸣器 (Zone=0x01, DevType=0x37) ----
    "buzzer_01": {"zone": 0x01, "dev_type": 0x37, "dev_index": 0x00, "name": "蜂鸣器", "category": "buzzer"},

    # ---- 灯光 (Zone=0x02, DevType=0x00) ----
    "light_all":      {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x10, "name": "全屋灯", "category": "light"},
    "light_entry":    {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x11, "name": "入户灯", "category": "light"},
    "light_living":   {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x12, "name": "客厅灯", "category": "light"},
    "light_kitchen":  {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x13, "name": "厨房灯", "category": "light"},
    "light_bathroom": {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x14, "name": "卫浴灯", "category": "light"},
    "light_bedroom":  {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x15, "name": "卧室灯", "category": "light"},
    "light_piano":    {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x16, "name": "钢琴室灯", "category": "light"},

    # ---- 全屋总控（发送两条帧：Zone1 + Zone2） ----
    "master_switch": {
        "zone": 0x01, "dev_type": 0x11, "dev_index": 0x11,
        "zone2": 0x02, "dev_type2": 0x22, "dev_index2": 0x11,
        "name": "全屋总控", "category": "master_switch", "dual_frame": True,
    },
}

# ---- 传感器类型码 → JSON 字段名 ----
SENSOR_TYPE_MAP = {
    0x30: "air_quality",
    0x31: "smoke",
    0x32: "lpg",
    0x33: "rain",
    0x34: "light",
    0x14: "pressure",
    0x15: "temperature",
    0x16: "humidity",
}

# 需 ÷1000 的传感器类型码
SENSOR_DIVIDE_BY_1000 = {0x30, 0x31, 0x32, 0x14, 0x15, 0x16}

# 无需 ÷1000（直接取值）的类型码
SENSOR_DIRECT = {0x33, 0x34}

# 传感器字段 → 虚拟设备ID映射（用于sensor_update的device_id）
SENSOR_DEVICE_MAP = {
    "temperature": "sensor_temp_hum",
    "humidity": "sensor_temp_hum",
    "light": "sensor_light_rain",
    "rain": "sensor_light_rain",
    "smoke": "sensor_gas",
    "lpg": "sensor_gas",
    "air_quality": "sensor_air",
    "pressure": "sensor_pressure",
}
