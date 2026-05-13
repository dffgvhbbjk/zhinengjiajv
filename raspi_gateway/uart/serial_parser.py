"""
FF/FE 6字节定长帧解析器 — 区分控制帧与传感器帧
"""

from config import SENSOR_TYPE_MAP, SENSOR_DIVIDE_BY_1000

FRAME_HEAD = 0xFF
FRAME_TAIL = 0xFE
FRAME_LEN = 6

CONTROL_ZONES = {0x01, 0x02}

_VALID_BYTE1 = set(SENSOR_TYPE_MAP.keys()) | CONTROL_ZONES


class SerialParser:
    """从字节流中提取 FF ... FE 定长帧，区分控制帧与传感器帧"""

    def __init__(self):
        self._buf = bytearray()

    # ---- 字节流 → 帧列表 ------------------------------------------------

    def feed(self, data: bytes) -> list[bytes]:
        self._buf.extend(data)
        frames = []

        while True:
            head_idx = self._buf.find(FRAME_HEAD)
            if head_idx < 0:
                self._buf.clear()
                break

            if head_idx > 0:
                del self._buf[:head_idx]

            if len(self._buf) < FRAME_LEN:
                break

            byte1_valid = self._buf[1] in _VALID_BYTE1
            tail_match = self._buf[5] == FRAME_TAIL

            if tail_match and byte1_valid:
                frames.append(bytes(self._buf[:FRAME_LEN]))
                del self._buf[:FRAME_LEN]
            else:
                del self._buf[0]

        return frames

    # ---- 帧类型判断 ----------------------------------------------------

    @staticmethod
    def is_sensor_frame(frame: bytes) -> bool:
        """Byte 1 在传感器类型码范围内"""
        if len(frame) < 2:
            return False
        return frame[1] in SENSOR_TYPE_MAP

    @staticmethod
    def is_control_frame(frame: bytes) -> bool:
        """Byte 1 为 0x01 或 0x02"""
        if len(frame) < 2:
            return False
        return frame[1] in CONTROL_ZONES

    # ---- 帧解析 --------------------------------------------------------

    @staticmethod
    def parse_control_frame(frame: bytes) -> dict:
        """解析控制帧 → {zone, dev_type, dev_index, value}"""
        if len(frame) != FRAME_LEN or frame[0] != FRAME_HEAD or frame[5] != FRAME_TAIL:
            raise ValueError("Invalid control frame")
        return {
            "zone": frame[1],
            "dev_type": frame[2],
            "dev_index": frame[3],
            "value": frame[4],
        }

    @staticmethod
    def parse_sensor_frame(frame: bytes) -> dict:
        """
        解析传感器帧 → 计算最终测量值

        步骤：
        1. 提取 Data1/Data2/Data3（Byte 2/3/4）
        2. 3 字节大端二进制 → 整数 raw 值
        3. 根据类型码选择换算规则 (÷1000 或直接取值)
        """
        if len(frame) != FRAME_LEN or frame[0] != FRAME_HEAD or frame[5] != FRAME_TAIL:
            raise ValueError("Invalid sensor frame")

        sen_type = frame[1]
        field_name = SENSOR_TYPE_MAP.get(sen_type)
        if field_name is None:
            raise ValueError(f"Unknown sensor type: 0x{sen_type:02X}")

        combined = int.from_bytes(frame[2:5], 'big')

        if sen_type in SENSOR_DIVIDE_BY_1000:
            value = combined / 1000.0
        else:
            value = float(combined)

        return {
            "field": field_name,
            "raw": combined,
            "value": value,
        }
