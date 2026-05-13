# 智能家居控制系统 — 项目书

## 一、项目概览

| 项目 | 详情 |
|------|------|
| **名称** | 智能家居控制系统 (Smart Home Control System) |
| **版本** | 0.1.0 |
| **技术栈** | Qt 6.10.2 + QML (C++20), 树莓派 (Python), 下位机 (Arduino/STM32 + 串口) |
| **构建系统** | CMake 3.16+ |
| **编译器** | MinGW 64-bit (Qt 自带) |
| **IDE** | Qt Creator |

---

## 二、系统架构总览

```
                          ┌─────────────────────────────────┐
                          │         QT6 桌面客户端            │
                          │     C++ 业务逻辑 + QML 界面       │
                          └───────┬─────────────────┬───────┘
                    UDP:8888      │    TCP:9999      │ TCP:9998
                   (设备发现/      │  (控制命令/      │ (摄像头
                    传感器广播)    │   场景/语音)     │  视频流)
                          │       │                 │
                    ┌─────┴───────┴─────────┐       │
                    │       树莓派 网关       │◄──────┘
                    │    Python 脚本逻辑      │
                    └─┬───┬───┬───┬───┬───┬─┘
                      │   │   │   │   │   │
               ┌──────┘   │   │   │   │   └──────┐
          串口/UART   GPIO  I2C  SPI  USB  其他接口
              │         │    │    │    │
    ┌────┴───┐   ┌──┴──┐ ┌─┴──┐ │ ┌──┴──┐
    │Arduino │   │继电器│ │DHT │ │ │麦克风│
    │STM32   │   │LED   │ │BH  │ │ │摄像头│
    │传感器  │   │按钮  │ │MQ  │ │ │      │
    └────────┘   └─────┘ └────┘ │ └─────┘
```

---

## 三、QT6 客户端模块划分

### 3.1 目录结构

```
src/
├── main.cpp                    # 程序入口 + 全模块初始化 + 信号连接
├── communication/              # 网络通信层
│   ├── udpdiscoverer.h/.cpp    # UDP 设备发现 + 传感器数据接收
│   ├── tcpcontroller.h/.cpp    # TCP 命令收发 + 视频流接收
│   └── scenetriggerengine.h/.cpp # 场景自动触发引擎
├── models/                     # 数据模型层（SQLite + QAbstractListModel）
│   ├── databasemanager.h/.cpp  # 单例数据库管理器
│   ├── devicemodel.h/.cpp      # 设备列表模型
│   ├── scenemodel.h/.cpp       # 场景列表模型
│   ├── energymodel.h/.cpp      # 能耗统计模型
│   ├── sensormodel.h/.cpp      # 传感器历史数据模型
│   └── alertmodel.h/.cpp       # 告警消息模型
├── utils/                      # 工具类
│   ├── voicecontroller.h/.cpp  # 语音识别(TTS/STT,百度API)
│   ├── weatherservice.h/.cpp   # 天气服务(和风API)
│   ├── locationservice.h/.cpp  # 定位服务
│   ├── networkmanager.h/.cpp   # 局域网IP扫描
│   ├── jsonutils.h/.cpp        # JSON工具(通用getValue/extractId)
│   └── timeutils.h/.cpp        # 时间工具
└── ...

qml/
├── main.qml                    # 应用窗口 + TabBar + StackLayout
├── components/                 # 可复用组件
└── pages/                      # 功能页面
    ├── HomePage.qml            # 首页(快捷控制+天气+语音入口)
    ├── DeviceControlPage.qml   # 设备控制页面
    ├── ScenePage.qml           # 场景列表页
    ├── SceneEditPage.qml       # 场景编辑页
    ├── SensorPage.qml          # 传感器数据页
    ├── EnergyPage.qml          # 能耗统计页
    ├── AlertCenterPage.qml     # 告警中心页
    ├── SecurityPage.qml        # 安全设置页
    ├── LogPage.qml             # 系统日志页
    └── SettingsPage.qml        # 系统设置页
```

### 3.2 C++ 类注册方式

全部业务类通过 `qmlRegisterSingletonInstance` 注册为 QML 单例：

| 类 | QML 引用名 | 类型 |
|----|-----------|------|
| `DatabaseManager` | `DatabaseManager` | 数据库操作 |
| `DeviceModel` | `DeviceModel` | QAbstractListModel |
| `SceneModel` | `SceneModel` | QAbstractListModel |
| `EnergyModel` | `EnergyModel` | QAbstractListModel |
| `SensorModel` | `SensorModel` | QAbstractListModel |
| `AlertModel` | `AlertModel` | QAbstractListModel |
| `TcpController` | `TcpController` | 网络控制 |
| `UdpDiscoverer` | `UdpDiscoverer` | 设备发现 |
| `SceneTriggerEngine` | `SceneTriggerEngine` | 场景触发 |
| `VoiceController` | `VoiceController` | 语音控制 |
| `WeatherService` | `WeatherService` | 天气服务 |
| `LocationService` | `LocationService` | 定位服务 |
| `NetworkManager` | `NetworkManager` | 网络管理 |

### 3.3 信号连接架构 (main.cpp)

```
UdpDiscoverer::deviceDiscovered ──→ TcpController::connectToDevice  (发现设备→自动连接)
                                ──→ DatabaseManager::addDevice      (持久化设备)
                                ──→ DatabaseManager::setDeviceOnline

UdpDiscoverer::deviceOffline    ──→ DatabaseManager::setDeviceOnline (标记离线)

UdpDiscoverer::dataReceived     ──→ DatabaseManager::addSensorData  (传感器数据入库)
                                ──→ SceneTriggerEngine::onSensorDataReceived (传感器触发场景)

TcpController::deviceControlled ──→ SceneTriggerEngine::onDeviceStateChanged (设备状态触发场景)

TcpController::alertReceived    ──→ DatabaseManager::addAlert       (告警入库)

TcpController::videoFrameReceived ──→ RemoteVideoImageProvider     (视频帧渲染)

WeatherService::weatherFetched  ──→ SceneTriggerEngine::onWeatherUpdated   (天气触发场景)

LocationService::locationChanged ──→ WeatherService::fetchWeatherByLocation

VoiceController::recognitionComplete ──→ 命令分发Lambda (语音→设备控制/查询)

NetworkManager::deviceFound     ──→ TcpController::connectToDevice  (IP扫描发现→连接)

DatabaseManager::databaseOpened ──→ DeviceModel::load               (数据库就绪→加载)
                                ──→ SceneModel::load
                                ──→ AlertModel::load
                                ──→ SceneTriggerEngine::start
```

---

## 四、数据库设计 (SQLite)

路径：`<应用数据目录>/smart_home.db`

### 4.1 devices 表

```sql
CREATE TABLE IF NOT EXISTS devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT UNIQUE NOT NULL,     -- "raspi_gateway_01"
    device_name TEXT NOT NULL,          -- "客厅灯"
    device_type TEXT NOT NULL,          -- "light", "air", "curtain", "gateway", "sensor"
    room TEXT DEFAULT '',               -- "客厅"
    ip TEXT DEFAULT '',                 -- "192.168.1.100"
    port INTEGER DEFAULT 0,
    status TEXT DEFAULT 'offline',      -- "online" / "offline"
    last_online_time TEXT DEFAULT '',
    firmware_version TEXT DEFAULT '',
    created_at TEXT DEFAULT '',
    updated_at TEXT DEFAULT ''
);
```

### 4.2 energy_data 表（传感器数据复用）

```sql
CREATE TABLE IF NOT EXISTS energy_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    power REAL DEFAULT 0,              -- 功率
    temperature REAL DEFAULT 0,         -- 温度 °C
    humidity REAL DEFAULT 0,            -- 湿度 %
    light REAL DEFAULT 0,               -- 光照 lux
    rain REAL DEFAULT 0,                -- 雨量
    smoke REAL DEFAULT 0,               -- 烟雾浓度
    lpg REAL DEFAULT 0,                 -- LPG浓度
    air_quality REAL DEFAULT 0          -- 空气质量
);
```

### 4.3 scenes 表

```sql
CREATE TABLE IF NOT EXISTS scenes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scene_id TEXT UNIQUE NOT NULL,
    scene_name TEXT NOT NULL,
    trigger_type TEXT NOT NULL,         -- "manual", "time", "sensor", "device", "weather", "custom"
    trigger_device_id TEXT DEFAULT '',
    trigger_sensor_data TEXT DEFAULT '',
    trigger_time TEXT DEFAULT '',
    actions TEXT DEFAULT '',            -- "turn_on,turn_off"
    action_devices TEXT DEFAULT '',     -- JSON数组字符串: ["light_01","ac_01"]
    is_enabled INTEGER DEFAULT 1,
    effective_date TEXT DEFAULT '',
    expire_date TEXT DEFAULT '',
    effective_count INTEGER DEFAULT -1,
    last_executed_at TEXT DEFAULT '',
    scene_status TEXT DEFAULT '',
    created_at TEXT DEFAULT ''
);
```

### 4.4 alerts 表

```sql
CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    alert_id TEXT UNIQUE NOT NULL,
    device_id TEXT NOT NULL,
    content TEXT DEFAULT '',
    level INTEGER DEFAULT 0,           -- 0=info 1=warn 2=severe 3=emergency
    alert_type TEXT DEFAULT '',
    is_read INTEGER DEFAULT 0,
    timestamp TEXT DEFAULT '',
    created_at TEXT DEFAULT ''
);
```

### 4.5 connection_logs 表

```sql
CREATE TABLE IF NOT EXISTS connection_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT DEFAULT '',
    message TEXT DEFAULT '',
    level TEXT DEFAULT 'INFO'
);
```

---

## 五、QML 页面功能清单

| 页面 | 文件 | 主要功能 |
|------|------|---------|
| **首页** | `HomePage.qml` | 天气卡片、快捷控制按钮、语音控制入口、设备状态概览 |
| **设备控制** | `DeviceControlPage.qml` | 设备网格/列表、筛选(全部/灯光/空调/窗帘)、批量开关、设备 Loader 动态加载控制组件 |
| **场景管理** | `ScenePage.qml` | 场景列表、启用/禁用开关、手动执行、新建/编辑场景入口 |
| **场景编辑** | `SceneEditPage.qml` | 场景名称、触发条件(定时/传感器/设备/天气/自定义)、执行动作列表、拖拽排序、保存/删除 |
| **传感器** | `SensorPage.qml` | 传感器数据图表(Graphs)、历史数据查询、实时数据刷新 |
| **能耗统计** | `EnergyPage.qml` | 能耗趋势图、日/周/月统计、设备能耗排行 |
| **告警中心** | `AlertCenterPage.qml` | 告警列表(未读/已读)、告警详情、清除告警 |
| **安全设置** | `SecurityPage.qml` | 安防模式开关、传感器告警阈值设置 |
| **系统日志** | `LogPage.qml` | 连接日志列表、数据刷新 |
| **系统设置** | `SettingsPage.qml` | 网关连接设置、语音设置、主题设置 |

---

## 六、C++ 模型类的 QML 角色字段

### 6.1 DeviceModel

| 角色名 | 字段说明 |
|--------|---------|
| `deviceId` | 设备唯一ID |
| `deviceName` | 设备名称 |
| `deviceType` | 设备类型(light/air/curtain/gateway/sensor) |
| `room` | 所在房间 |
| `ip` | IP 地址 |
| `port` | TCP端口 |
| `status` | 在线状态(online/offline) |
| `lastOnlineTime` | 最后一次在线时间 |

### 6.2 SceneModel

| 角色名 | 字段说明 |
|--------|---------|
| `sceneId` | 场景ID |
| `sceneName` | 场景名称 |
| `triggerType` | 触发类型(manual/time/sensor/device/weather/custom) |
| `triggerDeviceId` | 触发设备ID |
| `triggerSensorData` | 触发传感器数据条件 |
| `triggerTime` | 触发时间(定时) |
| `actions` | 动作序列(逗号分隔) |
| `actionDevices` | 动作设备列表(JSON数组) |
| `isEnabled` | 是否启用 |
| `effectiveDate` | 生效日期 |
| `expireDate` | 过期日期 |
| `effectiveCount` | 有效执行次数(-1=无限) |
| `lastExecutedAt` | 最后执行时间 |
| `sceneStatus` | 场景状态 |
| `createdAt` | 创建时间 |

### 6.3 SensorModel

| 角色名 | 字段说明 |
|--------|---------|
| `timestamp` | 数据时间戳 |
| `deviceId` | 设备ID |
| `temperature` | 温度 °C |
| `humidity` | 湿度 % |
| `light` | 光照 lux |
| `rain` | 雨量 |
| `smoke` | 烟雾浓度 |
| `lpg` | LPG浓度 |
| `airQuality` | 空气质量 |

### 6.4 EnergyModel

| 角色名 | 字段说明 |
|--------|---------|
| `timestamp` | 时间戳 |
| `deviceId` | 设备ID |
| `power` | 功率 |
| `temperature` | 温度 |
| `humidity` | 湿度 |

### 6.5 AlertModel

| 角色名 | 字段说明 |
|--------|---------|
| `alertId` | 告警ID |
| `deviceId` | 关联设备ID |
| `content` | 告警内容 |
| `level` | 等级(0-3) |
| `alertType` | 告警类型 |
| `isRead` | 是否已读 |
| `timestamp` | 时间戳 |

---

## 七、信号完整签名

### 7.1 TcpController 信号

| 信号 | 参数 |
|------|------|
| `connectionStatusChanged(bool connected)` | 连接状态变化 |
| `commandSuccess(const QString &commandId, const QString &message)` | 命令执行成功 |
| `commandFailed(const QString &commandId, const QString &error)` | 命令执行失败 |
| `alertReceived(const QString &alertId, const QString &deviceId, const QString &content, int level)` | 收到告警 |
| `firmwareUpdateProgress(int percent)` | 固件更新进度 |
| `firmwareUpdateComplete(bool success)` | 固件更新完成 |
| `errorOccurred(const QString &error)` | 通信错误 |
| `videoFrameReceived(const QString &base64Data, int width, int height, qint64 timestamp)` | JSON视频帧 |
| `rawVideoFrameReceived(const QByteArray &jpegData, int width, int height)` | 二进制视频帧 |
| `cameraStreamToggled(bool enabled)` | 摄像头流开关 |
| `deviceControlled(const QString &deviceId, const QString &action)` | 设备被控制通知 |

### 7.2 UdpDiscoverer 信号

| 信号 | 参数 |
|------|------|
| `deviceDiscovered(const QString &deviceId, const QString &deviceName, const QString &deviceType, const QString &ip, int tcpPort, const QString &firmwareVersion)` | 发现设备 |
| `dataReceived(const QString &deviceId, const QVariantMap &data)` | 收到传感器数据 |
| `deviceOffline(const QString &deviceId)` | 设备离线 |
| `errorOccurred(const QString &error)` | 网络错误 |
| `discoveryStarted()` | 发现服务启动 |
| `discoveryStopped()` | 发现服务停止 |

---

## 八、语音控制功能

### 8.1 技术实现

- **语音识别 (STT)**：百度语音 API (`vop.baidu.com/server_api`)
- **语音合成 (TTS)**：Qt `QTextToSpeech`
- **输入**：PCM 16kHz 单声道
- **API 认证**：OAuth 2.0 Client Credentials
- **密钥管理**：优先读 `voice_config.json`，不存在则用内置默认值

### 8.2 支持的命令

| 类别 | 语音指令 | 行为 |
|------|---------|------|
| 查询 | "天气" | 播报当前天气(温度、湿度、天气状况) |
| 查询 | "温度/湿度/传感器" | 播报最新传感器数据 |
| 查询 | "能耗/用电/电量" | 播报近期总能耗 |
| 控制 | "开灯/关灯" | 全部灯光 或 指定设备 |
| 控制 | "开空调/关空调" | 全部空调 或 指定设备 |
| 控制 | "全部打开/关闭" | 所有设备 |
| 场景 | "打开场景[名称]" | 执行指定场景 |

### 8.3 指定设备控制逻辑

语音中提及设备名或房间名时（如"打开客厅灯"），通过 `findDeviceByName()` 评分匹配：
- 设备名精确匹配：100 分
- 房间名匹配：50 分
- 房间+设备名组合匹配：30 分
- 无匹配时降级为全部同类型设备

---

## 九、通信协议关键参数

| 参数 | 值 |
|------|-----|
| UDP 端口 | 8888 |
| TCP 控制端口 | 9999 |
| TCP 视频端口 | 9998 |
| 心跳间隔 | 30 秒 |
| 心跳超时 | 10 秒 |
| 命令重试次数 | 3 次 |
| 命令超时 | 10 秒 |
| 重连间隔 | 10 秒 |
| 最大重连次数 | 3 次 |
| 固件数据块大小 | 1024 字节 |
| 录音最大时长 | 10 秒 |
| 语音识别结果展示时长 | 1.5 秒 |

---

## 十、场景触发引擎 (SceneTriggerEngine)

### 10.1 触发类型

| 类型 | 触发条件 | 数据来源 |
|------|---------|---------|
| `manual` | 手动执行 | ScenePage / 语音命令 |
| `time` | 定时触发 | 系统时钟 (QTimer) |
| `sensor` | 传感器数据阈值 | UdpDiscoverer::dataReceived |
| `device` | 设备状态变化 | TcpController::deviceControlled |
| `weather` | 天气条件 | WeatherService::weatherFetched |
| `custom` | 自定义条件 | 保留扩展 |

---

## 十一、版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 0.1.0 | 2026-05 | 初始版本：10个页面、6个数据模型、UDP/TCP通信、语音控制、场景引擎、天气服务 |
