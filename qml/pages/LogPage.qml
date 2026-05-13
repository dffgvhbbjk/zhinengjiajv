import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: logPage
    signal backToHome()
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property var allLogs: []
    property string filterModule: "全部"
    property string filterKeyword: ""

    Component.onCompleted: {
        refreshLogs()
    }

    header: ToolBar {
        Material.elevation: 4
        height: logHeader.implicitHeight + 16 * sc

        ColumnLayout {
            id: logHeader
            anchors.fill: parent
            anchors.margins: 8 * sc
            spacing: 8 * sc

            RowLayout {
                spacing: 8 * sc

                Button {
                    text: qsTr("🔄 刷新")
                    flat: true
                    font.pixelSize: 12 * sc
                    onClicked: refreshLogs()
                }

                Button {
                    text: qsTr("🗑️ 清理日志")
                    flat: true
                    font.pixelSize: 12 * sc
                    Material.foreground: "#ef5350"
                    onClicked: confirmClearDialog.open()
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: qsTr("共 %1 条").arg(allLogs.length)
                    color: "#4fc3f7"
                    font.pixelSize: 12 * sc
                }
            }

            RowLayout {
                spacing: 12 * sc

                ComboBox {
                    id: moduleFilter
                    model: ["全部", "🖥️ 系统", "📡 UDP", "🔌 TCP", "🎤 语音", "🌡️ 传感器", "🎬 场景", "📱 设备", "⚠️ 告警"]
                    Layout.preferredWidth: 140 * sc
                    font.pixelSize: 12 * sc

                    onActivated: function(index) {
                        filterModule = model[index]
                        refreshLogs()
                    }
                }

                ComboBox {
                    id: levelFilter
                    model: ["全部级别", "ℹ️ INFO", "⚠️ WARN", "❌ ERROR", "🐛 DEBUG"]
                    Layout.preferredWidth: 120 * sc
                    font.pixelSize: 12 * sc

                    onActivated: function(index) {
                        filterLevel = index - 1
                        refreshLogs()
                    }
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                spacing: 8 * sc

                TextField {
                    id: searchField
                    placeholderText: qsTr("搜索日志内容...")
                    Layout.fillWidth: true
                    font.pixelSize: 13 * sc

                    onTextChanged: {
                        filterKeyword = text
                        refreshLogs()
                    }
                }
            }

            RowLayout {
                spacing: 12 * sc
                Label {
                    text: "图例:"
                    color: "grey"
                    font.pixelSize: 10 * sc
                }
                Rectangle { width: 10 * sc; height: 10 * sc; radius: 2 * sc; color: "#4fc3f7" }
                Label { text: "系统"; color: "#4fc3f7"; font.pixelSize: 10 * sc }
                Rectangle { width: 10 * sc; height: 10 * sc; radius: 2 * sc; color: "#81c784" }
                Label { text: "UDP"; color: "#81c784"; font.pixelSize: 10 * sc }
                Rectangle { width: 10 * sc; height: 10 * sc; radius: 2 * sc; color: "#ffb74d" }
                Label { text: "TCP"; color: "#ffb74d"; font.pixelSize: 10 * sc }
                Rectangle { width: 10 * sc; height: 10 * sc; radius: 2 * sc; color: "#ba68c8" }
                Label { text: "场景"; color: "#ba68c8"; font.pixelSize: 10 * sc }
                Rectangle { width: 10 * sc; height: 10 * sc; radius: 2 * sc; color: "#4db6ac" }
                Label { text: "设备"; color: "#4db6ac"; font.pixelSize: 10 * sc }
                Rectangle { width: 10 * sc; height: 10 * sc; radius: 2 * sc; color: "#ef5350" }
                Label { text: "告警"; color: "#ef5350"; font.pixelSize: 10 * sc }

                Item { width: 8 * sc }

                Label { text: "ℹ️ INFO"; color: "#4fc3f7"; font.pixelSize: 10 * sc }
                Label { text: "⚠️ WARN"; color: "#ffb74d"; font.pixelSize: 10 * sc }
                Label { text: "❌ ERROR"; color: "#ef5350"; font.pixelSize: 10 * sc }
            }
        }
    }

    property int filterLevel: -1

    function refreshLogs() {
        var logs = DatabaseManager.getConnectionLogs(5000)

        if (filterModule !== "全部") {
            var moduleMap = {
                "🖥️ 系统": "[SYSTEM]",
                "📡 UDP": "[UDP]",
                "🔌 TCP": "[TCP]",
                "🎤 语音": "[VOICE]",
                "🌡️ 传感器": "[SENSOR]",
                "🎬 场景": "[SCENE]",
                "📱 设备": "[DEVICE]",
                "⚠️ 告警": "[ALERT]"
            }
            var prefix = moduleMap[filterModule]
            if (prefix) {
                var filtered = []
                for (var i = 0; i < logs.length; i++) {
                    if (logs[i].log_message && logs[i].log_message.indexOf(prefix) === 0) {
                        filtered.push(logs[i])
                    }
                }
                logs = filtered
            }
        }

        if (filterLevel >= 0) {
            var levelMap = ["INFO", "WARN", "ERROR", "DEBUG"]
            var targetLevel = levelMap[filterLevel]
            if (targetLevel) {
                var levelFiltered = []
                for (var j = 0; j < logs.length; j++) {
                    if (logs[j].log_message && logs[j].log_message.indexOf("[" + targetLevel + "]") >= 0) {
                        levelFiltered.push(logs[j])
                    }
                }
                logs = levelFiltered
            }
        }

        if (filterKeyword.length > 0) {
            var keywordFiltered = []
            var keyword = filterKeyword.toLowerCase()
            for (var k = 0; k < logs.length; k++) {
                if (logs[k].log_message && logs[k].log_message.toLowerCase().indexOf(keyword) >= 0) {
                    keywordFiltered.push(logs[k])
                }
            }
            logs = keywordFiltered
        }

        allLogs = logs
    }

    ListView {
        id: logListView
        anchors.fill: parent
        anchors.topMargin: logPage.header.height
        model: allLogs
        spacing: 6 * sc

        delegate: LogCard {
            width: ListView.view.width - 16 * sc
            logMessage: modelData.log_message
            logTimestamp: modelData.log_timestamp
        }

        Label {
            anchors.centerIn: parent
            text: qsTr("暂无日志记录")
            color: "grey"
            font.pixelSize: 14 * sc
            visible: allLogs.length === 0
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
    }

    Dialog {
        id: confirmClearDialog
        title: qsTr("确认清理")
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        Label {
            text: qsTr("确定要清理所有日志吗？此操作不可撤销。")
            wrapMode: Text.Wrap
        }

        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: {
            DatabaseManager.clearConnectionLogs()
            refreshLogs()
        }
    }
}
