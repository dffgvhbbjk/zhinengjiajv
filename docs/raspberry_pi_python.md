# 树莓派端 Python 脚本逻辑文档

## 一、整体架构

```
        ┌─────────────┐          ┌──────────────────┐
        │  QT6 客户端  │ ──TCP── │   树莓派网关      │
        │ (C++/QML)   │          │  (Python脚本)     │
        └─────────────┘          │                  │
                │                │  ┌── 摄像头(USB/CSI)
                │ (UDP发现)      │  └── 串口(/dev/ttyAMA0) ── STM32
                │                │                           │
                └────────────────┘                  ┌────────┴────────┐
                                                    │ 传感器/继电器    │
                                                    │ 门/风扇/加湿器等 │
                                                    └─────────────────┘
```

树莓派作为**网关 Hub**，负责：
1. UDP 广播自身存在（设备发现）
2. TCP 服务器接收 QT 客户端命令，转发到串口 STM32
3. 串口读取 STM32 上报的传感器数据，UDP 广播给 QT 客户端
4. 摄像头视频流推送到 QT 客户端

> **关键变更**：树莓派不外接任何 GPIO/I2C/SPI 设备，所有传感器和执行器都挂在 STM32 下面，树莓派仅通过串口与 STM32 通信。

---

## 二、通信协议总览

| 物理层 | 端口/接口 | 方向 | 数据格式 | 用途 |
|--------|----------|------|---------|------|
| UDP    | 8888     | 双向 | JSON | 设备发现、传感器数据上报 |
| TCP    | 9999     | 双向 | JSON | 控制命令、场景执行、语音文本 |
| TCP    | 9998     | 树莓派→QT | 二进制 | 摄像头视频流 |
| UART   | /dev/ttyAMA0 | 双向 | 6字节定长帧 | STM32 控制指令、传感器回传 |

---

## 三、JSON 数据包格式规范

> **重要**：所有 JSON 包的 `{` 和 `}` 边界检测由 QT 端 `findJsonBoundary()` 实现（括号计数法），TCP 流中连续 JSON 间**无需 `\n` 分隔**，但允许存在换行符。

### 3.1 UDP 协议（端口 8888）

#### 3.1.1 设备发现 — 树莓派定期广播自身

```json
{
    "type": "device_discovery",
    "device_id": "raspi_gateway_01",
    "device_name": "客厅网关",
    "device_type": "gateway",
    "tcp_port": 9999,
    "firmware_version": "1.0.0",
    "checksum": "md5_of_above_fields"
}
```

- **发送频率**：每 20 秒广播一次（QT 端超时阈值 30s）
- **checksum 算法**：移除 `checksum` 字段后的 JSON Compact 字符串的 MD5

#### 3.1.2 传感器数据上报 — 树莓派主动推送

```json
{
    "type": "sensor_data",
    "device_id": "raspi_gateway_01",
    "temperature": 25.5,
    "humidity": 60.2,
    "light": 320.0,
    "rain": 0.0,
    "smoke": 0.01,
    "lpg": 0.02,
    "air_quality": 85.0,
    "pressure": 1013.25,
    "checksum": "md5_of_above_fields"
}
```

- **发送时机**：串口收到 STM32 传感器帧后立即组装并广播
- **频率**：取决于 STM32 上报频率（通常 1~5 秒）

#### 3.1.3 数据刷新请求 — QT 客户端主动请求

```json
{
    "type": "data_refresh_request",
    "timestamp": 1712345678123
}
```

- 树莓派收到后应立即响应最新的 `sensor_data`。

---

### 3.2 TCP 协议（端口 9999）

#### 3.2.1 握手 — 连接确认

**树莓派主动发送（客户端连接后）**：

```json
{
    "type": "hello",
    "commandId": "hello",
    "timestamp": 1712345678123
}
```

**QT 客户端回复**：

```json
{
    "type": "hello",
    "commandId": "hello",
    "timestamp": 1712345678123
}
```

**树莓派 hello 响应**（带摄像头信息）：

```json
{
    "type": "command_response",
    "commandId": "hello",
    "status": "success",
    "message": "connected",
    "camera": true,
    "videoPort": 9998
}
```

#### 3.2.2 心跳

**QT 客户端每 30 秒发送**：

```json
{
    "type": "heartbeat",
    "timestamp": 1712345678123
}
```

**树莓派回应**：

```json
{
    "type": "heartbeat_ack",
    "timestamp": 1712345678123
}
```

#### 3.2.3 设备控制命令

**QT 客户端发送**：

```json
{
    "type": "control",
    "commandId": "voice_1712345678123_0",
    "device": "door_01",
    "action": "turn_on",
    "timestamp": 1712345678123,
    "retryCount": 0,
    "priority": 1
}
```

| 字段 | 值示例 | 说明 |
|------|--------|------|
| `type` | `"control"` | 固定值 |
| `commandId` | `"voice_1712345678123_0"` | 唯一命令ID |
| `device` | `"door_01"` | device_id，**必须与设备发现包一致** |
| `action` | `"turn_on"` / `"turn_off"` | 动作 |
| `priority` | 0=高 1=中 2=低 | 告警=0，控制=1，场景=2 |

**树莓派回应（必须）**：

```json
{
    "type": "command_response",
    "commandId": "voice_1712345678123_0",
    "status": "success",
    "message": "ok"
}
```

失败时 `status` 填 `"failed"`，QT 端会自动重试 3 次。

#### 3.2.4 场景执行命令

```json
{
    "type": "scene",
    "commandId": "voice_1712345678123",
    "sceneId": "scene_001",
    "sceneName": "回家模式",
    "triggerType": "manual",
    "triggerDeviceId": "",
    "triggerSensorData": "",
    "triggerTime": "",
    "actions": "turn_on,turn_on,turn_off",
    "actionDevices": "[\"light_01\",\"ac_01\",\"curtain_01\"]",
    "timestamp": 1712345678123,
    "retryCount": 0,
    "priority": 2
}
```

| 字段 | 说明 |
|------|------|
| `actions` | 逗号分隔的动作序列，与 `actionDevices` 一一对应 |
| `actionDevices` | JSON 数组字符串的 device_id 列表 |

树莓派应**按序**将每个 action 翻译成串口帧发送给 STM32。

#### 3.2.5 语音文本转发

```json
{
    "type": "voice_text",
    "text": "打开客厅灯",
    "is_command": true,
    "timestamp": 1712345678123
}
```

- `is_command: true` 表示该文本触发了指令（网关可做 TTS 播报）
- `is_command: false` 表示只是对话文本
- 此消息**无需 ACK**

#### 3.2.6 告警推送（树莓派→QT）

```json
{
    "type": "alert",
    "alertId": "alert_1712345678123",
    "deviceId": "smoke_sensor_01",
    "content": "烟雾浓度超标",
    "level": 3
}
```

| level | 含义 |
|-------|------|
| 0 | 信息 |
| 1 | 警告 |
| 2 | 严重 |
| 3 | 紧急 |

#### 3.2.7 固件 OTA（可选）

树莓派只需要**透传**以下消息类型：
- `"firmware_init"` — OTA 初始化
- `"firmware_chunk"` — OTA 数据块（base64）
- `"firmware_ack"` — 回复固件块状态

---

## 四、串口协议（与 STM32 通信）

### 4.1 串口参数

```
端口:     /dev/ttyAMA0（树莓派硬件 UART）
波特率:   9600
数据位:   8
停止位:   1
校验位:   无
流控:     无
```

### 4.2 帧格式

**固定 6 字节定长帧**，无需转义处理：

```
┌────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│  Byte 0│  Byte 1  │  Byte 2  │  Byte 3  │  Byte 4  │  Byte 5  │
│  0xFF  │   Zone   │ DevType  │ DevIndex │  Value   │  0xFE    │
│  帧头   │  区域组  │ 设备类型  │ 设备编号  │  开关值   │  帧尾    │
└────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
```

| 字节 | 名称 | 说明 |
|------|------|------|
| Byte 0 | 帧头 | 固定 `0xFF` |
| Byte 1 | Zone | `0x01` = Zone1（门/风扇/加湿器/蜂鸣器/总控），`0x02` = Zone2（灯光/总控） |
| Byte 2 | DevType | 设备类型码（见命令表） |
| Byte 3 | DevIndex | 设备编号或子参数 |
| Byte 4 | Value | `0x01` = 开/正转，`0x00` = 关/停，风扇 1~3 档 |
| Byte 5 | 帧尾 | 固定 `0xFE` |

### 4.3 控制命令表（QT6 → 树莓派 → STM32）

#### 4.3.1 门控（Zone=0x01, DevType=0x24）

| 命令帧 | 说明 |
|--------|------|
| `FF 01 24 01 01 FE` | 1号门 开 |
| `FF 01 24 01 00 FE` | 1号门 关 |
| `FF 01 24 02 01 FE` | 2号门 开 |
| `FF 01 24 02 00 FE` | 2号门 关 |
| `FF 01 24 03 01 FE` | 3号门 开 |
| `FF 01 24 03 00 FE` | 3号门 关 |

#### 4.3.2 风扇（Zone=0x01, DevType=0x22）

| 命令帧 | 说明 |
|--------|------|
| `FF 01 22 01 01 FE` | 风扇 正转 1档风速 |
| `FF 01 22 01 02 FE` | 风扇 正转 2档风速 |
| `FF 01 22 01 03 FE` | 风扇 正转 3档风速 |
| `FF 01 22 00 00 FE` | 风扇 关闭 |

#### 4.3.3 加湿器（Zone=0x01, DevType=0x36）

| 命令帧 | 说明 |
|--------|------|
| `FF 01 36 00 01 FE` | 加湿器 开启 |
| `FF 01 36 00 00 FE` | 加湿器 关闭 |

#### 4.3.4 蜂鸣器（Zone=0x01, DevType=0x37）

| 命令帧 | 说明 |
|--------|------|
| `FF 01 37 00 01 FE` | 蜂鸣器 开启 |
| `FF 01 37 00 00 FE` | 蜂鸣器 关闭 |

#### 4.3.5 全屋总控开关（Zone=0x01/0x02, DevType=0x11/0x22）

| 命令帧 | 说明 |
|--------|------|
| `FF 01 11 11 11 FE` + `FF 02 22 11 11 FE` | 全屋总控 开（两条帧） |
| `FF 01 11 00 00 FE` + `FF 02 22 00 00 FE` | 全屋总控 关（两条帧） |

#### 4.3.6 灯光（Zone=0x02, DevType=0x00）

| 命令帧 | DevIndex | 说明 |
|--------|----------|------|
| `FF 02 00 10 01 FE` | `0x10` | 全屋灯 开 |
| `FF 02 00 10 00 FE` | `0x10` | 全屋灯 关 |
| `FF 02 00 11 01 FE` | `0x11` | 入户灯 开 |
| `FF 02 00 11 00 FE` | `0x11` | 入户灯 关 |
| `FF 02 00 12 01 FE` | `0x12` | 客厅灯 开 |
| `FF 02 00 12 00 FE` | `0x12` | 客厅灯 关 |
| `FF 02 00 13 01 FE` | `0x13` | 厨房灯 开 |
| `FF 02 00 13 00 FE` | `0x13` | 厨房灯 关 |
| `FF 02 00 14 01 FE` | `0x14` | 卫浴灯 开 |
| `FF 02 00 14 00 FE` | `0x14` | 卫浴灯 关 |
| `FF 02 00 15 01 FE` | `0x15` | 卧室灯 开 |
| `FF 02 00 15 00 FE` | `0x15` | 卧室灯 关 |
| `FF 02 00 16 01 FE` | `0x16` | 钢琴室灯 开 |
| `FF 02 00 16 00 FE` | `0x16` | 钢琴室灯 关 |

### 4.4 传感器数据帧（STM32 → 串口 → 树莓派）

传感器帧同样是 **FF 开头、FE 结尾** 的 6 字节定长帧，但结构与控制帧不同：

```
┌────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│  Byte 0│  Byte 1  │  Byte 2  │  Byte 3  │  Byte 4  │  Byte 5  │
│  0xFF  │ 类型码   │  数据1   │  数据2   │  数据3   │  0xFE    │
│  帧头   │SenType   │  Data1   │  Data2   │  Data3   │  帧尾    │
└────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
```

| 字节 | 名称 | 说明 |
|------|------|------|
| Byte 0 | 帧头 | 固定 `0xFF` |
| Byte 1 | SenType | 传感器类型码 |
| Byte 2 | Data1 | 数据高位/百位 |
| Byte 3 | Data2 | 数据中位/十位 |
| Byte 4 | Data3 | 数据低位/个位 |
| Byte 5 | 帧尾 | 固定 `0xFE` |

#### 4.4.1 传感器类型码

| 类型码 | 传感器 | JSON 字段 |
|--------|--------|-----------|
| `0x30` | 空气质量 | `air_quality` |
| `0x31` | 烟雾 | `smoke` |
| `0x32` | 液化气 | `lpg` |
| `0x33` | 雨滴 | `rain` |
| `0x34` | 光敏 | `light` |
| `0x14` | 气压 | `pressure` |
| `0x15` | 温度 | `temperature` |
| `0x16` | 湿度 | `humidity` |

#### 4.4.2 通用数据拼接规则

**核心注意**：不是将十六进制数整体转十进制，而是**逐字节转十进制后数字拼接**。

1. 提取 3 字节有效数据段：`Data1`、`Data2`、`Data3`
2. 分别将每个十六进制字节**单独**转为十进制数值（如 `0x00→0`、`0x2D→45`、`0x24→36`）
3. 将 3 个十进制数值按 `Data1→Data2→Data3` 顺序**拼接**成完整十进制整数（前导 0 可省略）

**示例**：
- 数据 `00 2D 24` → 单字节转十进制 `0, 45, 36` → 拼接为 `04536 = 4536`
- 数据 `02 2D 24` → 单字节转十进制 `2, 45, 36` → 拼接为 `24536`

#### 4.4.3 分类型最终换算规则

**规则 1 — 除以 1000**（类型码 `0x30`/`0x31`/`0x32`）：

| 传感器 | 类型码 | 公式 |
|--------|--------|------|
| 空气质量 | `0x30` | `拼接值 ÷ 1000` |
| 烟雾 | `0x31` | `拼接值 ÷ 1000` |
| 液化气 | `0x32` | `拼接值 ÷ 1000` |

示例：帧 `FF 30 00 2D 24 FE`
→ 拼接值 4536 → `4536 ÷ 1000 = 4.536`

**规则 2 — 直接取值**（类型码 `0x33`/`0x34`）：

| 传感器 | 类型码 | 公式 |
|--------|--------|------|
| 雨滴 | `0x33` | `拼接值`（无需除法） |
| 光敏 | `0x34` | `拼接值`（无需除法） |

示例：帧 `FF 33 00 2D 24 FE`
→ 拼接值 4536 → 最终值 `4536`

**规则 3 — 气压/温度/湿度**（类型码 `0x14`/`0x15`/`0x16`）：

> 换算规则待 STM32 固件确认，暂按规则 1（÷1000）处理，如有差异后续调整。

#### 4.4.4 帧类型区分

控制帧与传感器帧通过 **Byte 1** 区分：

| Byte 1 取值范围 | 帧类型 | 方向 |
|-----------------|--------|------|
| `0x01` / `0x02` | 控制帧 | 树莓派 → STM32 |
| `0x14`~`0x16` / `0x30`~`0x34` | 传感器帧 | STM32 → 树莓派 |

### 4.5 串口收发逻辑

```
串口接收（STM32 → 树莓派）:
  ① 逐字节读取串口缓冲区
  ② 检测到 0xFF 帧头 → 开始缓存后续字节
  ③ 检测到 0xFE 帧尾 → 验证帧长=6 → 解析帧内容
  ④ 根据 Byte 1 区分帧类型：
     - Byte1 ∈ {0x14~0x16, 0x30~0x34} → 传感器帧
       → 提取 Data1/Data2/Data3 → 拼接+换算 → 组装 sensor_data JSON → UDP 广播
     - Byte1 ∈ {0x01, 0x02} → 控制响应帧
       → 组装 command_response JSON → TCP 回复 QT

串口发送（树莓派 → STM32）:
  ① TCP 收到 control/scene JSON 命令
  ② 查 device_id → 帧参数映射表
  ③ 拼装 6 字节帧: [0xFF, zone, devType, devIndex, value, 0xFE]
  ④ 写入串口
  ⑤ 等待 STM32 响应 → 组装 command_response JSON → TCP 回复 QT
```

---

## 五、设备注册表（device_id → 串口帧映射）

`config.py` 中的设备注册表，将 QT6 客户端使用的 `device_id` 映射为串口帧参数：

```python
# config.py
# device_id → (zone, dev_type, dev_index)

DEVICE_REGISTRY = {
    # ---- 门 ----
    "door_01":      {"zone": 0x01, "dev_type": 0x24, "dev_index": 0x01, "name": "1号门"},
    "door_02":      {"zone": 0x01, "dev_type": 0x24, "dev_index": 0x02, "name": "2号门"},
    "door_03":      {"zone": 0x01, "dev_type": 0x24, "dev_index": 0x03, "name": "3号门"},

    # ---- 风扇 ----
    "fan_01":       {"zone": 0x01, "dev_type": 0x22, "dev_index": 0x01, "name": "风扇"},

    # ---- 加湿器 ----
    "humidifier_01": {"zone": 0x01, "dev_type": 0x36, "dev_index": 0x00, "name": "加湿器"},

    # ---- 蜂鸣器 ----
    "buzzer_01":    {"zone": 0x01, "dev_type": 0x37, "dev_index": 0x00, "name": "蜂鸣器"},

    # ---- 灯光 ----
    "light_all":        {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x10, "name": "全屋灯"},
    "light_entry":      {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x11, "name": "入户灯"},
    "light_living":     {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x12, "name": "客厅灯"},
    "light_kitchen":    {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x13, "name": "厨房灯"},
    "light_bathroom":   {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x14, "name": "卫浴灯"},
    "light_bedroom":    {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x15, "name": "卧室灯"},
    "light_piano":      {"zone": 0x02, "dev_type": 0x00, "dev_index": 0x16, "name": "钢琴室灯"},

    # ---- 全屋总控（特殊：发送两条帧） ----
    "master_switch":    {"zone": 0x01, "dev_type": 0x11, "dev_index": 0x11,
                         "zone2": 0x02, "dev_type2": 0x22, "dev_index2": 0x11,
                         "name": "全屋总控", "dual_frame": True},
}
```

---

## 六、Python 脚本模块结构

```
raspi_gateway/
├── main.py                   # 主入口
├── config.py                 # 配置（端口/设备注册表/串口参数）
├── network/
│   ├── udp_broadcaster.py    # UDP 设备发现 + 传感器广播
│   ├── tcp_server.py         # TCP 命令接收 + 响应
│   └── video_streamer.py     # 摄像头 JPEG 推流
├── serial/
│   ├── serial_manager.py     # 单串口管理（/dev/ttyAMA0）
│   ├── serial_parser.py      # FF/FE 帧解析器
│   └── serial_dispatcher.py  # JSON→串口帧指令分发
├── protocol/
│   ├── json_packets.py       # JSON 包构建/解析
│   └── checksum.py           # MD5 checksum
└── logs/
    └── logger.py
```

> 与旧版相比：删除 `sensors/`（无直连传感器）、`devices/`（无 GPIO 继电器），
> `serial/` 目录简化为单串口管理。

---

## 七、关键 Python 类设计

### 7.1 JsonPacketBuilder — JSON 包构建

```python
import json, time, hashlib

def build_discovery_packet(device_id, name, dtype, tcp_port=9999, fw="1.0"):
    pkt = {
        "type": "device_discovery",
        "device_id": device_id,
        "device_name": name,
        "device_type": dtype,
        "tcp_port": tcp_port,
        "firmware_version": fw
    }
    raw = json.dumps(pkt, separators=(',', ':'), ensure_ascii=False)
    pkt["checksum"] = hashlib.md5(raw.encode()).hexdigest()
    return json.dumps(pkt, separators=(',', ':'), ensure_ascii=False)

def build_sensor_packet(device_id, temp, humi, light, rain, smoke, lpg, air_qual, pressure=0.0):
    pkt = {
        "type": "sensor_data",
        "device_id": device_id,
        "temperature": temp,
        "humidity": humi,
        "light": light,
        "rain": rain,
        "smoke": smoke,
        "lpg": lpg,
        "air_quality": air_qual,
        "pressure": pressure
    }
    raw = json.dumps(pkt, separators=(',', ':'), ensure_ascii=False)
    pkt["checksum"] = hashlib.md5(raw.encode()).hexdigest()
    return json.dumps(pkt, separators=(',', ':'), ensure_ascii=False)

def build_cmd_response(command_id, success=True, msg="ok"):
    return json.dumps({
        "type": "command_response",
        "commandId": command_id,
        "status": "success" if success else "failed",
        "message": msg
    }, separators=(',', ':'), ensure_ascii=False)
```

### 7.2 SerialParser — FF/FE 帧解析器

```python
class SerialParser:
    """从字节流中提取 FF ... FE 定长帧，区分控制帧与传感器帧"""

    FRAME_HEAD = 0xFF
    FRAME_TAIL = 0xFE
    FRAME_LEN = 6

    # 传感器类型码
    SENSOR_TYPES = {
        0x30: "air_quality",
        0x31: "smoke",
        0x32: "lpg",
        0x33: "rain",
        0x34: "light",
        0x14: "pressure",
        0x15: "temperature",
        0x16: "humidity",
    }

    # 需除以 1000 的类型码
    DIVIDE_BY_1000 = {0x30, 0x31, 0x32}

    def __init__(self):
        self._buf = bytearray()

    def feed(self, data: bytes) -> list[bytes]:
        """喂入原始字节，返回解析出的完整帧列表"""
        self._buf.extend(data)
        frames = []

        while True:
            head_idx = self._buf.find(self.FRAME_HEAD)
            if head_idx < 0:
                self._buf.clear()
                break

            if head_idx > 0:
                del self._buf[:head_idx]

            if len(self._buf) < self.FRAME_LEN:
                break

            if self._buf[5] == self.FRAME_TAIL:
                frames.append(bytes(self._buf[:self.FRAME_LEN]))
                del self._buf[:self.FRAME_LEN]
            else:
                del self._buf[0]

        return frames

    @staticmethod
    def is_sensor_frame(frame: bytes) -> bool:
        """判断是否为传感器帧（Byte 1 在传感器类型码范围内）"""
        if len(frame) < 2:
            return False
        return frame[1] in SerialParser.SENSOR_TYPES

    @staticmethod
    def is_control_frame(frame: bytes) -> bool:
        """判断是否为控制帧（Byte 1 为 0x01 或 0x02）"""
        if len(frame) < 2:
            return False
        return frame[1] in (0x01, 0x02)

    @staticmethod
    def parse_control_frame(frame: bytes) -> dict:
        """解析控制帧（树莓派→STM32 或 STM32→树莓派响应）"""
        if len(frame) != 6 or frame[0] != 0xFF or frame[5] != 0xFE:
            raise ValueError("Invalid frame")
        return {
            "zone": frame[1],
            "dev_type": frame[2],
            "dev_index": frame[3],
            "value": frame[4],
        }

    @classmethod
    def parse_sensor_frame(cls, frame: bytes) -> dict:
        """
        解析传感器帧 → 计算最终测量值

        步骤：
        1. 提取 Data1/Data2/Data3（Byte 2/3/4）
        2. 逐字节转十进制后拼接
        3. 根据类型码选择换算规则
        """
        if len(frame) != 6 or frame[0] != 0xFF or frame[5] != 0xFE:
            raise ValueError("Invalid frame")

        sen_type = frame[1]
        field_name = cls.SENSOR_TYPES.get(sen_type)
        if field_name is None:
            raise ValueError(f"Unknown sensor type: 0x{sen_type:02X}")

        # 逐字节转十进制 → 直接拼接字符串 → 转整数
        # 例: 0x00→"0", 0x2D→"45", 0x24→"36" → "04536" → 4536
        combined = int(f"{frame[2]}{frame[3]}{frame[4]}")

        # 分类型换算
        if sen_type in cls.DIVIDE_BY_1000:
            value = combined / 1000.0
        else:
            value = float(combined)

        return {
            "field": field_name,
            "raw": combined,
            "value": value,
        }
```

### 7.3 SerialDispatcher — JSON→串口帧分发

```python
class SerialDispatcher:
    """将 JSON 控制命令翻译成 6 字节串口帧"""

    def __init__(self, device_registry):
        self.registry = device_registry

    def dispatch(self, json_cmd: dict) -> list[bytes]:
        """
        返回要发送的帧列表（全屋总控返回 2 帧，其余返回 1 帧）
        """
        dev_id = json_cmd["device"]
        action = json_cmd["action"]
        dev = self.registry.get(dev_id)
        if not dev:
            raise ValueError(f"Unknown device: {dev_id}")

        value = self._action_to_value(dev_id, action)
        frames = []

        if dev.get("dual_frame"):
            frames.append(bytes([0xFF, dev["zone"], dev["dev_type"],
                                 dev["dev_index"], value, 0xFE]))
            frames.append(bytes([0xFF, dev["zone2"], dev["dev_type2"],
                                 dev["dev_index2"], value, 0xFE]))
        else:
            frames.append(bytes([0xFF, dev["zone"], dev["dev_type"],
                                 dev["dev_index"], value, 0xFE]))
        return frames

    def _action_to_value(self, dev_id: str, action: str) -> int:
        """将 JSON action 转为帧的 value 字节"""
        # 风扇速度（需在 turn_on/off 之前判断，避免被提前 return）
        if dev_id.startswith("fan_"):
            speed_map = {"turn_on": 0x01, "speed_1": 0x01,
                         "speed_2": 0x02, "speed_3": 0x03,
                         "turn_off": 0x00}
            return speed_map.get(action, 0x00)

        if action == "turn_on":
            return 0x01
        elif action == "turn_off":
            return 0x00
        return 0x00
```

### 7.4 SerialManager — 单串口管理

```python
import serial
from queue import Queue

class SerialManager:
    """管理 /dev/ttyAMA0 单串口"""

    def __init__(self, port="/dev/ttyAMA0", baudrate=9600,
                 on_sensor_data=None, on_cmd_response=None):
        self.port_name = port
        self.baudrate = baudrate
        self.on_sensor_data = on_sensor_data    # 收到传感器数据的回调
        self.on_cmd_response = on_cmd_response  # 收到控制响应帧的回调
        self.ser = None
        self.parser = SerialParser()
        self._send_queue = Queue()
        self._running = False
        # 缓存传感器数据 {field_name: value}
        self._sensor_cache = {}

    def open(self):
        self.ser = serial.Serial(
            port=self.port_name,
            baudrate=self.baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.1
        )
        self._running = True

    def close(self):
        self._running = False
        if self.ser and self.ser.is_open:
            self.ser.close()

    def send_frame(self, frame: bytes):
        """发送一帧到 STM32"""
        self._send_queue.put(frame)

    def poll(self):
        """在主循环中调用，处理收发"""
        # 发送队列
        while not self._send_queue.empty():
            frame = self._send_queue.get_nowait()
            if self.ser and self.ser.is_open:
                self.ser.write(frame)

        # 接收
        if self.ser and self.ser.in_waiting > 0:
            data = self.ser.read(self.ser.in_waiting)
            frames = self.parser.feed(data)
            for frame in frames:
                self._handle_frame(frame)

    def _handle_frame(self, frame: bytes):
        """根据 Byte 1 区分传感器帧/控制帧"""
        if SerialParser.is_sensor_frame(frame):
            parsed = SerialParser.parse_sensor_frame(frame)
            # 更新传感器缓存
            self._sensor_cache[parsed["field"]] = parsed["value"]
            # 回调通知上层（可在此组装 sensor_data JSON 并 UDP 广播）
            if self.on_sensor_data:
                self.on_sensor_data(parsed["field"], parsed["value"],
                                    self._sensor_cache.copy())
        elif SerialParser.is_control_frame(frame):
            parsed = SerialParser.parse_control_frame(frame)
            if self.on_cmd_response:
                self.on_cmd_response(parsed)
        else:
            # 未知帧类型，忽略
            pass

    def get_sensor_cache(self) -> dict:
        """获取最新的全量传感器数据快照"""
        return dict(self._sensor_cache)
```

---

## 八、主循环流程 (main.py)

```python
import json
import time


# ---- 全局变量 ----
serial_mgr = None
dispatcher = None
udp = None
tcp = None
current_command_id = None  # 当前正在等待 STM32 响应的命令ID


def main():
    global serial_mgr, dispatcher, udp, tcp

    # 1. 加载设备注册表
    registry = load_device_registry()

    # 2. 初始化串口管理器（单串口 /dev/ttyAMA0, 9600）
    serial_mgr = SerialManager(
        port="/dev/ttyAMA0", baudrate=9600,
        on_sensor_data=handle_sensor_data,
        on_cmd_response=handle_cmd_response
    )
    serial_mgr.open()

    # 3. 初始化串口指令分发器
    dispatcher = SerialDispatcher(registry)

    # 4. 初始化 UDP 广播器（端口 8888）
    udp = UdpBroadcaster(port=8888)
    udp.start_discovery_broadcast(registry)

    # 5. 初始化 TCP 服务器（端口 9999）
    tcp = TcpServer(port=9999, on_command=handle_tcp_command)
    tcp.start()

    # 6. 初始化视频流（端口 9998）
    video = VideoStreamer(port=9998)
    video.start()

    # 7. 主循环
    while True:
        serial_mgr.poll()       # 串口收发
        tcp.process_queue()     # TCP 命令队列
        time.sleep(0.05)


# ============================================================
# TCP JSON 命令 → 串口帧 转换入口
# ============================================================

def handle_tcp_command(json_cmd: dict):
    """
    TCP 收到 JSON 命令，按 type 路由到不同处理器。
    返回 None 表示异步处理（等 STM32 响应后再回复），
    返回 dict 表示同步回复（如 data_refresh_request）。
    """
    global current_command_id

    msg_type = json_cmd.get("type", "")

    if msg_type == "control":
        return _handle_control(json_cmd)

    elif msg_type == "scene":
        return _handle_scene(json_cmd)

    elif msg_type == "data_refresh_request":
        return _handle_data_refresh()

    elif msg_type == "hello":
        return _handle_hello()

    elif msg_type == "heartbeat":
        return {"type": "heartbeat_ack", "timestamp": int(time.time() * 1000)}

    elif msg_type == "voice_text":
        # 语音文本无需 ACK，仅做 TTS 或日志
        return None

    else:
        return {"status": "failed", "message": f"Unknown type: {msg_type}"}


# ----------------------------------------------------------
# 控制命令: device + action → 串口帧
# ----------------------------------------------------------

def _handle_control(json_cmd: dict):
    """单设备控制: {type:"control", device:"door_01", action:"turn_on"}"""
    global current_command_id

    try:
        frames = dispatcher.dispatch(json_cmd)
        current_command_id = json_cmd.get("commandId", "")
        for frame in frames:
            serial_mgr.send_frame(frame)
        return None  # 异步等待 STM32 响应帧
    except Exception as e:
        return {"status": "failed", "message": str(e),
                "commandId": json_cmd.get("commandId", "")}


# ----------------------------------------------------------
# 场景命令: actions + actionDevices → 逐设备串口帧
# ----------------------------------------------------------

def _handle_scene(json_cmd: dict):
    """
    场景执行: {type:"scene", actions:"turn_on,turn_off",
               actionDevices:'["door_01","light_living"]'}
    """
    global current_command_id

    try:
        actions = json_cmd.get("actions", "").split(",")
        devices_str = json_cmd.get("actionDevices", "[]")
        devices = json.loads(devices_str)

        if len(actions) != len(devices):
            return {"status": "failed",
                    "message": "actions/actionDevices length mismatch"}

        for i, (dev_id, action) in enumerate(zip(devices, actions)):
            sub_cmd = {
                "device": dev_id.strip(),
                "action": action.strip(),
            }
            frames = dispatcher.dispatch(sub_cmd)
            for frame in frames:
                serial_mgr.send_frame(frame)
            # 每个子命令间留一点间隔，避免 STM32 缓冲区溢出
            time.sleep(0.05)

        current_command_id = json_cmd.get("commandId", "")
        return None  # 异步等待 STM32 响应
    except Exception as e:
        return {"status": "failed", "message": str(e),
                "commandId": json_cmd.get("commandId", "")}


# ----------------------------------------------------------
# 数据刷新: 返回最新传感器快照
# ----------------------------------------------------------

def _handle_data_refresh():
    """QT 客户端请求最新传感器数据 → 立即用缓存组装 sensor_data 广播"""
    cache = serial_mgr.get_sensor_cache()
    pkt = build_sensor_packet(
        device_id="raspi_gateway_01",
        temp=cache.get("temperature", 0.0),
        humi=cache.get("humidity", 0.0),
        light=cache.get("light", 0.0),
        rain=cache.get("rain", 0.0),
        smoke=cache.get("smoke", 0.0),
        lpg=cache.get("lpg", 0.0),
        air_qual=cache.get("air_quality", 0.0),
        pressure=cache.get("pressure", 0.0),
    )
    udp.broadcast(pkt)
    return None  # 无需 TCP 回复，通过 UDP 广播即可


# ----------------------------------------------------------
# Hello 握手: 返回摄像头信息
# ----------------------------------------------------------

def _handle_hello():
    """TCP 连接后响应 hello，告知摄像头端口"""
    return {
        "type": "command_response",
        "commandId": "hello",
        "status": "success",
        "message": "connected",
        "camera": True,
        "videoPort": 9998,
    }


# ============================================================
# 串口帧 → JSON 转换（STM32 → 树莓派 → QT6）
# ============================================================

def handle_sensor_data(field: str, value: float, sensor_cache: dict):
    """
    STM32 传感器帧到达 → 缓存已更新 → 组装 sensor_data JSON → UDP 广播
    """
    pkt = build_sensor_packet(
        device_id="raspi_gateway_01",
        temp=sensor_cache.get("temperature", 0.0),
        humi=sensor_cache.get("humidity", 0.0),
        light=sensor_cache.get("light", 0.0),
        rain=sensor_cache.get("rain", 0.0),
        smoke=sensor_cache.get("smoke", 0.0),
        lpg=sensor_cache.get("lpg", 0.0),
        air_qual=sensor_cache.get("air_quality", 0.0),
        pressure=sensor_cache.get("pressure", 0.0),
    )
    udp.broadcast(pkt)


def handle_cmd_response(parsed: dict):
    """
    STM32 控制响应帧到达 → 组装 command_response JSON → TCP 回复 QT6
    """
    global current_command_id
    resp = build_cmd_response(current_command_id, success=True)
    tcp.send_response(resp)
    current_command_id = None
```

### 8.1 JSON ↔ 串口帧 完整转换链路

```
QT6 → TCP(JSON) → 树莓派 → 串口(FF/FE帧) → STM32
─────────────────────────────────────────────────────
type:"control"    → _handle_control    → FF [zone] [devType] [index] [value] FE
  device:"door_01"   查 DEVICE_REGISTRY    FF 01 24 01 01 FE
  action:"turn_on"   _action_to_value

type:"scene"      → _handle_scene      → 逐设备循环调用 dispatch
  actions:"on,off"   拆分 actions/devices  每设备一条帧
  actionDevices:[...]

type:"hello"      → _handle_hello       → 直接回复 command_response (含camera/videoPort)
type:"heartbeat"  → handle_tcp_command  → 直接回复 heartbeat_ack
type:"voice_text" → handle_tcp_command  → 无回复 (异步TTS)
type:"data_refresh_request" → _handle_data_refresh → UDP广播 sensor_data


STM32 → 串口(FF/FE帧) → 树莓派 → TCP/UDP(JSON) → QT6
─────────────────────────────────────────────────────
FF [senType] [d1] [d2] [d3] FE  → parse_sensor_frame  → sensor_data JSON → UDP 8888
                                     拼接+换算              {type:"sensor_data",
                                                            temperature:25.5, ...}

FF 01/02 [devType] [index] [val] FE → parse_control_frame → command_response JSON → TCP 9999
                                         (控制响应帧)          {type:"command_response",
                                                              commandId:"...",
                                                              status:"success"}
```

---



## 九、校验和 (checksum) 规则

```python
import hashlib, json

def compute_checksum(packet_dict: dict) -> str:
    """
    1. 从 dict 中移除 checksum 键（如果存在）
    2. json.dumps 成 Compact 格式（无空格，无缩进）
    3. MD5 并返回十六进制字符串
    """
    d = {k: v for k, v in packet_dict.items() if k != "checksum"}
    raw = json.dumps(d, separators=(',', ':'), ensure_ascii=False)
    return hashlib.md5(raw.encode('utf-8')).hexdigest()
```

---

## 十、摄像头视频流协议（端口 9998）

```
帧格式（二进制）:
┌─────────┬──────────┬──────────┐
│  Magic  │ JPEG长度  │ JPEG数据  │
│ 4 bytes │  4 bytes │ N bytes  │
│AABBCCDD │ LE u32   │           │
└─────────┴──────────┴──────────┘

Magic: 0xAA 0xBB 0xCC 0xDD
JPEG长度: 小端序 32 位无符号整数
```

Python 发送示例：
```python
import struct

MAGIC = b'\xAA\xBB\xCC\xDD'

def send_jpeg_frame(conn, jpeg_bytes: bytes):
    header = MAGIC + struct.pack('<I', len(jpeg_bytes))
    conn.sendall(header + jpeg_bytes)
```

---

## 十一、实现清单

| 项目 | 状态 |
|------|------|
| [x] UDP 设备发现 + 传感器广播 | 协议已定 |
| [x] TCP 命令接收 + 响应 | 协议已定 |
| [x] TCP 摄像头视频流 | 协议已定 |
| [x] JSON checksum (MD5) | 算法已定 |
| [x] 串口 FF/FE 6 字节帧协议 | 协议已定 |
| [x] 控制命令映射表（门/风扇/加湿器/蜂鸣器/灯/总控） | 已确定 |
| [x] STM32 传感器帧格式 + 换算规则 | 已确定 |
| [ ] 气压/温度/湿度换算规则（规则3） | 暂用 ÷1000，待固件确认 |
| [ ] 树莓派 Python 代码实现 | 待开发 |
| [ ] 固件 OTA 透传 | 可选 |
