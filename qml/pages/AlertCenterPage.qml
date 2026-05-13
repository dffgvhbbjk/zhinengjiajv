import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import zhinengjiajv

Page {
    id: alertCenterPage
    title: qsTr("警告中心")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property bool _isSelectAll: false
    property var _selectedAlertIds: []
    property bool _refreshing: false
    property bool _batchOperating: false

    component AlertButton : Button {
        id: alertBtn
        property color btnColor: "#1565c0"
        property color borderColor: "#1976d2"
        property color pressedColor: "#0d47a1"
        background: Rectangle {
            radius: 8 * sc
            color: alertBtn.pressed ? alertBtn.pressedColor : alertBtn.btnColor
            border.color: alertBtn.borderColor
            border.width: 1
        }
        contentItem: Label {
            text: alertBtn.text
            color: "#ffffff"
            font.pixelSize: 12 * sc
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component ActionButton : Button {
        id: actionBtn
        property color btnColor: "#2e7d32"
        property color borderColor: "#4caf50"
        property color pressedColor: "#1b5e20"
        property color textColor: "#ffffff"
        property real fontSize: 11 * sc
        background: Rectangle {
            radius: 8 * sc
            color: actionBtn.enabled ? (actionBtn.pressed ? actionBtn.pressedColor : actionBtn.btnColor) : "#1e2d3d"
            border.color: actionBtn.enabled ? actionBtn.borderColor : "#2a4a6a"
            border.width: 1
        }
        contentItem: Label {
            text: actionBtn.text
            color: actionBtn.enabled ? actionBtn.textColor : "#607d8b"
            font.pixelSize: actionBtn.fontSize
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component DangerButton : Button {
        id: dangerBtn
        property color btnColor: "#c62828"
        property color borderColor: "#e53935"
        property color pressedColor: "#b71c1c"
        property color textColor: "#ffffff"
        property real fontSize: 11 * sc
        background: Rectangle {
            radius: 8 * sc
            color: dangerBtn.enabled ? (dangerBtn.pressed ? dangerBtn.pressedColor : dangerBtn.btnColor) : "#1e2d3d"
            border.color: dangerBtn.enabled ? dangerBtn.borderColor : "#2a4a6a"
            border.width: 1
        }
        contentItem: Label {
            text: dangerBtn.text
            color: dangerBtn.enabled ? dangerBtn.textColor : "#607d8b"
            font.pixelSize: dangerBtn.fontSize
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
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
            Layout.preferredHeight: 80 * sc
            radius: 14 * sc; color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
            Material.elevation: 6

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12 * sc
                spacing: 8 * sc

                RowLayout {
                    Layout.fillWidth: true; spacing: 12 * sc

                    AlertButton {
                        text: qsTr("返回")
                        btnColor: "#1565c0"; borderColor: "#1976d2"; pressedColor: "#0d47a1"
                        onClicked: { if (Window.window) Window.window.tabBarCurrentIndex = 0; }
                    }

                    Label { text: qsTr("🔔 警告 (%1)").arg(AlertModel.count); font.pixelSize: 16 * sc; font.bold: true; color: "#ffffff" }
                    Item { Layout.fillWidth: true }

                    ComboBox {
                        id: filterCombo; width: 120 * sc
                        model: [qsTr("全部"), qsTr("未读"), qsTr("严重"), qsTr("警告"), qsTr("提示")]
                        currentIndex: 0

                        background: Rectangle { radius: 6 * sc; color: filterCombo.pressed ? "#1a2332" : "#1e3a50"; border.color: "#2a4a6a"; border.width: 1 }
                        contentItem: Label { text: filterCombo.displayText; color: "#e0e0e0"; font.pixelSize: 12 * sc; verticalAlignment: Text.AlignVCenter; leftPadding: 10 * sc }
                        popup: Popup {
                            y: filterCombo.height; width: filterCombo.width; implicitHeight: contentItem.implicitHeight; padding: 4 * sc
                            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: filterCombo.delegateModel; currentIndex: filterCombo.highlightedIndex }
                            background: Rectangle { radius: 8 * sc; color: "#1a2332"; border.color: "#2a4a6a" }
                        }
                        onActivated: function(idx) {
                            if (_refreshing) return;
                            _refreshing = true;
                            _selectedAlertIds = [];
                            _isSelectAll = false;
                            applyFilter(idx);
                            _refreshing = false;
                        }
                    }

                    AlertButton {
                        text: qsTr("↻ 刷新")
                        btnColor: "#1565c0"; borderColor: "#1976d2"; pressedColor: "#0d47a1"
                        onClicked: {
                            if (_refreshing) return;
                            _refreshing = true;
                            AlertModel.loadAll();
                            _selectedAlertIds = [];
                            _isSelectAll = false;
                            filterCombo.currentIndex = 0;
                            _refreshing = false;
                            snackbar.show(qsTr("警告列表已刷新"), "#4fc3f7");
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8 * sc

                    ActionButton {
                        text: qsTr("全部已读")
                        btnColor: "#2e7d32"; borderColor: "#4caf50"; pressedColor: "#1b5e20"
                        onClicked: {
                            if (_refreshing) return;
                            _refreshing = true;
                            AlertModel.markAllAsRead();
                            AlertModel.loadAll();
                            if (Window.window) Window.window.refreshAlertBadge();
                            _refreshing = false;
                            snackbar.show(qsTr("全部标记已读"), "#4caf50");
                        }
                    }
                    DangerButton {
                        text: qsTr("全部删除")
                        onClicked: { deleteAllConfirmDialog.visible = true; }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: AlertModel.unreadCount > 0 ? qsTr("未读: %1").arg(AlertModel.unreadCount) : qsTr("全部已读")
                        font.pixelSize: 12 * sc
                        color: AlertModel.unreadCount > 0 ? "#ff9800" : "#4caf50"
                        font.bold: true
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16 * sc; color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
            Material.elevation: 4

            ScrollView {
                anchors.fill: parent; anchors.margins: 8 * sc

                ListView {
                    id: alertListView
                    Layout.fillWidth: true
                    model: AlertModel
                    spacing: 8 * sc
                    clip: true

                    delegate: Rectangle {
                        id: alertDelegate
                        width: alertListView.width
                        height: alertContent.implicitHeight + 24 * sc
                        radius: 14 * sc
                        color: alertDelegate.isSelected ? "#1e3a50" : (model.isRead ? "#151f2e" : "#1e2d3d")
                        border.color: {
                            if (model.level >= 3) return "#e53935";
                            if (model.level >= 2) return "#ff9800";
                            return "#2a4a6a";
                        }
                        border.width: model.isRead ? 1 : 2
                        property bool isSelected: _selectedAlertIds.indexOf(model.alertId) >= 0
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Material.elevation: model.isRead ? 2 : 4

                        RowLayout {
                            id: alertContent
                            anchors.fill: parent
                            anchors.margins: 12 * sc
                            spacing: 12 * sc

                            CheckBox {
                                id: selectCheckBox
                                z: 10
                                checked: alertDelegate.isSelected
                                onToggled: {
                                    if (checked) {
                                        _selectedAlertIds.push(model.alertId);
                                    } else {
                                        var idx = _selectedAlertIds.indexOf(model.alertId);
                                        if (idx >= 0) _selectedAlertIds.splice(idx, 1);
                                    }
                                    _isSelectAll = _selectedAlertIds.length === AlertModel.count;
                                }
                            }

                            Rectangle {
                                width: 40 * sc; height: 40 * sc; radius: 10 * sc
                                color: {
                                    if (model.level >= 3) return "#e53935";
                                    if (model.level >= 2) return "#ff9800";
                                    return "#2196f3";
                                }
                                opacity: 0.2
                                Layout.alignment: Qt.AlignVCenter
                                Label {
                                    anchors.centerIn: parent
                                    text: model.level >= 3 ? "🔴" : (model.level >= 2 ? "🟠" : "🔵")
                                    font.pixelSize: 20 * sc
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4 * sc
                                Label {
                                    text: model.content || ""
                                    font.bold: true
                                    font.pixelSize: 14 * sc
                                    color: model.isRead ? "#90a4ae" : "#ffffff"
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: qsTr("时间: %1  |  级别: %2  |  来源: %3").arg(model.timestamp || "").arg(model.level || 0).arg(model.alertType || "手动")
                                    font.pixelSize: 11 * sc
                                    color: "#607d8b"
                                }
                            }

                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 6 * sc

                                Label {
                                    text: model.isRead ? qsTr("已读") : qsTr("未读")
                                    font.pixelSize: 11 * sc
                                    font.bold: true
                                    color: model.isRead ? "#4caf50" : "#f44336"
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                ActionButton {
                                    text: model.isRead ? qsTr("已读") : qsTr("标记已读")
                                    enabled: !model.isRead
                                    fontSize: 10 * sc
                                    btnColor: "#1976d2"; borderColor: "#2196f3"; pressedColor: "#1565c0"
                                    textColor: "#ffffff"
                                    onClicked: {
                                        AlertModel.markAsRead(model.alertId);
                                        if (Window.window) Window.window.refreshAlertBadge();
                                    }
                                }
                                DangerButton {
                                    text: qsTr("删除")
                                    fontSize: 10 * sc
                                    onClicked: {
                                        AlertModel.deleteAlert(model.alertId);
                                        if (Window.window) Window.window.refreshAlertBadge();
                                        snackbar.show(qsTr("警告已删除"), "#4fc3f7");
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 300 * sc; height: 200 * sc; radius: 16 * sc
                color: "#0f1923"; border.color: "#2a4a6a"; border.width: 1
                visible: AlertModel.count === 0

                ColumnLayout {
                    anchors.centerIn: parent; spacing: 12 * sc
                    Label { text: "🔔"; font.pixelSize: 48 * sc; Layout.alignment: Qt.AlignHCenter }
                    Label { text: qsTr("暂无警告"); font.pixelSize: 18 * sc; color: "#90a4ae"; Layout.alignment: Qt.AlignHCenter }
                    Label { text: qsTr("系统运行正常"); font.pixelSize: 14 * sc; color: "#607d8b"; Layout.alignment: Qt.AlignHCenter }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60 * sc
            radius: 14 * sc; color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
            Material.elevation: 4

            RowLayout {
                anchors.fill: parent; anchors.margins: 8 * sc; spacing: 10 * sc

                Button {
                    id: selectAllBtn
                    text: _isSelectAll ? qsTr("取消全选") : qsTr("全选")
                    background: Rectangle {
                        radius: 8 * sc
                        color: selectAllBtn.pressed ? "#37474f" : "#455a64"
                        border.color: "#607d8b"
                        border.width: 1
                    }
                    contentItem: Label {
                        text: selectAllBtn.text
                        color: "#ffffff"
                        font.pixelSize: 12 * sc
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (_isSelectAll) {
                            _selectedAlertIds = [];
                            _isSelectAll = false;
                        } else {
                            _selectedAlertIds = [];
                            for (var i = 0; i < AlertModel.count; i++)
                                _selectedAlertIds.push(AlertModel.data(AlertModel.index(i, 0), AlertModel.AlertIdRole));
                            _isSelectAll = true;
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: qsTr(" 批量标记已读")
                    enabled: _selectedAlertIds.length > 0 && !_batchOperating
                    onClicked: {
                        if (_batchOperating || _refreshing) return;
                        _batchOperating = true;
                        AlertModel.markMultipleAsRead(_selectedAlertIds);
                        _selectedAlertIds = [];
                        _isSelectAll = false;
                        filterCombo.currentIndex = 0;
                        AlertModel.clearFilter();
                        AlertModel.loadAll();
                        if (Window.window) Window.window.refreshAlertBadge();
                        _batchOperating = false;
                        snackbar.show(qsTr("批量标记已读完成"), "#4caf50");
                    }
                }
                DangerButton {
                    id: batchDeleteBtn
                    text: qsTr(" 批量删除 (%1)").arg(_selectedAlertIds.length)
                    enabled: _selectedAlertIds.length > 0 && !_batchOperating
                    onClicked: {
                        deleteConfirmDialog.text = qsTr("确定删除 %1 条警告?").arg(_selectedAlertIds.length);
                        deleteConfirmDialog.visible = true;
                    }
                }
            }
        }
    }

    Rectangle {
        id: snackbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80 * sc
        width: snackbarLabel.implicitWidth + 48 * sc
        height: 48 * sc; radius: 24 * sc
        color: "#333333"; opacity: 0; visible: opacity > 0; z: 100
        Material.elevation: 12
        property color accentColor: "#4fc3f7"
        border.color: accentColor; border.width: 1

        Label { id: snackbarLabel; anchors.centerIn: parent; text: ""; color: "#ffffff"; font.pixelSize: 13 * sc; font.bold: true }
        Timer { id: snackbarTimer; interval: 2500; repeat: false; onTriggered: snackbarHide.start() }
        NumberAnimation { id: snackbarShow; target: snackbar; property: "opacity"; to: 1.0; duration: 200 }
        NumberAnimation { id: snackbarHide; target: snackbar; property: "opacity"; to: 0.0; duration: 300 }

        function show(message, color) {
            snackbarLabel.text = message;
            accentColor = color || "#4fc3f7";
            snackbarTimer.restart();
            snackbarShow.start();
        }
    }

    Dialog {
        id: deleteConfirmDialog
        modal: true
        title: qsTr("确认删除")
        visible: false
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 360 * sc
        property string text: ""
        standardButtons: Dialog.Yes | Dialog.No

        background: Rectangle {
            radius: 12 * sc
            color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
        }
        Label {
            text: deleteConfirmDialog.text
            font.pixelSize: 14 * sc
            color: "#e0e0e0"
            wrapMode: Text.Wrap
        }
        onAccepted: {
            if (_batchOperating) return;
            _batchOperating = true;
            AlertModel.deleteMultipleAlerts(_selectedAlertIds);
            _selectedAlertIds = [];
            _isSelectAll = false;
            filterCombo.currentIndex = 0;
            AlertModel.loadAll();
            if (Window.window) Window.window.refreshAlertBadge();
            _batchOperating = false;
            snackbar.show(qsTr("批量删除完成"), "#4caf50");
        }
    }

    Dialog {
        id: deleteAllConfirmDialog
        modal: true
        title: qsTr("确认全部删除")
        visible: false
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 360 * sc
        standardButtons: Dialog.Yes | Dialog.No

        background: Rectangle {
            radius: 12 * sc
            color: "#1a2332"
            border.color: "#2a4a6a"; border.width: 1
        }
        Label {
            text: qsTr("确定删除全部 %1 条警告吗？此操作不可撤销！").arg(AlertModel.count)
            font.pixelSize: 14 * sc
            color: "#e0e0e0"
            wrapMode: Text.Wrap
        }
        onAccepted: {
            if (_batchOperating) return;
            _batchOperating = true;
            AlertModel.deleteAllAlerts();
            _selectedAlertIds = [];
            _isSelectAll = false;
            filterCombo.currentIndex = 0;
            AlertModel.loadAll();
            if (Window.window) Window.window.refreshAlertBadge();
            _batchOperating = false;
            snackbar.show(qsTr("全部警告已删除"), "#4caf50");
        }
    }

    function applyFilter(filterIndex) {
        AlertModel.clearFilter();
        switch (filterIndex) {
        case 0: AlertModel.loadAll(); break;
        case 1: AlertModel.loadUnreadOnly(); break;
        case 2: AlertModel.loadAll(); AlertModel.filterByLevel(3); break;
        case 3: AlertModel.loadAll(); AlertModel.filterByLevel(2); break;
        case 4: AlertModel.loadAll(); AlertModel.filterByLevel(1); break;
        }
    }

    Component.onCompleted: { AlertModel.loadAll(); }

    Connections {
        target: AlertModel
        function onCountChanged() {
            if (_refreshing || _batchOperating) return;
            _isSelectAll = false;
            _selectedAlertIds = [];
        }
    }
}
