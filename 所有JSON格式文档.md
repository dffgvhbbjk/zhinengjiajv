{
  "智能家居项目 - 所有JSON格式文档": {
    "说明": "本文档包含项目中所有接收和发送的JSON消息格式",
    "通信方式": {
      "UDP": "端口8888(设备发现/传感器数据) / 端口8889(NetworkManager扫描响应)",
      "TCP": "端口9999(命令/响应/心跳/固件/告警/视频)"
    }
  },

  "==================== UDP 接收的JSON(上位机接收) ====================": {

    "1. 设备发现广播 (device_discovery)": {
      "来源": "树莓派网关定时广播",
      "端口": "8888",
      "协议": "UDP",
      "格式": {
        "type": "device_discovery",
        "device_id": "raspberry_gateway_01",
        "device_name": "树莓派网关",
        "device_type": "gateway",
        "tcp_port": 9999,
        "firmware_version": "v1.0.0",
        "timestamp": 1698765432000,
        "subDeviceCount": 3,
        "checksum": "md5哈希值"
        
      },
      "字段说明": {
        "type": "消息类型标识",
        "device_id": "设备唯一ID",
        "device_name": "设备显示名称",
        "device_type": "设备类型(gateway/smart_light/temperature_sensor等)",
        "tcp_port": "该设备的TCP端口",
        "firmware_version": "固件版本号",
        "timestamp": "Unix时间戳(毫秒)",
        "subDeviceCount": "子设备数量",
        "checksum": "MD5校验和(除checksum字段外的JSON计算)"
      }
    },

    "2. 传感器数据 (sensor_data)": {
      "来源": "网关上报子设备传感器数据",
      "端口": "8888",
      "协议": "UDP",
      "格式": {
        "type": "sensor_data",
        "deviceId": "sensor_01",
        "gatewayId": "raspberry_gateway_01",
        "temperature": 25.5,
        "humidity": 60.2,
        "timestamp": 1698765432000,
        "checksum": "md5哈希值"
      },
      "字段说明": {
        "type": "消息类型标识",
        "deviceId": "子设备ID",
        "gatewayId": "网关设备ID",
        "temperature": "温度值(温度传感器)",
        "humidity": "湿度值(湿度传感器)",
        "timestamp": "Unix时间戳(毫秒)",
        "checksum": "MD5校验和"
      }
    },

    "3. 扫描响应 (discovery_response)": {
      "来源": "网关响应NetworkManager的扫描请求",
      "端口": "8889",
      "协议": "UDP",
      "格式": {
        "type": "discovery_response",
        "deviceId": "raspberry_gateway_01",
        "deviceName": "树莓派网关",
        "deviceType": "gateway",
        "tcpPort": 9999,
        "firmwareVersion": "v1.0.0",
        "ip": "192.168.1.100",
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "deviceId": "设备ID",
        "deviceName": "设备名称",
        "deviceType": "设备类型",
        "tcpPort": "TCP端口",
        "firmwareVersion": "固件版本",
        "ip": "设备IP地址",
        "timestamp": "Unix时间戳(毫秒)"
      }
    }
  },

  "==================== UDP 发送的JSON(上位机发送) ====================": {

    "4. 扫描请求 (discovery_request)": {
      "目标": "网关/子设备",
      "端口": "8888",
      "协议": "UDP广播",
      "格式": {
        "type": "discovery_request",
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/utils/networkmanager.cpp -> sendDiscoveryBroadcast()"
    },

    "5. 数据刷新请求 (data_refresh_request)": {
      "目标": "指定IP的网关",
      "端口": "8888",
      "协议": "UDP单播",
      "格式": {
        "type": "data_refresh_request",
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/udpdiscoverer.cpp -> requestDataRefresh()"
    }
  },

  "==================== TCP 发送的JSON(上位机→网关) ====================": {

    "6. 握手消息 (hello)": {
      "触发时机": "TCP连接建立后自动发送",
      "格式": {
        "type": "hello",
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> onConnected()"
    },

    "7. 心跳消息 (heartbeat)": {
      "触发时机": "定时发送(30秒间隔)",
      "格式": {
        "type": "heartbeat",
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendHeartbeat()"
    },

    "8. 设备控制命令 (control)": {
      "触发时机": "用户控制设备时",
      "格式": {
        "type": "control",
        "commandId": "cmd_001",
        "device": "light_01",
        "action": "set_brightness=50",
        "timestamp": 1698765432000,
        "retryCount": 0,
        "priority": 1
      },
      "action示例": [
        "on - 开启设备",
        "off - 关闭设备",
        "set_brightness=50 - 设置亮度为50",
        "set_temperature=26 - 设置温度为26度"
      ],
      "字段说明": {
        "type": "消息类型标识",
        "commandId": "命令唯一ID",
        "device": "目标设备ID",
        "action": "控制动作",
        "timestamp": "Unix时间戳(毫秒)",
        "retryCount": "重试次数",
        "priority": "优先级(数字越小优先级越高)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendControlCommand()"
    },

    "9. 场景命令 (scene)": {
      "触发时机": "用户执行场景时",
      "格式": {
        "type": "scene",
        "commandId": "cmd_002",
        "sceneId": "scene_movie_mode",
        "sceneName": "观影模式",
        "triggerType": "manual",
        "triggerDeviceId": "",
        "triggerSensorData": "",
        "triggerTime": "20:00",
        "actions": "开灯,调暗亮度,关闭窗帘",
        "actionDevices": "[\"light_01\",\"curtain_01\"]",
        "timestamp": 1698765432000,
        "retryCount": 0,
        "priority": 2
      },
      "triggerType取值": [
        "manual - 手动触发",
        "time - 定时触发",
        "sensor - 传感器触发",
        "device - 设备状态触发"
      ],
      "字段说明": {
        "type": "消息类型标识",
        "commandId": "命令唯一ID",
        "sceneId": "场景ID",
        "sceneName": "场景名称",
        "triggerType": "触发类型",
        "triggerDeviceId": "触发设备ID(传感器/设备触发时)",
        "triggerSensorData": "传感器数据(传感器触发时)",
        "triggerTime": "触发时间(定时触发时)",
        "actions": "动作描述(逗号分隔)",
        "actionDevices": "执行设备列表(JSON数组字符串)",
        "timestamp": "Unix时间戳(毫秒)",
        "retryCount": "重试次数",
        "priority": "优先级"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendSceneCommand()"
    },

    "10. 定时任务命令 (schedule)": {
      "触发时机": "用户设置定时任务时",
      "格式": {
        "type": "schedule",
        "commandId": "cmd_003",
        "data": "{...定时任务JSON数据...}",
        "timestamp": 1698765432000,
        "retryCount": 0,
        "priority": 2
      },
      "字段说明": {
        "type": "消息类型标识",
        "commandId": "命令唯一ID",
        "data": "定时任务数据(JSON字符串)",
        "timestamp": "Unix时间戳(毫秒)",
        "retryCount": "重试次数",
        "priority": "优先级"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendScheduleCommand()"
    },

    "11. 告警命令 (alert_command)": {
      "触发时机": "用户处理告警时",
      "格式": {
        "type": "alert_command",
        "commandId": "cmd_004",
        "action": "dismiss",
        "timestamp": 1698765432000,
        "retryCount": 0,
        "priority": 0
      },
      "action取值": [
        "dismiss - 忽略告警",
        "resolve - 解决告警",
        "read - 标记已读"
      ],
      "字段说明": {
        "type": "消息类型标识",
        "commandId": "命令唯一ID",
        "action": "告警处理动作",
        "timestamp": "Unix时间戳(毫秒)",
        "retryCount": "重试次数",
        "priority": "优先级(0最高)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendAlertCommand()"
    },

    "12. 语音文本 (voice_text)": {
      "触发时机": "用户发送语音命令时",
      "格式": {
        "type": "voice_text",
        "text": "打开客厅灯",
        "is_command": true,
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "text": "语音识别文本",
        "is_command": "是否为命令(否则为普通对话)",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendVoiceText()"
    },

    "13. 固件初始化 (firmware_init)": {
      "触发时机": "开始OTA固件升级时",
      "格式": {
        "type": "firmware_init",
        "totalChunks": 50,
        "fileSize": 512000,
        "fileName": "firmware_v1.1.0.bin",
        "md5": "md5哈希值"
      },
      "字段说明": {
        "type": "消息类型标识",
        "totalChunks": "总分块数",
        "fileSize": "固件文件大小(字节)",
        "fileName": "固件文件名",
        "md5": "固件文件MD5校验"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> startFirmwareUpdate()"
    },

    "14. 固件数据块 (firmware_chunk)": {
      "触发时机": "OTA升级时分块传输固件",
      "格式": {
        "type": "firmware_chunk",
        "chunk": 0,
        "total": 50,
        "md5": "md5哈希值",
        "data": "base64编码的固件数据"
      },
      "字段说明": {
        "type": "消息类型标识",
        "chunk": "当前块索引(从0开始)",
        "total": "总分块数",
        "md5": "该块的MD5校验",
        "data": "Base64编码的固件数据"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> sendFirmwareChunk()"
    }
  },

  "==================== TCP 接收的JSON(网关→上位机) ====================": {

    "15. 命令响应 (command_response)": {
      "触发时机": "网关响应上位机命令",
      "格式": {
        "type": "command_response",
        "commandId": "cmd_001",
        "status": "success",
        "message": "设备 light_01 执行 set_brightness=50 成功",
        "timestamp": 1698765432000
      },
      "status取值": [
        "success - 命令执行成功",
        "fail - 命令执行失败"
      ],
      "字段说明": {
        "type": "消息类型标识",
        "commandId": "对应的命令ID",
        "status": "执行状态",
        "message": "执行结果描述",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> handleCommandResponse()"
    },

    "16. 心跳响应 (heartbeat_ack)": {
      "触发时机": "网关响应心跳",
      "格式": {
        "type": "heartbeat_ack",
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> handleIncomingData()"
    },

    "17. 告警上报 (alert)": {
      "触发时机": "设备离线/异常时网关主动上报",
      "格式": {
        "type": "alert",
        "alertId": "alert_1698765432",
        "deviceId": "light_01",
        "content": "设备 light_01 离线",
        "level": 2,
        "timestamp": 1698765432000
      },
      "level取值": [
        "0 - 信息",
        "1 - 警告",
        "2 - 严重",
        "3 - 紧急"
      ],
      "字段说明": {
        "type": "消息类型标识",
        "alertId": "告警唯一ID",
        "deviceId": "触发告警的设备ID",
        "content": "告警内容描述",
        "level": "告警等级",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> handleAlertPacket()"
    },

    "18. 固件确认 (firmware_ack)": {
      "触发时机": "网关确认收到固件数据块",
      "格式": {
        "type": "firmware_ack",
        "status": "ok",
        "chunk": 0
      },
      "status取值": [
        "ok - 数据块接收成功",
        "retry - 需要重传该块"
      ],
      "字段说明": {
        "type": "消息类型标识",
        "status": "接收状态",
        "chunk": "确认的块索引"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> handleFirmwareResponse()"
    },

    "19. 视频帧 (video_frame)": {
      "触发时机": "网关推送摄像头视频数据",
      "格式": {
        "type": "video_frame",
        "data": "base64编码的视频帧数据",
        "width": 640,
        "height": 480,
        "timestamp": 1698765432000
      },
      "字段说明": {
        "type": "消息类型标识",
        "data": "Base64编码的视频帧(JPEG等格式)",
        "width": "帧宽度(像素)",
        "height": "帧高度(像素)",
        "timestamp": "Unix时间戳(毫秒)"
      },
      "代码位置": "src/communication/tcpcontroller.cpp -> handleVideoFrame()"
    }
  },

  "==================== JSON处理机制 ====================": {

    "TCP粘包处理": {
      "问题": "TCP是流式协议,可能一次收到多个JSON或一个JSON被拆分",
      "解决方案": "接收缓冲区 + JSON边界定位算法",
      "算法": {
        "步骤1": "将收到的数据追加到m_receiveBuffer",
        "步骤2": "使用findJsonBoundary()查找完整JSON的结束位置",
        "步骤3": "从缓冲区提取完整JSON并解析",
        "步骤4": "循环处理直到缓冲区无完整JSON"
      },
      "findJsonBoundary算法": {
        "原理": "大括号计数 + 字符串转义处理",
        "规则": [
          "遇到'{' braceCount++",
          "遇到'}' braceCount--",
          "braceCount==0时找到完整JSON边界",
          "跳过字符串内的括号(双引号标记)",
          "处理反斜杠转义字符"
        ]
      }
    },

    "MD5校验机制": {
      "使用场景": "UDP消息(device_discovery, sensor_data)",
      "计算方法": "对整个JSON(除checksum字段)计算MD5",
      "验证过程": {
        "步骤1": "提取checksum字段值",
        "步骤2": "从JSON对象中移除checksum字段",
        "步骤3": "将剩余JSON序列化为字符串",
        "步骤4": "计算MD5并与提供的checksum比较"
      }
    },

    "优先级队列": {
      "说明": "TCP命令按优先级排序发送",
      "优先级值": {
        "0": "最高优先级(告警命令)",
        "1": "设备控制命令",
        "2": "场景/定时任务命令"
      },
      "排序规则": "数字越小优先级越高,优先发送"
    },

    "重试机制": {
      "命令重试": {
        "最大重试次数": 3,
        "触发条件": "command_response.status == fail",
        "策略": "失败命令重新加入队列头部"
      },
      "重连机制": {
        "最大重连次数": 有限次(由MaxReconnectAttempts定义)",
        "重连间隔": ReconnectIntervalMs(毫秒)",
        "定时器类型": "单次定时器(singleShot),失败后手动重启"
      }
    }
  }
}
