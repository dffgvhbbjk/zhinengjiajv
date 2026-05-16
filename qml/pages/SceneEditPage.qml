import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

Page {
    id: root

    title: qsTr("编辑场景")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property var editingScene: ({
            "sceneId": "", "sceneName": "", "triggerType": "manual",
            "triggerDeviceId": "", "triggerSensorData": "", "triggerTime": "",
            "actions": "", "actionDevices": [], "isEnabled": true
        })
    property bool isEditMode: editingScene && editingScene["sceneId"] !== ""

    property string sceneName: editingScene["sceneName"] || ""
    property string selectedTriggerType: editingScene["triggerType"] || "manual"
    property string selectedTriggerDeviceId: editingScene["triggerDeviceId"] || ""
    property string selectedTriggerSensorData: editingScene["triggerSensorData"] || ""
    property string selectedTriggerSensorDeviceId: ""
    property string selectedTriggerSensorType: "temperature"
    property string selectedTriggerSensorOperator: ">"
    property double selectedTriggerSensorThreshold: 0
    property string selectedTriggerTime: editingScene["triggerTime"] || ""
    property string selectedTriggerDeviceAction: editingScene["triggerType"] === "device" ? (editingScene["triggerTime"] || "change") : "change"
    property var actionDevices: []
    property var actionDeviceActions: ({})

    property bool _refreshing: false
    property bool canSave: sceneName.trim().length > 0

    readonly property var hourOptions: (function() {
        var arr = []; for (var h = 0; h < 24; h++) arr.push(String(h).padStart(2, '0')); return arr;
    })()
    readonly property var minuteOptions: (function() {
        var arr = []; for (var m = 0; m < 60; m += 5) arr.push(String(m).padStart(2, '0')); return arr;
    })()

    signal saveScene(var sceneData)
    signal cancelEdit
    signal deleteScene(string sceneId)

    function getDeviceName(deviceId) {
        for (var i = 0; i < DeviceModel.count; i++)
            if (DeviceModel.deviceIdAt(i) === deviceId) return DeviceModel.data(DeviceModel.index(i, 0), DeviceModel.DeviceNameRole);
        return deviceId;
    }
    function getDeviceType(deviceId) {
        for (var i = 0; i < DeviceModel.count; i++)
            if (DeviceModel.deviceIdAt(i) === deviceId) return DeviceModel.data(DeviceModel.index(i, 0), DeviceModel.DeviceTypeRole);
        return "";
    }
    function getSensorTypeName(sensorType) {
        switch (sensorType) {
        case "temperature": return qsTr("温度"); case "humidity": return qsTr("湿度");
        case "pm25": return qsTr("PM2.5"); case "co2": return qsTr("CO2"); case "light": return qsTr("光照");
        case "rain": return qsTr("雨滴"); case "smoke": return qsTr("烟雾"); case "lpg": return qsTr("液化气");
        case "air_quality": return qsTr("空气质量"); case "power": return qsTr("功率"); default: return sensorType;
        }
    }
    function findGatewayDeviceId() {
        for (var i = 0; i < DeviceModel.count; i++) {
            var t = DeviceModel.data(DeviceModel.index(i, 0), DeviceModel.DeviceTypeRole);
            if (t && String(t).toLowerCase().indexOf("gateway") >= 0)
                return DeviceModel.deviceIdAt(i);
        }
        return DeviceModel.count > 0 ? DeviceModel.deviceIdAt(0) : "";
    }

    function defaultActionForDevice(deviceId) {
        var t = getDeviceType(deviceId).toLowerCase();
        if (t.indexOf("door") >= 0 || t.indexOf("门") >= 0) return "open";
        if (t.indexOf("light") >= 0 || t.indexOf("灯") >= 0) return "on";
        if (t.indexOf("fan") >= 0 || t.indexOf("风") >= 0) return "on";
        if (t.indexOf("humidifier") >= 0 || t.indexOf("加湿") >= 0) return "on";
        if (t.indexOf("buzzer") >= 0 || t.indexOf("蜂鸣") >= 0) return "on";
        if (t.indexOf("master") >= 0 || t.indexOf("总控") >= 0) return "on";
        return "on";
    }

    function addDeviceToDeviceList(deviceId) {
        if (root.actionDevices.indexOf(deviceId) < 0) {
            var newList = root.actionDevices.slice();
            newList.push(deviceId);
            root.actionDevices = newList;
            var newActions = {};
            var keys = Object.keys(root.actionDeviceActions);
            for (var k = 0; k < keys.length; k++) newActions[keys[k]] = root.actionDeviceActions[keys[k]];
            newActions[deviceId] = defaultActionForDevice(deviceId);
            root.actionDeviceActions = newActions;
        }
    }
    function removeDeviceFromList(deviceId) {
        var idx = root.actionDevices.indexOf(deviceId);
        if (idx >= 0) {
            var newList = root.actionDevices.slice();
            newList.splice(idx, 1);
            root.actionDevices = newList;
            var newActions = {};
            var keys = Object.keys(root.actionDeviceActions);
            for (var k = 0; k < keys.length; k++) {
                if (keys[k] !== deviceId) newActions[keys[k]] = root.actionDeviceActions[keys[k]];
            }
            root.actionDeviceActions = newActions;
        }
    }
    function confirmDelete() { if (root.isEditMode) confirmDeleteDialog.open(); }

    function saveCurrentScene() {
        if (!canSave) { toast.show(qsTr("请输入场景名称")); return; }

        if (root.actionDevices.length === 0) {
            toast.show(qsTr("请至少选择一个执行设备"));
            return;
        }

        if (root.selectedTriggerType === "device" && root.selectedTriggerDeviceId === "") {
            toast.show(qsTr("请选择触发设备"));
            return;
        }

        if (root.selectedTriggerType === "sensor" && root.selectedTriggerSensorDeviceId === "") {
            toast.show(qsTr("请选择传感器来源"));
            return;
        }

        var actionDevicesJson = JSON.stringify(root.actionDevices);
        var actionList = [];
        for (var i = 0; i < root.actionDevices.length; i++) {
            var devId = root.actionDevices[i];
            actionList.push(root.actionDeviceActions[devId] || "on");
        }
        var actionsJson = JSON.stringify(actionList);
        var triggerTimeForDb = root.selectedTriggerTime;
        if (root.selectedTriggerType === "device")
            triggerTimeForDb = root.selectedTriggerDeviceAction;
        var sensorDataJson = JSON.stringify({
            "sensorDeviceId": root.selectedTriggerSensorDeviceId, "sensorType": root.selectedTriggerSensorType,
            "operator": root.selectedTriggerSensorOperator, "threshold": root.selectedTriggerSensorThreshold
        });
        var sceneData = {
            "sceneId": root.editingScene["sceneId"] || ("scene_" + Date.now()),
            "sceneName": root.sceneName.trim(), "triggerType": root.selectedTriggerType,
            "triggerDeviceId": root.selectedTriggerType === "device" ? root.selectedTriggerDeviceId : "",
            "triggerSensorData": root.selectedTriggerType === "sensor" ? sensorDataJson : "",
            "triggerTime": triggerTimeForDb,
            "actions": actionsJson, "actionDevices": actionDevicesJson,
            "isEnabled": root.editingScene["isEnabled"] !== undefined ? root.editingScene["isEnabled"] : true,
            "createdAt": root.editingScene["createdAt"] || new Date().toISOString()
        };
        if (root.isEditMode) DatabaseManager.updateScene(sceneData["sceneId"], sceneData);
        else DatabaseManager.addScene(sceneData["sceneId"], sceneData["sceneName"], sceneData["triggerType"],
               sceneData["triggerDeviceId"], sceneData["triggerSensorData"], sceneData["triggerTime"],
               sceneData["actions"], sceneData["actionDevices"]);
        SceneModel.load();
        toast.show(root.isEditMode ? qsTr("场景已更新") : qsTr("场景已创建"));
        root.saveScene(sceneData);
    }

    Component.onCompleted: {
        _refreshing = true; DeviceModel.load(); _refreshing = false;
        if (root.editingScene && root.editingScene["sceneId"] !== "") {
            root.sceneName = root.editingScene["sceneName"] || "";
            root.selectedTriggerType = root.editingScene["triggerType"] || "manual";
            root.selectedTriggerDeviceId = root.editingScene["triggerDeviceId"] || "";
            root.selectedTriggerSensorData = root.editingScene["triggerSensorData"] || "";
            root.selectedTriggerTime = root.editingScene["triggerTime"] || "";
            root.selectedTriggerSensorDeviceId = root.findGatewayDeviceId();
            try {
                var sensorData = JSON.parse(root.selectedTriggerSensorData);
                if (sensorData && typeof sensorData === "object") {
                    root.selectedTriggerSensorType = sensorData["sensorType"] || "temperature";
                    root.selectedTriggerSensorOperator = sensorData["operator"] || ">";
                    root.selectedTriggerSensorThreshold = sensorData["threshold"] || 0;
                }
            } catch (e) { root.selectedTriggerSensorType = "temperature"; root.selectedTriggerSensorOperator = ">"; root.selectedTriggerSensorThreshold = 0; }
            var actionDevicesStr = root.editingScene["actionDevices"];
            if (actionDevicesStr && typeof actionDevicesStr === 'string') {
                try { root.actionDevices = JSON.parse(actionDevicesStr); } catch (e) { root.actionDevices = []; }
            } else if (Array.isArray(actionDevicesStr)) root.actionDevices = actionDevicesStr;
            var actionsStr = root.editingScene["actions"] || "";
            var parsedActions = [];
            if (actionsStr && typeof actionsStr === 'string') {
                try { parsedActions = JSON.parse(actionsStr); } catch (e) { parsedActions = []; }
            } else if (Array.isArray(actionsStr)) parsedActions = actionsStr;
            var newDeviceActions = {};
            for (var di = 0; di < root.actionDevices.length; di++) {
                newDeviceActions[root.actionDevices[di]] = (di < parsedActions.length && parsedActions[di]) ? parsedActions[di] : "on";
            }
            root.actionDeviceActions = newDeviceActions;
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0d1b2a" }
            GradientStop { position: 0.5; color: "#1a1a2e" }
            GradientStop { position: 1.0; color: "#0f1d2d" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: 56 * sc
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#112240" }
                GradientStop { position: 1.0; color: "#0a1628" }
            }
            Material.elevation: 6

            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: "#2a4a7f"; opacity: 0.5
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12 * sc
                spacing: 12 * sc

                Rectangle {
                    width: 36 * sc; height: 36 * sc; radius: 8 * sc; color: "#555577"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.cancelEdit()
                        hoverEnabled: true
                        Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.1 : 0) }
                        Label { anchors.centerIn: parent; text: "←"; font.pixelSize: 18 * sc; color: "#ffffff" }
                    }
                }

                Label { text: root.isEditMode ? qsTr("编辑场景") : qsTr("新建场景"); font.pixelSize: 18 * sc; font.bold: true; color: "#ffffff" }
                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 80 * sc; height: 36 * sc; radius: 8 * sc
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.canSave ? "#4caf50" : "#424242" }
                        GradientStop { position: 1.0; color: root.canSave ? "#388e3c" : "#333333" }
                    }
                    Material.elevation: root.canSave ? 4 : 0
                    enabled: root.canSave

                    MouseArea {
                        anchors.fill: parent; enabled: root.canSave
                        onClicked: root.saveCurrentScene(); hoverEnabled: true
                        Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.1 : 0) }
                        Label { anchors.centerIn: parent; text: qsTr("保存"); font.pixelSize: 14 * sc; font.bold: true; color: root.canSave ? "#ffffff" : "#757575" }
                    }
                }
            }
        }

        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: scrollView.width
                spacing: 16 * sc

                Item { height: 16 * sc; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110 * sc
                    radius: 14 * sc; color: "#1e2844"
                    border.color: "#2a3f5f"; border.width: 1

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.margins: 2; width: 3; radius: 2; color: "#4fc3f7"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 10 * sc

                        Row {
                            spacing: 6 * sc
                            Label { text: "📋"; font.pixelSize: 16 * sc }
                            Label { text: qsTr("基本信息"); font.pixelSize: 15 * sc; font.bold: true; color: "#e0e0e0" }
                            Label { text: "*"; font.pixelSize: 15 * sc; font.bold: true; color: "#f44336" }
                        }

                        TextField {
                            id: nameField
                            Layout.fillWidth: true
                            placeholderText: qsTr("请输入场景名称（必填）")
                            placeholderTextColor: "#757575"
                            font.pixelSize: 14 * sc; color: "#ffffff"
                            background: Rectangle {
                                radius: 8 * sc; color: "#152038"
                                border.color: nameField.activeFocus ? "#4fc3f7" : (root.sceneName.trim() === "" ? "#f44336" : "#424242")
                                border.width: 1
                            }
                            Component.onCompleted: text = root.sceneName
                            onTextEdited: root.sceneName = text
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 196 * sc
                    radius: 14 * sc; color: "#1e2844"
                    border.color: "#2a3f5f"; border.width: 1

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.margins: 2; width: 3; radius: 2; color: "#ff9800"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 12 * sc

                        Row {
                            spacing: 6 * sc
                            Label { text: "⚡"; font.pixelSize: 16 * sc }
                            Label { text: qsTr("触发方式"); font.pixelSize: 15 * sc; font.bold: true; color: "#e0e0e0" }
                        }

                        Grid {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 10 * sc; columnSpacing: 10 * sc

                            Rectangle {
                                width: (parent.width - 10 * sc) / 2; height: 60 * sc; radius: 10 * sc
                                color: root.selectedTriggerType === "manual" ? "#1565C0" : "#1a2340"
                                border.color: root.selectedTriggerType === "manual" ? "#42A5F5" : "#424242"
                                border.width: root.selectedTriggerType === "manual" ? 2 : 1

                                Row {
                                    anchors.centerIn: parent; spacing: 8 * sc
                                    Label { text: "👆"; font.pixelSize: 22 * sc }
                                    Label { text: qsTr("手动触发"); font.pixelSize: 13 * sc; color: root.selectedTriggerType === "manual" ? "#BBDEFB" : "#9e9e9e"; font.bold: root.selectedTriggerType === "manual" }
                                }
                                MouseArea {
                                    anchors.fill: parent; onClicked: root.selectedTriggerType = "manual"; hoverEnabled: true
                                    Rectangle { anchors.fill: parent; radius: 10 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) }
                                }
                            }
                            Rectangle {
                                width: (parent.width - 10 * sc) / 2; height: 60 * sc; radius: 10 * sc
                                color: root.selectedTriggerType === "time" ? "#1565C0" : "#1a2340"
                                border.color: root.selectedTriggerType === "time" ? "#42A5F5" : "#424242"
                                border.width: root.selectedTriggerType === "time" ? 2 : 1

                                Row {
                                    anchors.centerIn: parent; spacing: 8 * sc
                                    Label { text: "⏰"; font.pixelSize: 22 * sc }
                                    Label { text: qsTr("定时触发"); font.pixelSize: 13 * sc; color: root.selectedTriggerType === "time" ? "#BBDEFB" : "#9e9e9e"; font.bold: root.selectedTriggerType === "time" }
                                }
                                MouseArea {
                                    anchors.fill: parent; onClicked: root.selectedTriggerType = "time"; hoverEnabled: true
                                    Rectangle { anchors.fill: parent; radius: 10 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) }
                                }
                            }
                            Rectangle {
                                width: (parent.width - 10 * sc) / 2; height: 60 * sc; radius: 10 * sc
                                color: root.selectedTriggerType === "device" ? "#1565C0" : "#1a2340"
                                border.color: root.selectedTriggerType === "device" ? "#42A5F5" : "#424242"
                                border.width: root.selectedTriggerType === "device" ? 2 : 1

                                Row {
                                    anchors.centerIn: parent; spacing: 8 * sc
                                    Label { text: "💻"; font.pixelSize: 22 * sc }
                                    Label { text: qsTr("设备状态"); font.pixelSize: 13 * sc; color: root.selectedTriggerType === "device" ? "#BBDEFB" : "#9e9e9e"; font.bold: root.selectedTriggerType === "device" }
                                }
                                MouseArea {
                                    anchors.fill: parent; onClicked: root.selectedTriggerType = "device"; hoverEnabled: true
                                    Rectangle { anchors.fill: parent; radius: 10 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) }
                                }
                            }
                            Rectangle {
                                width: (parent.width - 10 * sc) / 2; height: 60 * sc; radius: 10 * sc
                                color: root.selectedTriggerType === "sensor" ? "#1565C0" : "#1a2340"
                                border.color: root.selectedTriggerType === "sensor" ? "#42A5F5" : "#424242"
                                border.width: root.selectedTriggerType === "sensor" ? 2 : 1

                                Row {
                                    anchors.centerIn: parent; spacing: 8 * sc
                                    Label { text: "🌡️"; font.pixelSize: 22 * sc }
                                    Label { text: qsTr("传感器"); font.pixelSize: 13 * sc; color: root.selectedTriggerType === "sensor" ? "#BBDEFB" : "#9e9e9e"; font.bold: root.selectedTriggerType === "sensor" }
                                }
                                MouseArea {
                                    anchors.fill: parent; onClicked: root.selectedTriggerType = "sensor"; hoverEnabled: true
                                    Rectangle { anchors.fill: parent; radius: 10 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: {
                        if (root.selectedTriggerType === "manual") return 0;
                        if (root.selectedTriggerType === "time") return 150 * sc;
                        if (root.selectedTriggerType === "device") return 260 * sc;
                        if (root.selectedTriggerType === "sensor") return 310 * sc;
                        return 0;
                    }
                    radius: 14 * sc; color: "#1e2844"
                    border.color: "#2a3f5f"; border.width: 1
                    visible: root.selectedTriggerType !== "manual"

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.margins: 2; width: 3; radius: 2; color: "#a1887f"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 12 * sc

                        Row {
                            spacing: 6 * sc
                            Label { text: "🎯"; font.pixelSize: 16 * sc }
                            Label { text: qsTr("触发条件"); font.pixelSize: 15 * sc; font.bold: true; color: "#e0e0e0" }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.selectedTriggerType === "time" ? timeTriggerLayout.implicitHeight : 0
                            visible: root.selectedTriggerType === "time"

                            ColumnLayout {
                                id: timeTriggerLayout
                                width: parent.width; spacing: 10 * sc

                                Label { text: "⏰ " + qsTr("设置触发时间"); font.pixelSize: 13 * sc; color: "#e0e0e0" }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6 * sc

                                    ComboBox {
                                        id: triggerHourCombo; model: root.hourOptions
                                        Component.onCompleted: {
                                            var parts = root.selectedTriggerTime.split(":");
                                            var hour = parts.length >= 2 ? String(parseInt(parts[0])).padStart(2, '0') : "08";
                                            for (var i = 0; i < model.length; i++) { if (model[i] === hour) { currentIndex = i; break; } }
                                        }
                                        onActivated: function(index) { root.selectedTriggerTime = model[index] + ":" + triggerMinuteCombo.currentText; }
                                    }
                                    Label { text: ":"; font.pixelSize: 16 * sc; font.bold: true; color: "#ffffff" }
                                    ComboBox {
                                        id: triggerMinuteCombo; model: root.minuteOptions
                                        Component.onCompleted: {
                                            var parts = root.selectedTriggerTime.split(":");
                                            var min = parts.length >= 2 ? String(parseInt(parts[1])).padStart(2, '0') : "00";
                                            var bestIdx = 0;
                                            for (var i = 0; i < model.length; i++) {
                                                if (model[i] === min) { bestIdx = i; break; }
                                                if (i < model.length - 1 && parseInt(model[i]) < parseInt(min) && parseInt(min) <= parseInt(model[i + 1]))
                                                    bestIdx = parseInt(min) - parseInt(model[i]) <= parseInt(model[i + 1]) - parseInt(min) ? i : i + 1;
                                            }
                                            currentIndex = bestIdx;
                                        }
                                        onActivated: function(index) { root.selectedTriggerTime = triggerHourCombo.currentText + ":" + model[index]; }
                                    }
                                    Label { text: qsTr("出发场景"); font.pixelSize: 13 * sc; color: "#90a4ae" }
                                }
                                Label { text: qsTr("场景将在每天此时自动执行"); font.pixelSize: 11 * sc; color: "#607d8b" }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.selectedTriggerType === "device" ? deviceTriggerLayout.implicitHeight : 0
                            visible: root.selectedTriggerType === "device"

                            ColumnLayout {
                                id: deviceTriggerLayout
                                width: parent.width; spacing: 10 * sc

                                Label { text: qsTr("当以下设备状态变化时触发场景"); font.pixelSize: 13 * sc; color: "#e0e0e0" }

                                ComboBox {
                                    id: triggerDeviceCombo; Layout.fillWidth: true; model: DeviceModel; textRole: "deviceName"; valueRole: "deviceId"
                                    displayText: {
                                        if (currentIndex >= 0 && currentIndex < DeviceModel.count)
                                            return DeviceModel.data(DeviceModel.index(currentIndex, 0), DeviceModel.DeviceNameRole) + " (" + DeviceModel.data(DeviceModel.index(currentIndex, 0), DeviceModel.DeviceTypeRole) + ")";
                                        return qsTr("选择设备");
                                    }
                                    Component.onCompleted: {
                                        if (root.selectedTriggerDeviceId !== "")
                                            for (var i = 0; i < DeviceModel.count; i++) {
                                                if (DeviceModel.deviceIdAt(i) === root.selectedTriggerDeviceId) { currentIndex = i; break; }
                                            }
                                    }
                                    onActivated: function(index) { root.selectedTriggerDeviceId = DeviceModel.deviceIdAt(index); }
                                    delegate: ItemDelegate {
                                        width: triggerDeviceCombo.width
                                        contentItem: Label { text: model.deviceName + (model.deviceType ? " (" + model.deviceType + ")" : ""); color: "#ffffff"; font.pixelSize: 13 * sc }
                                        background: Rectangle { color: index === triggerDeviceCombo.currentIndex ? "#1565C0" : "transparent" }
                                    }
                                }

                                Label { text: qsTr("触发条件"); font.pixelSize: 12 * sc; color: "#9e9e9e" }

                                Row {
                                    spacing: 8 * sc
                                    Rectangle {
                                        width: 90 * sc; height: 36 * sc; radius: 8 * sc
                                        color: root.selectedTriggerDeviceAction === "open" ? "#1b5e20" : "#152038"
                                        border.color: root.selectedTriggerDeviceAction === "open" ? "#4caf50" : "#424242"
                                        border.width: root.selectedTriggerDeviceAction === "open" ? 2 : 1
                                        Label { anchors.centerIn: parent; text: qsTr("设备打开"); font.pixelSize: 12 * sc; color: root.selectedTriggerDeviceAction === "open" ? "#a5d6a7" : "#9e9e9e"; font.bold: root.selectedTriggerDeviceAction === "open" }
                                        MouseArea { anchors.fill: parent; onClicked: root.selectedTriggerDeviceAction = "open"; hoverEnabled: true; Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) } }
                                    }
                                    Rectangle {
                                        width: 90 * sc; height: 36 * sc; radius: 8 * sc
                                        color: root.selectedTriggerDeviceAction === "close" ? "#b71c1c" : "#152038"
                                        border.color: root.selectedTriggerDeviceAction === "close" ? "#f44336" : "#424242"
                                        border.width: root.selectedTriggerDeviceAction === "close" ? 2 : 1
                                        Label { anchors.centerIn: parent; text: qsTr("设备关闭"); font.pixelSize: 12 * sc; color: root.selectedTriggerDeviceAction === "close" ? "#ef9a9a" : "#9e9e9e"; font.bold: root.selectedTriggerDeviceAction === "close" }
                                        MouseArea { anchors.fill: parent; onClicked: root.selectedTriggerDeviceAction = "close"; hoverEnabled: true; Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) } }
                                    }
                                    Rectangle {
                                        width: 90 * sc; height: 36 * sc; radius: 8 * sc
                                        color: root.selectedTriggerDeviceAction === "change" ? "#e65100" : "#152038"
                                        border.color: root.selectedTriggerDeviceAction === "change" ? "#ff9800" : "#424242"
                                        border.width: root.selectedTriggerDeviceAction === "change" ? 2 : 1
                                        Label { anchors.centerIn: parent; text: qsTr("任意变化"); font.pixelSize: 12 * sc; color: root.selectedTriggerDeviceAction === "change" ? "#ffcc80" : "#9e9e9e"; font.bold: root.selectedTriggerDeviceAction === "change" }
                                        MouseArea { anchors.fill: parent; onClicked: root.selectedTriggerDeviceAction = "change"; hoverEnabled: true; Rectangle { anchors.fill: parent; radius: 8 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.15 : (parent.containsMouse ? 0.08 : 0) } }
                                    }
                                }

                                Label {
                                    text: root.selectedTriggerDeviceAction === "open" ? qsTr("当选中设备打开时，自动执行本场景") :
                                          (root.selectedTriggerDeviceAction === "close" ? qsTr("当选中设备关闭时，自动执行本场景") :
                                           (root.selectedTriggerDeviceAction === "change" ? qsTr("当选中设备状态变化时，自动执行本场景") : qsTr("请选择触发条件")))
                                    font.pixelSize: 11 * sc; color: "#607d8b"; wrapMode: Text.Wrap; Layout.fillWidth: true
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.selectedTriggerType === "sensor" ? sensorTriggerLayout.implicitHeight : 0
                            visible: root.selectedTriggerType === "sensor"

                            ColumnLayout {
                                id: sensorTriggerLayout
                                width: parent.width; spacing: 10 * sc

                                Label { text: qsTr("当以下传感器数据满足条件时触发场景"); font.pixelSize: 13 * sc; color: "#e0e0e0" }

                                Label {
                                    text: qsTr("传感器来源: 网关传感器")
                                    font.pixelSize: 12 * sc; color: "#81c784"
                                }

                                RowLayout { spacing: 8 * sc
                                    Label { text: qsTr("数值"); font.pixelSize: 13 * sc; color: "#e0e0e0" }
                                    ComboBox {
                                        id: sensorTypeCombo; model: ["temperature", "humidity", "pm25", "co2", "light", "rain", "smoke", "lpg", "air_quality", "power"]
                                        displayText: root.getSensorTypeName(currentText)
                                        Component.onCompleted: { for (var i = 0; i < model.length; i++) { if (model[i] === root.selectedTriggerSensorType) { currentIndex = i; break; } } }
                                        onActivated: function(index) { root.selectedTriggerSensorType = model[index]; }
                                        delegate: ItemDelegate {
                                            width: sensorTypeCombo.width
                                            contentItem: Label { text: root.getSensorTypeName(sensorTypeCombo.model[index]); color: "#ffffff"; font.pixelSize: 13 * sc }
                                            background: Rectangle { color: index === sensorTypeCombo.currentIndex ? "#1565C0" : "transparent" }
                                        }
                                    }
                                }

                                RowLayout { spacing: 8 * sc
                                    Label { text: qsTr("条件"); font.pixelSize: 13 * sc; color: "#e0e0e0" }
                                    ComboBox {
                                        id: sensorOperatorCombo; model: [">", ">=", "<", "<=", "=="]
                                        Component.onCompleted: { for (var i = 0; i < model.length; i++) { if (model[i] === root.selectedTriggerSensorOperator) { currentIndex = i; break; } } }
                                        onActivated: function(index) { root.selectedTriggerSensorOperator = model[index]; }
                                    }
                                    SpinBox { id: sensorThresholdSpin; from: -100; to: 10000; stepSize: 1; editable: false; Component.onCompleted: value = root.selectedTriggerSensorThreshold; onValueModified: root.selectedTriggerSensorThreshold = value }
                                }

                                Label {
                                    text: {
                                        var opText = "";
                                        switch (root.selectedTriggerSensorOperator) { case ">": opText = qsTr("大于"); break; case ">=": opText = qsTr("大于等于"); break; case "<": opText = qsTr("小于"); break; case "<=": opText = qsTr("小于等于"); break; case "==": opText = qsTr("等于"); break; default: opText = root.selectedTriggerSensorOperator; }
                                        return qsTr("当传感器的 %1 %2 %3 时触发场景").arg(root.getSensorTypeName(root.selectedTriggerSensorType)).arg(opText).arg(root.selectedTriggerSensorThreshold);
                                    }
                                    font.pixelSize: 11 * sc; color: "#607d8b"; wrapMode: Text.Wrap; Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: {
                        var selectedH = root.actionDevices.length > 0 ? Math.min(220 * sc, root.actionDevices.length * 52 * sc + 8 * sc) : 0;
                        var pickerH = DeviceModel.count > 0 ? Math.min(260 * sc, Math.ceil(DeviceModel.count / 2) * 72 * sc + 8 * sc) : 0;
                        return Math.max(120 * sc, selectedH + pickerH + 100 * sc);
                    }
                    radius: 14 * sc; color: "#1e2844"
                    border.color: "#2a3f5f"; border.width: 1

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.margins: 2; width: 3; radius: 2; color: "#66bb6a"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16 * sc
                        spacing: 8 * sc

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6 * sc
                            Label { text: "▶"; font.pixelSize: 16 * sc }
                            Label { text: qsTr("执行动作"); font.pixelSize: 15 * sc; font.bold: true; color: "#e0e0e0" }
                            Item { Layout.fillWidth: true }
                            Label { text: qsTr("%1 个设备").arg(root.actionDevices.length); font.pixelSize: 12 * sc; color: "#9e9e9e" }
                        }

                        Label {
                            visible: DeviceModel.count === 0
                            text: qsTr("暂无设备，请先连接网关")
                            font.pixelSize: 12 * sc; color: "#9e9e9e"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        ListView {
                            id: actionDeviceList
                            Layout.fillWidth: true
                            implicitHeight: root.actionDevices.length > 0 ? Math.min(220 * sc, root.actionDevices.length * 52 * sc + 8 * sc) : 0
                            model: root.actionDevices; spacing: 6 * sc; clip: true
                            visible: root.actionDevices.length > 0

                            delegate: Rectangle {
                                width: actionDeviceList.width; height: 48 * sc; radius: 8 * sc
                                color: "#152038"; border.color: "#424242"; border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10 * sc; spacing: 8 * sc
                                    Label { text: "💻"; font.pixelSize: 16 * sc }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1 * sc
                                        Label { text: root.getDeviceName(modelData); font.pixelSize: 13 * sc; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Label { text: root.getDeviceType(modelData); font.pixelSize: 10 * sc; color: "#9e9e9e" }
                                    }

                                    Rectangle {
                                        width: 52 * sc; height: 28 * sc; radius: 14 * sc
                                        color: root.actionDeviceActions[modelData] === "on" || root.actionDeviceActions[modelData] === "open" ? "#2e7d32" : "#c62828"
                                        border.color: root.actionDeviceActions[modelData] === "on" || root.actionDeviceActions[modelData] === "open" ? "#4caf50" : "#ef5350"
                                        border.width: 1

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var cur = root.actionDeviceActions[modelData] || "on";
                                                var devType = root.getDeviceType(modelData).toLowerCase();
                                                var newAction = "on";
                                                if (devType.indexOf("door") >= 0 || devType.indexOf("门") >= 0) {
                                                    newAction = (cur === "open") ? "close" : "open";
                                                } else {
                                                    newAction = (cur === "on") ? "off" : "on";
                                                }
                                                var newActions = JSON.parse(JSON.stringify(root.actionDeviceActions));
                                                newActions[modelData] = newAction;
                                                root.actionDeviceActions = newActions;
                                            }
                                        }

                                        Label {
                                            anchors.centerIn: parent
                                            text: {
                                                var act = root.actionDeviceActions[modelData] || "on";
                                                if (act === "open") return qsTr("开");
                                                if (act === "close") return qsTr("关");
                                                if (act === "on") return qsTr("开");
                                                if (act === "off") return qsTr("关");
                                                return act;
                                            }
                                            font.pixelSize: 11 * sc; font.bold: true; color: "#ffffff"
                                        }
                                    }

                                    Rectangle {
                                        width: 26 * sc; height: 26 * sc; radius: 6 * sc; color: "#c62828"
                                        MouseArea {
                                            anchors.fill: parent; onClicked: root.removeDeviceFromList(modelData)
                                            Label { anchors.centerIn: parent; text: "✕"; font.pixelSize: 12 * sc; color: "#ffffff" }
                                        }
                                    }
                                }
                            }
                        }

                        Label {
                            text: qsTr("点击选择执行设备：")
                            font.pixelSize: 12 * sc; color: "#9e9e9e"
                            visible: DeviceModel.count > 0
                        }

                        GridView {
                            id: devicePicker
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(260 * sc, Math.ceil(DeviceModel.count / 2) * 72 * sc + 8 * sc)
                            cellWidth: (width - 6 * sc) / 2
                            cellHeight: 68 * sc
                            model: DeviceModel
                            clip: true
                            visible: DeviceModel.count > 0

                            delegate: Rectangle {
                                width: devicePicker.cellWidth - 6 * sc
                                height: devicePicker.cellHeight - 6 * sc
                                radius: 10 * sc
                                color: root.actionDevices.indexOf(model.deviceId) >= 0 ? "#1b5e20" : "#152038"
                                border.color: root.actionDevices.indexOf(model.deviceId) >= 0 ? "#4caf50" : "#424242"
                                border.width: root.actionDevices.indexOf(model.deviceId) >= 0 ? 2 : 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8 * sc
                                    spacing: 6 * sc

                                    Label { text: "💻"; font.pixelSize: 16 * sc }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1 * sc
                                        Label { text: model.deviceName || qsTr("未命名设备"); font.pixelSize: 12 * sc; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Label { text: model.deviceType || ""; font.pixelSize: 9 * sc; color: "#9e9e9e" }
                                    }

                                    Label {
                                        text: root.actionDevices.indexOf(model.deviceId) >= 0 ? "✓" : "+"
                                        font.pixelSize: 16 * sc; font.bold: true
                                        color: root.actionDevices.indexOf(model.deviceId) >= 0 ? "#a5d6a7" : "#4fc3f7"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    z: 1
                                    hoverEnabled: true
                                    onClicked: {
                                        var idx = root.actionDevices.indexOf(model.deviceId);
                                        if (idx >= 0) root.removeDeviceFromList(model.deviceId);
                                        else root.addDeviceToDeviceList(model.deviceId);
                                    }
                                }
                            }
                        }
                    }
                }

                Item { height: 20 * sc; Layout.fillWidth: true }
            }
        }

        Rectangle {
            id: bottomBar
            Layout.fillWidth: true
            Layout.preferredHeight: 50 * sc
            color: root.isEditMode ? "#4a1c1c" : "#16213e"
            border.color: root.isEditMode ? "#c62828" : "#2a2a4a"; border.width: 1
            visible: root.isEditMode

            MouseArea {
                anchors.fill: parent; onClicked: root.confirmDelete(); hoverEnabled: true
                Rectangle { anchors.fill: parent; radius: 10 * sc; color: "#ffffff"; opacity: parent.pressed ? 0.08 : (parent.containsMouse ? 0.05 : 0) }
                Row {
                    anchors.centerIn: parent; spacing: 8 * sc
                    Label { text: "🗑"; font.pixelSize: 18 * sc; color: "#ef5350" }
                    Label { text: qsTr("删除此场景"); font.pixelSize: 14 * sc; color: "#ef5350" }
                }
            }
        }
    }

    Dialog {
        id: confirmDeleteDialog
        title: qsTr("确认删除")
        modal: true
        width: 360 * sc
        anchors.centerIn: parent

        Label {
            text: qsTr("确定要删除场景 \"%1\" 吗？\n此操作不可恢复！").arg(root.sceneName)
            font.pixelSize: 14 * sc; wrapMode: Text.Wrap; width: parent.width - 48 * sc; color: "#e0e0e0"
        }
        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: { DatabaseManager.deleteScene(root.editingScene["sceneId"]); SceneModel.load(); toast.show(qsTr("场景已删除")); root.deleteScene(root.editingScene["sceneId"]); }
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
}
