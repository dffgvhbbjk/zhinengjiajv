import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

Page {
    id: root

    title: qsTr("首页")

    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property var latestEnvironmentData: ({
            "temperature": "--",
            "humidity": "--",
            "pm25": "--",
            "co2": "--"
        })
    property var recentAlerts: []
    property bool hasUnhandledAlerts: false
    property bool _voiceDialogVisible: false
    property string _voiceRecognizedText: ""
    property bool _voiceListening: false
    property bool _voiceProcessing: false
    property int _deviceCountVersion: 0

    property int onlineDeviceCount: {
        _deviceCountVersion;
        var c = 0;
        for (var i = 0; i < DeviceModel.count; i++) {
            if (DeviceModel.data(DeviceModel.index(i, 0), DeviceModel.StatusRole))
                c++;
        }
        return c;
    }

    Connections {
        target: DeviceModel
        function onCountChanged() {
            _deviceCountVersion++;
        }
        function onDataChanged(topLeft, bottomRight, roles) {
            if (roles.indexOf(DeviceModel.StatusRole) >= 0)
                _deviceCountVersion++;
        }
    }

    Connections {
        target: UdpDiscoverer

        function onDataReceived(deviceId, data) {
            if (data["temperature"] !== undefined || data["humidity"] !== undefined) {
                root.latestEnvironmentData = {
                    "temperature": data["temperature"] !== undefined ? data["temperature"] : root.latestEnvironmentData["temperature"],
                    "humidity": data["humidity"] !== undefined ? data["humidity"] : root.latestEnvironmentData["humidity"],
                    "pm25": data["pm25"] !== undefined ? data["pm25"] : root.latestEnvironmentData["pm25"],
                    "co2": data["co2"] !== undefined ? data["co2"] : root.latestEnvironmentData["co2"]
                };
            }
        }
    }

    Connections {
        target: AlertModel

        function onCountChanged() {
            loadRecentAlerts();
        }
    }

    Component.onCompleted: {
        loadRecentAlerts();
    }

    Connections {
        target: VoiceController

        function onIsListeningChanged() {
            _voiceListening = VoiceController.isListening;
        }

        function onIsProcessingChanged() {
            _voiceProcessing = VoiceController.isProcessing;
        }

        function onRecognizedTextChanged() {
            _voiceRecognizedText = VoiceController.recognizedText;
        }

        function onRecognitionComplete(text) {
            _voiceRecognizedText = text;
            recognitionResultTimer.restart();
        }

        function onRecognitionFailed(error) {
            _voiceRecognizedText = "识别失败: " + error;
            _voiceProcessing = false;
            recognitionResultTimer.restart();
        }

        function onSpeechComplete() {
        }

        function onSpeechFailed(error) {
        }
    }

    function refreshAll() {
        UdpDiscoverer.startDiscovery();
        UdpDiscoverer.requestDataRefresh("255.255.255.255");
        loadRecentAlerts();
        toast.show(qsTr("已刷新"));
    }

    function loadRecentAlerts() {
        var alerts = [];
        var count = AlertModel.count;
        var limit = Math.min(count, 3);
        root.hasUnhandledAlerts = false;
        for (var i = 0; i < limit; i++) {
            var alertData = AlertModel.data(AlertModel.index(i, 0), AlertModel.ContentRole);
            var alertLevel = AlertModel.data(AlertModel.index(i, 0), AlertModel.LevelRole);
            var alertTimestamp = AlertModel.data(AlertModel.index(i, 0), AlertModel.TimestampRole);
            var isRead = AlertModel.data(AlertModel.index(i, 0), AlertModel.IsReadRole);
            if (!isRead && alertLevel >= 2) {
                root.hasUnhandledAlerts = true;
            }
            alerts.push({
                "id": i,
                "content": alertData || "",
                "level": alertLevel || 0,
                "timestamp": alertTimestamp || "",
                "isRead": isRead || false
            });
        }
        root.recentAlerts = alerts;
    }

    function navigateToDeviceControl(deviceId) {
        if (Window.window) {
            Window.window.tabBarCurrentIndex = 2;
        }
    }

    function navigateToSecurity() {
        if (Window.window) {
            Window.window.tabBarCurrentIndex = 1;
        }
    }

    function navigateToScene() {
        if (Window.window) {
            Window.window.tabBarCurrentIndex = 4;
        }
    }

    function navigateToAlerts() {
        if (Window.window) {
            Window.window.tabBarCurrentIndex = 5;
        }
        AlertModel.load();
    }

    function showEnvWarning(message) {
        toast.show(message);
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "#1a1a2e"
            }
            GradientStop {
                position: 1.0
                color: "#16213e"
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20 * sc
        spacing: 16 * sc

        Rectangle {
            id: topArea
            Layout.fillWidth: true
            Layout.preferredHeight: 280 * sc
            color: "transparent"

            Item {
                anchors.fill: parent

                Rectangle {
                    id: envCard
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.horizontalCenter
                    anchors.rightMargin: 8 * sc
                    radius: 16 * sc
                    Material.elevation: 6

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "#0f3460"
                        }
                        GradientStop {
                            position: 1.0
                            color: "#16213e"
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 8 * sc

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: qsTr("环境数据")
                                font.pixelSize: 18 * sc
                                font.bold: true
                                color: "#e94560"
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 24 * sc
                                height: 24 * sc
                                radius: 12 * sc
                                color: "#e94560"

                                Label {
                                    anchors.centerIn: parent
                                    text: "↻"
                                    font.pixelSize: 14 * sc
                                    color: "#ffffff"

                                    SequentialAnimation on rotation {
                                        id: refreshAnim
                                        running: false
                                        NumberAnimation {
                                            from: 0
                                            to: 360
                                            duration: 800
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        refreshAll();
                                        refreshAnim.start();
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12 * sc

                            EnvSubCard {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                cardIcon: "🌡"
                                cardLabel: qsTr("温度")
                                cardValue: root.latestEnvironmentData["temperature"] !== "--" ? root.latestEnvironmentData["temperature"] + "°C" : "--"
                                isAbnormal: root.latestEnvironmentData["temperature"] !== "--" && root.latestEnvironmentData["temperature"] > 35
                                normalGradientStart: "#ff6b35"
                                normalGradientEnd: "#f7931e"
                                onAbnormal: showEnvWarning(qsTr("温度异常: %1°C").arg(root.latestEnvironmentData["temperature"]))
                            }

                            EnvSubCard {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                cardIcon: "💧"
                                cardLabel: qsTr("湿度")
                                cardValue: root.latestEnvironmentData["humidity"] !== "--" ? root.latestEnvironmentData["humidity"] + "%" : "--"
                                isAbnormal: false
                                normalGradientStart: "#4ecdc4"
                                normalGradientEnd: "#44a08d"
                            }

                            EnvSubCard {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                cardIcon: "🌬"
                                cardLabel: qsTr("空气质量")
                                cardValue: root.latestEnvironmentData["pm25"] !== "--" ? "PM2.5: " + root.latestEnvironmentData["pm25"] : "--"
                                isAbnormal: root.latestEnvironmentData["pm25"] !== "--" && root.latestEnvironmentData["pm25"] > 100
                                normalGradientStart: "#667eea"
                                normalGradientEnd: "#764ba2"
                                onAbnormal: showEnvWarning(qsTr("PM2.5异常: %1").arg(root.latestEnvironmentData["pm25"]))
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Rectangle {
                                width: 6 * sc
                                height: 16 * sc
                                radius: 3 * sc
                                color: "#ba68c8"

                                Label {
                                    anchors.left: parent.right
                                    anchors.leftMargin: 8 * sc
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("CO₂: %1").arg(root.latestEnvironmentData["co2"] !== "--" ? root.latestEnvironmentData["co2"] : "--")
                                    font.pixelSize: 13 * sc
                                    color: "#ba68c8"
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Label {
                                text: "🕒 " + Qt.formatDateTime(new Date(), "hh:mm:ss")
                                font.pixelSize: 11 * sc
                                color: "#777777"
                            }
                        }
                    }
                }

                Rectangle {
                    id: weatherCard
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.horizontalCenter
                    anchors.leftMargin: 8 * sc
                    radius: 16 * sc
                    Material.elevation: 6

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "#1b4332"
                        }
                        GradientStop {
                            position: 1.0
                            color: "#2d6a4f"
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 12 * sc

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: "🌤 " + qsTr("天气") + (LocationService.city !== "" ? " - " + LocationService.city : "")
                                font.pixelSize: 18 * sc
                                font.bold: true
                                color: "#95d5b2"
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            ComboBox {
                                id: citySelector
                                model: LocationService.cityList
                                textRole: "name"
                                currentIndex: {
                                    for (var i = 0; i < LocationService.cityList.length; i++) {
                                        if (LocationService.cityList[i].name === LocationService.city)
                                            return i;
                                    }
                                    return 0;
                                }

                                onActivated: function (idx) {
                                    LocationService.selectCityByIndex(idx);
                                }

                                delegate: ItemDelegate {
                                    required property var model
                                    required property var modelData
                                    width: citySelector.width
                                    text: modelData.name
                                    font.pixelSize: 12 * sc

                                    background: Rectangle {
                                        color: citySelector.highlightedIndex === model.index ? "#2d6a4f" : "transparent"
                                        radius: 4 * sc
                                    }

                                    contentItem: Label {
                                        text: modelData.name
                                        color: citySelector.highlightedIndex === model.index ? "#ffffff" : "#d8f3dc"
                                        font.pixelSize: 12 * sc
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: 6 * sc
                                    color: citySelector.pressed ? "#2d6a4f" : "#40916c"
                                    width: 80 * sc
                                    height: 30 * sc
                                }

                                contentItem: Label {
                                    text: citySelector.currentText
                                    color: "#ffffff"
                                    font.pixelSize: 11 * sc
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 10 * sc
                                }

                                popup: Popup {
                                    y: citySelector.height
                                    width: citySelector.width
                                    implicitHeight: contentItem.implicitHeight
                                    padding: 4 * sc

                                    contentItem: ListView {
                                        clip: true
                                        implicitHeight: contentHeight
                                        model: citySelector.delegateModel
                                        currentIndex: citySelector.highlightedIndex
                                    }

                                    background: Rectangle {
                                        radius: 8 * sc
                                        color: "#1a2332"
                                        border.color: "#2a4a6a"
                                    }
                                }
                            }

                            Button {
                                text: "\u{1F4CD}"
                                flat: true
                                onClicked: {
                                    LocationService.locate();
                                }

                                background: Rectangle {
                                    radius: 6 * sc
                                    color: parent.pressed ? "#2d6a4f" : "#40916c"
                                    width: 30 * sc
                                    height: 30 * sc
                                }

                                contentItem: Label {
                                    text: parent.text
                                    color: "#ffffff"
                                    font.pixelSize: 14 * sc
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                width: 8 * sc
                                height: 8 * sc
                                radius: 4 * sc
                                color: LocationService.isLocating ? "#ff9800" : (WeatherService.errorString !== "" ? "#f44336" : "#4caf50")

                                SequentialAnimation on opacity {
                                    running: LocationService.isLocating || WeatherService.isLoading
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        to: 0.3
                                        duration: 500
                                    }
                                    NumberAnimation {
                                        to: 1.0
                                        duration: 500
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 20 * sc

                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 6 * sc

                                Label {
                                    text: WeatherService.weatherText !== "" ? getWeatherIcon(WeatherService.weatherText) : "🌤"
                                    font.pixelSize: 56 * sc
                                }

                                Label {
                                    text: WeatherService.temperature || "--"
                                    font.pixelSize: 32 * sc
                                    font.bold: true
                                    color: "#ffffff"
                                }

                                Label {
                                    text: WeatherService.weatherText || qsTr("加载中...")
                                    font.pixelSize: 14 * sc
                                    color: WeatherService.errorString !== "" ? "#ff6b6b" : "#95d5b2"
                                }
                            }

                            Rectangle {
                                width: 1
                                Layout.fillHeight: true
                                color: "#40916c"
                            }

                            ColumnLayout {
                                Layout.fillHeight: true
                                spacing: 8 * sc

                                Label {
                                    text: qsTr("详细信息")
                                    font.pixelSize: 13 * sc
                                    font.bold: true
                                    color: "#95d5b2"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6 * sc

                                    RowLayout {
                                        spacing: 8 * sc
                                        Label {
                                            text: "💧"
                                            font.pixelSize: 14 * sc
                                        }
                                        Label {
                                            text: qsTr("湿度: %1").arg(WeatherService.humidity || "--")
                                            font.pixelSize: 12 * sc
                                            color: "#d8f3dc"
                                        }
                                    }

                                    RowLayout {
                                        spacing: 8 * sc
                                        Label {
                                            text: "💨"
                                            font.pixelSize: 14 * sc
                                        }
                                        Label {
                                            text: qsTr("风向: %1").arg(WeatherService.windDirection || "--")
                                            font.pixelSize: 12 * sc
                                            color: "#d8f3dc"
                                        }
                                    }

                                    RowLayout {
                                        spacing: 8 * sc
                                        Label {
                                            text: "🌬"
                                            font.pixelSize: 14 * sc
                                        }
                                        Label {
                                            text: qsTr("风速: %1").arg(WeatherService.windSpeed || "--")
                                            font.pixelSize: 12 * sc
                                            color: "#d8f3dc"
                                        }
                                    }

                                    RowLayout {
                                        spacing: 8 * sc
                                        Label {
                                            text: "📍"
                                            font.pixelSize: 14 * sc
                                        }
                                        Label {
                                            text: qsTr("坐标: %1°N, %2°E").arg(LocationService.latitude.toFixed(2)).arg(LocationService.longitude.toFixed(2))
                                            font.pixelSize: 12 * sc
                                            color: "#d8f3dc"
                                        }
                                    }

                                    RowLayout {
                                        spacing: 8 * sc
                                        Label {
                                            text: "🏙"
                                            font.pixelSize: 14 * sc
                                        }
                                        Label {
                                            text: qsTr("城市编码: %1").arg(LocationService.cityCode)
                                            font.pixelSize: 12 * sc
                                            color: "#d8f3dc"
                                        }
                                    }
                                }

                                Label {
                                    text: WeatherService.lastUpdate !== "" ? qsTr("更新: %1").arg(WeatherService.lastUpdate) : qsTr("等待更新...")
                                    font.pixelSize: 10 * sc
                                    color: "#52b788"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12 * sc

            Label {
                text: qsTr("📊 设备概览")
                font.pixelSize: 18 * sc
                font.bold: true
                color: "#ffffff"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100 * sc
                radius: 14 * sc
                color: "#1a2332"
                border.color: "#2a4a6a"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16 * sc
                    spacing: 16 * sc

                    StatCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        statIcon: "💻"
                        statLabel: "设备总数"
                        statValue: DeviceModel.count
                        statColor: "#4fc3f7"
                    }
                    StatCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        statIcon: "🟢"
                        statLabel: "在线设备"
                        statValue: onlineDeviceCount
                        statColor: "#4caf50"
                    }
                    StatCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        statIcon: "🔔"
                        statLabel: "告警"
                        statValue: AlertModel.unreadCount || 0
                        statColor: "#ff9800"
                    }
                }
            }

            Label {
                text: qsTr("💡 快捷入口")
                font.pixelSize: 18 * sc
                font.bold: true
                color: "#ffffff"
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 64 * sc
                spacing: 12 * sc

                QuickButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64 * sc
                    buttonText: qsTr("语音控制")
                    buttonIcon: "🎤"
                    buttonColorStart: "#1565c0"
                    buttonColorEnd: "#0d47a1"
                    onClicked: {
                        recognitionResultTimer.stop();
                        _voiceDialogVisible = true;
                        VoiceController.startListening();
                    }
                }

                QuickButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64 * sc
                    buttonText: qsTr("场景模式")
                    buttonIcon: "🎬"
                    buttonColorStart: "#e65100"
                    buttonColorEnd: "#bf360c"
                    onClicked: navigateToScene()
                }

                QuickButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64 * sc
                    buttonText: qsTr("安防监控")
                    buttonIcon: "🛡"
                    buttonColorStart: "#c62828"
                    buttonColorEnd: "#b71c1c"
                    onClicked: navigateToSecurity()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48 * sc
            Material.elevation: root.hasUnhandledAlerts ? 8 : 4

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: root.hasUnhandledAlerts ? "#4a2c0a" : "#1e1e2e"
                }
                GradientStop {
                    position: 1.0
                    color: root.hasUnhandledAlerts ? "#3e2723" : "#16213e"
                }
            }

            border.color: root.hasUnhandledAlerts ? "#ff9800" : "#2a2a4a"
            border.width: root.hasUnhandledAlerts ? 2 : 1

            MouseArea {
                anchors.fill: parent
                onClicked: navigateToAlerts()
                hoverEnabled: true

                Rectangle {
                    anchors.fill: parent
                    color: "#ffffff"
                    opacity: parent.pressed ? 0.1 : 0
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12 * sc
                anchors.rightMargin: 12 * sc
                spacing: 10 * sc

                Rectangle {
                    width: 28 * sc
                    height: 28 * sc
                    radius: 14 * sc
                    color: root.hasUnhandledAlerts ? "#ff9800" : "#555577"

                    Label {
                        anchors.centerIn: parent
                        text: "🔔"
                        font.pixelSize: 14 * sc
                    }

                    SequentialAnimation on opacity {
                        running: root.hasUnhandledAlerts
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.3
                            duration: 500
                        }
                        NumberAnimation {
                            to: 1.0
                            duration: 500
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: alertListView
                        anchors.fill: parent
                        orientation: Qt.Horizontal
                        spacing: 48 * sc
                        model: root.recentAlerts
                        interactive: false

                        delegate: Label {
                            text: {
                                var alert = modelData || {};
                                var levelText = "";
                                if (alert["level"] >= 3)
                                    levelText = "🔴 [严重] ";
                                else if (alert["level"] >= 2)
                                    levelText = "🟠 [警告] ";
                                else
                                    levelText = "🔵 [提示] ";
                                return levelText + (alert["content"] || "") + "  -  " + (alert["timestamp"] || "");
                            }
                            font.pixelSize: 12 * sc
                            color: {
                                var lvl = (modelData && modelData["level"]) || 0;
                                if (lvl >= 3)
                                    return "#ff5252";
                                if (lvl >= 2)
                                    return "#ff9800";
                                return "#9e9e9e";
                            }
                            verticalAlignment: Text.AlignVCenter
                            height: parent.height
                        }
                    }

                    SequentialAnimation {
                        running: alertListView.contentWidth > alertListView.width && root.recentAlerts.length > 0
                        loops: Animation.Infinite

                        PauseAnimation {
                            duration: 1500
                        }
                        NumberAnimation {
                            target: alertListView
                            property: "contentX"
                            from: 0
                            to: alertListView.contentWidth - alertListView.width
                            duration: 10000
                        }
                        PauseAnimation {
                            duration: 1500
                        }
                        NumberAnimation {
                            target: alertListView
                            property: "contentX"
                            from: alertListView.contentWidth - alertListView.width
                            to: 0
                            duration: 10000
                        }
                    }
                }
            }

            visible: root.recentAlerts.length > 0
        }
    }

    Timer {
        id: recognitionResultTimer
        interval: 1500
        repeat: false
        onTriggered: {
            _voiceDialogVisible = false;
        }
    }

    Rectangle {
        id: voiceOverlay
        anchors.fill: parent
        color: "#000000"
        opacity: _voiceDialogVisible ? 0.7 : 0
        visible: opacity > 0
        z: 150

        MouseArea {
            anchors.fill: parent
            onClicked: {
                _voiceDialogVisible = false;
                VoiceController.stopListening();
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 360 * sc
            height: 420 * sc
            radius: 24 * sc
            color: "#1a1a2e"
            border.color: "#4fc3f7"
            border.width: 2
            Material.elevation: 16

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24 * sc
                spacing: 20 * sc

                Label {
                    text: "🎤"
                    font.pixelSize: 48 * sc
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: _voiceListening ? qsTr("正在聆听...") : (_voiceProcessing ? qsTr("识别中...") : qsTr("语音控制"))
                    font.pixelSize: 20 * sc
                    font.bold: true
                    color: "#4fc3f7"
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80 * sc
                    radius: 16 * sc
                    color: _voiceListening ? "#0d47a1" : (_voiceProcessing ? "#1b5e20" : "#2d2d2d")

                    Label {
                        anchors.centerIn: parent
                        text: _voiceListening ? qsTr("请说话...") : (_voiceRecognizedText || qsTr("点击按钮开始说话"))
                        font.pixelSize: 16 * sc
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        width: parent.width - 24 * sc
                    }

                    SequentialAnimation on opacity {
                        running: _voiceListening
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.5
                            duration: 800
                        }
                        NumberAnimation {
                            to: 1.0
                            duration: 800
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 16 * sc

                    Rectangle {
                        width: 64 * sc
                        height: 64 * sc
                        radius: 32 * sc
                        color: _voiceListening ? "#f44336" : "#4fc3f7"

                        Label {
                            anchors.centerIn: parent
                            text: _voiceListening ? "⏹" : "🎤"
                            font.pixelSize: 24 * sc
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (_voiceListening) {
                                    VoiceController.stopListening();
                                } else {
                                    VoiceController.startListening();
                                }
                            }
                        }

                        SequentialAnimation on scale {
                            id: voicePulse
                            running: _voiceListening
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 1.15
                                duration: 600
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 1.0
                                duration: 600
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: 64 * sc
                        height: 64 * sc
                        radius: 32 * sc
                        color: "#555555"

                        Label {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 24 * sc
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                _voiceDialogVisible = false;
                                VoiceController.stopListening();
                            }
                        }
                    }
                }

                Label {
                    text: qsTr("指令: 开灯/关灯 [名称]、开空调/关空调 [名称]、全部打开/关闭、天气、传感器、能耗、打开场景[名称]")
                    font.pixelSize: 11 * sc
                    color: "#777777"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    Rectangle {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 64 * sc
        width: toastLabel.implicitWidth + 48 * sc
        height: 52 * sc
        radius: 26 * sc
        color: "#333333"
        opacity: 0
        visible: opacity > 0
        z: 100

        Material.elevation: 12

        Label {
            id: toastLabel
            anchors.centerIn: parent
            text: ""
            color: "#ffffff"
            font.pixelSize: 14 * sc
        }

        Timer {
            id: toastTimer
            interval: 2500
            repeat: false
            onTriggered: {
                toastHide.start();
            }
        }

        function show(message) {
            toastLabel.text = message;
            toastShow.start();
            toastTimer.restart();
        }

        NumberAnimation {
            id: toastShow
            target: toast
            property: "opacity"
            to: 1.0
            duration: 200
        }

        NumberAnimation {
            id: toastHide
            target: toast
            property: "opacity"
            to: 0.0
            duration: 300
        }
    }

    function getWeatherIcon(weatherText) {
        if (weatherText.indexOf("晴") >= 0)
            return "🌞";
        if (weatherText.indexOf("多云") >= 0)
            return "🌤";
        if (weatherText.indexOf("阴") >= 0)
            return "🌒";
        if (weatherText.indexOf("小雨") >= 0)
            return "🌧";
        if (weatherText.indexOf("中雨") >= 0)
            return "🌧";
        if (weatherText.indexOf("大雨") >= 0)
            return "🌧";
        if (weatherText.indexOf("暴雨") >= 0)
            return "🌩";
        if (weatherText.indexOf("雷阵雨") >= 0)
            return "🌩";
        if (weatherText.indexOf("雪") >= 0)
            return "🌨";
        if (weatherText.indexOf("雾") >= 0)
            return "🌫";
        if (weatherText.indexOf("霾") >= 0)
            return "🌫";
        return "🌤";
    }

    component EnvSubCard: Rectangle {
        property string cardIcon: ""
        property string cardLabel: ""
        property string cardValue: "--"
        property bool isAbnormal: false
        property string normalGradientStart: "#667eea"
        property string normalGradientEnd: "#764ba2"
        signal abnormal

        radius: 14
        Material.elevation: isAbnormal ? 10 : 4

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: isAbnormal ? "#b71c1c" : normalGradientStart
            }
            GradientStop {
                position: 1.0
                color: isAbnormal ? "#d32f2f" : normalGradientEnd
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 32 * sc
            height: 32 * sc
            radius: 16 * sc
            color: "#ffffff"
            opacity: 0.15

            Label {
                anchors.centerIn: parent
                text: parent.parent.isAbnormal ? "!" : "✓"
                font.pixelSize: 16 * sc
                color: "#ffffff"
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6 * sc

            Label {
                text: cardIcon
                font.pixelSize: 30 * sc
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: cardValue
                font.pixelSize: 18 * sc
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignHCenter
                elide: Text.ElideMiddle
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                text: cardLabel
                font.pixelSize: 12 * sc
                color: "#ffffff"
                opacity: 0.8
                Layout.alignment: Qt.AlignHCenter
            }
        }

        onIsAbnormalChanged: {
            if (isAbnormal) {
                abnormal();
            }
        }
    }

    component StatCard: Rectangle {
        property string statIcon: ""
        property string statLabel: ""
        property var statValue: ""
        property color statColor: "#4fc3f7"

        radius: 12 * sc
        color: "#0f1623"
        border.color: "#2a2a4a"
        border.width: 1

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4 * sc

            Label {
                text: statIcon
                font.pixelSize: 24 * sc
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: typeof statValue === "number" ? String(statValue) : String(statValue)
                font.pixelSize: 20 * sc
                font.bold: true
                color: statColor
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: statLabel
                font.pixelSize: 11 * sc
                color: "#90a4ae"
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    component QuickButton: Rectangle {
        property string buttonText: ""
        property string buttonIcon: ""
        property string buttonColorStart: "#2196f3"
        property string buttonColorEnd: "#1976d2"
        signal clicked

        radius: 14 * sc
        Material.elevation: 6

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: buttonColorStart
            }
            GradientStop {
                position: 1.0
                color: buttonColorEnd
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: parent.clicked()
            hoverEnabled: true

            Rectangle {
                anchors.fill: parent
                radius: 14 * sc
                color: "#ffffff"
                opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.08 : 0)
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 10 * sc

                Rectangle {
                    width: 36 * sc
                    height: 36 * sc
                    radius: 10 * sc
                    color: "#ffffff"
                    opacity: 0.2

                    Label {
                        anchors.centerIn: parent
                        text: buttonIcon
                        font.pixelSize: 18 * sc
                    }
                }

                Label {
                    text: buttonText
                    font.pixelSize: 15 * sc
                    font.bold: true
                    color: "#ffffff"
                }
            }
        }
    }
}
