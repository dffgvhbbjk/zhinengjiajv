import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

ApplicationWindow {
    id: mainWindow

    readonly property real refWidth: 1600
    readonly property real refHeight: 900
    readonly property real scaleX: width / refWidth
    readonly property real scaleY: height / refHeight
    readonly property real scaleBase: Math.min(scaleX, scaleY)

    width: Math.min(Screen.desktopAvailableWidth * 0.85, 1600)
    height: Math.min(Screen.desktopAvailableHeight * 0.85, 900)
    minimumWidth: 960
    minimumHeight: 600
    visible: true
    title: qsTr("智能家居")
    Material.theme: Material.Dark
    Material.accent: "#4FC3F7"

    property var devices: ({})
    property int onlineCount: 0
    property bool tcpConnected: TcpController ? TcpController.isConnected : false
    property bool videoConnected: TcpController ? TcpController.isVideoConnected : false
    property int alertBadgeCount: 0
    property alias tabBarCurrentIndex: navBar.currentIndex

    property bool _refreshing: false
    property bool _splashVisible: true

    // ========== 启动画面 ==========
    Rectangle {
        id: splashScreen
        anchors.fill: parent
        color: "#0d47a1"
        visible: mainWindow._splashVisible
        z: 500

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0d47a1" }
            GradientStop { position: 1.0; color: "#1565c0" }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 24 * scaleBase

            Label {
                text: "🏠"
                font.pixelSize: 64 * scaleBase
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("智能家居")
                font.pixelSize: 28 * scaleBase
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("正在初始化系统...")
                font.pixelSize: 14 * scaleBase
                color: "#bbdefb"
                Layout.alignment: Qt.AlignHCenter
            }

            ProgressBar {
                id: splashProgress
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 240 * scaleBase
                value: 0
                to: 1.0
                from: 0.0

                background: Rectangle {
                    implicitWidth: 240 * scaleBase
                    implicitHeight: 4 * scaleBase
                    color: "#1e3a5c"
                    radius: 2
                }

                contentItem: Item {
                    implicitWidth: 240 * scaleBase
                    implicitHeight: 4 * scaleBase
                    Rectangle {
                        width: splashProgress.visualPosition * parent.width
                        height: parent.height
                        color: "#4fc3f7"
                        radius: 2
                    }
                }
            }
        }

        SequentialAnimation {
            id: splashAnimation
            running: mainWindow._splashVisible

            NumberAnimation {
                target: splashProgress; property: "value"
                from: 0; to: 1.0; duration: 1500
            }
            PauseAnimation { duration: 300 }
            ScriptAction {
                script: {
                    mainWindow._splashVisible = false;
                    initializeApp();
                }
            }
        }
    }

    // ========== 全局信号处理 ==========
    Connections {
        target: UdpDiscoverer

        function onDeviceDiscovered(deviceId, deviceName, deviceType, ip, tcpPort, firmwareVersion) {
            mainWindow.devices[deviceId] = {
                "id": deviceId, "name": deviceName, "type": deviceType,
                "ip": ip, "tcpPort": tcpPort, "firmware": firmwareVersion,
                "online": true, "temperature": "--", "humidity": "--",
                "pm25": "--", "co2": "--", "power": "--", "lastUpdate": ""
            };
            DatabaseManager.addConnectionLog("[UDP] [INFO] UDP发现设备: " + deviceName + " (" + deviceType + ") - " + ip + ":" + tcpPort);
            snackbar.show("发现新设备：" + deviceName);
        }

        function onDataReceived(deviceId, data) {
            if (mainWindow.devices[deviceId]) {
                var dev = mainWindow.devices[deviceId];

                if (data["temperature"] !== undefined) {
                    dev.temperature = data["temperature"] + "°C";
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 温度数据: " + data["temperature"] + "°C");
                    if (data["temperature"] > 40 || data["temperature"] < 0) {
                        var alertId = "qt_temp_" + Qt.formatDateTime(new Date(), "yyyyMMddhhmmss");
                        var alertContent = qsTr("设备 %1 温度异常: %2°C (阈值: 0-40°C)").arg(deviceId).arg(data["temperature"]);
                        DatabaseManager.addAlert(alertId, deviceId, alertContent, 2, "qt_sensor_alert");
                        snackbar.show("⚠️ " + alertContent);
                    }
                }
                if (data["humidity"] !== undefined) {
                    dev.humidity = data["humidity"] + "%";
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 湿度数据: " + data["humidity"] + "%");
                }
                if (data["pm25"] !== undefined) {
                    dev.pm25 = data["pm25"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " PM2.5数据: " + data["pm25"] + "μg/m³");
                }
                if (data["co2"] !== undefined) {
                    dev.co2 = data["co2"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " CO2数据: " + data["co2"] + "ppm");
                }
                if (data["power"] !== undefined) {
                    dev.power = data["power"] + "W";
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 功率数据: " + data["power"] + "W");
                }
                if (data["light"] !== undefined) {
                    dev.light = data["light"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 光照数据: " + data["light"] + "lux");
                }
                if (data["rain"] !== undefined) {
                    dev.rain = data["rain"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 雨滴数据: " + data["rain"]);
                }
                if (data["smoke"] !== undefined) {
                    dev.smoke = data["smoke"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 烟雾数据: " + data["smoke"] + "ppm");
                    if (data["smoke"] > 50) {
                        var alertId = "qt_smoke_" + Qt.formatDateTime(new Date(), "yyyyMMddhhmmss");
                        var alertContent = qsTr("设备 %1 烟雾浓度超标: %2ppm (阈值: 50ppm)").arg(deviceId).arg(data["smoke"]);
                        DatabaseManager.addAlert(alertId, deviceId, alertContent, 3, "qt_sensor_alert");
                        snackbar.show(" " + alertContent);
                    }
                }
                if (data["lpg"] !== undefined) {
                    dev.lpg = data["lpg"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 液化气数据: " + data["lpg"] + "ppm");
                    if (data["lpg"] > 100) {
                        var alertId = "qt_lpg_" + Qt.formatDateTime(new Date(), "yyyyMMddhhmmss");
                        var alertContent = qsTr("设备 %1 液化气浓度超标: %2ppm (阈值: 100ppm)").arg(deviceId).arg(data["lpg"]);
                        DatabaseManager.addAlert(alertId, deviceId, alertContent, 3, "qt_sensor_alert");
                        snackbar.show("⛽ " + alertContent);
                    }
                }
                if (data["air_quality"] !== undefined) {
                    dev.airQuality = data["air_quality"];
                    DatabaseManager.addConnectionLog("[SENSOR] [INFO] 设备 " + deviceId + " 空气质量数据: " + data["air_quality"] + "AQI");
                    if (data["air_quality"] > 300) {
                        var alertId = "qt_air_" + Qt.formatDateTime(new Date(), "yyyyMMddhhmmss");
                        var alertContent = qsTr("设备 %1 空气质量严重污染: AQI %2 (阈值: 300)").arg(deviceId).arg(data["air_quality"]);
                        DatabaseManager.addAlert(alertId, deviceId, alertContent, 2, "qt_sensor_alert");
                        snackbar.show("🌫️ " + alertContent);
                    }
                }
                dev.lastUpdate = data["datetime"] !== undefined ? data["datetime"] : dev.lastUpdate;
                dev.online = true;
            }
        }

        function onSensorFieldUpdated(deviceId, field, value, version) {
            if (mainWindow.devices[deviceId]) {
                var dev = mainWindow.devices[deviceId];
                switch (field) {
                case "temperature":
                    dev.temperature = value.toFixed(1) + "°C";
                    break;
                case "humidity":
                    dev.humidity = value.toFixed(1) + "%";
                    break;
                case "light":
                    dev.light = value.toFixed(1);
                    break;
                case "rain":
                    dev.rain = value.toFixed(1);
                    break;
                case "smoke":
                    dev.smoke = value.toFixed(1);
                    break;
                case "lpg":
                    dev.lpg = value.toFixed(1);
                    break;
                case "air_quality":
                    dev.airQuality = value.toFixed(1);
                    break;
                case "pressure":
                    dev.pressure = value.toFixed(1);
                    break;
                }
                dev.lastUpdate = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
                dev.online = true;
            }
        }

        function onDeviceOffline(deviceId) {
            if (mainWindow.devices[deviceId]) {
                mainWindow.devices[deviceId].online = false;
                DatabaseManager.setDeviceOnline(deviceId, false);
                DatabaseManager.addConnectionLog("[UDP] [WARN] UDP设备离线: " + deviceId);
                snackbar.show("设备离线：" + deviceId);
                var alertId = "qt_offline_" + Qt.formatDateTime(new Date(), "yyyyMMddhhmmss");
                var alertContent = qsTr("设备 %1 离线，请检查网络连接").arg(deviceId);
                DatabaseManager.addAlert(alertId, deviceId, alertContent, 2, "qt_device_offline");

                mainWindow._refreshing = true;
                DeviceModel.load();
                initializeOnlineCount();
                mainWindow._refreshing = false;
            }
        }

        function onErrorOccurred(errorCode, errorString) {
            snackbar.show("网络错误：" + errorString);
        }
    }

    Connections {
        target: TcpController

        function onConnectionStatusChanged(isConnected) {
            mainWindow.tcpConnected = isConnected;
            if (isConnected) {
                DatabaseManager.addConnectionLog("[TCP] [INFO] 设备连接成功: " + TcpController.targetIp + ":" + TcpController.targetPort);
                snackbar.show("设备连接成功");
                let pendingCommands = DatabaseManager.getAllPendingCommands();
                for (let i = 0; i < pendingCommands.length; i++) {
                    let command = JSON.parse(pendingCommands[i].command_data);
                    TcpController.sendControlCommand(command.commandId, command.device, command.action);
                    DatabaseManager.deletePendingCommand(pendingCommands[i].command_id);
                }
            } else {
                DatabaseManager.addConnectionLog("[TCP] [WARN] 设备连接断开");
                snackbar.show("设备连接断开，正在重连...");
            }
        }

        function onCameraStreamToggled(enabled) {
            mainWindow.videoConnected = enabled;
            if (enabled) {
                DatabaseManager.addConnectionLog("[VIDEO] [INFO] 视频流已连接");
                snackbar.show("视频流已连接");
            } else {
                DatabaseManager.addConnectionLog("[VIDEO] [WARN] 视频流已断开");
            }
        }

        function onCommandSuccess(commandId, message) {
            DatabaseManager.addConnectionLog("[TCP] [INFO] 命令成功 [" + commandId + "]: " + message);
        }

        function onCommandFailed(commandId, errorString) {
            DatabaseManager.addConnectionLog("[TCP] [ERROR] 命令失败 [" + commandId + "]: " + errorString);
            snackbar.show("指令失败：" + errorString);
        }

        function onAlertReceived(alertId, content, level) {
            DatabaseManager.addConnectionLog("[ALERT] [WARN] 新告警: " + content + " (level: " + level + ")");
            refreshAlertBadge();
            snackbar.show("新警告：" + content);
        }

        function onFirmwareUpdateProgress(progress) {
            snackbar.show("固件更新中：" + progress + "%");
        }

        function onFirmwareUpdateComplete() {
            snackbar.show("固件更新完成");
        }

        function onErrorOccurred(errorCode, errorString) {
            DatabaseManager.addConnectionLog("[TCP] [ERROR] TCP错误 [" + errorCode + "]: " + errorString);
            snackbar.show("TCP错误：" + errorString);
        }
    }

    // ========== 全局工具函数 ==========
    function sendDeviceControl(deviceId, action) {
        DatabaseManager.addConnectionLog("[DEVICE] [INFO] 设备控制: " + deviceId + " - 动作: " + action);
        var cmdId = "cmd_" + Date.now();
        TcpController.sendControlCommand(cmdId, deviceId, action);
    }



    // ========== 全局状态管理 ==========
    Connections {
        target: DeviceModel
        function onCountChanged() {
            if (mainWindow._refreshing) return;
            initializeOnlineCount();
        }
    }

    Connections {
        target: AlertModel
        function onCountChanged() { refreshAlertBadge(); }
    }

    function initializeApp() {
        UdpDiscoverer.startDiscovery();
        LocationService.locate();
        initializeOnlineCount();
    }

    function initializeOnlineCount() {
        onlineCount = 0;
        for (var i = 0; i < DeviceModel.count; i++) {
            if (DeviceModel.data(DeviceModel.index(i, 0), DeviceModel.StatusRole))
                onlineCount++;
        }
    }

    function refreshAlertBadge() {
        alertBadgeCount = AlertModel.unreadCount;
    }

    // ========== 页面容器 ==========
    Item {
        id: mainContainer
        anchors.fill: parent
        anchors.bottomMargin: navBar.height

        HomePage {
            id: homePage
            anchors.fill: parent
            visible: navBar.currentIndex === 0
        }

        DeviceControlPage {
            id: deviceControlInstance
            anchors.fill: parent
            visible: navBar.currentIndex === 2
            onBackRequested: navigateToPage(0)
        }

        ScenePage {
            id: scenePageInstance
            anchors.fill: parent
            visible: navBar.currentIndex === 4
            onNavigateToEdit: function (sceneData) {
                editOverlay.visible = true;
                sceneEditOverlayInstance.editingScene = sceneData;
            }
            onBackToHome: navigateToPage(0)
        }

        SecurityPage {
            id: securityPageInstance
            anchors.fill: parent
            visible: navBar.currentIndex === 1
        }

        AlertCenterPage {
            id: alertCenterPageInstance
            anchors.fill: parent
            visible: navBar.currentIndex === 5
        }

        EnergyPage {
            id: energyPage
            anchors.fill: parent
            visible: navBar.currentIndex === 6
        }

        SensorPage {
            id: sensorPage
            anchors.fill: parent
            visible: navBar.currentIndex === 3
        }

        SettingsPage {
            id: settingsPageInstance
            anchors.fill: parent
            visible: navBar.currentIndex === 7
        }

        LogPage {
            id: logPageInstance
            anchors.fill: parent
            visible: navBar.currentIndex === 8
        }
    }

    // ========== 底部导航栏 ==========
    TabBar {
        id: navBar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 56 + 8 * scaleBase
        Material.background: "#0a1929"
        Material.elevation: 8
        currentIndex: 0

        // --- Nav Tab 0: Home ---
        TabButton {
            id: navHome
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "🏠"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("首页")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 0
                    color: navBar.currentIndex === 0 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 0 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 0
                }
            }
            onClicked: navBar.currentIndex = 0
        }

        // --- Nav Tab 1: Security ---
        TabButton {
            id: navSecurity
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "🛡"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("安防")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 1
                    color: navBar.currentIndex === 1 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 1 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 1
                }
            }
            onClicked: navBar.currentIndex = 1
        }

        // --- Nav Tab 2: Device ---
        TabButton {
            id: navDevice
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "📱"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("设备")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 2
                    color: navBar.currentIndex === 2 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 2 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 12 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 2
                }
            }
            onClicked: navBar.currentIndex = 2
        }

        // --- Nav Tab 3: Sensor ---
        TabButton {
            id: navSensor
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "🌡"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("传感器")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 3
                    color: navBar.currentIndex === 3 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 3 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 3
                }
            }
            onClicked: navBar.currentIndex = 3
        }

        // --- Nav Tab 4: Scene ---
        TabButton {
            id: navScene
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "🎬"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("场景")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 4
                    color: navBar.currentIndex === 4 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 4 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 4
                }
            }
            onClicked: navBar.currentIndex = 4
        }

        // --- Nav Tab 5: Alert ---
        TabButton {
            id: navAlert
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "🔔"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("警告")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 5
                    color: navBar.currentIndex === 5 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 5 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 5
                }
            }
            onClicked: { navBar.currentIndex = 5; AlertModel.load(); }
        }

        // --- Nav Tab 6: Energy ---
        TabButton {
            id: navEnergy
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "💡"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("能耗")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 6
                    color: navBar.currentIndex === 6 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 6 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 6
                }
            }
            onClicked: navBar.currentIndex = 6
        }

        // --- Nav Tab 7: Settings ---
        TabButton {
            id: navSettings
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "🛠"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("设置")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 7
                    color: navBar.currentIndex === 7 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 7 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 7
                }
            }
            onClicked: navBar.currentIndex = 7
        }

        // --- Nav Tab 8: Log ---
        TabButton {
            id: navLog
            width: navBar.width / 9
            contentItem: ColumnLayout {
                spacing: 2 * scaleBase
                Label {
                    text: "📝"
                    font.pixelSize: 18 * scaleBase
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("日志")
                    font.pixelSize: 10 * scaleBase
                    font.bold: navBar.currentIndex === 8
                    color: navBar.currentIndex === 8 ? "#4fc3f7" : "#90a4ae"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            background: Rectangle {
                anchors.fill: parent
                color: navBar.currentIndex === 8 ? "#1a3050" : "transparent"
                radius: 8 * scaleBase
                Rectangle {
                    width: parent.width - 16 * scaleBase
                    height: 3 * scaleBase
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * scaleBase
                    color: "#4fc3f7"; radius: 2 * scaleBase
                    visible: navBar.currentIndex === 8
                }
            }
            onClicked: { navBar.currentIndex = 8; logPageInstance.refreshLogs(); }
        }
    }

    // ========== 场景编辑页覆盖层 ==========
    Rectangle {
        id: editOverlay
        anchors.fill: parent
        color: "#000000"
        opacity: 0.85
        visible: false
        z: 100

        MouseArea { anchors.fill: parent; onClicked: {} }

        SceneEditPage {
            id: sceneEditOverlayInstance
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.9, 900 * scaleBase)
            height: Math.min(parent.height * 0.9, 700 * scaleBase)
            visible: editOverlay.visible

            onSaveScene: function (sceneData) {
                editOverlay.visible = false;
            }
            onCancelEdit: editOverlay.visible = false
            onDeleteScene: function (sceneId) {
                editOverlay.visible = false;
                SceneModel.load();
            }
        }
    }

    // ========== 全局 Snackbar ==========
    Rectangle {
        id: snackbar
        width: Math.min(parent.width - 40 * scaleBase, 600)
        height: 48 * scaleBase
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: navBar.height + 16 * scaleBase
        radius: 12 * scaleBase
        color: "#2d2d2d"
        opacity: snackbarVisible ? 1 : 0
        visible: opacity > 0
        z: 200

        property string snackbarText: ""
        property bool snackbarVisible: false
        Material.elevation: 8

        Label {
            anchors.fill: parent
            anchors.leftMargin: 20 * scaleBase
            anchors.rightMargin: 50 * scaleBase
            text: snackbar.snackbarText
            color: "#ffffff"
            font.pixelSize: 13 * scaleBase
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 12 * scaleBase
            width: 28 * scaleBase
            height: 28 * scaleBase
            radius: 14 * scaleBase
            color: "#4fc3f7"
            opacity: 0.8

            MouseArea {
                anchors.fill: parent
                onClicked: snackbar.hide()
                Label {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 12 * scaleBase
                    color: "#ffffff"
                }
            }
        }

        Timer {
            id: snackbarTimer
            interval: 3500; repeat: false
            onTriggered: snackbar.hide()
        }

        function show(message) {
            snackbar.snackbarText = message;
            snackbar.snackbarVisible = true;
            snackbarTimer.restart();
        }

        function hide() {
            snackbar.snackbarVisible = false;
            snackbarTimer.stop();
        }
    }

    function navigateToPage(index) {
        if (index >= 0 && index < 9) navBar.currentIndex = index;
    }
}
