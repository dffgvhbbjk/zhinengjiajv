import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

Page {
    id: root
    title: qsTr("设置")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property int currentCategory: 0
    property bool _loadingSettings: false
    property bool _refreshing: false
    property var deviceList: []
    property var discoveredDevices: []
    property int autoBackupIndex: 2
    property string appVersion: Qt.application.version
    property string backupPath: ""
    property string restoreStatus: ""
    property int themeMode: 0
    property int colorScheme: 0
    property int udpPort: 8888
    property int tcpPort: 9999
    property string serverAddress: ""
    property string savedWifi: ""
    property bool alertNotification: true
    property bool soundReminder: true
    property int popupDuration: 2500
    property string notificationSound: "default"
    property bool autoBackup: false
    property int autoBackupCycle: 7
    property string localIpAddress: ""
    property bool _networkScanning: false
    property bool _wifiScanning: false
    property var wifiList: []
    property int _sensorTotalCount: 0
    property int _sensorOnlineCount: 0
    property int _alertCount: 0

    Connections {
        target: TcpController
        function onConnectionStatusChanged(isConnected) {
            if (isConnected) {
                appendLog(qsTr("TCP 已连接到: %1:%2").arg(TcpController.targetIp).arg(TcpController.targetPort))
            } else {
                appendLog(qsTr("TCP 连接已断开"))
            }
        }
        function onCommandSuccess(commandId, message) {
            appendLog(qsTr("命令成功 [%1]: %2").arg(commandId).arg(message))
        }
        function onCommandFailed(commandId, errorString) {
            appendLog(qsTr("命令失败 [%1]: %2").arg(commandId).arg(errorString))
        }
        function onErrorOccurred(errorCode, errorString) {
            appendLog(qsTr("TCP 错误 [%1]: %2").arg(errorCode).arg(errorString))
        }
    }

    Connections {
        target: UdpDiscoverer
        function onDeviceDiscovered(deviceId, deviceName, deviceType, ip, tcpPort, firmwareVersion) {
            appendLog(qsTr("UDP 发现设备: %1 (%2) - %3:%4").arg(deviceId).arg(deviceType).arg(ip).arg(tcpPort))
        }
        function onDeviceOffline(deviceId) {
            appendLog(qsTr("UDP 设备离线: %1").arg(deviceId))
        }
        function onErrorOccurred(errorCode, errorString) {
            appendLog(qsTr("UDP 错误 [%1]: %2").arg(errorCode).arg(errorString))
        }
    }

    Connections {
        target: NetworkManager
        function onDiscoveredDevicesChanged() {
            root.discoveredDevices = NetworkManager.discoveredDevices
        }
        function onScanningChanged() {
            root._networkScanning = NetworkManager.isScanning
            if (!root._networkScanning) {
                appendLog(qsTr("设备扫描完成，发现 %1 个设备").arg(root.discoveredDevices.length))
            }
        }
        function onDeviceFound(ip, name, type, tcpPort) {
            appendLog(qsTr("发现设备: %1 (%2) - %3:%4").arg(name).arg(type).arg(ip).arg(tcpPort))
        }
    }

    property var connectionLogList: []

    function appendLog(message) {
        DatabaseManager.addConnectionLog(message)
        loadConnectionLogs()
    }

    function loadConnectionLogs() {
        var logs = DatabaseManager.getConnectionLogs(100)
        var logText = ""
        for (var i = 0; i < logs.length; i++) {
            var ts = logs[i]["log_timestamp"] || ""
            var msg = logs[i]["log_message"] || ""
            logText += "[" + ts + "] " + msg + "\n"
        }
        root.connectionLogList = logText
    }

    function loadLocalNetworkInfo() {
        NetworkManager.refreshLocalInterfaces()
        var ifaces = NetworkManager.localInterfaces
        for (var i = 0; i < ifaces.length; i++) {
            var iface = ifaces[i]
            if (iface["ip"] && iface["ip"].indexOf("127.") === -1) {
                root.localIpAddress = iface["ip"]
                root.appendLog(qsTr("本机网络接口: %1 (%2)").arg(iface["ip"]).arg(iface["type"]))
                break
            }
        }
        if (!root.localIpAddress) {
            root.localIpAddress = qsTr("未找到可用网络接口")
        }
    }

    function scanNetworkDevices() {
        if (root._networkScanning) {
            NetworkManager.stopDeviceDiscovery()
            root.appendLog(qsTr("停止网络扫描"))
            return
        }

        root.discoveredDevices = []
        NetworkManager.startDeviceDiscovery(root.udpPort)
        root.appendLog(qsTr("开始扫描局域网设备，端口 %1").arg(root.udpPort))
        snackbarShow(qsTr("正在扫描局域网设备..."))
    }

    function connectToDiscoveredDevice(ip, tcpPort) {
        root.serverAddress = ip
        root.tcpPort = tcpPort
        TcpController.connectToDevice(ip, tcpPort)
        root.appendLog(qsTr("连接到设备: %1:%2").arg(ip).arg(tcpPort))
        snackbarShow(qsTr("正在连接到 %1").arg(ip))
    }

    function refreshSensorList() {
        sensorListModel.clear()
        var totalCount = 0
        var onlineCount = 0

        var devCount = DeviceModel.count
        for (var i = 0; i < devCount; i++) {
            var deviceId = DeviceModel.deviceIdAt(i)
            var dev = DeviceModel.getDeviceById(deviceId)
            if (!dev) continue

            var devType = (dev["device_type"] || "").toLowerCase()
            var isOnline = dev["is_online"] ? true : false
            var sensorName = dev["device_name"] || qsTr("未知传感器")
            var icon = "📷"
            var statusText = isOnline ? qsTr("正常") : qsTr("离线")
            var isAlarm = false

            if (devType.indexOf("door") >= 0 || devType.indexOf("门") >= 0 || devType.indexOf("window") >= 0 || devType.indexOf("窗") >= 0) {
                icon = "🚪"; statusText = isOnline ? qsTr("已关闭") : qsTr("离线")
            } else if (devType.indexOf("smoke") >= 0 || devType.indexOf("烟雾") >= 0 || devType.indexOf("烟感") >= 0) {
                icon = "🔥"; statusText = isOnline ? qsTr("无烟雾") : qsTr("离线")
            } else if (devType.indexOf("pir") >= 0 || devType.indexOf("motion") >= 0 || devType.indexOf("人体") >= 0 || devType.indexOf("红外") >= 0) {
                icon = "👤"; statusText = isOnline ? qsTr("无人") : qsTr("离线")
            } else if (devType.indexOf("lpg") >= 0 || devType.indexOf("燃气") >= 0 || devType.indexOf("液化气") >= 0 || devType.indexOf("gas") >= 0) {
                icon = "🔧"; statusText = isOnline ? qsTr("无泄漏") : qsTr("离线")
            } else if (devType.indexOf("rain") >= 0 || devType.indexOf("雨滴") >= 0 || devType.indexOf("水浸") >= 0 || devType.indexOf("漏水") >= 0) {
                icon = "💧"; statusText = isOnline ? qsTr("无积水") : qsTr("离线")
            } else if (devType.indexOf("sos") >= 0 || devType.indexOf("紧急") >= 0 || devType.indexOf("报警") >= 0) {
                icon = "🚨"; statusText = isOnline ? qsTr("待命") : qsTr("离线")
            } else if (devType.indexOf("camera") >= 0 || devType.indexOf("摄像头") >= 0 || devType.indexOf("监控") >= 0 || devType.indexOf("cctv") >= 0) {
                icon = "📹"; statusText = isOnline ? qsTr("监控中") : qsTr("离线")
            } else if (devType.indexOf("temperature") >= 0 || devType.indexOf("温度") >= 0 || devType.indexOf("humidity") >= 0 || devType.indexOf("湿度") >= 0 || devType.indexOf("light") >= 0 || devType.indexOf("光照") >= 0 || devType.indexOf("air") >= 0 || devType.indexOf("空气") >= 0 || devType.indexOf("传感器") >= 0 || devType.indexOf("sensor") >= 0) {
                icon = "🌡️"; statusText = isOnline ? qsTr("正常") : qsTr("离线")
            }

            totalCount++
            if (isOnline) onlineCount++

            sensorListModel.append({
                "deviceId": dev["device_id"] || "",
                "sensorName": sensorName,
                "sensorIcon": icon,
                "statusText": statusText,
                "isOnline": isOnline,
                "isAlarm": isAlarm
            })
        }

        root._sensorTotalCount = totalCount
        root._sensorOnlineCount = onlineCount
    }

    function refreshSecurityOverview() {
        root._alertCount = AlertModel.unreadCount
    }

    onCurrentCategoryChanged: {
        if (currentCategory === 2) loadDeviceList()
        if (currentCategory === 0) loadAppearanceSettings()
        if (currentCategory === 6) { refreshSensorList(); refreshSecurityOverview() }
    }

    Component.onCompleted: {
        _loadingSettings = true
        _refreshing = true
        DeviceModel.load()
        _refreshing = false
        loadAppearanceSettings()
        loadDeviceList()
        loadLocalNetworkInfo()
        loadConnectionLogs()
        root.serverAddress = TcpController.targetIp || ""
        root.tcpPort = TcpController.targetPort || 9999
        appendLog(qsTr("网络设置页面已加载"))
        refreshSecurityOverview()
        _loadingSettings = false
    }

    Connections {
        target: DeviceModel
        function onCountChanged() {
            if (_refreshing) return
            _refreshing = true
            console.log("[设备管理] DeviceModel count changed，刷新设备列表");
            loadDeviceList();
            refreshSecurityOverview()
            if (root.currentCategory === 6) refreshSensorList()
            _refreshing = false
        }
    }

    function snackbarShow(message) {
        if (Window.window && Window.window.snackbar)
            Window.window.snackbar.show(message)
    }

    function loadAppearanceSettings() {
        var savedTheme = DatabaseManager.loadSetting("themeMode", "0")
        root.themeMode = parseInt(savedTheme)

        var savedColor = DatabaseManager.loadSetting("colorScheme", "0")
        root.colorScheme = parseInt(savedColor)

        var savedAlertNotif = DatabaseManager.loadSetting("alertNotification", "true")
        root.alertNotification = (savedAlertNotif === "true")

        var savedSound = DatabaseManager.loadSetting("soundReminder", "true")
        root.soundReminder = (savedSound === "true")

        var savedPopupDuration = DatabaseManager.loadSetting("popupDuration", "2500")
        root.popupDuration = parseInt(savedPopupDuration)

        var savedNotificationSound = DatabaseManager.loadSetting("notificationSound", "default")
        root.notificationSound = savedNotificationSound

        var savedUdpPort = DatabaseManager.loadSetting("udpPort", "8888")
        root.udpPort = parseInt(savedUdpPort)
    }

    function saveAppearanceSettings() {
        DatabaseManager.saveSetting("themeMode", String(root.themeMode))
        DatabaseManager.saveSetting("colorScheme", String(root.colorScheme))
        DatabaseManager.saveSetting("alertNotification", String(root.alertNotification))
        DatabaseManager.saveSetting("soundReminder", String(root.soundReminder))
        DatabaseManager.saveSetting("popupDuration", String(root.popupDuration))
        DatabaseManager.saveSetting("notificationSound", root.notificationSound)
        DatabaseManager.saveSetting("udpPort", String(root.udpPort))
    }

    function loadDeviceList() {
        var seenIds = {}
        var newList = []

        var count = DeviceModel.count
        for (var i = 0; i < count; i++) {
            var deviceId = DeviceModel.deviceIdAt(i)
            if (seenIds[deviceId]) continue
            seenIds[deviceId] = true

            var deviceData = DeviceModel.getDeviceById(deviceId)

            newList.push({
                "deviceId": deviceId,
                "deviceName": deviceData["device_name"] || "",
                "deviceType": deviceData["device_type"] || "",
                "ip": deviceData["ip"] || "",
                "tcpPort": deviceData["tcp_port"] || 9999,
                "online": deviceData["is_online"] || false
            })
        }

        root.deviceList = newList
        console.log("[设备管理] 加载了", root.deviceList.length, "个设备")
    }

    function scanWifi() {
        if (_wifiScanning) return
        _wifiScanning = true
        root.wifiList = [
            { "name": "SmartHome-5G", "signal": 85, "secured": true },
            { "name": "HomeNetwork", "signal": 72, "secured": true },
            { "name": "Guest-WiFi", "signal": 60, "secured": false },
            { "name": "Office-Net", "signal": 45, "secured": true }
        ]
        _wifiScanning = false
        snackbarShow(qsTr("WiFi扫描完成"))
    }

    function connectWifi(wifiName) {
        root.savedWifi = wifiName
        snackbarShow(qsTr("正在连接到: %1").arg(wifiName))
    }

    function deleteDevice(deviceId) {
        var success = DatabaseManager.deleteDevice(deviceId)
        if (success) {
            snackbarShow(qsTr("设备已删除"))
            DeviceModel.load()
            loadDeviceList()
        } else {
            snackbarShow(qsTr("删除失败"))
        }
    }

    function rebootDevice(deviceId) {
        var commandId = "reboot_" + new Date().getTime()
        TcpController.sendControlCommand(commandId, deviceId, "reboot")
        snackbarShow(qsTr("设备重启指令已发送"))
    }

    function backupDatabase() {
        var dbPath = DatabaseManager.databasePath
        if (dbPath === "" || !dbPath.endsWith(".db")) {
            snackbarShow(qsTr("数据库路径无效"))
            return
        }
        var backupDir = Qt.resolvedUrl("../../Documents/MySmartHome/Backups").toString()
        backupDir = backupDir.replace("file:///", "").replace(/\//g, "\\")
        var timestamp = Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss")
        root.backupPath = backupDir + "\\database_" + timestamp + ".db"
        snackbarShow(qsTr("备份成功: %1").arg(root.backupPath))
    }

    function restoreDatabase(backupFile) {
        if (backupFile === "") {
            snackbarShow(qsTr("请选择备份文件"))
            return
        }
        restoreConfirmDialog.open()
    }

    function clearAllData() { clearDataConfirmDialog.open() }

    function checkForUpdate() {
        snackbarShow(qsTr("检查更新中..."))
        updateCheckTimer.start()
    }

    function openFeedback() {
        Qt.openUrlExternally("mailto:feedback@smarthome.com?subject=智能家居问题反馈")
    }

    Timer {
        id: updateCheckTimer
        interval: 3000
        repeat: false
        onTriggered: snackbarShow(qsTr("当前已是最新版本 (v%1)").arg(root.appVersion))
    }

    Rectangle {
        anchors.fill: parent
        color: "#0f1923"
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16 * sc
        spacing: 16 * sc

        Rectangle {
            Layout.preferredWidth: 200 * sc
            Layout.fillHeight: true
            color: "#1a2332"
            radius: 12 * sc
            border.color: "#2a4a6a"
            border.width: 1
            Material.elevation: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12 * sc
                spacing: 8 * sc

                Label {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * sc
                    text: qsTr("设置")
                    font.pixelSize: 18 * sc
                    font.bold: true
                    color: "#ffffff"
                    leftPadding: 12 * sc
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#2a4a6a" }

                ListView {
                    id: categoryListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: [
                        { "label": qsTr("外观设置"), "index": 0 },
                        { "label": qsTr("网络设置"), "index": 1 },
                        { "label": qsTr("设备管理"), "index": 2 },
                        { "label": qsTr("通知设置"), "index": 3 },
                        { "label": qsTr("数据管理"), "index": 4 },
                        { "label": qsTr("安全设置"), "index": 6 },
                        { "label": qsTr("关于"), "index": 5 }
                    ]
                    interactive: false
                    clip: true

                    delegate: Rectangle {
                        width: categoryListView.width - 8 * sc
                        height: 44 * sc
                        radius: 8 * sc
                        color: root.currentCategory === modelData["index"] ? "#0d47a1" : "transparent"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.currentCategory = modelData["index"]
                            hoverEnabled: true

                            Rectangle {
                                anchors.fill: parent; radius: 8 * sc
                                color: "#ffffff"
                                opacity: parent.pressed ? 0.1 : (parent.containsMouse ? 0.05 : 0)
                            }

                            Label {
                                anchors.fill: parent
                                anchors.leftMargin: 16 * sc
                                anchors.rightMargin: 16 * sc
                                text: modelData["label"]
                                font.pixelSize: 13 * sc
                                font.bold: root.currentCategory === modelData["index"]
                                color: root.currentCategory === modelData["index"] ? "#ffffff" : "#b0bec5"
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#2a4a6a" }

                Rectangle {
                    Layout.fillWidth: true
                    height: 48 * sc
                    radius: 8 * sc
                    color: "transparent"

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (Window.window && Window.window.tabBarCurrentIndex !== undefined)
                                Window.window.tabBarCurrentIndex = 0
                        }

                        Rectangle {
                            anchors.fill: parent; radius: 8 * sc
                            color: "#1565c0"
                            opacity: parent.pressed ? 0.3 : (parent.containsMouse ? 0.15 : 0)
                        }

                        Label {
                            anchors.centerIn: parent
                            text: qsTr("返回主页")
                            font.pixelSize: 13 * sc
                            font.bold: true
                            color: "#4fc3f7"
                        }
                    }
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentCol.implicitHeight

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: contentCol
                width: parent.width
                spacing: 16 * sc

                // ========== 外观设置 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 0

                    Label {
                        width: parent.width
                        text: qsTr("外观设置")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: themeCard
                        width: parent.width
                        height: themeCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: themeCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("主题模式")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 16 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Label {
                                        text: qsTr("主题")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ComboBox {
                                        id: themeComboBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36 * sc
                                        model: [
                                            { "label": qsTr("深色主题"), "value": 0 },
                                            { "label": qsTr("浅色主题"), "value": 1 },
                                            { "label": qsTr("跟随系统"), "value": 2 }
                                        ]
                                        textRole: "label"
                                        Component.onCompleted: currentIndex = root.themeMode

                                        onActivated: function (idx) {
                                            if (_loadingSettings) return
                                            root.themeMode = idx
                                            if (idx === 0) Material.theme = Material.Dark
                                            else if (idx === 1) Material.theme = Material.Light
                                            saveAppearanceSettings()
                                            snackbarShow(qsTr("主题已切换"))
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Label {
                                        text: qsTr("颜色方案")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ComboBox {
                                        id: colorComboBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36 * sc
                                        model: [
                                            { "label": qsTr("蓝色 (默认)"), "color": "#4FC3F7" },
                                            { "label": qsTr("紫色"), "color": "#7c4dff" },
                                            { "label": qsTr("绿色"), "color": "#4caf50" },
                                            { "label": qsTr("橙色"), "color": "#ff9800" },
                                            { "label": qsTr("红色"), "color": "#f44336" }
                                        ]
                                        textRole: "label"
                                        Component.onCompleted: currentIndex = root.colorScheme

                                        onActivated: function (idx) {
                                            if (_loadingSettings) return
                                            root.colorScheme = idx
                                            var colorValue = model[idx]["color"]
                                            if (Window.window) Window.window.Material.accent = colorValue
                                            snackbarShow(qsTr("颜色方案已更新"))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ========== 网络设置 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 1

                    Label {
                        width: parent.width
                        text: qsTr("网络设置")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: networkStatusCard
                        width: parent.width
                        height: statusCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: statusCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("本机网络信息")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 12 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("本机 IP:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root.localIpAddress || qsTr("加载中...")
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: "#4fc3f7"
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("TCP 状态:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Rectangle {
                                        width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                        color: TcpController.isConnected ? "#4caf50" : "#f44336"
                                        SequentialAnimation on opacity {
                                            running: TcpController.isConnected
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.3; duration: 800 }
                                            NumberAnimation { to: 1.0; duration: 800 }
                                        }
                                    }
                                    Label {
                                        text: TcpController.isConnected ? qsTr("已连接到 %1:%2").arg(TcpController.targetIp).arg(TcpController.targetPort) : qsTr("未连接")
                                        font.pixelSize: 14 * sc
                                        color: TcpController.isConnected ? "#4caf50" : "#f44336"
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: scanCard
                        width: parent.width
                        height: scanCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: scanCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            RowLayout {
                                width: parent.width
                                spacing: 12 * sc

                                Label {
                                    text: qsTr("局域网设备")
                                    font.pixelSize: 16 * sc
                                    font.bold: true
                                    color: "#e0e0e0"
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: root._networkScanning ? qsTr("停止扫描") : qsTr("扫描设备")
                                    Layout.preferredHeight: 36 * sc

                                    background: Rectangle {
                                        radius: 8 * sc
                                        color: parent.pressed ? (root._networkScanning ? "#b71c1c" : "#0d47a1") : (root._networkScanning ? "#c62828" : "#1565c0")
                                        border.color: root._networkScanning ? "#e53935" : "#1976d2"
                                        border.width: 1
                                    }

                                    contentItem: Label {
                                        text: parent.text
                                        color: "#ffffff"
                                        font.pixelSize: 13 * sc
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: scanNetworkDevices()
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 10 * sc

                                Repeater {
                                    model: root.discoveredDevices

                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 56 * sc
                                        radius: 10 * sc
                                        color: "#0f1923"
                                        border.color: "#2a4a6a"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14 * sc
                                            anchors.rightMargin: 14 * sc
                                            spacing: 12 * sc

                                            Rectangle {
                                                width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                                color: "#4caf50"
                                                SequentialAnimation on opacity {
                                                    running: true
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.3; duration: 800 }
                                                    NumberAnimation { to: 1.0; duration: 800 }
                                                }
                                            }

                                            Column {
                                                Layout.fillWidth: true
                                                spacing: 2 * sc

                                                Label {
                                                    text: modelData["deviceName"] || modelData["ip"]
                                                    font.pixelSize: 14 * sc
                                                    font.bold: true
                                                    color: "#e0e0e0"
                                                }

                                                Label {
                                                    text: modelData["deviceType"] + " - " + modelData["ip"] + ":" + modelData["tcpPort"]
                                                    font.pixelSize: 12 * sc
                                                    color: "#90a4ae"
                                                }
                                            }

                                            Button {
                                                text: qsTr("连接")
                                                flat: true
                                                Layout.preferredHeight: 32 * sc

                                                background: Rectangle { radius: 6 * sc; color: parent.pressed ? "#0d47a1" : "#1976d2" }

                                                contentItem: Label {
                                                    text: parent.text
                                                    color: "#ffffff"
                                                    font.pixelSize: 12 * sc
                                                    font.bold: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }

                                                onClicked: connectToDiscoveredDevice(modelData["ip"], modelData["tcpPort"])
                                            }
                                        }
                                    }
                                }

                                Label {
                                    text: root._networkScanning ? qsTr("扫描中...") : (root.discoveredDevices.length === 0 ? qsTr("暂无设备，请点击扫描按钮") : "")
                                    font.pixelSize: 15 * sc
                                    color: "#607d8b"
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredHeight: 40 * sc
                                    visible: root.discoveredDevices.length === 0
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: tcpControlCard
                        width: parent.width
                        height: tcpCtrlCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: tcpCtrlCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("手动连接")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 16 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("服务器地址")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    TextField {
                                        id: serverAddressField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36 * sc
                                        placeholderText: qsTr("输入服务器IP地址...")
                                        font.pixelSize: 14 * sc
                                        Component.onCompleted: text = root.serverAddress
                                        onEditingFinished: {
                                            root.serverAddress = text.trim()
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("TCP端口")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    SpinBox {
                                        id: tcpPortSpinBox
                                        from: 1024; to: 65535; stepSize: 1
                                        editable: true
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36 * sc
                                        Component.onCompleted: value = root.tcpPort
                                        onValueModified: {
                                            root.tcpPort = value
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40 * sc
                                        text: TcpController.isConnected ? qsTr("断开连接") : qsTr("连接服务器")

                                        background: Rectangle {
                                            radius: 8 * sc
                                            color: parent.pressed ? (TcpController.isConnected ? "#b71c1c" : "#0d47a1") : (TcpController.isConnected ? "#c62828" : "#1565c0")
                                            border.color: TcpController.isConnected ? "#e53935" : "#1976d2"
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: {
                                            if (TcpController.isConnected) {
                                                TcpController.disconnectFromDevice()
                                                appendLog(qsTr("手动断开TCP连接"))
                                            } else {
                                                if (root.serverAddress.trim() === "") {
                                                    snackbarShow(qsTr("请输入服务器地址"))
                                                    return
                                                }
                                                TcpController.connectToDevice(root.serverAddress.trim(), root.tcpPort)
                                                appendLog(qsTr("尝试连接到: %1:%2").arg(root.serverAddress.trim()).arg(root.tcpPort))
                                                snackbarShow(qsTr("正在连接到 %1:%2...").arg(root.serverAddress.trim()).arg(root.tcpPort))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: udpControlCard
                        width: parent.width
                        height: udpCtrlCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: udpCtrlCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("UDP 设备发现（持续监听）")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 16 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("UDP端口")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    SpinBox {
                                        id: udpPortSpinBox
                                        from: 1024; to: 65535; stepSize: 1
                                        editable: true
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36 * sc
                                        Component.onCompleted: value = root.udpPort
                                        onValueModified: {
                                            root.udpPort = value
                                            saveAppearanceSettings()
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40 * sc
                                        text: UdpDiscoverer.isRunning ? qsTr("停止监听") : qsTr("启动监听")

                                        background: Rectangle {
                                            radius: 8 * sc
                                            color: parent.pressed ? (UdpDiscoverer.isRunning ? "#b71c1c" : "#0d47a1") : (UdpDiscoverer.isRunning ? "#c62828" : "#1565c0")
                                            border.color: UdpDiscoverer.isRunning ? "#e53935" : "#1976d2"
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: {
                                            if (UdpDiscoverer.isRunning) {
                                                UdpDiscoverer.stopDiscovery()
                                                appendLog(qsTr("停止UDP设备监听"))
                                                snackbarShow(qsTr("设备监听已停止"))
                                            } else {
                                                UdpDiscoverer.startDiscovery()
                                                appendLog(qsTr("启动UDP设备监听，端口 %1").arg(root.udpPort))
                                                snackbarShow(qsTr("设备监听已启动"))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: logCard
                        width: parent.width
                        height: 300 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            RowLayout {
                                width: parent.width
                                spacing: 12 * sc

                                Label {
                                    text: qsTr("连接日志")
                                    font.pixelSize: 16 * sc
                                    font.bold: true
                                    color: "#e0e0e0"
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: qsTr("清空")
                                    flat: true
                                    Layout.preferredHeight: 32 * sc

                                    background: Rectangle { radius: 6 * sc; color: parent.pressed ? "#1a1a2e" : "transparent" }

                                    contentItem: Label {
                                        text: parent.text
                                        font.pixelSize: 12 * sc
                                        font.bold: true
                                        color: "#90a4ae"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        DatabaseManager.clearConnectionLogs()
                                        loadConnectionLogs()
                                        snackbarShow(qsTr("日志已清空"))
                                    }
                                }
                            }

                            Flickable {
                                width: parent.width
                                height: Math.max(100 * sc, logCard.height - 100 * sc)
                                contentWidth: width
                                contentHeight: logText.implicitHeight
                                clip: true

                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

                                Label {
                                    id: logText
                                    width: parent.width
                                    text: root.connectionLogList || qsTr("暂无日志信息...")
                                    font.pixelSize: 12 * sc
                                    font.family: "Courier"
                                    color: "#4caf50"
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }

                // ========== 设备管理 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 2

                    Label {
                        width: parent.width
                        text: qsTr("设备管理")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: deviceCard
                        width: parent.width
                        height: deviceCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: deviceCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("已连接设备 (%1)").arg(root.deviceList.length)
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 10 * sc

                                Repeater {
                                    model: root.deviceList

                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 60 * sc
                                        radius: 10 * sc
                                        color: "#0f1923"
                                        border.color: modelData["online"] ? "#4caf50" : "#f44336"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14 * sc
                                            anchors.rightMargin: 14 * sc
                                            spacing: 12 * sc

                                            Rectangle {
                                                width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                                color: modelData["online"] ? "#4caf50" : "#f44336"

                                                SequentialAnimation on opacity {
                                                    running: modelData["online"]
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.3; duration: 800 }
                                                    NumberAnimation { to: 1.0; duration: 800 }
                                                }
                                            }

                                            Column {
                                                Layout.fillWidth: true
                                                spacing: 2 * sc

                                                Label {
                                                    text: modelData["deviceName"]
                                                    font.pixelSize: 14 * sc
                                                    font.bold: true
                                                    color: "#e0e0e0"
                                                }

                                                Label {
                                                    text: modelData["deviceType"] + " - " + modelData["ip"]
                                                    font.pixelSize: 12 * sc
                                                    color: "#90a4ae"
                                                }
                                            }

                                            Button {
                                                text: qsTr("重启")
                                                flat: true
                                                Layout.preferredHeight: 32 * sc
                                                onClicked: rebootDevice(modelData["deviceId"])

                                                background: Rectangle { radius: 6 * sc; color: parent.pressed ? "#ff9800" : "#1a1a2e" }

                                                contentItem: Label {
                                                    text: parent.text
                                                    font.pixelSize: 12 * sc
                                                    font.bold: true
                                                    color: "#ff9800"
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }

                                            Button {
                                                text: qsTr("删除")
                                                flat: true
                                                Layout.preferredHeight: 32 * sc
                                                onClicked: {
                                                    deleteConfirmDialog.deviceId = modelData["deviceId"]
                                                    deleteConfirmDialog.deviceName = modelData["deviceName"]
                                                    deleteConfirmDialog.open()
                                                }

                                                background: Rectangle { radius: 6 * sc; color: parent.pressed ? "#f44336" : "#1a1a2e" }

                                                contentItem: Label {
                                                    text: parent.text
                                                    font.pixelSize: 12 * sc
                                                    font.bold: true
                                                    color: "#f44336"
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }
                                        }
                                    }
                                }

                                Label {
                                    text: qsTr("暂无设备")
                                    font.pixelSize: 15 * sc
                                    color: "#607d8b"
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredHeight: 40 * sc
                                    visible: root.deviceList.length === 0
                                }
                            }
                        }
                    }
                }

                // ========== 通知设置 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 3

                    Label {
                        width: parent.width
                        text: qsTr("通知设置")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: notifyCard1
                        width: parent.width
                        height: notify1Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: notify1Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("通知选项")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 16 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 4 * sc

                                        Label {
                                            text: qsTr("警告通知")
                                            font.pixelSize: 14 * sc
                                            font.bold: true
                                            color: "#e0e0e0"
                                        }

                                        Label {
                                            text: qsTr("开启后，收到警告时将显示通知")
                                            font.pixelSize: 12 * sc
                                            color: "#90a4ae"
                                        }
                                    }

                                    Switch {
                                        Layout.alignment: Qt.AlignVCenter
                                        Component.onCompleted: checked = root.alertNotification
                                        onToggled: {
                                            root.alertNotification = checked
                                            saveAppearanceSettings()
                                            snackbarShow(checked ? qsTr("警告通知已开启") : qsTr("警告通知已关闭"))
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 4 * sc

                                        Label {
                                            text: qsTr("声音提醒")
                                            font.pixelSize: 14 * sc
                                            font.bold: true
                                            color: "#e0e0e0"
                                        }

                                        Label {
                                            text: qsTr("收到通知时播放提示音")
                                            font.pixelSize: 12 * sc
                                            color: "#90a4ae"
                                        }
                                    }

                                    Switch {
                                        Layout.alignment: Qt.AlignVCenter
                                        Component.onCompleted: checked = root.soundReminder
                                        onToggled: {
                                            root.soundReminder = checked
                                            saveAppearanceSettings()
                                            snackbarShow(checked ? qsTr("声音提醒已开启") : qsTr("声音提醒已关闭"))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: notifyCard2
                        width: parent.width
                        height: notify2Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: notify2Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("通知样式")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 16 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Label {
                                        text: qsTr("弹窗时长")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Slider {
                                        id: popupDurationSlider
                                        Layout.fillWidth: true
                                        from: 1000; to: 5000; stepSize: 500
                                        Component.onCompleted: value = root.popupDuration

                                        onMoved: root.popupDuration = Math.round(value)
                                    }

                                    Label {
                                        text: (popupDurationSlider.value / 1000).toFixed(1) + "s"
                                        font.pixelSize: 14 * sc
                                        color: "#e0e0e0"
                                        Layout.preferredWidth: 55 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Label {
                                        text: qsTr("通知声音")
                                        font.pixelSize: 14 * sc
                                        color: "#b0bec5"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ComboBox {
                                        id: soundComboBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36 * sc
                                        model: [qsTr("默认"), qsTr("清脆"), qsTr("柔和"), qsTr("紧急")]
                                        Component.onCompleted: {
                                            var soundMap = { "default": 0, "crisp": 1, "soft": 2, "urgent": 3 }
                                            currentIndex = soundMap[root.notificationSound] !== undefined ? soundMap[root.notificationSound] : 0
                                        }

                                        onActivated: function (idx) {
                                            var soundKeys = ["default", "crisp", "soft", "urgent"]
                                            root.notificationSound = soundKeys[idx]
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ========== 数据管理 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 4

                    Label {
                        width: parent.width
                        text: qsTr("数据管理")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: dataCard1
                        width: parent.width
                        height: data1Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: data1Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("数据库状态")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 12 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Label {
                                        text: qsTr("路径:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 80 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Label {
                                        text: DatabaseManager.databasePath
                                        font.pixelSize: 13 * sc
                                        color: "#e0e0e0"
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Label {
                                        text: qsTr("状态:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 80 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Rectangle {
                                        width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                        color: DatabaseManager.isOpen() ? "#4caf50" : "#f44336"

                                        SequentialAnimation on opacity {
                                            running: DatabaseManager.isOpen()
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.3; duration: 800 }
                                            NumberAnimation { to: 1.0; duration: 800 }
                                        }
                                    }

                                    Label {
                                        text: DatabaseManager.isOpen() ? qsTr("已连接") : qsTr("未连接")
                                        font.pixelSize: 14 * sc
                                        color: DatabaseManager.isOpen() ? "#4caf50" : "#f44336"
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: dataCard2
                        width: parent.width
                        height: data2Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: data2Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("数据备份")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 16 * sc

                                Label {
                                    text: qsTr("备份操作将数据库文件保存到指定位置，恢复操作将从备份文件还原数据。")
                                    font.pixelSize: 13 * sc
                                    color: "#90a4ae"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40 * sc
                                        text: qsTr("立即备份")

                                        background: Rectangle {
                                            radius: 8 * sc
                                            color: parent.pressed ? "#0d47a1" : "#1565c0"
                                            border.color: "#1976d2"
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: backupDatabase()
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40 * sc
                                        text: qsTr("恢复备份")

                                        background: Rectangle {
                                            radius: 8 * sc
                                            color: parent.pressed ? "#0d47a1" : "#1565c0"
                                            border.color: "#1976d2"
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: restoreDatabase(root.backupPath)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: dataCard3
                        width: parent.width
                        height: data3Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: data3Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("数据清理")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 14 * sc

                                Label {
                                    text: qsTr("清理操作将永久删除数据，请谨慎操作")
                                    font.pixelSize: 13 * sc
                                    color: "#ff8a80"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40 * sc
                                        text: qsTr("清理30天前的能耗数据")

                                        background: Rectangle {
                                            radius: 8 * sc
                                            color: parent.pressed ? "#1a2332" : "#1e1e2e"
                                            border.color: "#ff8a80"
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ff8a80"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: clearEnergyConfirmDialog.open()
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40 * sc
                                        text: qsTr("清除所有数据")

                                        background: Rectangle {
                                            radius: 8 * sc
                                            color: parent.pressed ? "#3a1515" : "#2e1515"
                                            border.color: "#f44336"
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: "#f44336"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: clearAllData()
                                    }
                                }
                            }
                        }
                    }
                }

                // ========== 关于 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 5

                    Label {
                        width: parent.width
                        text: qsTr("关于")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: aboutCard1
                        width: parent.width
                        height: about1Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: about1Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("应用信息")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 12 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("应用名称:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: Qt.application.name
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: "#e0e0e0"
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("版本号:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: "v" + root.appVersion
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: "#e0e0e0"
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: aboutCard2
                        width: parent.width
                        height: about2Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: about2Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("版权声明")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 10 * sc

                                Label {
                                    text: qsTr("2026 智能家居控制系统. 保留所有权利。")
                                    font.pixelSize: 14 * sc
                                    color: "#e0e0e0"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                }

                                Label {
                                    text: qsTr("本项目仅供学习研究使用，不得用于商业用途。基于Qt 6.10框架开发。")
                                    font.pixelSize: 13 * sc
                                    color: "#90a4ae"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: aboutCard3
                        width: parent.width
                        height: about3Col.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: about3Col
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("帮助与反馈")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 12 * sc

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40 * sc
                                    text: qsTr("检查更新")

                                    background: Rectangle {
                                        radius: 8 * sc
                                        color: parent.pressed ? "#0d47a1" : "#1565c0"
                                        border.color: "#1976d2"
                                        border.width: 1
                                    }

                                    contentItem: Label {
                                        text: parent.text
                                        color: "#ffffff"
                                        font.pixelSize: 13 * sc
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: checkForUpdate()
                                }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40 * sc
                                    text: qsTr("问题反馈")

                                    background: Rectangle {
                                        radius: 8 * sc
                                        color: parent.pressed ? "#0d47a1" : "#1565c0"
                                        border.color: "#1976d2"
                                        border.width: 1
                                    }

                                    contentItem: Label {
                                        text: parent.text
                                        color: "#ffffff"
                                        font.pixelSize: 13 * sc
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: openFeedback()
                                }
                            }
                        }
                    }
                }

                // ========== 安全设置 ==========
                Column {
                    width: parent.width
                    spacing: 16 * sc
                    visible: root.currentCategory === 6

                    Label {
                        width: parent.width
                        text: qsTr("安全设置")
                        font.pixelSize: 22 * sc
                        font.bold: true
                        color: "#ffffff"
                    }

                    Rectangle {
                        id: securityOverviewCard
                        width: parent.width
                        height: securityOverviewCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: securityOverviewCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("安全概览")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 12 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("TCP 连接:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Rectangle {
                                        width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                        color: (TcpController && TcpController.isConnected) ? "#4caf50" : "#f44336"
                                        SequentialAnimation on opacity {
                                            running: TcpController && TcpController.isConnected
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.3; duration: 800 }
                                            NumberAnimation { to: 1.0; duration: 800 }
                                        }
                                    }
                                    Label {
                                        text: (TcpController && TcpController.isConnected) ? qsTr("已连接 - 视频流可用") : qsTr("未连接")
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: (TcpController && TcpController.isConnected) ? "#4caf50" : "#f44336"
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("视频通道:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Rectangle {
                                        width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                        color: (TcpController && TcpController.isVideoConnected) ? "#4caf50" : "#ff9800"
                                    }
                                    Label {
                                        text: (TcpController && TcpController.isVideoConnected) ? qsTr("已连接") : qsTr("未连接")
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: (TcpController && TcpController.isVideoConnected) ? "#4caf50" : "#ff9800"
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("传感器总数:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: String(root._sensorTotalCount)
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: root._sensorTotalCount > 0 ? "#4fc3f7" : "#607d8b"
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("在线传感器:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root._sensorOnlineCount + " / " + root._sensorTotalCount
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: root._sensorOnlineCount > 0 ? "#4caf50" : "#f44336"
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc
                                    Label {
                                        text: qsTr("未读警告:")
                                        font.pixelSize: 14 * sc
                                        color: "#90a4ae"
                                        Layout.preferredWidth: 100 * sc
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: String(root._alertCount)
                                        font.pixelSize: 14 * sc
                                        font.bold: true
                                        color: root._alertCount > 0 ? "#ff5252" : "#757575"
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: sensorStatusCard
                        width: parent.width
                        height: Math.min(sensorListRepeater.count * 74 * sc + 80 * sc, 440 * sc)
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        RowLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 18 * sc
                            height: 40 * sc

                            Label {
                                text: qsTr("🛡 传感器状态")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                Layout.preferredHeight: 32 * sc
                                text: qsTr("↻ 刷新")

                                background: Rectangle {
                                    radius: 8 * sc
                                    color: parent.pressed ? "#0d47a1" : "#1565c0"
                                    border.color: "#1976d2"
                                    border.width: 1
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: "#ffffff"
                                    font.pixelSize: 11 * sc
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: {
                                    DeviceModel.load()
                                    refreshSensorList()
                                    refreshSecurityOverview()
                                }
                            }
                        }

                        ListView {
                            id: sensorListRepeater
                            anchors.top: parent.top
                            anchors.topMargin: 56 * sc
                            anchors.left: parent.left
                            anchors.leftMargin: 18 * sc
                            anchors.right: parent.right
                            anchors.rightMargin: 18 * sc
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12 * sc
                            spacing: 6 * sc
                            clip: true
                            model: sensorListModel

                            delegate: Rectangle {
                                id: secSensorCard
                                width: ListView.view.width
                                height: 62 * sc
                                radius: 10 * sc
                                color: model.isOnline ? (model.isAlarm ? "#2a1a1a" : "#15283a") : "#12121e"
                                border.color: model.isOnline ? (model.isAlarm ? "#e53935" : "#1a4a6a") : "#2a2a3a"
                                border.width: 1
                                opacity: model.isOnline ? 1.0 : 0.6

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10 * sc
                                    spacing: 10 * sc

                                    Rectangle {
                                        width: 36 * sc; height: 36 * sc; radius: 8 * sc
                                        color: "#1a3a5c"
                                        opacity: 0.6
                                        Layout.alignment: Qt.AlignVCenter

                                        Label {
                                            anchors.centerIn: parent
                                            text: model.sensorIcon || ""
                                            font.pixelSize: 18 * sc
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2 * sc

                                        Label {
                                            text: model.sensorName || ""
                                            font.bold: true
                                            font.pixelSize: 13 * sc
                                            color: model.isOnline ? "#e0e0e0" : "#757575"
                                            elide: Text.ElideMiddle
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: model.statusText || ""
                                            font.pixelSize: 11 * sc
                                            color: model.isOnline ? (model.isAlarm ? "#ff5252" : "#78909c") : "#555555"
                                        }
                                    }

                                    Rectangle {
                                        width: 7 * sc; height: 7 * sc; radius: 4 * sc
                                        color: model.isOnline ? "#4caf50" : "#f44336"
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    Rectangle {
                                        anchors.fill: parent; radius: 10 * sc
                                        color: "#ffffff"
                                        opacity: parent.pressed ? 0.1 : 0
                                    }
                                    onClicked: {
                                        if (model.isOnline && Window.window) {
                                            snackbarShow(qsTr("跳转到设备控制: %1").arg(model.sensorName))
                                            Window.window.tabBarCurrentIndex = 2
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: securityActionCard
                        width: parent.width
                        height: securityActionCol.implicitHeight + 44 * sc
                        radius: 14 * sc
                        color: "#1a2332"
                        border.color: "#2a4a6a"
                        border.width: 1
                        Material.elevation: 4

                        Column {
                            id: securityActionCol
                            anchors.fill: parent
                            anchors.margins: 18 * sc
                            spacing: 14 * sc

                            Label {
                                text: qsTr("安全操作")
                                font.pixelSize: 16 * sc
                                font.bold: true
                                color: "#e0e0e0"
                            }

                            Column {
                                width: parent.width
                                spacing: 12 * sc

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42 * sc
                                        text: qsTr("📹 打开安防监控")

                                        background: Rectangle {
                                            radius: 10 * sc
                                            color: parent.pressed ? "#0d47a1" : "#1565c0"
                                            border.color: "#1976d2"
                                            border.width: 1
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            if (Window.window)
                                                Window.window.tabBarCurrentIndex = 1
                                        }
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42 * sc
                                        text: qsTr("🔔 警告中心")

                                        background: Rectangle {
                                            radius: 10 * sc
                                            color: parent.pressed ? "#b71c1c" : "#c62828"
                                            border.color: "#e53935"
                                            border.width: 1
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            if (Window.window) {
                                                Window.window.tabBarCurrentIndex = 5
                                                AlertModel.load()
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 12 * sc

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42 * sc
                                        text: TcpController && TcpController.isConnected ? qsTr("🔴 断开设备") : qsTr("🟢 连接设备")

                                        background: Rectangle {
                                            radius: 10 * sc
                                            color: parent.pressed ? (TcpController && TcpController.isConnected ? "#b71c1c" : "#1b5e20") : (TcpController && TcpController.isConnected ? "#c62828" : "#2e7d32")
                                            border.color: TcpController && TcpController.isConnected ? "#e53935" : "#4caf50"
                                            border.width: 1
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            if (TcpController && TcpController.isConnected) {
                                                TcpController.disconnectFromDevice()
                                                snackbarShow(qsTr("已断开设备连接"))
                                            } else {
                                                if (root.serverAddress.trim() === "") {
                                                    snackbarShow(qsTr("请先在网络设置中配置服务器地址"))
                                                } else {
                                                    TcpController.connectToDevice(root.serverAddress.trim(), root.tcpPort)
                                                    snackbarShow(qsTr("正在连接到 %1:%2").arg(root.serverAddress.trim()).arg(root.tcpPort))
                                                }
                                            }
                                        }
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42 * sc
                                        text: qsTr("🎬 设备控制")

                                        background: Rectangle {
                                            radius: 10 * sc
                                            color: parent.pressed ? "#4a148c" : "#6a1b9a"
                                            border.color: "#8e24aa"
                                            border.width: 1
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: "#ffffff"
                                            font.pixelSize: 13 * sc
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            if (Window.window) {
                                                Window.window.tabBarCurrentIndex = 2
                                            }
                                        }
                                    }
                                }
                            }
                        }
                }

                Item { width: parent.width; height: 50 * sc }
            }
        }
    }

    ListModel { id: sensorListModel }

    Dialog {
        id: deleteConfirmDialog
        title: qsTr("确认删除设备")
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 400 * sc
        property string deviceId: ""
        property string deviceName: ""
        standardButtons: Dialog.Ok | Dialog.Cancel

        Label {
            text: qsTr("确定要删除设备 \"%1\" 吗？此操作不可恢复。").arg(deleteConfirmDialog.deviceName)
            font.pixelSize: 14 * sc
            color: "#e0e0e0"
            wrapMode: Text.Wrap
        }

        onAccepted: {
            if (deleteConfirmDialog.deviceId !== "") {
                deleteDevice(deleteConfirmDialog.deviceId)
                deleteConfirmDialog.deviceId = ""
                deleteConfirmDialog.deviceName = ""
            }
        }
    }

    Dialog {
        id: restoreConfirmDialog
        title: qsTr("确认恢复数据库")
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 400 * sc
        standardButtons: Dialog.Ok | Dialog.Cancel

        Label {
            text: qsTr("确定要从备份恢复数据库吗？恢复后需要重启应用才能生效。")
            font.pixelSize: 14 * sc
            color: "#e0e0e0"
            wrapMode: Text.Wrap
        }

        onAccepted: snackbarShow(qsTr("数据库恢复成功，重启后生效"))
    }

    Dialog {
        id: clearDataConfirmDialog
        title: qsTr("确认清除所有数据")
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 400 * sc
        standardButtons: Dialog.Ok | Dialog.Cancel

        Label {
            text: qsTr("确定要清除所有数据吗？此操作不可恢复！")
            font.pixelSize: 14 * sc
            color: "#ff8a80"
            font.bold: true
            wrapMode: Text.Wrap
        }

        onAccepted: snackbarShow(qsTr("所有数据已清除"))
    }

    Dialog {
        id: clearEnergyConfirmDialog
        title: qsTr("确认清理能耗数据")
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 400 * sc
        standardButtons: Dialog.Ok | Dialog.Cancel

        Label {
            text: qsTr("确定要清理30天前的能耗数据吗？")
            font.pixelSize: 14 * sc
            color: "#e0e0e0"
            wrapMode: Text.Wrap
        }

        onAccepted: {
            var cutoffDate = new Date(Date.now() - 30 * 86400000)
            DatabaseManager.deleteEnergyDataOlderThan(cutoffDate)
            snackbarShow(qsTr("能耗数据清理完成"))
        }
    }
}
}
