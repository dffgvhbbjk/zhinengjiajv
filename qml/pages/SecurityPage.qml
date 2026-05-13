import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtMultimedia
import zhinengjiajv

Page {
    id: securityPage
    title: qsTr("安防监控")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property bool _isRecording: false
    property int _recordingTimerSeconds: 0
    property bool _remoteStreamActive: false
    property bool _videoConnected: TcpController ? TcpController.isVideoConnected : false
    property bool _manualVideoMode: false
    property int _frameCounter: 0

    property string screenshotDir: "C:/Users/Public/Pictures/MySmartHome/Screenshots"
    property string videoDir: "C:/Users/Public/Videos/MySmartHome/Videos"

    WindowCapture {
        id: windowCapture
        active: false
        window: Window.window
    }

    MediaRecorder {
        id: cameraRecorder
        quality: MediaRecorder.HighQuality
        videoBitRate: 8000000
        videoFrameRate: 30

        onRecorderStateChanged: function(state) {
            if (state === MediaRecorder.RecordingState) {
                _isRecording = true;
                customSnackbar.show(qsTr("开始录像"), "#4caf50");
            } else if (state === MediaRecorder.StoppedState) {
                _isRecording = false;
                windowCapture.active = false;
                customSnackbar.show(qsTr("录像已保存"), "#4fc3f7");
            }
        }

        onErrorOccurred: function(error, message) {
            _isRecording = false;
            windowCapture.active = false;
            customSnackbar.show(qsTr("录像错误: ") + message, "#f44336");
        }
    }

    CaptureSession {
        id: captureSession
        windowCapture: windowCapture
        recorder: cameraRecorder
    }

    Timer {
        id: autoRecordTimer
        interval: 1000
        repeat: true
        onTriggered: {
            _recordingTimerSeconds++;
            if (_recordingTimerSeconds >= 30)
                stopAutoRecording();
        }
    }

    function startAutoRecording() {
        if (!_isRecording) {
            _recordingTimerSeconds = 0;
            var newFile = videoDir + "/alert_" + new Date().toISOString().replace(/[:.]/g, "-") + ".mp4";
            cameraRecorder.outputLocation = newFile;
            windowCapture.active = true;
            cameraRecorder.record();
            autoRecordTimer.start();
            customSnackbar.show(qsTr("警告联动：自动录像30秒"), "#ff9800");
        }
    }

    function stopAutoRecording() {
        if (_isRecording) {
            autoRecordTimer.stop();
            cameraRecorder.stop();
            windowCapture.active = false;
        }
    }

    Connections {
        target: TcpController
        function onAlertReceived(alertId, content, level) {
            if (level >= 2)
                startAutoRecording();
            customSnackbar.show(qsTr("警告: %1").arg(content), level >= 3 ? "#f44336" : "#ff9800");
        }

        function onVideoFrameReceived(base64Data, width, height, timestamp) {
            _frameCounter++;
            _remoteStreamActive = true;
            remoteVideo.source = "";
            remoteVideo.source = "image://remotevideo/frame_" + _frameCounter + "_" + timestamp;
        }

        function onRawVideoFrameReceived(jpegData, width, height) {
            _frameCounter++;
            _remoteStreamActive = true;
            remoteVideo.source = "";
            remoteVideo.source = "image://remotevideo/raw_" + _frameCounter + "_" + Date.now();
        }

        function onCameraStreamToggled(enabled) {
            if (!enabled)
                _remoteStreamActive = false;
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f1923" }
            GradientStop { position: 1.0; color: "#162233" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20 * sc
        spacing: 16 * sc

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: securityPage.height * 0.6
            radius: 16 * sc
            color: "#0a1220"
            border.color: "#2a4a6a"
            border.width: 1
            Material.elevation: 6
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8 * sc
                spacing: 8 * sc

                Item {
                    id: cameraViewArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Image {
                        id: remoteVideo
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        asynchronous: true
                        visible: true
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 240 * sc; height: 160 * sc; radius: 12 * sc
                        color: "#1a2332"
                        visible: !_remoteStreamActive
                        border.color: "#2a4a6a"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12 * sc

                            Label {
                                text: "📹"
                                font.pixelSize: 48 * sc
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Label {
                                text: qsTr("树莓派视频流")
                                font.pixelSize: 16 * sc
                                font.bold: true; color: "#90a4ae"
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Label {
                                text: _remoteStreamActive ? qsTr("正在接收视频流") : qsTr("点击下方按钮连接视频流")
                                font.pixelSize: 12 * sc; color: "#607d8b"
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Label {
                                text: _videoConnected ? qsTr("视频通道 %1:9998").arg(TcpController ? TcpController.targetIp : "") : qsTr("TCP 连接后可使用视频")
                                font.pixelSize: 11 * sc; color: "#455a64"
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12 * sc
                        width: recIndicator.implicitWidth + 16 * sc
                        height: 28 * sc; radius: 14 * sc
                        color: "#c62828"
                        visible: _isRecording

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6 * sc

                            Rectangle {
                                id: recIndicator
                                width: 10 * sc; height: 10 * sc; radius: 5 * sc
                                color: "#ff0000"

                                SequentialAnimation on opacity {
                                    running: _isRecording; loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: 500 }
                                    NumberAnimation { to: 1.0; duration: 500 }
                                }
                            }

                            Label {
                                text: "REC " + formatSeconds(_recordingTimerSeconds)
                                font.pixelSize: 11 * sc; font.bold: true; color: "#ffffff"
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * sc
                    spacing: 10 * sc

                    Button {
                        text: qsTr("📸 截图")
                        enabled: _remoteStreamActive

                        background: Rectangle {
                            radius: 10 * sc
                            color: parent.enabled ? (parent.pressed ? "#1565c0" : "#1976d2") : "#1e2d3d"
                            border.color: parent.enabled ? "#2196f3" : "#2a4a6a"; border.width: 1
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? "#ffffff" : "#607d8b"
                            font.pixelSize: 12 * sc; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: takeScreenshot()
                    }

                    Button {
                        id: recordBtn
                        text: _isRecording ? qsTr("⏹ 停止录像") : qsTr("⏺ 开始录像")

                        background: Rectangle {
                            radius: 10 * sc
                            color: _isRecording ? (recordBtn.pressed ? "#b71c1c" : "#c62828") : (recordBtn.pressed ? "#1b5e20" : "#2e7d32")
                            border.color: _isRecording ? "#e53935" : "#4caf50"; border.width: 1
                        }
                        contentItem: Label {
                            text: recordBtn.text; color: "#ffffff"
                            font.pixelSize: 12 * sc; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (_isRecording) {
                                cameraRecorder.stop(); windowCapture.active = false;
                            } else {
                                _recordingTimerSeconds = 0;
                                var ts = new Date().toISOString().replace(/[:.]/g, "-");
                                cameraRecorder.outputLocation = videoDir + "/manual_" + ts + ".mp4";
                                windowCapture.active = true; cameraRecorder.record();
                            }
                        }
                    }

                    Button {
                        text: _videoConnected ? qsTr("🔴 断开视频") : qsTr("📹 连接视频")
                        enabled: TcpController ? TcpController.isConnected : false

                        background: Rectangle {
                            radius: 10 * sc
                            color: parent.enabled ? (_videoConnected ? (parent.pressed ? "#b71c1c" : "#c62828") : (parent.pressed ? "#1b5e20" : "#2e7d32")) : "#1e2d3d"
                            border.color: parent.enabled ? (_videoConnected ? "#e53935" : "#4caf50") : "#2a4a6a"; border.width: 1
                        }
                        contentItem: Label {
                            text: parent.text; color: parent.enabled ? "#ffffff" : "#607d8b"
                            font.pixelSize: 12 * sc; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (_videoConnected) {
                                TcpController.disconnectFromVideoStream(); _manualVideoMode = false;
                                customSnackbar.show(qsTr("视频流已断开"), "#ff9800");
                            } else {
                                _manualVideoMode = true;
                                TcpController.connectToVideoStream(TcpController.targetIp, 9998);
                                customSnackbar.show(qsTr("正在连接视频流 %1:9998").arg(TcpController.targetIp), "#4fc3f7");
                            }
                        }
                    }

                    Button {
                        text: qsTr("⛶ 全屏")

                        background: Rectangle {
                            radius: 10 * sc
                            color: parent.pressed ? "#4a148c" : "#6a1b9a"
                            border.color: "#8e24aa"; border.width: 1
                        }
                        contentItem: Label {
                            text: parent.text; color: "#ffffff"
                            font.pixelSize: 12 * sc; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (Window.window)
                                Window.window.visibility = Window.window.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: {
                            if (!TcpController || !TcpController.isConnected) return qsTr("⚪ TCP 未连接");
                            else if (_videoConnected && !_remoteStreamActive) return qsTr("🔵 视频已连接，接收中...");
                            else if (_videoConnected && _remoteStreamActive) return qsTr("🔴 树莓派实时视频");
                            else if (_manualVideoMode) return qsTr("🔵 视频连接中...");
                            else return qsTr("📹 点击连接视频流");
                        }
                        font.pixelSize: 12 * sc; font.bold: true
                        color: {
                            if (!TcpController || !TcpController.isConnected) return "#757575";
                            else if (_remoteStreamActive) return "#4caf50";
                            else if (_videoConnected || _manualVideoMode) return "#2196f3";
                            else return "#ff9800";
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: securityPage.height * 0.3
            radius: 16 * sc
            color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
            Material.elevation: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14 * sc
                spacing: 10 * sc

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: qsTr("🛡 传感器状态")
                        font.pixelSize: 16 * sc; font.bold: true; color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: qsTr("↻ 刷新")

                        background: Rectangle {
                            radius: 8 * sc
                            color: parent.pressed ? "#0d47a1" : "#1565c0"
                            border.color: "#1976d2"; border.width: 1
                        }
                        contentItem: Label {
                            text: parent.text; color: "#ffffff"
                            font.pixelSize: 11 * sc; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            DeviceModel.load(); refreshSensorList();
                            customSnackbar.show(qsTr("传感器列表已刷新"), "#4fc3f7");
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: sensorList
                        Layout.fillWidth: true
                        spacing: 8 * sc
                        clip: true
                        model: sensorListModel

                        delegate: Rectangle {
                            id: sensorCard
                            width: ListView.view.width
                            height: 72 * sc; radius: 12 * sc
                            color: model.isOnline ? (model.isAlarm ? "#2a1a1a" : "#1e3a50") : "#1a1a2e"
                            border.color: model.isOnline ? (model.isAlarm ? "#e53935" : "#2196f3") : "#333333"
                            border.width: 1
                            opacity: model.isOnline ? 1.0 : 0.5

                            Behavior on color { ColorAnimation { duration: 200 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12 * sc
                                spacing: 12 * sc

                                Rectangle {
                                    width: 40 * sc; height: 40 * sc; radius: 10 * sc
                                    color: {
                                        if (!model.isOnline) return "#616161";
                                        if (model.isAlarm) return "#e53935";
                                        return "#2196f3";
                                    }
                                    opacity: 0.2
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        anchors.centerIn: parent
                                        text: model.sensorIcon
                                        font.pixelSize: 20 * sc
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4 * sc

                                    Label {
                                        text: model.sensorName
                                        font.bold: true; font.pixelSize: 14 * sc
                                        color: model.isOnline ? "#ffffff" : "#757575"
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: model.statusText
                                        font.pixelSize: 11 * sc
                                        color: model.isOnline ? (model.isAlarm ? "#ff5252" : "#90a4ae") : "#616161"
                                    }
                                }

                                Rectangle {
                                    width: 8 * sc; height: 8 * sc; radius: 4 * sc
                                    color: model.isOnline ? "#4caf50" : "#f44336"
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                Rectangle {
                                    anchors.fill: parent; radius: 12 * sc
                                    color: "#ffffff"; opacity: parent.pressed ? 0.1 : 0
                                }
                                onClicked: {
                                    if (model.isOnline) {
                                        customSnackbar.show(qsTr("查看设备: %1").arg(model.sensorName), "#4fc3f7");
                                        if (Window.window) Window.window.tabBarCurrentIndex = 2;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60 * sc
            radius: 14 * sc
            color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
            Material.elevation: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8 * sc
                spacing: 10 * sc

                Button {
                    text: qsTr("🔔 警告中心")

                    background: Rectangle {
                        radius: 10 * sc
                        color: parent.pressed ? "#b71c1c" : "#c62828"
                        border.color: "#e53935"; border.width: 1
                    }
                    contentItem: Label {
                        text: parent.text; color: "#ffffff"
                        font.pixelSize: 13 * sc; font.bold: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (Window.window) { Window.window.tabBarCurrentIndex = 5; AlertModel.load(); }
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("🏠 返回首页")

                    background: Rectangle {
                        radius: 10 * sc
                        color: parent.pressed ? "#0d47a1" : "#1565c0"
                        border.color: "#1976d2"; border.width: 1
                    }
                    contentItem: Label {
                        text: parent.text; color: "#ffffff"
                        font.pixelSize: 13 * sc; font.bold: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (Window.window) Window.window.tabBarCurrentIndex = 0;
                    }
                }
            }
        }
    }

    Rectangle {
        id: customSnackbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80 * sc
        width: snackbarLabel.implicitWidth + 48 * sc
        height: 48 * sc; radius: 24 * sc
        color: "#333333"
        opacity: 0; visible: opacity > 0
        z: 100
        Material.elevation: 12

        property color accentColor: "#4fc3f7"
        border.color: accentColor; border.width: 1

        Label {
            id: snackbarLabel
            anchors.centerIn: parent
            text: ""; color: "#ffffff"
            font.pixelSize: 13 * sc; font.bold: true
        }

        Timer {
            id: snackbarTimer
            interval: 2500; repeat: false
            onTriggered: snackbarHide.start()
        }

        NumberAnimation { id: snackbarShow; target: customSnackbar; property: "opacity"; to: 1.0; duration: 200 }
        NumberAnimation { id: snackbarHide; target: customSnackbar; property: "opacity"; to: 0.0; duration: 300 }

        function show(message, color) {
            snackbarLabel.text = message;
            accentColor = color || "#4fc3f7";
            snackbarTimer.restart();
            snackbarShow.start();
        }
    }

    ListModel { id: sensorListModel }

    function refreshSensorList() {
        sensorListModel.clear();
        var count = DeviceModel.count;
        for (var i = 0; i < count; i++) {
            var dev = DeviceModel.getDeviceById(DeviceModel.deviceIdAt(i));
            if (!dev) continue;
            var devType = (dev["device_type"] || "").toLowerCase();
            var isOnline = dev["is_online"] ? true : false;
            var sensorName = dev["device_name"] || qsTr("未知传感器");
            var icon = "📷";
            var statusText = isOnline ? qsTr("正常") : qsTr("离线");
            var isAlarm = false;

            if (devType.indexOf("door") >= 0 || devType.indexOf("门") >= 0 || devType.indexOf("window") >= 0 || devType.indexOf("窗") >= 0) {
                icon = "🚪"; statusText = isOnline ? qsTr("已关闭") : qsTr("离线");
            } else if (devType.indexOf("smoke") >= 0 || devType.indexOf("烟雾") >= 0 || devType.indexOf("烟感") >= 0) {
                icon = "🔥"; statusText = isOnline ? qsTr("无烟雾") : qsTr("离线");
            } else if (devType.indexOf("pir") >= 0 || devType.indexOf("motion") >= 0 || devType.indexOf("人体") >= 0 || devType.indexOf("红外") >= 0) {
                icon = "👤"; statusText = isOnline ? qsTr("无人") : qsTr("离线");
            } else if (devType.indexOf("lpg") >= 0 || devType.indexOf("燃气") >= 0 || devType.indexOf("液化气") >= 0 || devType.indexOf("gas") >= 0) {
                icon = "🔧"; statusText = isOnline ? qsTr("无泄漏") : qsTr("离线");
            } else if (devType.indexOf("rain") >= 0 || devType.indexOf("雨滴") >= 0 || devType.indexOf("水浸") >= 0 || devType.indexOf("漏水") >= 0) {
                icon = "💧"; statusText = isOnline ? qsTr("无积水") : qsTr("离线");
            } else if (devType.indexOf("sos") >= 0 || devType.indexOf("紧急") >= 0 || devType.indexOf("报警") >= 0) {
                icon = "🚨"; statusText = isOnline ? qsTr("待命") : qsTr("离线");
            } else if (devType.indexOf("camera") >= 0 || devType.indexOf("摄像头") >= 0 || devType.indexOf("监控") >= 0 || devType.indexOf("cctv") >= 0) {
                icon = "📹"; statusText = isOnline ? qsTr("监控中") : qsTr("离线");
            } else if (devType.indexOf("temperature") >= 0 || devType.indexOf("温度") >= 0 || devType.indexOf("humidity") >= 0 || devType.indexOf("湿度") >= 0 || devType.indexOf("light") >= 0 || devType.indexOf("光照") >= 0 || devType.indexOf("air") >= 0 || devType.indexOf("空气") >= 0 || devType.indexOf("传感器") >= 0 || devType.indexOf("sensor") >= 0) {
                icon = "🌡️"; statusText = isOnline ? qsTr("正常") : qsTr("离线");
            }

            sensorListModel.append({
                "deviceId": dev["device_id"] || "",
                "sensorName": sensorName, "sensorIcon": icon,
                "statusText": statusText, "isOnline": isOnline, "isAlarm": isAlarm
            });
        }
    }

    function takeScreenshot() {
        if (!_remoteStreamActive) {
            customSnackbar.show(qsTr("树莓派视频流未就绪，无法截图"), "#f44336"); return;
        }
        var ts = new Date().toISOString().replace(/[:.]/g, "-");
        var fileName = screenshotDir + "/screenshot_" + ts + ".png";
        remoteVideo.grabToImage(function(result) { result.saveToFile(fileName); customSnackbar.show(qsTr("截图已保存"), "#4caf50"); });
    }

    function formatSeconds(s) {
        var mins = Math.floor(s / 60); var secs = s % 60;
        return (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    Component.onCompleted: { refreshSensorList(); }

    Connections {
        target: DeviceModel
        function onCountChanged() { refreshSensorList(); }
    }
}
