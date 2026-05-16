"""
JSON 控制命令 → 6字节串口帧 分发器
动作值映射从 config.ACTION_VALUE_MAP 加载，支持运行时热更新
"""

from config import DEVICE_REGISTRY, ACTION_VALUE_MAP, FRAME_HEAD, FRAME_TAIL


class SerialDispatcher:
    """将 JSON 控制命令翻译成 6 字节串口帧"""

    def __init__(self, device_registry: dict = None, action_map: dict = None):
        self.registry = device_registry or DEVICE_REGISTRY
        self.action_map = action_map or ACTION_VALUE_MAP

    def dispatch(self, json_cmd: dict) -> list[bytes]:
        """
        返回要发送的帧列表（全屋总控返回 2 帧，其余返回 1 帧）
        json_cmd = {"device": "door_01", "action": "open"}
        """
        dev_id = json_cmd["device"]
        action = json_cmd["action"]
        dev = self.registry.get(dev_id)
        if not dev:
            raise ValueError(f"Unknown device: {dev_id}")

        value = self._action_to_value(dev_id, dev, action)
        frames = []

        if dev.get("dual_frame"):
            frames.append(bytes([FRAME_HEAD, dev["zone"], dev["dev_type"],
                                 dev["dev_index"], value, FRAME_TAIL]))
            frames.append(bytes([FRAME_HEAD, dev["zone2"], dev["dev_type2"],
                                 dev["dev_index2"], value, FRAME_TAIL]))
        else:
            frames.append(bytes([FRAME_HEAD, dev["zone"], dev["dev_type"],
                                 dev["dev_index"], value, FRAME_TAIL]))
        return frames

    def _action_to_value(self, dev_id: str, dev: dict, action: str) -> int:
        """将 JSON action 转为帧的 value 字节，从 ACTION_VALUE_MAP 查表"""
        category = dev.get("category", "")
        base_action = action.split("|")[0].strip() if "|" in action else action

        cat_map = self.action_map.get(category)
        if cat_map:
            if base_action in cat_map:
                val = cat_map[base_action]
                if isinstance(val, str) and val.startswith("param:"):
                    return self._resolve_param_action(action, val)
                return val

            if "|" in action:
                try:
                    param = int(action.split("|")[1].strip())
                    return max(0x00, min(0x64, param))
                except (ValueError, IndexError):
                    pass

        if base_action == "turn_on":
            return 0x01
        if base_action == "turn_off":
            return 0x00

        raise ValueError(f"Unsupported action '{action}' for device '{dev_id}' (category='{category}')")

    def _resolve_param_action(self, action: str, spec: str) -> int:
        """解析 'param:min:max' 格式的动作值，支持 brightness 等参数化动作"""
        parts = spec.split(":")
        if len(parts) == 3:
            min_val = int(parts[1])
            max_val = int(parts[2])
            if "|" in action:
                try:
                    param = int(action.split("|")[1].strip())
                    return max(min_val, min(max_val, param))
                except (ValueError, IndexError):
                    return min_val
        return 0x01