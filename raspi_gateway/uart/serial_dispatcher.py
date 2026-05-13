"""
JSON 控制命令 → 6字节串口帧 分发器
"""

from config import DEVICE_REGISTRY

FRAME_HEAD = 0xFF
FRAME_TAIL = 0xFE


class SerialDispatcher:
    """将 JSON 控制命令翻译成 6 字节串口帧"""

    def __init__(self, device_registry: dict = None):
        self.registry = device_registry or DEVICE_REGISTRY

    def dispatch(self, json_cmd: dict) -> list[bytes]:
        """
        返回要发送的帧列表（全屋总控返回 2 帧，其余返回 1 帧）
        json_cmd = {"device": "door_01", "action": "turn_on"}
        """
        dev_id = json_cmd["device"]
        action = json_cmd["action"]
        dev = self.registry.get(dev_id)
        if not dev:
            raise ValueError(f"Unknown device: {dev_id}")

        value = self._action_to_value(dev_id, action)
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

    def _action_to_value(self, dev_id: str, action: str) -> int:
        """将 JSON action 转为帧的 value 字节"""
        base_action = action.split("|")[0].strip() if "|" in action else action

        if dev_id.startswith("fan_"):
            speed_map = {
                "turn_on": 0x01, "speed_1": 0x01,
                "speed_2": 0x02, "speed_3": 0x03,
                "turn_off": 0x00,
            }
            v = speed_map.get(base_action)
            if v is not None:
                return v
            if "|" in action:
                try:
                    param = int(action.split("|")[1].strip())
                    return max(0x00, min(0x03, param))
                except (ValueError, IndexError):
                    pass
            raise ValueError(f"Unsupported fan action: {action}")

        if dev_id.startswith("door_"):
            door_map = {
                "open": 0x01,
                "close": 0x00,
                "turn_on": 0x01,
                "turn_off": 0x00,
            }
            v = door_map.get(base_action)
            if v is not None:
                return v
            raise ValueError(f"Unsupported door action: {action}")

        if dev_id.startswith("humidifier_"):
            onoff_map = {"turn_on": 0x01, "turn_off": 0x00}
            v = onoff_map.get(base_action)
            if v is not None:
                return v
            raise ValueError(f"Unsupported humidifier action: {action}")

        if dev_id.startswith("buzzer_"):
            onoff_map = {"turn_on": 0x01, "turn_off": 0x00}
            v = onoff_map.get(base_action)
            if v is not None:
                return v
            raise ValueError(f"Unsupported buzzer action: {action}")

        if dev_id.startswith("light_"):
            if "|" in action:
                try:
                    brightness = int(action.split("|")[1].strip())
                    return max(0x00, min(0x64, brightness))
                except (ValueError, IndexError):
                    pass
            onoff_map = {"turn_on": 0x01, "turn_off": 0x00}
            v = onoff_map.get(base_action)
            if v is not None:
                return v
            raise ValueError(f"Unsupported light action: {action}")

        if dev_id == "master_switch":
            onoff_map = {"turn_on": 0x01, "turn_off": 0x00}
            v = onoff_map.get(base_action)
            if v is not None:
                return v
            raise ValueError(f"Unsupported master_switch action: {action}")

        if base_action == "turn_on":
            return 0x01
        if base_action == "turn_off":
            return 0x00

        raise ValueError(f"Unsupported action '{action}' for device '{dev_id}'")
