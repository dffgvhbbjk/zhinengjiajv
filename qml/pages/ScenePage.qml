import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

Page {
    id: root

    title: qsTr("智能场景")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property bool _refreshing: false
    property string _executingSceneId: ""
    property real _executionProgress: 0.0
    property var sceneDataList: []

    signal navigateToEdit(var sceneData)
    signal backToHome

    function getSceneStatusGradient(status) {
        switch (status) {
        case 0: return { "start": "#2d2d2d", "end": "#3d3d3d", "border": "#555555" };
        case 1: return { "start": "#1a2744", "end": "#1e3a5f", "border": "#2196F3" };
        case 2: return { "start": "#1a365d", "end": "#2563eb", "border": "#4caf50" };
        case 3: return { "start": "#3d2d1a", "end": "#5d4037", "border": "#ff9800" };
        default: return { "start": "#2d2d2d", "end": "#3d3d3d", "border": "#555555" };
        }
    }

    function getSceneStatusText(status) {
        switch (status) {
        case 0: return qsTr("已停用"); case 1: return qsTr("未生效");
        case 2: return qsTr("生效中"); case 3: return qsTr("已过期");
        default: return qsTr("未知");
        }
    }

    Component.onCompleted: { loadScenes(); }

    Connections {
        target: SceneModel
        function onCountChanged() { if (_refreshing) return; loadScenes(); }
    }

    function loadScenes() {
        if (_refreshing) return;
        _refreshing = true;
        var scenes = [];
        var count = SceneModel.count;
        for (var i = 0; i < count; i++) {
scenes.push({
                    "sceneId": SceneModel.data(SceneModel.index(i, 0), SceneModel.SceneIdRole) || "",
                    "sceneName": SceneModel.data(SceneModel.index(i, 0), SceneModel.SceneNameRole) || "",
                    "triggerType": SceneModel.data(SceneModel.index(i, 0), SceneModel.TriggerTypeRole) || "manual",
                    "triggerDeviceId": SceneModel.data(SceneModel.index(i, 0), SceneModel.TriggerDeviceIdRole) || "",
                    "triggerSensorData": SceneModel.data(SceneModel.index(i, 0), SceneModel.TriggerSensorDataRole) || "",
                    "triggerTime": SceneModel.data(SceneModel.index(i, 0), SceneModel.TriggerTimeRole) || "",
                    "actions": SceneModel.data(SceneModel.index(i, 0), SceneModel.ActionsRole) || "",
                    "actionDevices": SceneModel.data(SceneModel.index(i, 0), SceneModel.ActionDevicesRole) || "",
                    "isEnabled": SceneModel.data(SceneModel.index(i, 0), SceneModel.IsEnabledRole),
                    "effectiveCount": SceneModel.data(SceneModel.index(i, 0), SceneModel.EffectiveCountRole) || 0,
                    "lastExecutedAt": SceneModel.data(SceneModel.index(i, 0), SceneModel.LastExecutedAtRole) || "",
                    "sceneStatus": SceneModel.data(SceneModel.index(i, 0), SceneModel.SceneStatusRole) || 0
                });
        }
        root.sceneDataList = scenes;
        _refreshing = false;
    }

    function executeScene(sceneId, sceneName) {
        if (!TcpController.isConnected()) {
            toast.show(qsTr("未连接网关，无法执行场景"));
            return;
        }
        if (_executingSceneId !== "") return;
        var cmdId = "scene_" + new Date().getTime();
        _executingSceneId = sceneId; _executionProgress = 0.0;
        executionDialog.sceneName = sceneName; executionDialog.open();
        progressTimer.start();
        TcpController.sendSceneCommand(cmdId, sceneId);
    }

    function onExecutionSuccess(sceneId) {
        if (_executingSceneId === "" || _executingSceneId !== sceneId) return;
        progressTimer.stop(); _executionProgress = 1.0;
        toast.show(qsTr("场景执行成功")); delayCloseTimer.start();
    }

    function onExecutionFailed(sceneId, error) {
        if (_executingSceneId === "" || _executingSceneId !== sceneId) return;
        progressTimer.stop(); _executionProgress = -1;
        toast.show(qsTr("场景执行失败: %1").arg(error || qsTr("未知错误"))); delayCloseTimer.start();
    }

    function deleteSceneConfirm(sceneId, sceneName) {
        confirmDeleteDialog.sceneId = sceneId; confirmDeleteDialog.sceneName = sceneName; confirmDeleteDialog.open();
    }

    function toggleSceneEnabled(sceneId, enabled) {
        if (_refreshing) return;
        _refreshing = true;
        DatabaseManager.enableScene(sceneId, enabled);
        _refreshing = false;
        loadScenes();
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1a1a2e" }
            GradientStop { position: 1.0; color: "#16213e" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20 * sc
        spacing: 16 * sc

        Rectangle {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: 80 * sc
            radius: 12 * sc
            color: "#0f3460"
            Material.elevation: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16 * sc
                spacing: 16 * sc

                Label {
                    text: "🎬 " + qsTr("智能场景")
                    font.pixelSize: 22 * sc; font.bold: true; color: "#ffffff"
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: qsTr("共 %1 个场景").arg(root.sceneDataList.length)
                    font.pixelSize: 14 * sc; color: "#95d5b2"
                }

                Rectangle {
                    width: 120 * sc; height: 40 * sc; radius: 8 * sc
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4caf50" }
                        GradientStop { position: 1.0; color: "#388e3c" }
                    }
                    Material.elevation: 4

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var newScene = {
                                "sceneId": "", "sceneName": "", "triggerType": "manual",
                                "triggerDeviceId": "", "triggerSensorData": "", "triggerTime": "",
                                "actions": "", "actionDevices": [], "isEnabled": true, "createdAt": ""
                            };
                            root.navigateToEdit(newScene);
                        }
                        hoverEnabled: true

                        Rectangle {
                            anchors.fill: parent; radius: 8 * sc; color: "#ffffff"
                            opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.1 : 0)
                        }

                        RowLayout {
                            anchors.centerIn: parent; spacing: 6 * sc
                            Label { text: "+"; font.pixelSize: 20 * sc; font.bold: true; color: "#ffffff" }
                            Label { text: qsTr("添加场景"); font.pixelSize: 14 * sc; font.bold: true; color: "#ffffff" }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            GridView {
                id: sceneGrid
                anchors.fill: parent
                cellWidth: width / 2
                cellHeight: 180 * sc
                model: root.sceneDataList
                clip: true

                delegate: Rectangle {
                    id: sceneCard
                    width: (sceneGrid.width / 2) - 24 * sc
                    height: 166 * sc
                    radius: 16 * sc
                    Material.elevation: modelData["sceneStatus"] === 2 ? 8 : 3

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.getSceneStatusGradient(modelData["sceneStatus"])["start"] }
                        GradientStop { position: 1.0; color: root.getSceneStatusGradient(modelData["sceneStatus"])["end"] }
                    }
                    border.color: root.getSceneStatusGradient(modelData["sceneStatus"])["border"]
                    border.width: 1
                    opacity: modelData["sceneStatus"] === 0 ? 0.5 : 1.0

                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 5 * sc; radius: 4 * sc
                        color: root.getSceneStatusGradient(modelData["sceneStatus"])["border"]
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 10 * sc

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12 * sc

                            Rectangle {
                                width: 48 * sc; height: 48 * sc; radius: 12 * sc
                                color: root.getSceneStatusGradient(modelData["sceneStatus"])["border"]
                                opacity: 0.2

                                Label {
                                    anchors.centerIn: parent
                                    text: {
                                        switch (modelData["triggerType"]) {
                                        case "manual": return "👆"; case "time": return "⏰";
                                        case "device": return "💻"; case "sensor": return "🌡️";
                                        default: return "🎬";
                                        }
                                    }
                                    font.pixelSize: 26 * sc
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4 * sc

                                Label {
                                    text: modelData["sceneName"] || qsTr("未命名场景")
                                    font.bold: true; font.pixelSize: 16 * sc; color: "#ffffff"
                                    elide: Text.ElideMiddle
                                    Layout.maximumWidth: sceneCard.width - 150 * sc
                                }
                                RowLayout {
                                    spacing: 8 * sc
                                    Label {
                                        text: root.getSceneStatusText(modelData["sceneStatus"])
                                        font.pixelSize: 11 * sc
                                        color: root.getSceneStatusGradient(modelData["sceneStatus"])["border"]
                                    }
                                    Label {
                                        text: modelData["effectiveCount"] > 0 ? qsTr("已执行 %1 次").arg(modelData["effectiveCount"]) : ""
                                        font.pixelSize: 10 * sc; color: "#9e9e9e"
                                    }
                                }
                            }

                            Switch {
                                id: enableSwitch
                                Component.onCompleted: checked = modelData["isEnabled"]
                                onToggled: root.toggleSceneEnabled(modelData["sceneId"], checked)
                            }
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8 * sc

                            Rectangle {
                                Layout.fillWidth: true
                                height: 36 * sc; radius: 8 * sc
                                color: modelData["sceneStatus"] === 0 ? "#555555" : (modelData["sceneStatus"] === 3 ? "#c62828" : "#4caf50")
                                enabled: modelData["sceneStatus"] === 2

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (modelData["sceneStatus"] === 2) root.executeScene(modelData["sceneId"], modelData["sceneName"])
                                    hoverEnabled: true

                                    Rectangle {
                                        anchors.fill: parent; radius: 8 * sc; color: "#ffffff"
                                        opacity: parent.pressed ? 0.25 : (parent.containsMouse ? 0.15 : 0)
                                    }
                                    RowLayout {
                                        anchors.centerIn: parent; spacing: 6 * sc
                                        Label { text: "▶"; font.pixelSize: 14 * sc; color: "#ffffff" }
                                        Label {
                                            text: modelData["sceneStatus"] === 2 ? qsTr("执行") : (modelData["sceneStatus"] === 3 ? qsTr("已过期") : qsTr("已停用"))
                                            font.pixelSize: 13 * sc; font.bold: true; color: "#ffffff"
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: 36 * sc; height: 36 * sc; radius: 8 * sc; color: "#555577"
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.navigateToEdit(modelData)
                                    hoverEnabled: true
                                    Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.25 : (parent.containsMouse ? 0.15 : 0) }
                                    Label { anchors.centerIn: parent; text: "✎"; font.pixelSize: 16 * sc }
                                }
                            }

                            Rectangle {
                                width: 36 * sc; height: 36 * sc; radius: 8 * sc; color: "#c62828"
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.deleteSceneConfirm(modelData["sceneId"], modelData["sceneName"])
                                    hoverEnabled: true
                                    Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.25 : (parent.containsMouse ? 0.15 : 0) }
                                    Label { anchors.centerIn: parent; text: "✕"; font.pixelSize: 16 * sc; color: "#ffffff" }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 40 * sc; height: parent.height - 40 * sc
                    radius: 16 * sc; color: "#1a1a2e"
                    border.color: "#333333"; border.width: 1
                    visible: root.sceneDataList.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 12 * sc
                        Label { text: "🎭"; font.pixelSize: 48 * sc; Layout.alignment: Qt.AlignHCenter }
                        Label { text: qsTr("暂无场景"); font.pixelSize: 18 * sc; color: "#999999"; Layout.alignment: Qt.AlignHCenter }
                        Label { text: qsTr("点击上方按钮创建您的第一个智能场景"); font.pixelSize: 13 * sc; color: "#666666"; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60 * sc
            radius: 10 * sc
            color: "#16213e"
            border.color: "#2a2a4a"; border.width: 1

            MouseArea {
                anchors.fill: parent
                onClicked: root.backToHome()
                hoverEnabled: true

                Rectangle { anchors.fill: parent; radius: 10 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.08 : (parent.containsMouse ? 0.05 : 0) }

                RowLayout {
                    anchors.centerIn: parent; spacing: 8 * sc
                    Label { text: "←"; font.pixelSize: 18 * sc; color: "#95d5b2" }
                    Label { text: qsTr("返回首页"); font.pixelSize: 15 * sc; color: "#95d5b2" }
                }
            }
        }
    }

    Dialog {
        id: executionDialog
        title: qsTr("正在执行场景")
        modal: true
        width: 400 * sc
        anchors.centerIn: parent
        property string sceneName: ""

        ColumnLayout {
            width: parent.width; spacing: 16 * sc
            Label { text: qsTr("场景: %1").arg(executionDialog.sceneName); font.pixelSize: 16 * sc; font.bold: true; color: "#ffffff"; Layout.alignment: Qt.AlignHCenter }
            ProgressBar {
                Layout.fillWidth: true
                value: root._executionProgress >= 0 ? root._executionProgress : 0
                Material.accent: root._executionProgress < 0 ? "#f44336" : "#4caf50"
            }
            Label {
                text: root._executionProgress < 0 ? qsTr("执行失败") : (root._executionProgress >= 1.0 ? qsTr("执行完成") : qsTr("正在执行... %1%").arg(Math.round(root._executionProgress * 100)))
                font.pixelSize: 13 * sc
                color: root._executionProgress < 0 ? "#f44336" : (root._executionProgress >= 1.0 ? "#4caf50" : "#9e9e9e")
                Layout.alignment: Qt.AlignHCenter
            }
            Button {
                text: qsTr("确定")
                visible: root._executionProgress === 1.0 || root._executionProgress < 0
                Layout.alignment: Qt.AlignHCenter
                onClicked: executionDialog.close()
            }
        }

        onClosed: { progressTimer.stop(); delayCloseTimer.stop(); root._executingSceneId = ""; root._executionProgress = 0.0; }
    }

    Timer { id: progressTimer; interval: 200; repeat: true; onTriggered: { if (root._executionProgress < 0.9) root._executionProgress += 0.05; } }
    Timer { id: delayCloseTimer; interval: 1500; repeat: false; onTriggered: executionDialog.close() }

    Dialog {
        id: confirmDeleteDialog
        title: qsTr("确认删除")
        modal: true
        width: 360 * sc
        anchors.centerIn: parent
        property string sceneId: ""
        property string sceneName: ""

        background: Rectangle {
            radius: 14 * sc; color: "#1a2332"; border.color: "#c62828"; border.width: 1
        }
        Label {
            text: qsTr("确定要删除场景 \"%1\" 吗？\n此操作不可恢复！").arg(confirmDeleteDialog.sceneName)
            font.pixelSize: 14 * sc; wrapMode: Text.Wrap; width: parent.width - 48 * sc; color: "#e0e0e0"
        }
        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: {
            if (_refreshing) return;
            _refreshing = true;
            DatabaseManager.deleteScene(confirmDeleteDialog.sceneId);
            _refreshing = false;
            SceneModel.load();
            toast.show(qsTr("场景已删除"));
        }
    }

    Rectangle {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 64 * sc
        width: toastLabel.implicitWidth + 48 * sc
        height: 52 * sc; radius: 26 * sc
        color: "#333333"
        opacity: 0; visible: opacity > 0; z: 100
        Material.elevation: 12

        Label { id: toastLabel; anchors.centerIn: parent; text: ""; color: "#ffffff"; font.pixelSize: 14 * sc }

        Timer { id: toastTimer; interval: 2500; repeat: false; onTriggered: toastHide.start() }

        function show(message) { toastLabel.text = message; toastShow.start(); toastTimer.restart(); }

        NumberAnimation { id: toastShow; target: toast; property: "opacity"; to: 1.0; duration: 200 }
        NumberAnimation { id: toastHide; target: toast; property: "opacity"; to: 0.0; duration: 300 }
    }

    Connections {
        target: TcpController
        function onCommandSuccess(commandId, message) { if (String(commandId).startsWith("scene_")) root.onExecutionSuccess(root._executingSceneId); }
        function onCommandFailed(commandId, errorString) { if (String(commandId).startsWith("scene_")) root.onExecutionFailed(root._executingSceneId, errorString); }
    }
}
