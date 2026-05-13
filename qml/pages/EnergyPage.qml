import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtGraphs
import zhinengjiajv

Page {
    id: root

    title: qsTr("能耗统计")
    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property int timeGranularity: 0
    property var lineData: []
    property var pieData: []
    property string selectedDeviceId: ""
    property bool _refreshing: false
    property var highlightedDeviceId: ""
    property real lineAxisYMax: 100

    Component.onCompleted: {
        _refreshing = true;
        EnergyModel.load();
        _refreshing = false;
        refreshEnergyData();
    }

    Connections {
        target: EnergyModel

        function onCountChanged() {
            if (_refreshing)
                return;
            refreshEnergyData();
        }

        function onTotalEnergyChanged(total) {
            updateLineChartData();
        }
    }

    Connections {
        target: DeviceModel

        function onCountChanged() {
            if (_refreshing)
                return;
            refreshPieData();
        }
    }

    function refreshEnergyData() {
        if (_refreshing)
            return;
        _refreshing = true;
        updateLineChartData();
        refreshPieData();
        _refreshing = false;
    }

    function updateLineChartData() {
        lineData = [];
        var count = EnergyModel.count;
        for (var i = 0; i < count; i++) {
            var ts = EnergyModel.data(EnergyModel.index(i, 0), EnergyModel.TimestampRole);
            var power = EnergyModel.data(EnergyModel.index(i, 0), EnergyModel.PowerRole);
            var deviceId = EnergyModel.data(EnergyModel.index(i, 0), EnergyModel.DeviceIdRole);

            if (highlightedDeviceId !== "" && deviceId !== highlightedDeviceId)
                continue;

            lineData.push({
                "timestamp": ts || "",
                "power": power || 0,
                "deviceId": deviceId || ""
            });
        }

        var maxP = 0;
        lineSeries.clear();
        for (var j = 0; j < lineData.length; j++) {
            var p = lineData[j]["power"] || 0;
            lineSeries.append(j, p);
            if (p > maxP)
                maxP = p;
        }
        lineAxisYMax = Math.max(100, maxP);
    }

    function refreshPieData() {
        pieData = [];
        var deviceCount = DeviceModel.count;
        for (var i = 0; i < deviceCount; i++) {
            var devId = DeviceModel.deviceIdAt(i);
            var devName = DeviceModel.data(DeviceModel.index(i, 0), DeviceModel.DeviceNameRole);
            pieData.push({
                "deviceId": devId,
                "deviceName": devName || devId,
                "energy": 0
            });
        }

        var modelCount = EnergyModel.count;
        for (var k = 0; k < modelCount; k++) {
            var dId = EnergyModel.data(EnergyModel.index(k, 0), EnergyModel.DeviceIdRole);
            var pwr = EnergyModel.data(EnergyModel.index(k, 0), EnergyModel.PowerRole);
            for (var m = 0; m < pieData.length; m++) {
                if (pieData[m]["deviceId"] === dId) {
                    pieData[m]["energy"] += (pwr || 0);
                    break;
                }
            }
        }

        pieSeries.clear();
        var pieColors = ["#4fc3f7", "#81c784", "#ffb74d", "#e57373", "#ba68c8", "#4dd0e1", "#ff8a65", "#a1887f"];
        for (var p = 0; p < pieData.length; p++) {
            if (pieData[p]["energy"] > 0) {
                var slice = pieSeries.append(pieData[p]["deviceName"], pieData[p]["energy"]);
                slice.color = pieColors[p % pieColors.length];
                slice.labelVisible = true;
                slice.borderWidth = 2;
                slice.borderColor = "#1a1a2e";
            }
        }
    }

    function loadTimeRange(granularity) {
        if (_refreshing)
            return;
        timeGranularity = granularity;
        _refreshing = true;
        highlightedDeviceId = "";

        var idx = deviceSelector.currentIndex;
        var deviceId = idx >= 0 ? DeviceModel.deviceIdAt(idx) : "";

        var now = new Date();
        var start = new Date();

        switch (granularity) {
        case 0:
            start.setHours(0, 0, 0, 0);
            break;
        case 1:
            start.setDate(now.getDate() - 7);
            break;
        case 2:
            start.setMonth(now.getMonth() - 1);
            break;
        case 3:
            start.setFullYear(now.getFullYear() - 1);
            break;
        }

        EnergyModel.load(deviceId, start, now);
        _refreshing = false;
    }

    function calculateTotalCost() {
        var total = EnergyModel.totalEnergy;
        var rate = 0.6;
        return (total * rate).toFixed(2);
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "#0f1923"
            }
            GradientStop {
                position: 1.0
                color: "#162233"
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20 * sc
        spacing: 16 * sc

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 70 * sc
            radius: 14 * sc
            color: "#1a2332"
            border.color: "#2a4a6a"
            border.width: 1
            Material.elevation: 2

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12 * sc
                spacing: 12 * sc

                Label {
                    text: qsTr("⚡ 能耗统计")
                    font.pixelSize: 18 * sc
                    font.bold: true
                    color: "#ffffff"
                }

                Item {
                    Layout.fillWidth: true
                }

                ComboBox {
                    id: deviceSelector
                    Layout.preferredWidth: 160 * sc
                    model: DeviceModel
                    textRole: "deviceName"
                    displayText: currentText || qsTr("全部设备")
                    Layout.alignment: Qt.AlignVCenter

                    background: Rectangle {
                        radius: 8 * sc
                        color: "#1e2d3d"
                        border.color: "#2a4a6a"
                        border.width: 1
                    }

                    delegate: ItemDelegate {
                        width: deviceSelector.width
                        contentItem: Label {
                            text: model.deviceName || ""
                            color: "#ffffff"
                            font.pixelSize: 13 * sc
                        }
                        highlighted: deviceSelector.highlightedIndex === index
                    }

                    popup: Popup {
                        y: deviceSelector.height
                        width: deviceSelector.width
                        implicitHeight: contentItem.implicitHeight
                        padding: 4 * sc

                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: deviceSelector.popup.visible ? deviceSelector.delegateModel : null
                            currentIndex: deviceSelector.highlightedIndex
                            ScrollIndicator.vertical: ScrollIndicator {}
                        }

                        background: Rectangle {
                            radius: 8 * sc
                            color: "#1e2d3d"
                            border.color: "#2a4a6a"
                            border.width: 1
                        }
                    }

                    onActivated: {
                        if (currentIndex >= 0) {
                            selectedDeviceId = DeviceModel.deviceIdAt(currentIndex);
                            loadTimeRange(timeGranularity);
                        }
                    }
                }

                ButtonGroup {
                    id: timeGroup
                }

                Repeater {
                    model: [qsTr("日"), qsTr("周"), qsTr("月"), qsTr("年")]

                    delegate: Button {
                        text: modelData
                        checked: timeGranularity === index
                        ButtonGroup.group: timeGroup
                        onClicked: loadTimeRange(index)
                        Layout.alignment: Qt.AlignVCenter

                        background: Rectangle {
                            radius: 8 * sc
                            color: parent.checked ? "#2196f3" : "#1e2d3d"
                            border.color: parent.checked ? "#2196f3" : "#2a4a6a"
                            border.width: 1
                        }

                        contentItem: Label {
                            text: parent.text
                            color: parent.checked ? "#ffffff" : "#90a4ae"
                            font.pixelSize: 12 * sc
                            font.bold: parent.checked
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80 * sc
            spacing: 12 * sc

            EnergyStatCard {
                Layout.fillWidth: true
                statIcon: "⚡"
                statLabel: qsTr("总能耗")
                statValue: Math.round(EnergyModel.totalEnergy) + " kWh"
                statColor: "#4fc3f7"
                statBgStart: "#0d47a1"
                statBgEnd: "#1565c0"
            }

            EnergyStatCard {
                Layout.fillWidth: true
                statIcon: "💰"
                statLabel: qsTr("总费用")
                statValue: "¥" + calculateTotalCost()
                statColor: "#81c784"
                statBgStart: "#1b5e20"
                statBgEnd: "#2e7d32"
            }

            EnergyStatCard {
                Layout.fillWidth: true
                statIcon: "📊"
                statLabel: qsTr("数据条数")
                statValue: EnergyModel.count
                statColor: "#ffb74d"
                statBgStart: "#e65100"
                statBgEnd: "#f57c00"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16 * sc

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: 16 * sc
                color: "#1a2332"
                border.color: "#2a4a6a"
                border.width: 1
                Material.elevation: 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16 * sc
                    spacing: 8 * sc

                    Label {
                        text: qsTr("📈 能耗趋势")
                        font.pixelSize: 14 * sc
                        font.bold: true
                        color: "#e0e0e0"
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        GraphsView {
                            id: lineChart
                            anchors.fill: parent
                            marginTop: 10 * sc
                            marginBottom: 40 * sc
                            marginLeft: 50 * sc
                            marginRight: 20 * sc

                            theme: GraphsTheme {
                                theme: GraphsTheme.Theme.UserDefined
                                colorScheme: GraphsTheme.ColorScheme.Dark
                                backgroundColor: "#1a2332"
                                plotAreaBackgroundColor: "#15202d"
                                grid.mainColor: "#253545"
                                grid.subColor: "#1e2c3a"
                                labelTextColor: "#90a4ae"
                                axisX.mainColor: "#4a6a8a"
                                axisX.subColor: "#2a3a4a"
                                axisY.mainColor: "#4a6a8a"
                                axisY.subColor: "#2a3a4a"
                                seriesColors: ["#4fc3f7"]
                            }

                            ValueAxis {
                                id: lineAxisX
                                min: 0
                                max: Math.max(1, lineData.length - 1)
                                subTickCount: 3
                                labelFormat: "%d"
                            }

                            ValueAxis {
                                id: lineAxisY
                                min: 0
                                max: lineAxisYMax
                                subTickCount: 4
                                labelFormat: "%.0f"
                                titleText: qsTr("功率 (W)")
                                titleVisible: true
                            }

                            LineSeries {
                                id: lineSeries
                                name: qsTr("功率")
                                axisX: lineAxisX
                                axisY: lineAxisY
                                width: 2.5
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 40 * sc
                            height: parent.height - 40 * sc
                            radius: 16 * sc
                            color: "#1a2332"
                            visible: lineData.length === 0

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8 * sc

                                Label {
                                    text: "📈"
                                    font.pixelSize: 36 * sc
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Label {
                                    text: qsTr("暂无能耗数据")
                                    font.pixelSize: 14 * sc
                                    color: "#90a4ae"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: 16 * sc
                color: "#1a2332"
                border.color: "#2a4a6a"
                border.width: 1
                Material.elevation: 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16 * sc
                    spacing: 8 * sc

                    Label {
                        text: qsTr("🥧 设备占比")
                        font.pixelSize: 14 * sc
                        font.bold: true
                        color: "#e0e0e0"
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        GraphsView {
                            id: pieChart
                            anchors.fill: parent
                            marginTop: 10 * sc
                            marginBottom: 30 * sc
                            marginLeft: 20 * sc
                            marginRight: 20 * sc

                            theme: GraphsTheme {
                                theme: GraphsTheme.Theme.UserDefined
                                colorScheme: GraphsTheme.ColorScheme.Dark
                                backgroundColor: "#1a2332"
                                plotAreaBackgroundColor: "#15202d"
                                grid.mainColor: "#253545"
                                grid.subColor: "#1e2c3a"
                                labelTextColor: "#90a4ae"
                                seriesColors: ["#4fc3f7", "#81c784", "#ffb74d", "#e57373", "#ba68c8", "#64b5f6", "#4db6ac", "#fff176"]
                            }

                            onHoverEnter: function (seriesName, position, value) {
                                pieChartTitle.text = seriesName + ": " + value.y.toFixed(1) + " kWh";
                            }

                            onHoverExit: function (seriesName, position) {
                                pieChartTitle.text = "";
                            }

                            PieSeries {
                                id: pieSeries

                                onClicked: function (slice) {
                                    for (var i = 0; i < root.pieData.length; i++) {
                                        if (root.pieData[i]["deviceName"] === slice.label) {
                                            root.highlightedDeviceId = root.pieData[i]["deviceId"];
                                            root.updateLineChartData();
                                            break;
                                        }
                                    }
                                }
                            }
                        }

                        Label {
                            id: pieChartTitle
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8 * sc
                            font.pixelSize: 13 * sc
                            color: "#90a4ae"
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 40 * sc
                            height: parent.height - 40 * sc
                            radius: 16 * sc
                            color: "#1a2332"
                            visible: pieSeries.count === 0

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8 * sc

                                Label {
                                    text: "🥧"
                                    font.pixelSize: 36 * sc
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Label {
                                    text: qsTr("暂无设备数据")
                                    font.pixelSize: 14 * sc
                                    color: "#90a4ae"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: 16 * sc
                color: "#1a2332"
                border.color: "#2a4a6a"
                border.width: 1
                Material.elevation: 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16 * sc
                    spacing: 12 * sc

                    Label {
                        text: qsTr("💡 节能建议")
                        font.pixelSize: 14 * sc
                        font.bold: true
                        color: "#e0e0e0"
                    }

                    ScrollView {
                        id: suggestionsScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 10 * sc

                            Repeater {
                                model: generateSuggestions()

                                delegate: Rectangle {
                                    width: suggestionsScroll.availableWidth - 16 * sc
                                    height: suggestionColumn.implicitHeight + 20 * sc
                                    radius: 12 * sc
                                    color: "#0f1923"
                                    border.color: modelData.color || "#2a4a6a"
                                    border.width: 1

                                    ColumnLayout {
                                        id: suggestionColumn
                                        anchors.fill: parent
                                        anchors.margins: 12 * sc
                                        spacing: 6 * sc

                                        RowLayout {
                                            spacing: 8 * sc

                                            Rectangle {
                                                width: 28 * sc
                                                height: 28 * sc
                                                radius: 14 * sc
                                                color: modelData.color || "#2a4a6a"

                                                Label {
                                                    anchors.centerIn: parent
                                                    text: modelData.icon || "💡"
                                                    font.pixelSize: 14 * sc
                                                }
                                            }

                                            Label {
                                                text: modelData.title || ""
                                                font.pixelSize: 13 * sc
                                                font.bold: true
                                                color: "#e0e0e0"
                                            }
                                        }

                                        Label {
                                            text: modelData.description || ""
                                            font.pixelSize: 12 * sc
                                            color: "#90a4ae"
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function generateSuggestions() {
        var suggestions = [];
        var total = EnergyModel.totalEnergy;
        var count = EnergyModel.count;

        if (count === 0) {
            return [
                {
                    "icon": "ℹ️",
                    "title": qsTr("暂无建议"),
                    "description": qsTr("设备运行中，待收集足够数据后生成节能建议。"),
                    "color": "#2a4a6a"
                }
            ];
        }

        var avgPower = total / count;

        if (avgPower > 50) {
            suggestions.push({
                "icon": "🔌",
                "title": qsTr("降低待机功耗"),
                "description": qsTr("当前平均功耗较高，建议关闭不必要的设备或启用自动休眠模式，预计可节省15%-20%能耗。"),
                "color": "#e57373"
            });
        } else {
            suggestions.push({
                "icon": "✅",
                "title": qsTr("功耗正常"),
                "description": qsTr("当前平均功耗处于合理范围，继续保持良好使用习惯。"),
                "color": "#81c784"
            });
        }

        if (pieData.length > 0) {
            var maxDevice = pieData[0];
            for (var i = 1; i < pieData.length; i++) {
                if (pieData[i]["energy"] > maxDevice["energy"]) {
                    maxDevice = pieData[i];
                }
            }
            if (maxDevice["energy"] > total * 0.4) {
                suggestions.push({
                    "icon": "⚠️",
                    "title": qsTr("高耗能设备: %1").arg(maxDevice["deviceName"]),
                    "description": qsTr("该设备占总能耗的%1%以上，建议优化使用时间或考虑升级节能型号。").arg(Math.round(maxDevice["energy"] / total * 100)),
                    "color": "#ffb74d"
                });
            } else {
                suggestions.push({
                    "icon": "📊",
                    "title": qsTr("能耗分布合理"),
                    "description": qsTr("各设备能耗分布均衡，无单一高耗能设备。"),
                    "color": "#4fc3f7"
                });
            }
        }

        suggestions.push({
            "icon": "💡",
            "title": qsTr("定时控制建议"),
            "description": qsTr("建议为常用设备设置定时开关，避免无效运行时间，预计可降低10%左右的能耗。"),
            "color": "#ba68c8"
        });

        return suggestions;
    }

    component EnergyStatCard: Rectangle {
        id: statCardRoot
        property string statIcon: ""
        property string statLabel: ""
        property string statValue: ""
        property string statColor: "#ffffff"
        property string statBgStart: "#1a2332"
        property string statBgEnd: "#1a2332"

        height: 70 * sc
        radius: 14 * sc
        Material.elevation: 4

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: statBgStart
            }
            GradientStop {
                position: 1.0
                color: statBgEnd
            }
        }

        border.color: statColor
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14 * sc
            spacing: 14 * sc

            Rectangle {
                width: 42 * sc
                height: 42 * sc
                radius: 12 * sc
                color: statColor
                opacity: 0.2

                Label {
                    anchors.centerIn: parent
                    text: statCardRoot.statIcon
                    font.pixelSize: 22 * sc
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4 * sc

                Label {
                    text: statCardRoot.statLabel
                    font.pixelSize: 12 * sc
                    color: "#90a4ae"
                }

                Label {
                    text: statCardRoot.statValue
                    font.pixelSize: 20 * sc
                    font.bold: true
                    color: statColor
                }
            }
        }
    }
}
