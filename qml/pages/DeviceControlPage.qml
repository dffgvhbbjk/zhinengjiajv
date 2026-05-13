import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

Page {
    id: root

    title: qsTr("设备控制")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property string selectedRoom: qsTr("全部房间")
    property string selectedType: qsTr("全部类型")
    property var selectedDevices: []
    property var pendingCommands: ({})
    property bool _refreshing: false
    property int _selectionVersion: 0
    property var _deviceDataCache: ({})
    property int _dataCacheVersion: 0

    signal backRequested

    Component.onCompleted: {
        _refreshing = true;
        DeviceModel.load();
        refreshDeviceList();
        roomCombo.currentIndex = 0;
        typeCombo.currentIndex = 0;
        _refreshing = false;
    }

    Connections {
        target: DeviceModel

        function onCountChanged() {
            if (_refreshing)
                return;
            refreshDeviceList();
        }
    }

    Connections {
        target: TcpController

        function onCommandSuccess(commandId, message) {
            if (root.pendingCommands[commandId]) {
                snackbar.show(qsTr("✅ 成功: %1").arg(message));
                delete root.pendingCommands[commandId];
            }
        }

        function onCommandFailed(commandId, errorString) {
            if (root.pendingCommands[commandId]) {
                snackbar.show(qsTr("❌ 失败: %1").arg(errorString));
                delete root.pendingCommands[commandId];
                _refreshing = true;
                DeviceModel.load();
                _refreshing = false;
            }
        }
    }

    Connections {
        target: UdpDiscoverer

        function onDataReceived(deviceId, data) {
            var obj = root._deviceDataCache[deviceId];
            if (!obj) {
                obj = ({});
                root._deviceDataCache[deviceId] = obj;
            }
            var keys = Object.keys(data);
            for (var k = 0; k < keys.length; k++) {
                obj[keys[k]] = data[keys[k]];
            }
            root._dataCacheVersion = root._dataCacheVersion + 1;
        }
    }

    function refreshDeviceList() {
        if (_refreshing)
            return;
        _refreshing = true;
        DeviceModel.filterByRoom(root.selectedRoom === qsTr("全部房间") ? "" : root.selectedRoom);
        DeviceModel.filterByType(root.selectedType === qsTr("全部类型") ? "" : root.selectedType);
        _refreshing = false;
    }

    function getDeviceIcon(deviceType) {
        var canonicalIcons = {
            "智能灯": "💡", "light": "💡",
            "空调": "❄️", "ac": "❄️",
            "智能插座": "🔌", "socket": "🔌",
            "窗帘": "🪟", "curtain": "🪟",
            "door": "🚪", "门": "🚪",
            "fan": "🌀", "风扇": "🌀",
            "humidifier": "💧", "加湿器": "💧",
            "buzzer": "🔔", "蜂鸣器": "🔔",
            "master_switch": "⚡", "总控": "⚡",
            "gateway": "🏠", "网关": "🏠"
        };
        if (canonicalIcons[deviceType])
            return canonicalIcons[deviceType];

        var fallbackIcons = ["⚙️", "📡", "🔋", "🎧", "🛜", "👀", "🔑", "🌡️"];
        var h = _hashString(deviceType);
        return fallbackIcons[((h % fallbackIcons.length) + fallbackIcons.length) % fallbackIcons.length];
    }

    property var _canonicalColors: ({
            "智能灯": "#FFD54F", "light": "#FFD54F",
            "空调": "#4FC3F7", "ac": "#4FC3F7",
            "智能插座": "#FFB74D", "socket": "#FFB74D",
            "窗帘": "#CE93D8", "curtain": "#CE93D8",
            "door": "#8D6E63", "门": "#8D6E63",
            "fan": "#4DD0E1", "风扇": "#4DD0E1",
            "humidifier": "#81D4FA", "加湿器": "#81D4FA",
            "buzzer": "#EF5350", "蜂鸣器": "#EF5350",
            "master_switch": "#FFD740", "总控": "#FFD740",
            "gateway": "#78909C", "网关": "#78909C"
        })

    function _hashString(str) {
        var hash = 0;
        for (var i = 0; i < str.length; i++) {
            hash = ((hash << 5) - hash) + str.charCodeAt(i);
            hash |= 0;
        }
        return hash;
    }

    function _generateDeviceColor(typeName) {
        if (_canonicalColors[typeName])
            return _canonicalColors[typeName];

        var hash = _hashString(typeName);
        var hue = ((Math.abs(hash) * 0.618033988749895) % 1.0) * 360;
        var r, g, b;
        var c = 0.38;
        var x = c * (1 - Math.abs((hue / 60) % 2 - 1));
        var m = 0.38;
        if (hue < 60) {
            r = c; g = x; b = 0;
        } else if (hue < 120) {
            r = x; g = c; b = 0;
        } else if (hue < 180) {
            r = 0; g = c; b = x;
        } else if (hue < 240) {
            r = 0; g = x; b = c;
        } else if (hue < 300) {
            r = x; g = 0; b = c;
        } else {
            r = c; g = 0; b = x;
        }
        var toHex = function (v) {
            return ("0" + Math.round((v + m) * 255).toString(16)).slice(-2);
        };
        return "#" + toHex(r) + toHex(g) + toHex(b);
    }

    function _generateGradientBase(typeName) {
        var hash = _hashString(typeName);
        var r = (((Math.abs(hash) * 0.618033988749895) % 1.0) * 0.15 + 0.06).toFixed(2);
        var g = (((Math.abs(hash * 3) * 0.618033988749895) % 1.0) * 0.15 + 0.06).toFixed(2);
        var b = (((Math.abs(hash * 7) * 0.618033988749895) % 1.0) * 0.15 + 0.08).toFixed(2);
        return [r, g, b];
    }

    function _toHexChannel(raw) {
        return ("0" + Math.round(parseFloat(raw) * 255).toString(16)).slice(-2);
    }

    property var _gradientCache: ({})

    function _getOrCalcGradient(typeName) {
        if (_gradientCache[typeName])
            return _gradientCache[typeName];
        var base = _generateGradientBase(typeName);
        var idx = Math.abs(_hashString(typeName + "shift")) % 3;
        base[idx] = (parseFloat(base[idx]) + 0.07).toFixed(2);
        var endColor = "#" + _toHexChannel(base[0]) + _toHexChannel(base[1]) + _toHexChannel(base[2]);
        base[idx] = (parseFloat(base[idx]) - 0.07).toFixed(2);
        var startColor = "#" + _toHexChannel(base[0]) + _toHexChannel(base[1]) + _toHexChannel(base[2]);
        _gradientCache[typeName] = [startColor, endColor];
        return _gradientCache[typeName];
    }

    function getDeviceTypeColor(deviceType) {
        return _generateDeviceColor(deviceType);
    }

    function getDeviceGradientStart(deviceType, isOnline) {
        if (!isOnline)
            return "#1a1a24";
        return _getOrCalcGradient(deviceType)[0];
    }

    function getDeviceGradientEnd(deviceType, isOnline) {
        if (!isOnline)
            return "#22222e";
        return _getOrCalcGradient(deviceType)[1];
    }

    function sendDeviceCommand(deviceId, action) {
        var commandId = "cmd_" + new Date().getTime();
        root.pendingCommands[commandId] = {
            "deviceId": deviceId,
            "action": action
        };
        TcpController.sendControlCommand(commandId, deviceId, action);
    }

    function toggleDeviceSelection(deviceId) {
        var newList = root.selectedDevices.slice();
        var idx = newList.indexOf(deviceId);
        if (idx >= 0) {
            newList.splice(idx, 1);
        } else {
            newList.push(deviceId);
        }
        root.selectedDevices = newList;
        _selectionVersion++;
    }

    function selectAllDevices() {
        var newSelected = [];
        for (var i = 0; i < DeviceModel.count; i++) {
            newSelected.push(DeviceModel.deviceIdAt(i));
        }
        root.selectedDevices = newSelected;
        _selectionVersion++;
    }

    function deselectAllDevices() {
        root.selectedDevices = [];
        _selectionVersion++;
    }

    function isDeviceSelected(deviceId) {
        return root.selectedDevices.indexOf(deviceId) >= 0;
    }

    function batchControl(action) {
        if (root.selectedDevices.length === 0) {
            snackbar.show(qsTr("⚠️ 请先选择设备"));
            return;
        }
        for (var i = 0; i < root.selectedDevices.length; i++) {
            sendDeviceCommand(root.selectedDevices[i], action);
        }
        snackbar.show(qsTr("📥 已向 %1 个设备发送指令").arg(root.selectedDevices.length));
    }

    Dialog {
        id: batchDeleteDialog
        title: qsTr("确认批量删除")
        property alias text: batchDeleteContent.text
        modal: true
        width: 400 * sc
        height: 240 * sc
        anchors.centerIn: parent

        background: Rectangle {
            radius: 16 * sc
            color: "#1e1e30"
            border.color: "#3a2a2a"
            border.width: 1.5
        }

        header: Rectangle {
            width: parent.width
            height: 50 * sc
            radius: 16 * sc
            color: "transparent"

            Label {
                anchors.centerIn: parent
                text: parent.parent.title
                font.pixelSize: 17 * sc
                font.bold: true
                color: "#FF5252"
            }
        }

        footer: RowLayout {
            width: parent.width
            spacing: 12 * sc
            Layout.alignment: Qt.AlignRight

            Rectangle {
                width: 90 * sc
                height: 38 * sc
                radius: 8 * sc
                color: "#33334a"
                border.color: "#444455"
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    text: qsTr("取消")
                    font.pixelSize: 14 * sc
                    font.weight: Font.DemiBold
                    color: "#B0BEC5"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: batchDeleteDialog.close()

                    Rectangle {
                        anchors.fill: parent
                        radius: 8 * sc
                        color: "#ffffff"
                        opacity: parent.pressed ? 0.12 : (parent.containsMouse ? 0.06 : 0)
                    }
                }
            }

            Rectangle {
                width: 90 * sc
                height: 38 * sc
                radius: 8 * sc
                color: batchDeleteBtnArea.pressed ? "#b71c1c" : (batchDeleteBtnArea.containsMouse ? "#d32f2f" : "#c62828")
                Material.elevation: 4

                Label {
                    anchors.centerIn: parent
                    text: qsTr("删除")
                    font.pixelSize: 14 * sc
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }

                MouseArea {
                    id: batchDeleteBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        DeviceModel.deleteMultipleDevices(root.selectedDevices);
                        deselectAllDevices();
                        _refreshing = true;
                        DeviceModel.load();
                        _refreshing = false;
                        refreshDeviceList();
                        batchDeleteDialog.close();
                        snackbar.show(qsTr("已批量删除选中设备"));
                    }
                }
            }
        }

        Label {
            id: batchDeleteContent
            anchors.fill: parent
            color: "#e0e0e0"
            font.pixelSize: 14 * sc
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f1118" }
            GradientStop { position: 0.5; color: "#141620" }
            GradientStop { position: 1.0; color: "#1a1c28" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16 * sc
        spacing: 14 * sc

        Item {
            id: headerArea
            Layout.fillWidth: true
            Layout.preferredHeight: 72 * sc

            RowLayout {
                anchors.fill: parent
                spacing: 14 * sc

                RoundIconButton {
                    iconText: "←"
                    tooltipText: qsTr("返回首页")
                    bgColor: "#2a2a40"
                    onClicked: root.backRequested()
                }

                ColumnLayout {
                    spacing: 2 * sc

                    Label {
                        text: qsTr("设备控制中心")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Label {
                        text: DeviceModel.count > 0 ? qsTr("共 %1 台设备").arg(DeviceModel.count) : qsTr("暂无设备")
                        font.pixelSize: 14 * sc
                        color: DeviceModel.count > 0 ? "#B0BEC5" : "#EF5350"
                        font.bold: DeviceModel.count === 0
                    }
                }

                Item { Layout.fillWidth: true }

                ComboBox {
                    id: statusCombo
                    Layout.preferredWidth: 120 * sc
                    Layout.preferredHeight: 36 * sc
                    model: [qsTr("全部状态"), qsTr("在线"), qsTr("离线")]
                    currentIndex: 0

                    background: Rectangle {
                        radius: 8 * sc
                        color: "#1e1e32"
                        border.color: statusCombo.activeFocus ? "#455a64" : (statusCombo.hovered ? "#455a64" : "#333344")
                        border.width: 1
                    }

                    contentItem: Label {
                        text: statusCombo.displayText
                        color: "#e0e0e0"
                        font.pixelSize: 13 * sc
                        leftPadding: 12 * sc
                        verticalAlignment: Text.AlignVCenter
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) {
                            if (currentIndex === 0)
                                DeviceModel.clearStatusFilter();
                            else
                                DeviceModel.filterByStatus(currentIndex === 1);
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: 24 * sc
                    radius: 1
                    color: "#333344"
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: qsTr("🏠")
                    font.pixelSize: 16 * sc
                    color: DeviceModel.count > 0 ? "#90A4AE" : "#555566"
                    Layout.alignment: Qt.AlignVCenter
                }

                ComboBox {
                    id: roomCombo
                    Layout.preferredWidth: 110 * sc
                    Layout.preferredHeight: 36 * sc
                    currentIndex: 0
                    model: [qsTr("全部房间"), qsTr("客厅"), qsTr("卧室"), qsTr("厨房"), qsTr("书房"), qsTr("浴室")]

                    background: Rectangle {
                        radius: 8 * sc
                        color: "#1e1e32"
                        border.color: roomCombo.activeFocus ? "#455a64" : (roomCombo.hovered ? "#455a64" : "#333344")
                        border.width: 1
                    }

                    contentItem: Label {
                        text: roomCombo.displayText
                        color: "#e0e0e0"
                        font.pixelSize: 13 * sc
                        leftPadding: 12 * sc
                        verticalAlignment: Text.AlignVCenter
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) {
                            root.selectedRoom = model[currentIndex];
                            refreshDeviceList();
                        }
                    }
                }

                Label {
                    text: qsTr("🔄")
                    font.pixelSize: 16 * sc
                    color: DeviceModel.count > 0 ? "#90A4AE" : "#555566"
                    Layout.alignment: Qt.AlignVCenter
                }

                ComboBox {
                    id: typeCombo
                    Layout.preferredWidth: 110 * sc
                    Layout.preferredHeight: 36 * sc
                    currentIndex: 0
                    model: [qsTr("全部类型"), qsTr("智能灯"), qsTr("空调"), qsTr("智能插座"), qsTr("窗帘"), qsTr("门"), qsTr("风扇"), qsTr("加湿器"), qsTr("蜂鸣器"), qsTr("总控")]

                    background: Rectangle {
                        radius: 8 * sc
                        color: "#1e1e32"
                        border.color: typeCombo.activeFocus ? "#455a64" : (typeCombo.hovered ? "#455a64" : "#333344")
                        border.width: 1
                    }

                    contentItem: Label {
                        text: typeCombo.displayText
                        color: "#e0e0e0"
                        font.pixelSize: 13 * sc
                        leftPadding: 12 * sc
                        verticalAlignment: Text.AlignVCenter
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) {
                            root.selectedType = model[currentIndex];
                            var typeMap = {"智能灯": "light", "空调": "ac", "智能插座": "socket", "窗帘": "curtain",
                                           "门": "door", "风扇": "fan", "加湿器": "humidifier", "蜂鸣器": "buzzer", "总控": "master_switch"};
                            var filterType = model[currentIndex] === qsTr("全部类型") ? "" : (typeMap[model[currentIndex]] || model[currentIndex]);
                            root.selectedType = filterType;
                            refreshDeviceList();
                        }
                    }
                }

                Rectangle {
                    width: 60 * sc
                    height: 36 * sc
                    radius: 8 * sc
                    color: refreshBtnArea.pressed ? "#2a2a44" : (refreshBtnArea.containsMouse ? "#252540" : "#1e1e32")
                    border.color: "#3a3a4e"
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        id: refreshIcon
                        anchors.centerIn: parent
                        text: "↻"
                        font.pixelSize: 16 * sc
                        color: "#90A4AE"

                        SequentialAnimation on rotation {
                            id: refreshAnim
                            running: false
                            NumberAnimation {
                                from: 0; to: 360; duration: 600; easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        id: refreshBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            _refreshing = true;
                            DeviceModel.load();
                            _refreshing = false;
                            refreshDeviceList();
                            refreshAnim.start();
                            snackbar.show(qsTr("🔄 已刷新设备列表"));
                        }
                    }
                }
            }
        }

        Rectangle {
            id: gridContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            GridView {
                id: deviceGridView
                anchors.fill: parent
                cellWidth: width / 2
                cellHeight: 240 * sc
                model: DeviceModel
                clip: true

                delegate: Rectangle {
                    id: deviceCard
                    width: (deviceGridView.width / 2) - 14 * sc
                    height: 228 * sc
                    radius: 18 * sc
                    clip: true

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: getDeviceGradientStart(model.deviceType || "", model.status || false)
                        }
                        GradientStop {
                            position: 1.0
                            color: getDeviceGradientEnd(model.deviceType || "", model.status || false)
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 5 * sc
                        radius: 4 * sc
                        color: getDeviceTypeColor(model.deviceType || "")
                        opacity: model.status ? 1.0 : 0.3
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12 * sc
                        width: (model.deviceType || "").length * 12 * sc + 12 * sc
                        height: 22 * sc
                        radius: 6 * sc
                        color: getDeviceTypeColor(model.deviceType || "")
                        opacity: 0.12

                        Label {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: model.deviceType || ""
                            font.pixelSize: 10 * sc
                            font.weight: Font.Medium
                            color: getDeviceTypeColor(model.deviceType || "")
                            opacity: 0.85
                        }
                    }

                    MouseArea {
                        id: cardMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14 * sc
                        spacing: 10 * sc

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12 * sc

                            Rectangle {
                                width: 52 * sc
                                height: 52 * sc
                                radius: 14 * sc
                                color: getDeviceTypeColor(model.deviceType || "")
                                opacity: model.status ? 0.18 : 0.08

                                Label {
                                    anchors.centerIn: parent
                                    text: getDeviceIcon(model.deviceType || "")
                                    font.pixelSize: 26 * sc
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: -2 * sc
                                    width: 14 * sc
                                    height: 14 * sc
                                    radius: 7 * sc
                                    color: model.status ? "#4CAF50" : "#616161"
                                    border.color: getDeviceGradientEnd(model.deviceType || "", true)
                                    border.width: 2
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3 * sc

                                Label {
                                    text: model.deviceName || qsTr("未命名设备")
                                    font.bold: true
                                    font.pixelSize: 16 * sc
                                    color: "#ffffff"
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    spacing: 8 * sc

                                    Rectangle {
                                        width: model.status ? 52 * sc : 40 * sc
                                        height: 22 * sc
                                        radius: 11 * sc
                                        color: model.status ? "#1b3a1b" : "#3a1b1b"

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4 * sc

                                            Rectangle {
                                                width: 7 * sc
                                                height: 7 * sc
                                                radius: 3.5 * sc
                                                color: model.status ? "#4CAF50" : "#EF5350"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Label {
                                                text: model.status ? qsTr("在线") : qsTr("离线")
                                                font.pixelSize: 11 * sc
                                                font.weight: Font.DemiBold
                                                color: model.status ? "#81C784" : "#EF9A9A"
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 3 * sc; height: 3 * sc; radius: 1.5 * sc
                                        color: "#555566"
                                        visible: (model.room || "") !== ""
                                    }

                                    Label {
                                        text: model.room || ""
                                        font.pixelSize: 11 * sc
                                        color: "#78909C"
                                        visible: (model.room || "") !== ""
                                    }
                                }
                            }

                            Rectangle {
                                id: selectionBox
                                width: 32 * sc; height: 32 * sc; radius: 4 * sc
                                property int selVer: root._selectionVersion
                                property bool isSelected: root.isDeviceSelected(model.deviceId || "")
                                color: isSelected ? "#1565C0" : "transparent"
                                border.color: isSelected ? "#42A5F5" : "#555566"
                                border.width: 2

                                Label {
                                    anchors.centerIn: parent
                                    text: parent.isSelected ? "✓" : ""
                                    font.pixelSize: 16 * sc
                                    font.bold: true
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: toggleDeviceSelection(model.deviceId)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 4 * sc
                                        color: "#ffffff"
                                        opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.1 : 0)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12 * sc
                            color: "#000000"
                            opacity: 0.06
                            clip: true

                            Loader {
                                id: controlLoader
                                anchors.fill: parent
                                anchors.margins: 8 * sc

                                property string currentDeviceId: model.deviceId || ""
                                property bool isOnline: model.status || false
                                property string deviceTypeStr: model.deviceType || ""
                                property var deviceData: {
                                    root._dataCacheVersion;
                                    return root._deviceDataCache[model.deviceId || ""] || ({});
                                }

                                Component.onCompleted: {
                                    var comp = root._controlRegistry[model.deviceType || ""];
                                    sourceComponent = comp || defaultControlComponent;
                                }
                                onItemChanged: {
                                    if (item) {
                                        item.loaderObj = controlLoader;
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 18 * sc
                        color: "#1a0a0a"
                        opacity: 0.85
                        visible: !model.status

                        Rectangle {
                            anchors.centerIn: parent
                            width: 190 * sc
                            height: 48 * sc
                            radius: 24 * sc
                            color: "#2a1515"
                            border.color: "#EF5350"
                            border.width: 2

                            Row {
                                anchors.centerIn: parent
                                spacing: 8 * sc

                                Rectangle {
                                    width: 10 * sc; height: 10 * sc; radius: 5 * sc
                                    color: "#EF5350"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Label {
                                    text: qsTr("设备离线 · 不可操作")
                                    font.pixelSize: 13 * sc
                                    font.bold: true
                                    color: "#EF9A9A"
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.7, 460 * sc)
                    height: 280 * sc
                    radius: 20 * sc
                    color: "#18182a"
                    border.color: "#2a2a3e"
                    border.width: 2
                    visible: DeviceModel.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 16 * sc

                        Rectangle {
                            width: 80 * sc; height: 80 * sc; radius: 40 * sc
                            color: "#252540"
                            Layout.alignment: Qt.AlignHCenter

                            Label {
                                anchors.centerIn: parent
                                text: "📱"
                                font.pixelSize: 40 * sc
                            }
                        }

                        Label {
                            text: qsTr("暂无设备")
                            font.pixelSize: 22 * sc
                            font.bold: true
                            color: "#E0E0E0"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Label {
                            text: qsTr("请添加设备或检查网络连接")
                            font.pixelSize: 14 * sc
                            color: "#90A4AE"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 160 * sc; height: 44 * sc; radius: 22 * sc
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#1976D2" }
                                GradientStop { position: 1.0; color: "#1565C0" }
                            }
                            Material.elevation: 6

                            Row {
                                anchors.centerIn: parent
                                spacing: 8 * sc

                                Label {
                                    text: "+"
                                    font.pixelSize: 20 * sc
                                    font.bold: true
                                    color: "#ffffff"
                                }
                                Label {
                                    text: qsTr("添加设备")
                                    font.pixelSize: 15 * sc
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: snackbar.show(qsTr("请通过设置页面添加新设备"))

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 22 * sc
                                    color: "#ffffff"
                                    opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.1 : 0)
                                }
                            }
                        }

                        Label {
                            text: qsTr("提示：设备连接后会自动出现在此处")
                            font.pixelSize: 12 * sc
                            color: "#607D8B"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }

        Rectangle {
            id: batchToolbar
            Layout.fillWidth: true
            Layout.preferredHeight: 56 * sc
            radius: 12 * sc
            color: "#1e1e30"
            Material.elevation: 6
            border.color: "#2e2e44"
            border.width: 1
            visible: DeviceModel.count > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14 * sc
                anchors.rightMargin: 14 * sc
                spacing: 10 * sc

                ToolBtn {
                    btnIcon: "✓"
                    btnText: qsTr("全选")
                    btnAccent: "#66BB6A"
                    btnBgColor: "#1b3a1b"
                    onBtnClicked: selectAllDevices()
                }
                ToolBtn {
                    btnIcon: "✕"
                    btnText: qsTr("取消")
                    btnAccent: "#EF5350"
                    btnBgColor: "#3a1b1b"
                    onBtnClicked: deselectAllDevices()
                }

                Rectangle {
                    width: 1; height: 28 * sc; radius: 0.5; color: "#3a3a50"
                }

                ToolBtn {
                    btnIcon: "🟢"
                    btnText: qsTr("批量开启")
                    btnAccent: "#81C784"
                    btnBgColor: "#1b3a1b"
                    btnEnabled: root.selectedDevices.length > 0
                    onBtnClicked: batchControl("turn_on")
                }
                ToolBtn {
                    btnIcon: "🔴"
                    btnText: qsTr("批量关闭")
                    btnAccent: "#E57373"
                    btnBgColor: "#3a1b1b"
                    btnEnabled: root.selectedDevices.length > 0
                    onBtnClicked: batchControl("turn_off")
                }

                Rectangle {
                    width: 1; height: 28 * sc; radius: 0.5; color: "#5a3a3a"
                }

                ToolBtn {
                    btnIcon: "🗑️"
                    btnText: qsTr("批量删除")
                    btnAccent: "#FF5252"
                    btnBgColor: "#4a1a1a"
                    btnEnabled: root.selectedDevices.length > 0
                    onBtnClicked: {
                        batchDeleteDialog.text = qsTr("确定删除选中的 %1 个设备吗?\n此操作将同时删除设备相关的历史和告警数据").arg(root.selectedDevices.length);
                        batchDeleteDialog.open();
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 100 * sc; height: 28 * sc; radius: 14 * sc
                    color: root.selectedDevices.length > 0 ? "#1565C0" : "#2a2a40"
                    border.color: root.selectedDevices.length > 0 ? "#1976D2" : "#3a3a50"
                    border.width: 1

                    Label {
                        id: selectBadge
                        anchors.centerIn: parent
                        text: {
                            var _ver = root._selectionVersion;
                            return root.selectedDevices.length > 0 ? qsTr("☑ %1 已选").arg(root.selectedDevices.length) : qsTr("□ 0 已选");
                        }
                        font.pixelSize: 12 * sc
                        font.weight: Font.DemiBold
                        color: root.selectedDevices.length > 0 ? "#90CAF9" : "#78909C"
                    }
                }
            }
        }
    }

    component RoundIconButton: Rectangle {
        property string iconText: ""
        property string tooltipText: ""
        property string bgColor: "#2a2a3e"
        property string iconColor: "#ffffff"
        signal clicked

        width: 42 * sc; height: 42 * sc; radius: 21 * sc
        color: bgColor
        Material.elevation: 4

        Label {
            anchors.centerIn: parent
            text: parent.iconText
            font.pixelSize: 18 * sc
            color: parent.iconColor
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()

            Rectangle {
                anchors.fill: parent
                radius: 21 * sc
                color: "#ffffff"
                opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0)
            }
        }
    }

    component ToolBtn: Rectangle {
        property string btnText: ""
        property string btnIcon: ""
        property string btnBgColor: "#33334a"
        property string btnAccent: "#888899"
        property bool btnEnabled: true
        signal btnClicked

        width: btnText !== "" ? btnText.length * 14 * sc + (btnIcon !== "" ? 36 * sc : 20 * sc) : 36 * sc
        height: 36 * sc
        radius: 8 * sc
        color: toolBtnMouse.pressed ? btnAccent : (btnEnabled ? btnBgColor : "#222233")
        opacity: btnEnabled ? 1.0 : 0.4
        Material.elevation: toolBtnMouse.containsMouse && btnEnabled ? 4 : 0

        RowLayout {
            anchors.centerIn: parent
            spacing: 6 * sc

            Label {
                text: btnIcon
                font.pixelSize: 15 * sc
                visible: btnIcon !== ""
                color: btnAccent
            }
            Label {
                id: btnLabel
                text: btnText
                font.pixelSize: 13 * sc
                font.weight: Font.DemiBold
                visible: btnText !== ""
                color: btnAccent
            }
        }

        MouseArea {
            id: toolBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btnEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btnEnabled) btnClicked()

            Rectangle {
                anchors.fill: parent
                radius: 8 * sc
                color: "#ffffff"
                opacity: toolBtnMouse.pressed ? 0.12 : (toolBtnMouse.containsMouse && parent.parent.btnEnabled ? 0.06 : 0)
            }
        }
    }

    component LightControl: ColumnLayout {
        property var loaderObj: null
        property bool isPowerOn: false
        property int brightnessValue: 70
        property real temperatureValue: 5000

        spacing: 10 * sc

        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * sc

            Rectangle {
                width: 46 * sc; height: 26 * sc; radius: 13 * sc
                color: isPowerOn ? "#FFD54F" : "#3a3a4a"
                border.color: isPowerOn ? "#FFC107" : "#4a4a5a"
                border.width: 2

                Rectangle {
                    x: isPowerOn ? parent.width - height - 2 : 2
                    y: 2
                    width: 22 * sc; height: 22 * sc; radius: 11 * sc
                    color: isPowerOn ? "#ffffff" : "#888899"
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: loaderObj ? loaderObj.isOnline : false
                    onClicked: {
                        isPowerOn = !isPowerOn;
                        sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", isPowerOn ? "light_on" : "light_off");
                    }
                }
            }

            Label {
                text: isPowerOn ? qsTr("● 已开启") : qsTr("○ 已关闭")
                font.pixelSize: 13 * sc
                font.weight: Font.DemiBold
                color: isPowerOn ? "#FFD54F" : "#90A4AE"
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("%1%").arg(brightnessValue)
                font.pixelSize: 16 * sc
                font.bold: true
                color: isPowerOn ? "#FFD54F" : "#607D8B"
            }
        }

        Slider {
            id: brightSlider
            Layout.fillWidth: true
            from: 0; to: 100
            live: false
            value: brightnessValue
            Material.accent: "#FFD54F"
            onMoved: {
                brightnessValue = Math.round(value);
                if (!isPowerOn) {
                    isPowerOn = true;
                    sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "light_on");
                }
                sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "brightness_" + brightnessValue);
            }

            background: Rectangle {
                x: brightSlider.leftPadding
                y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                implicitWidth: 200; implicitHeight: 6 * sc
                width: brightSlider.availableWidth; height: implicitHeight
                radius: 3 * sc; color: "#3a3a50"

                Rectangle {
                    width: brightSlider.visualPosition * parent.width
                    height: parent.height
                    color: isPowerOn ? "#FFD54F" : "#555566"
                    radius: 3 * sc
                }
            }

            handle: Rectangle {
                x: brightSlider.leftPadding + brightSlider.visualPosition * (brightSlider.availableWidth - width)
                y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                implicitWidth: 22 * sc; implicitHeight: 22 * sc; radius: 11 * sc
                color: isPowerOn ? "#FFD54F" : "#888899"
                border.color: "#ffffff"; border.width: 2
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * sc

            Label {
                text: qsTr("色温")
                font.pixelSize: 11 * sc
                color: "#90A4AE"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 24 * sc; radius: 12 * sc
                color: "#151520"
                border.color: "#2a2a3a"; border.width: 1

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#FFECB3" }
                    GradientStop { position: 0.5; color: "#FFFDE7" }
                    GradientStop { position: 1.0; color: "#B3E5FC" }
                }

                Rectangle {
                    x: Math.min(Math.max((parent.width * ((temperatureValue - 2700) / 5300)) - 3, 0), parent.width - 6)
                    y: -2
                    width: 6; height: parent.height + 4; radius: 3
                    color: "#ffffff"; border.color: "#cccccc"; border.width: 1
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: function (mouse) {
                        var ratio = Math.max(0, Math.min(1, mouse.x / parent.width));
                        temperatureValue = 2700 + ratio * 5300;
                        sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "color_temp_" + Math.round(temperatureValue));
                    }
                }
            }

            Label {
                text: Math.round(temperatureValue) + "K"
                font.pixelSize: 12 * sc; font.weight: Font.DemiBold; color: "#B0BEC5"
                Layout.preferredWidth: 48 * sc
            }
        }
    }

    component AcControl: ColumnLayout {
        property var loaderObj: null
        property bool isPowerOn: false
        property int tempValue: 24
        property int modeIndex: 0
        property int fanSpeedValue: 3

        spacing: 8 * sc

        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * sc

            Rectangle {
                width: 46 * sc; height: 26 * sc; radius: 13 * sc
                color: isPowerOn ? "#4FC3F7" : "#3a3a4a"
                border.color: isPowerOn ? "#29B6F6" : "#4a4a5a"
                border.width: 2

                Rectangle {
                    x: isPowerOn ? parent.width - height - 2 : 2
                    y: 2
                    width: 22 * sc; height: 22 * sc; radius: 11 * sc
                    color: isPowerOn ? "#ffffff" : "#888899"
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: loaderObj ? loaderObj.isOnline : false
                    onClicked: {
                        isPowerOn = !isPowerOn;
                        sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", isPowerOn ? "ac_on" : "ac_off");
                    }
                }
            }

            Label {
                text: isPowerOn ? qsTr("● 运行中 %1°C").arg(tempValue) : qsTr("○ 待机")
                font.pixelSize: 13 * sc; font.weight: Font.DemiBold
                color: isPowerOn ? "#4FC3F7" : "#90A4AE"
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * sc

            Label {
                text: qsTr("温度")
                font.pixelSize: 11 * sc; color: "#90A4AE"
            }

            SpinBox {
                id: tempSpin
                from: 16; to: 30
                value: tempValue
                Material.accent: "#4FC3F7"
                onValueModified: {
                    tempValue = value;
                    if (!isPowerOn && loaderObj && loaderObj.isOnline) {
                        isPowerOn = true;
                        sendDeviceCommand(loaderObj.currentDeviceId, "ac_on");
                    }
                    sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "ac_temp_" + value);
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("🌬 风速 %1").arg(fanSpeedValue)
                font.pixelSize: 13 * sc; color: "#81D4FA"; font.weight: Font.DemiBold
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6 * sc

            Repeater {
                model: [
                    { "label": qsTr("❄ 制冷"), "val": 0, "accent": "#4FC3F7" },
                    { "label": qsTr("☀ 制热"), "val": 1, "accent": "#FF8A65" },
                    { "label": qsTr("💧 除湿"), "val": 2, "accent": "#81C784" },
                    { "label": qsTr("🌬 送风"), "val": 3, "accent": "#90A4AE" }
                ]

                Rectangle {
                    width: (modelData.label || "").length * 14 * sc + 20 * sc
                    height: 32 * sc; radius: 8 * sc
                    color: modeIndex === modelData.val ? modelData.accent : "#1e1e32"
                    border.color: modeIndex === modelData.val ? modelData.accent : "#3a3a4a"
                    border.width: 2

                    Label {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 13 * sc; font.weight: Font.DemiBold
                        color: modeIndex === modelData.val ? "#ffffff" : "#78909C"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!isPowerOn && loaderObj && loaderObj.isOnline) {
                                isPowerOn = true;
                                sendDeviceCommand(loaderObj.currentDeviceId, "ac_on");
                            }
                            modeIndex = modelData.val;
                            sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "ac_mode_" + modelData.val);
                        }

                        Rectangle {
                            anchors.fill: parent; radius: 8 * sc; color: "#ffffff"
                            opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.07 : 0)
                        }
                    }
                }
            }
        }

        Slider {
            id: fanSlider
            Layout.fillWidth: true
            from: 1; to: 5; stepSize: 1
            value: fanSpeedValue
            Material.accent: "#4FC3F7"
            onMoved: {
                fanSpeedValue = Math.round(value);
                if (!isPowerOn && loaderObj && loaderObj.isOnline) {
                    isPowerOn = true;
                    sendDeviceCommand(loaderObj.currentDeviceId, "ac_on");
                }
                sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "fan_speed_" + fanSpeedValue);
            }

            background: Rectangle {
                x: fanSlider.leftPadding
                y: fanSlider.topPadding + fanSlider.availableHeight / 2 - height / 2
                implicitWidth: 200; implicitHeight: 6 * sc
                width: fanSlider.availableWidth; height: implicitHeight
                radius: 3 * sc; color: "#3a3a50"

                Rectangle {
                    width: fanSlider.visualPosition * parent.width
                    height: parent.height
                    color: isPowerOn ? "#4FC3F7" : "#555566"
                    radius: 3 * sc
                }
            }

            handle: Rectangle {
                x: fanSlider.leftPadding + fanSlider.visualPosition * (fanSlider.availableWidth - width)
                y: fanSlider.topPadding + fanSlider.availableHeight / 2 - height / 2
                implicitWidth: 22 * sc; implicitHeight: 22 * sc; radius: 11 * sc
                color: isPowerOn ? "#4FC3F7" : "#888899"
                border.color: "#ffffff"; border.width: 2
            }
        }
    }

    component SocketControl: ColumnLayout {
        property var loaderObj: null
        property bool isPowerOn: false
        property real powerValue: 0.0

        spacing: 10 * sc

        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * sc

            Rectangle {
                width: 46 * sc; height: 26 * sc; radius: 13 * sc
                color: isPowerOn ? "#FFB74D" : "#3a3a4a"
                border.color: isPowerOn ? "#FF9800" : "#4a4a5a"
                border.width: 2

                Rectangle {
                    x: isPowerOn ? parent.width - height - 2 : 2
                    y: 2
                    width: 22 * sc; height: 22 * sc; radius: 11 * sc
                    color: isPowerOn ? "#ffffff" : "#888899"
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: loaderObj ? loaderObj.isOnline : false
                    onClicked: {
                        isPowerOn = !isPowerOn;
                        sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", isPowerOn ? "socket_on" : "socket_off");
                    }
                }
            }

            Label {
                text: isPowerOn ? qsTr("● 运行中") : qsTr("○ 待机")
                font.pixelSize: 13 * sc; font.weight: Font.DemiBold
                color: isPowerOn ? "#FFB74D" : "#90A4AE"
            }

            Item { Layout.fillWidth: true }

            Label {
                text: isPowerOn && powerValue > 0 ? qsTr("%1 W").arg(powerValue.toFixed(1)) : qsTr("-- W")
                font.pixelSize: 16 * sc; font.bold: true
                color: isPowerOn ? "#FFB74D" : "#607D8B"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 40 * sc; radius: 10 * sc
            color: "#1a1a28"; border.color: "#3a3a4a"; border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14 * sc; anchors.rightMargin: 14 * sc
                spacing: 8 * sc

                Label { text: "🕛"; font.pixelSize: 15 * sc }
                Label {
                    text: qsTr("定时设置")
                    font.pixelSize: 13 * sc; font.weight: Font.DemiBold; color: "#FFB74D"
                }
                Item { Layout.fillWidth: true }
                Label { text: "›"; font.pixelSize: 14 * sc; color: "#90A4AE" }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!isPowerOn && loaderObj && loaderObj.isOnline) {
                        isPowerOn = true;
                        sendDeviceCommand(loaderObj.currentDeviceId, "socket_on");
                    }
                    sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "socket_timer");
                }

                Rectangle {
                    anchors.fill: parent; radius: 10 * sc; color: "#ffffff"
                    opacity: parent.pressed ? 0.1 : (parent.containsMouse ? 0.05 : 0)
                }
            }
        }
    }

    component CurtainControl: ColumnLayout {
        property var loaderObj: null
        property bool isPowerOn: false
        property int openLevel: 100
        property int curtainMode: 0

        spacing: 10 * sc

        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * sc

            Rectangle {
                width: 46 * sc; height: 26 * sc; radius: 13 * sc
                color: isPowerOn ? "#CE93D8" : "#3a3a4a"
                border.color: isPowerOn ? "#AB47BC" : "#4a4a5a"
                border.width: 2

                Rectangle {
                    x: isPowerOn ? parent.width - height - 2 : 2
                    y: 2
                    width: 22 * sc; height: 22 * sc; radius: 11 * sc
                    color: isPowerOn ? "#ffffff" : "#888899"
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: loaderObj ? loaderObj.isOnline : false
                    onClicked: {
                        isPowerOn = !isPowerOn;
                        sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", isPowerOn ? "curtain_open" : "curtain_close");
                    }
                }
            }

            Label {
                text: isPowerOn ? qsTr("● 已打开") : qsTr("○ 已关闭")
                font.pixelSize: 13 * sc; font.weight: Font.DemiBold
                color: isPowerOn ? "#CE93D8" : "#90A4AE"
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("%1%").arg(openLevel)
                font.pixelSize: 16 * sc; font.bold: true
                color: isPowerOn ? "#CE93D8" : "#607D8B"
            }
        }

        Slider {
            id: curtainSlider
            Layout.fillWidth: true
            from: 0; to: 100
            value: openLevel
            Material.accent: "#CE93D8"
            onMoved: {
                openLevel = Math.round(value);
                if (!isPowerOn) {
                    isPowerOn = true;
                    sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "curtain_open");
                }
                sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "curtain_level_" + openLevel);
            }

            background: Rectangle {
                x: curtainSlider.leftPadding
                y: curtainSlider.topPadding + curtainSlider.availableHeight / 2 - height / 2
                implicitWidth: 200; implicitHeight: 6 * sc
                width: curtainSlider.availableWidth; height: implicitHeight
                radius: 3 * sc; color: "#3a3a50"

                Rectangle {
                    width: curtainSlider.visualPosition * parent.width
                    height: parent.height
                    color: isPowerOn ? "#CE93D8" : "#555566"
                    radius: 3 * sc
                }
            }

            handle: Rectangle {
                x: curtainSlider.leftPadding + curtainSlider.visualPosition * (curtainSlider.availableWidth - width)
                y: curtainSlider.topPadding + curtainSlider.availableHeight / 2 - height / 2
                implicitWidth: 22 * sc; implicitHeight: 22 * sc; radius: 11 * sc
                color: isPowerOn ? "#CE93D8" : "#888899"
                border.color: "#ffffff"; border.width: 2
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * sc

            Repeater {
                model: [
                    { "label": qsTr("✍️ 手动"), "val": 0, "accent": "#CE93D8" },
                    { "label": qsTr("🔄 自动"), "val": 1, "accent": "#81C784" },
                    { "label": qsTr("🕛 定时"), "val": 2, "accent": "#FFB74D" }
                ]

                Rectangle {
                    width: (modelData.label || "").length * 14 * sc + 20 * sc
                    height: 32 * sc; radius: 8 * sc
                    color: curtainMode === modelData.val ? modelData.accent : "#1e1e32"
                    border.color: curtainMode === modelData.val ? modelData.accent : "#3a3a4a"
                    border.width: 2

                    Label {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 13 * sc; font.weight: Font.DemiBold
                        color: curtainMode === modelData.val ? "#ffffff" : "#78909C"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!isPowerOn && loaderObj && loaderObj.isOnline) {
                                isPowerOn = true;
                                sendDeviceCommand(loaderObj.currentDeviceId, "curtain_open");
                            }
                            curtainMode = modelData.val;
                            sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", "curtain_mode_" + modelData.val);
                        }

                        Rectangle {
                            anchors.fill: parent; radius: 8 * sc; color: "#ffffff"
                            opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.07 : 0)
                        }
                    }
                }
            }
        }
    }

    component DoorControl: Item {
        id: doorRoot
        property var loaderObj: null
        property string currentDeviceId: loaderObj ? (loaderObj.currentDeviceId || "") : ""

        width: 280 * sc; height: 580 * sc

        Rectangle {
            anchors.fill: parent; radius: 14 * sc
            color: "#1e222d"; border.color: Qt.rgba(141, 110, 99, 0.6)
        }

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
            anchors.topMargin: 24 * sc; spacing: 18 * sc

            Label {
                text: "🚪"; font.pixelSize: 56 * sc
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 4 * sc
                Label {
                    text: loaderObj ? (loaderObj.currentDeviceName || "未知设备") : "未知设备"
                    font.pixelSize: 16 * sc; font.bold: true; color: "#d7ccc8"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("门")
                    font.pixelSize: 11 * sc; color: "#8d6e63"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("状态: %1").arg(loaderObj && loaderObj.currentStatus ? loaderObj.currentStatus : qsTr("未知"))
                    font.pixelSize: 12 * sc; color: "#a0a0a0"
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6 * sc
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#333" }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 24 * sc
                Rectangle {
                    width: 80 * sc; height: 80 * sc; radius: 10 * sc
                    color: "#4caf50"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { sendDeviceCommand(doorRoot.currentDeviceId, "turn_on"); }
                        Rectangle { anchors.fill: parent; radius: 10 * sc
                            color: "#ffffff"; opacity: parent.pressed ? 0.2 : 0 }
                    }
                    Label { anchors.centerIn: parent; text: qsTr("开"); color: "#ffffff"; font.pixelSize: 20 * sc; font.bold: true }
                }
                Rectangle {
                    width: 80 * sc; height: 80 * sc; radius: 10 * sc
                    color: "#f44336"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { sendDeviceCommand(doorRoot.currentDeviceId, "turn_off"); }
                        Rectangle { anchors.fill: parent; radius: 10 * sc
                            color: "#ffffff"; opacity: parent.pressed ? 0.2 : 0 }
                    }
                    Label { anchors.centerIn: parent; text: qsTr("关"); color: "#ffffff"; font.pixelSize: 20 * sc; font.bold: true }
                }
            }
        }
    }

    component FanControl: Item {
        id: fanRoot
        property var loaderObj: null
        property string currentDeviceId: loaderObj ? (loaderObj.currentDeviceId || "") : ""
        property int currentSpeed: 0

        width: 280 * sc; height: 580 * sc

        Rectangle {
            anchors.fill: parent; radius: 14 * sc
            color: "#1e222d"; border.color: Qt.rgba(77, 208, 225, 0.6)
        }

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
            anchors.topMargin: 24 * sc; spacing: 18 * sc

            Label {
                text: "🌀"; font.pixelSize: 56 * sc
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 4 * sc
                Label {
                    text: loaderObj ? (loaderObj.currentDeviceName || "未知设备") : "未知设备"
                    font.pixelSize: 16 * sc; font.bold: true; color: "#b2ebf2"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("风扇")
                    font.pixelSize: 11 * sc; color: "#4dd0e1"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("档位: %1").arg(fanRoot.currentSpeed)
                    font.pixelSize: 12 * sc; color: "#a0a0a0"
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6 * sc
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#333" }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 10 * sc
                Repeater {
                    model: [0, 1, 2, 3]
                    delegate: Rectangle {
                        width: 52 * sc; height: 52 * sc; radius: 26 * sc
                        color: modelData === 0 ? "#555" : (fanRoot.currentSpeed === modelData ? "#00bcd4" : "#3a3f55")
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                fanRoot.currentSpeed = modelData;
                                var act = modelData === 0 ? "turn_off" : ("speed_" + modelData);
                                sendDeviceCommand(fanRoot.currentDeviceId, act);
                            }
                            Rectangle { anchors.fill: parent; radius: 26 * sc
                                color: "#ffffff"; opacity: parent.pressed ? 0.2 : 0 }
                        }
                        Label {
                            anchors.centerIn: parent
                            text: modelData === 0 ? qsTr("关") : qsTr("%1档").arg(modelData)
                            color: (modelData === 0 || fanRoot.currentSpeed === modelData) ? "#ffffff" : "#aaa"
                            font.pixelSize: 12 * sc; font.bold: modelData !== 0 && fanRoot.currentSpeed === modelData
                        }
                    }
                }
            }
        }
    }

    component HumidifierControl: Item {
        id: humidifierRoot
        property var loaderObj: null
        property string currentDeviceId: loaderObj ? (loaderObj.currentDeviceId || "") : ""
        property bool isOn: false

        width: 280 * sc; height: 580 * sc

        Rectangle {
            anchors.fill: parent; radius: 14 * sc
            color: "#1e222d"; border.color: Qt.rgba(129, 212, 250, 0.6)
        }

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
            anchors.topMargin: 24 * sc; spacing: 18 * sc

            Label {
                text: "💧"; font.pixelSize: 56 * sc
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 4 * sc
                Label {
                    text: loaderObj ? (loaderObj.currentDeviceName || "未知设备") : "未知设备"
                    font.pixelSize: 16 * sc; font.bold: true; color: "#b3e5fc"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("加湿器")
                    font.pixelSize: 11 * sc; color: "#81d4fa"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: humidifierRoot.isOn ? qsTr("已开启") : qsTr("已关闭")
                    font.pixelSize: 12 * sc; color: humidifierRoot.isOn ? "#4fc3f7" : "#888"
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6 * sc
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#333" }

            Switch {
                id: humidifierSwitch
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 120 * sc; Layout.preferredHeight: 48 * sc
                Component.onCompleted: checked = humidifierRoot.isOn
                onToggled: {
                    humidifierRoot.isOn = checked;
                    var act = checked ? "turn_on" : "turn_off";
                    sendDeviceCommand(humidifierRoot.currentDeviceId, act);
                }
            }
        }
    }

    component BuzzerControl: Item {
        id: buzzerRoot
        property var loaderObj: null
        property string currentDeviceId: loaderObj ? (loaderObj.currentDeviceId || "") : ""
        property bool isOn: false

        width: 280 * sc; height: 580 * sc

        Rectangle {
            anchors.fill: parent; radius: 14 * sc
            color: "#1e222d"; border.color: Qt.rgba(239, 83, 80, 0.6)
        }

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
            anchors.topMargin: 24 * sc; spacing: 18 * sc

            Label {
                text: "🔔"; font.pixelSize: 56 * sc
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 4 * sc
                Label {
                    text: loaderObj ? (loaderObj.currentDeviceName || "未知设备") : "未知设备"
                    font.pixelSize: 16 * sc; font.bold: true; color: "#ef9a9a"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("蜂鸣器")
                    font.pixelSize: 11 * sc; color: "#ef5350"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: buzzerRoot.isOn ? qsTr("🔊 鸣响中") : qsTr("静音")
                    font.pixelSize: 12 * sc; color: buzzerRoot.isOn ? "#ef5350" : "#888"
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6 * sc
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#333" }

            Switch {
                id: buzzerSwitch
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 120 * sc; Layout.preferredHeight: 48 * sc
                Component.onCompleted: checked = buzzerRoot.isOn
                onToggled: {
                    buzzerRoot.isOn = checked;
                    var act = checked ? "turn_on" : "turn_off";
                    sendDeviceCommand(buzzerRoot.currentDeviceId, act);
                }
            }
        }
    }

    component MasterSwitchControl: Item {
        id: masterRoot
        property var loaderObj: null
        property string currentDeviceId: loaderObj ? (loaderObj.currentDeviceId || "") : ""
        property bool isOn: false

        width: 280 * sc; height: 580 * sc

        Rectangle {
            anchors.fill: parent; radius: 14 * sc
            color: "#1e222d"; border.color: Qt.rgba(255, 215, 64, 0.6)
        }

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
            anchors.topMargin: 24 * sc; spacing: 18 * sc

            Label {
                text: "⚡"; font.pixelSize: 56 * sc
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 4 * sc
                Label {
                    text: loaderObj ? (loaderObj.currentDeviceName || "未知设备") : "未知设备"
                    font.pixelSize: 16 * sc; font.bold: true; color: "#ffe082"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("全屋总控")
                    font.pixelSize: 11 * sc; color: "#ffd740"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: masterRoot.isOn ? qsTr("全部设备已开启") : qsTr("全部设备已关闭")
                    font.pixelSize: 12 * sc; color: masterRoot.isOn ? "#ffd740" : "#888"
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6 * sc
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#333" }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 24 * sc
                Rectangle {
                    width: 80 * sc; height: 80 * sc; radius: 10 * sc
                    color: "#4caf50"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { masterRoot.isOn = true; sendDeviceCommand(masterRoot.currentDeviceId, "turn_on"); }
                        Rectangle { anchors.fill: parent; radius: 10 * sc
                            color: "#ffffff"; opacity: parent.pressed ? 0.2 : 0 }
                    }
                    Label { anchors.centerIn: parent; text: qsTr("全开"); color: "#ffffff"; font.pixelSize: 16 * sc; font.bold: true }
                }
                Rectangle {
                    width: 80 * sc; height: 80 * sc; radius: 10 * sc
                    color: "#f44336"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { masterRoot.isOn = false; sendDeviceCommand(masterRoot.currentDeviceId, "turn_off"); }
                        Rectangle { anchors.fill: parent; radius: 10 * sc
                            color: "#ffffff"; opacity: parent.pressed ? 0.2 : 0 }
                    }
                    Label { anchors.centerIn: parent; text: qsTr("全关"); color: "#ffffff"; font.pixelSize: 16 * sc; font.bold: true }
                }
            }
        }
    }

    component DefaultControl: ColumnLayout {
        property var loaderObj: null
        property bool isPowerOn: false

        property string _accent: {
            if (!loaderObj || !loaderObj.deviceTypeStr)
                return "#90A4AE";
            return root.getDeviceTypeColor(loaderObj.deviceTypeStr);
        }
        property var _data: loaderObj ? loaderObj.deviceData : ({})
        property var _sensorList: {
            var raw = _data;
            var list = [];
            if (!raw || typeof raw !== "object")
                return list;
            var keys = Object.keys(raw);
            for (var i = 0; i < keys.length; i++) {
                var v = raw[keys[i]];
                if (v !== undefined && v !== null && v !== "" && v !== "--" && typeof v !== "object") {
                    list.push({ "sensorKey": keys[i], "sensorVal": String(v) });
                }
            }
            return list;
        }

        spacing: 6 * sc

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * sc

            Rectangle {
                width: 46 * sc; height: 26 * sc; radius: 13 * sc
                color: isPowerOn ? _accent : "#3a3a4a"
                border.color: isPowerOn ? _accent : "#4a4a5a"
                border.width: 2

                Rectangle {
                    x: isPowerOn ? parent.width - height - 2 : 2
                    y: 2
                    width: 22 * sc; height: 22 * sc; radius: 11 * sc
                    color: isPowerOn ? "#ffffff" : "#888899"
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: loaderObj ? loaderObj.isOnline : false
                    onClicked: {
                        isPowerOn = !isPowerOn;
                        sendDeviceCommand(loaderObj ? loaderObj.currentDeviceId : "", isPowerOn ? "turn_on" : "turn_off");
                    }
                }
            }

            Label {
                text: isPowerOn ? qsTr("● 已开启") : qsTr("○ 待机")
                font.pixelSize: 13 * sc; font.weight: Font.DemiBold
                color: isPowerOn ? _accent : "#90A4AE"
            }

            Item { Layout.fillWidth: true }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5 * sc
            visible: _sensorList.length > 0

            Repeater {
                model: _sensorList

                Rectangle {
                    width: Math.max(54 * sc, (modelData.sensorKey || "").length * 11 * sc + 36 * sc)
                    height: 44 * sc; radius: 8 * sc
                    color: "#151520"; border.color: "#2a2a3a"; border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 2 * sc

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: _fmtSensorLabel(modelData.sensorKey || "")
                            font.pixelSize: 9 * sc; color: "#90A4AE"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: _fmtSensorVal(modelData.sensorKey || "", modelData.sensorVal || "")
                            font.pixelSize: 13 * sc; font.bold: true; color: _accent
                        }
                    }
                }
            }
        }

        function _fmtSensorLabel(key) {
            var m = ({
                "temperature": "🌡 温度", "humidity": "💧 湿度", "pm25": "PM2.5",
                "co2": "CO₂", "power": "⚡ 功率", "voltage": "🔋 电压",
                "current": "🔌 电流", "brightness": "☀ 亮度"
            });
            return m[key] || key;
        }

        function _fmtSensorVal(key, raw) {
            var s = ({
                "temperature": "°C", "humidity": "%", "pm25": " µg/m³",
                "co2": " ppm", "power": " W", "voltage": " V", "current": " A"
            });
            return raw + (s[key] || "");
        }
    }

    property Component lightControlComponent: LightControl {}
    property Component acControlComponent: AcControl {}
    property Component socketControlComponent: SocketControl {}
    property Component curtainControlComponent: CurtainControl {}
    property Component doorControlComponent: DoorControl {}
    property Component fanControlComponent: FanControl {}
    property Component humidifierControlComponent: HumidifierControl {}
    property Component buzzerControlComponent: BuzzerControl {}
    property Component masterSwitchControlComponent: MasterSwitchControl {}
    property Component defaultControlComponent: DefaultControl {}

    property var _controlRegistry: ({
            "智能灯": lightControlComponent, "light": lightControlComponent,
            "空调": acControlComponent, "ac": acControlComponent,
            "智能插座": socketControlComponent, "socket": socketControlComponent,
            "窗帘": curtainControlComponent, "curtain": curtainControlComponent,
            "door": doorControlComponent, "门": doorControlComponent,
            "fan": fanControlComponent, "风扇": fanControlComponent,
            "humidifier": humidifierControlComponent, "加湿器": humidifierControlComponent,
            "buzzer": buzzerControlComponent, "蜂鸣器": buzzerControlComponent,
            "master_switch": masterSwitchControlComponent, "总控": masterSwitchControlComponent
        })

    Rectangle {
        id: snackbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 76 * sc
        width: 300 * sc
        height: 50 * sc
        radius: 25 * sc
        color: "#252538"
        opacity: 0
        visible: opacity > 0
        z: 9999

        Material.elevation: 16
        border.color: "#3a3a52"
        border.width: 1

        Label {
            id: snackbarLabel
            anchors.centerIn: parent
            text: ""
            color: "#eceff1"
            font.pixelSize: 14 * sc
            font.weight: Font.Medium
        }

        Timer {
            id: snackbarTimer
            interval: 2600
            repeat: false
            onTriggered: snackbarHide.start()
        }

        function show(message) {
            snackbarLabel.text = message;
            snackbarShow.start();
            snackbarTimer.restart();
        }

        NumberAnimation {
            id: snackbarShow
            target: snackbar
            property: "opacity"
            to: 1.0
            duration: 280
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: snackbarHide
            target: snackbar
            property: "opacity"
            to: 0.0
            duration: 320
            easing.type: Easing.InCubic
        }
    }
}
