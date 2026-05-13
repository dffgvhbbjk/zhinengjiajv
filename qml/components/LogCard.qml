import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: logCard

    property string logMessage: ""
    property string logTimestamp: ""

    property string modulePrefix: {
        if (logMessage.indexOf("[SYSTEM]") === 0) return "🖥️ 系统"
        if (logMessage.indexOf("[UDP]") === 0) return "📡 UDP"
        if (logMessage.indexOf("[TCP]") === 0) return "🔌 TCP"
        if (logMessage.indexOf("[SENSOR]") === 0) return "🌡️ 传感器"
        if (logMessage.indexOf("[SCENE]") === 0) return "🎬 场景"
        if (logMessage.indexOf("[DEVICE]") === 0) return "📱 设备"
        if (logMessage.indexOf("[ALERT]") === 0) return "⚠️ 警告"
        if (logMessage.indexOf("[ENERGY]") === 0) return "💾 能耗"
        return "📝 其他"
    }

    property color moduleColor: {
        if (logMessage.indexOf("[SYSTEM]") === 0) return "#4fc3f7"
        if (logMessage.indexOf("[UDP]") === 0) return "#81c784"
        if (logMessage.indexOf("[TCP]") === 0) return "#ffb74d"
        if (logMessage.indexOf("[SENSOR]") === 0) return "#4fc3f7"
        if (logMessage.indexOf("[SCENE]") === 0) return "#ba68c8"
        if (logMessage.indexOf("[DEVICE]") === 0) return "#4db6ac"
        if (logMessage.indexOf("[ALERT]") === 0) return "#ef5350"
        if (logMessage.indexOf("[ENERGY]") === 0) return "#ffd54f"
        return "grey"
    }

    property string levelBadge: {
        if (logMessage.indexOf("[INFO]") >= 0) return "INFO"
        if (logMessage.indexOf("[WARN]") >= 0) return "WARN"
        if (logMessage.indexOf("[ERROR]") >= 0) return "ERROR"
        if (logMessage.indexOf("[DEBUG]") >= 0) return "DEBUG"
        return ""
    }

    property color levelColor: {
        if (levelBadge === "INFO") return "#4fc3f7"
        if (levelBadge === "WARN") return "#ffb74d"
        if (levelBadge === "ERROR") return "#ef5350"
        if (levelBadge === "DEBUG") return "#81c784"
        return "#9e9e9e"
    }

    property string displayMessage: {
        var msg = logMessage
        msg = msg.replace(/\[SYSTEM\]/g, "").replace(/\[UDP\]/g, "").replace(/\[TCP\]/g, "")
        msg = msg.replace(/\[SENSOR\]/g, "").replace(/\[SCENE\]/g, "").replace(/\[DEVICE\]/g, "")
        msg = msg.replace(/\[ALERT\]/g, "").replace(/\[ENERGY\]/g, "")
        msg = msg.replace(/\[INFO\]/g, "").replace(/\[WARN\]/g, "").replace(/\[ERROR\]/g, "").replace(/\[DEBUG\]/g, "")
        return msg.trim()
    }

    property string displayTime: {
        if (!logTimestamp) return ""
        var ts = logTimestamp.replace("T", " ")
        if (ts.indexOf(".") >= 0) {
            ts = ts.substring(0, ts.indexOf("."))
        }
        if (ts.length >= 19) {
            var parts = ts.split(" ")
            if (parts.length >= 2) {
                var dateParts = parts[0].split("-")
                var timeParts = parts[1].split(":")
                var localDate = new Date(Date.UTC(
                    parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]),
                    parseInt(timeParts[0]), parseInt(timeParts[1]), parseInt(timeParts[2])
                ))
                var localHour = localDate.getHours()
                var localMinute = localDate.getMinutes()
                var localSecond = localDate.getSeconds()
                var hStr = localHour < 10 ? "0" + localHour : "" + localHour
                var mStr = localMinute < 10 ? "0" + localMinute : "" + localMinute
                var sStr = localSecond < 10 ? "0" + localSecond : "" + localSecond
                return parts[0] + " " + hStr + ":" + mStr + ":" + sStr
            }
        }
        return ts
    }

    height: 76
    radius: 10
    color: "#151515"
    border.color: moduleColor
    border.width: 2

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Rectangle {
            width: 4
            height: parent.height - 20
            color: logCard.moduleColor
            radius: 2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                spacing: 6

                Label {
                    text: logCard.modulePrefix
                    color: logCard.moduleColor
                    font.pixelSize: 11
                    font.bold: true
                }

                Rectangle {
                    visible: logCard.levelBadge.length > 0
                    color: levelColor
                    radius: 3
                    height: 16
                    width: levelText.implicitWidth + 10

                    Label {
                        id: levelText
                        anchors.centerIn: parent
                        text: logCard.levelBadge
                        color: "#151515"
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Label {
                    text: logCard.displayTime
                    color: "#90a4ae"
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }
            }

            Label {
                text: logCard.displayMessage
                color: "#ffffff"
                font.pixelSize: 13
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
}
