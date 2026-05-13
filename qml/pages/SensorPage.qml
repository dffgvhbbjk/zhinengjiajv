import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import QtGraphs
import zhinengjiajv

Page {
    id: root

    readonly property real sc: Window.window ? Window.window.scaleBase : 1.0

    property string selectedDeviceId: ""
    property int selectedMetricIndex: 0
    property bool _refreshing: false
    property var sensorDeviceList: []
    property var chartData: []
    property var fullTimelineData: []
    property string currentMetricLabel: "温度"
    property string currentMetricUnit: "°C"
    property color currentMetricColor: "#4fc3f7"

    property string currentTempValue: "--"
    property string currentHumiValue: "--"
    property string currentLightValue: "--"
    property string currentRainValue: "--"
    property string currentSmokeValue: "--"
    property string currentLpgValue: "--"
    property string currentAirValue: "--"

    property string currentPressValue: "--"

    property bool tempNormal: true
    property bool humiNormal: true
    property bool lightNormal: true
    property bool rainNormal: true
    property bool smokeNormal: true
    property bool lpgNormal: true
    property bool airNormal: true
    property bool pressNormal: true

    readonly property var metricKeys: ["temperature", "humidity", "light", "rain", "smoke", "lpg", "air_quality", "pressure"]
    readonly property var metricLabels: ["温度", "湿度", "光照", "雨滴", "烟雾", "液化气", "空气质量", "气压"]
    readonly property var metricUnits: ["°C", "%RH", "lux", "", "ppm", "ppm", "AQI", " hPa"]
    readonly property var metricColors: ["#4fc3f7", "#81c784", "#ffd54f", "#4dd0e1", "#e57373", "#ffb74d", "#ce93d8", "#90a4ae"]
    readonly property var metricRanges: [[-10, 50], [0, 100], [0, 2000], [0, 100], [0, 500], [0, 500], [0, 500], [900, 1100]]
    readonly property var alertThresholds: [
        {
            min: 10,
            max: 35
        },
        {
            min: 30,
            max: 80
        },
        {
            min: 0,
            max: 5000
        },
        {
            min: 0,
            max: 80
        },
        {
            min: 0,
            max: 100
        },
        {
            min: 0,
            max: 100
        },
        {
            min: 0,
            max: 150
        },
        {
            min: 900,
            max: 1100
        }
    ]

    property string granularityMode: "day"
    property date selectedAnchorDate: new Date()
    property int selectedHour: new Date().getHours()
    property double windowDurationMs: 86400000
    property bool _timelineReady: false

    property double _rangeStartMs: 0
    property double _rangeEndMs: 0
    property double _fullStartMs: 0
    property double _fullEndMs: 0

    property double _appliedStartMs: 0
    property double _appliedEndMs: 0
    property bool _canApply: false
    property bool _canReset: false

    property double hoverDataValue: 0
    property string hoverDataTime: ""
    property bool showHover: false
    property double hoverTipX: 0
    property double hoverTipY: 0

    property bool _loadingTimeline: false
    property var lastAlertTimes: ({})

    function parseTs(ts) {
        if (!ts)
            return 0;
        var s = String(ts);
        var m = s.match(/(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})/);
        if (m) {
            var d = new Date(parseInt(m[1]), parseInt(m[2]) - 1, parseInt(m[3]), parseInt(m[4]), parseInt(m[5]), parseInt(m[6]));
            return d.getTime();
        }
        m = s.match(/(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
        if (m) {
            var d2 = new Date(parseInt(m[1]), parseInt(m[2]) - 1, parseInt(m[3]), parseInt(m[4]), parseInt(m[5]), parseInt(m[6]));
            return d2.getTime();
        }
        return 0;
    }

    function parseNum(val) {
        if (typeof val === "number" && isFinite(val))
            return val;
        var s = String(val || "0").replace(/[^\d.\-]/g, "");
        var n = parseFloat(s);
        return isFinite(n) ? n : 0;
    }

    function niceAxisRange(dataMin, dataMax) {
        if (dataMax - dataMin < 0.001)
            return {
                min: dataMin - 2,
                max: dataMax + 2
            };
        var range = dataMax - dataMin;
        var roughStep = range / 5;
        var magnitude = Math.pow(10, Math.floor(Math.log10(roughStep)));
        var residual = roughStep / magnitude;
        var niceStep;
        if (residual <= 1.5)
            niceStep = 1 * magnitude;
        else if (residual <= 3.5)
            niceStep = 2 * magnitude;
        else if (residual <= 7.5)
            niceStep = 5 * magnitude;
        else
            niceStep = 10 * magnitude;
        return {
            min: Math.floor(dataMin / niceStep) * niceStep,
            max: Math.ceil(dataMax / niceStep) * niceStep
        };
    }

    function fmtShort(ms) {
        if (ms <= 0)
            return "--";
        var d = new Date(ms);
        return String(d.getMonth() + 1).padStart(2, '0') + "-" + String(d.getDate()).padStart(2, '0');
    }
    function fmtFull(ms) {
        if (ms <= 0)
            return "--";
        var d = new Date(ms);
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, '0') + "-" + String(d.getDate()).padStart(2, '0');
    }
    function fmtTime(ms) {
        if (ms <= 0)
            return "--";
        var d = new Date(ms);
        return String(d.getHours()).padStart(2, '0') + ":" + String(d.getMinutes()).padStart(2, '0') + ":" + String(d.getSeconds()).padStart(2, '0');
    }
    function fmtDateTime(ms) {
        return fmtFull(ms) + " " + fmtTime(ms);
    }
    function fmtRangeLabel() {
        if (granularityMode === "minute")
            return fmtDateTime(_rangeStartMs) + "  —  " + fmtTime(_rangeEndMs);
        if (granularityMode === "hour")
            return fmtDateTime(_rangeStartMs) + "  —  " + fmtTime(_rangeEndMs);
        return fmtFull(_rangeStartMs) + "  —  " + fmtFull(_rangeEndMs);
    }
    function fmtLabelDate(ms) {
        if (ms <= 0)
            return "--";
        var d = new Date(ms);
        var y = d.getFullYear();
        var m = String(d.getMonth() + 1).padStart(2, '0');
        var day = String(d.getDate()).padStart(2, '0');
        if (granularityMode === "minute")
            return y + "/" + m + "/" + day + " " + String(d.getHours()).padStart(2, '0') + ":" + String(d.getMinutes()).padStart(2, '0') + ":" + String(d.getSeconds()).padStart(2, '0');
        if (granularityMode === "hour")
            return y + "/" + m + "/" + day + " " + String(d.getHours()).padStart(2, '0') + ":" + String(d.getMinutes()).padStart(2, '0');
        return y + "/" + m + "/" + day;
    }

    function downsample(raw, maxPoints) {
        if (!raw || raw.length <= maxPoints)
            return raw;
        var step = raw.length / maxPoints;
        var result = [];
        for (var i = 0; i < maxPoints; ++i) {
            var idx = Math.floor(i * step);
            if (idx < raw.length)
                result.push(raw[idx]);
        }
        return result;
    }

    function smoothData(data, key) {
        var points = [];
        for (var i = 0; i < data.length; ++i) {
            var ms = parseTs(data[i]["timestamp"]);
            var y = parseNum(data[i][key]);
            if (ms > 0 && isFinite(y))
                points.push({
                    ms: ms,
                    y: y
                });
        }
        return points;
    }

    function buildAnchorMs() {
        var d = new Date(selectedAnchorDate);
        if (granularityMode === "day")
            d.setHours(0, 0, 0, 0);
        else
            d.setHours(selectedHour, 0, 0, 0);
        return d.getTime();
    }

    function buildFullRange() {
        var anchorMs = buildAnchorMs();
        switch (granularityMode) {
        case "minute":
            return {
                start: anchorMs - 6 * 3600000,
                end: anchorMs + 6 * 3600000
            };
        case "hour":
            return {
                start: anchorMs - 12 * 3600000,
                end: anchorMs + 12 * 3600000
            };
        default:
            return {
                start: anchorMs - 3 * 86400000,
                end: anchorMs + 4 * 86400000
            };
        }
    }

    function refreshData(resetRange) {
        if (_refreshing || !selectedDeviceId)
            return;
        _refreshing = true;
        if (resetRange !== false) {
            if (_appliedStartMs > 0 && _appliedEndMs > _appliedStartMs) {
                _rangeStartMs = _appliedStartMs;
                _rangeEndMs = _appliedEndMs;
            } else {
                var anchorMs = buildAnchorMs();
                _rangeStartMs = anchorMs;
                _rangeEndMs = anchorMs + windowDurationMs;
            }
        }
        var fr = buildFullRange();
        SensorModel.load(selectedDeviceId, new Date(fr.start), new Date(fr.end));
        chartData = buildChartData();
        updateCurrentValues();
        updateMainChart();
        updateTimelineWindow();
        _refreshing = false;
    }

    function loadTimeline() {
        if (!selectedDeviceId)
            return;
        _loadingTimeline = true;
        var fr = buildFullRange();
        SensorModel.load(selectedDeviceId, new Date(fr.start), new Date(fr.end));
        buildTimeline();
    }

    function buildTimeline() {
        fullTimelineData = [];
        for (var i = 0; i < SensorModel.count; ++i)
            fullTimelineData.push(SensorModel.get(i));
        timelineLine.clear();
        var key = metricKeys[selectedMetricIndex];
        var allPts = smoothData(fullTimelineData, key);
        if (allPts.length === 0) {
            var fr = buildFullRange();
            _fullStartMs = fr.start;
            _fullEndMs = fr.end;
            timelineXAxis.min = new Date(_fullStartMs);
            timelineXAxis.max = new Date(_fullEndMs);
            timelineYAxis.min = -1;
            timelineYAxis.max = 50;
            _timelineReady = true;
            updateTimelineWindow();
            _loadingTimeline = false;
            return;
        }
        var pts = downsample(allPts, 400);
        _fullStartMs = Infinity;
        _fullEndMs = -Infinity;
        var tlMinY = Infinity, tlMaxY = -Infinity;
        for (var j = 0; j < pts.length; ++j) {
            timelineLine.append(new Date(pts[j].ms), pts[j].y);
            if (pts[j].ms < _fullStartMs)
                _fullStartMs = pts[j].ms;
            if (pts[j].ms > _fullEndMs)
                _fullEndMs = pts[j].ms;
            if (pts[j].y < tlMinY)
                tlMinY = pts[j].y;
            if (pts[j].y > tlMaxY)
                tlMaxY = pts[j].y;
        }
        if (_fullEndMs <= _fullStartMs) {
            var fr2 = buildFullRange();
            _fullStartMs = fr2.start;
            _fullEndMs = fr2.end;
        }
        var frCtx = buildFullRange();
        if (_fullStartMs > frCtx.start)
            _fullStartMs = frCtx.start;
        if (_fullEndMs < frCtx.end)
            _fullEndMs = frCtx.end;
        timelineXAxis.min = new Date(_fullStartMs);
        timelineXAxis.max = new Date(_fullEndMs);
        var tlRange = niceAxisRange(tlMinY, tlMaxY);
        timelineYAxis.min = tlRange.min;
        timelineYAxis.max = tlRange.max;
        _timelineReady = true;
        updateTimelineWindow();
        _loadingTimeline = false;
    }

    function buildChartData() {
        var result = [];
        for (var i = 0; i < SensorModel.count; ++i)
            result.push(SensorModel.get(i));
        return result;
    }

    function updateMainChart() {
        mainLine.clear();
        var key = metricKeys[selectedMetricIndex];
        xAxis.min = _rangeStartMs > 0 ? new Date(_rangeStartMs) : new Date(0);
        xAxis.max = _rangeEndMs > 0 ? new Date(_rangeEndMs) : new Date(86400000);
        if (chartData.length === 0) {
            yAxis.min = metricRanges[selectedMetricIndex][0];
            yAxis.max = metricRanges[selectedMetricIndex][1];
            return;
        }
        var allPts = smoothData(chartData, key);
        var pts = downsample(allPts, 500);
        if (pts.length === 0) {
            yAxis.min = metricRanges[selectedMetricIndex][0];
            yAxis.max = metricRanges[selectedMetricIndex][1];
            return;
        }
        var minY = Infinity, maxY = -Infinity;
        for (var i = 0; i < pts.length; ++i) {
            mainLine.append(new Date(pts[i].ms), pts[i].y);
            if (pts[i].y < minY)
                minY = pts[i].y;
            if (pts[i].y > maxY)
                maxY = pts[i].y;
        }
        var nr = niceAxisRange(minY, maxY);
        yAxis.min = nr.min;
        yAxis.max = nr.max;
    }

    function updateTimelineWindow() {
        var tw = timelineContainer.width;
        if (tw <= 0)
            return;
        var fStart = _fullStartMs;
        var fEnd = _fullEndMs;
        if (!_timelineReady || fEnd <= fStart) {
            var fr = buildFullRange();
            fStart = fr.start;
            fEnd = fr.end;
        }
        var totalRange = fEnd - fStart;
        if (totalRange <= 0)
            return;
        var winWidth = _rangeEndMs - _rangeStartMs;
        if (winWidth <= 0)
            winWidth = 1;
        var sx = ((_rangeStartMs - fStart) / totalRange) * tw;
        var sw = (winWidth / totalRange) * tw;
        if (sw < 22)
            sw = 22;
        if (sx + sw > tw)
            sx = Math.max(0, tw - sw);
        if (sx < 0)
            sx = 0;
        selWinBg.x = sx;
        selWinBg.width = sw;
        leftGrip.x = sx - 4;
        rightGrip.x = sx + sw - rightGrip.width + 4;
    }

    function applyFull(startMs, endMs) {
        _rangeStartMs = startMs;
        _rangeEndMs = endMs;
        _appliedStartMs = startMs;
        _appliedEndMs = endMs;
        _canReset = true;
        updateMainChart();
        updateTimelineWindow();
    }
    function applyPreview(startMs, endMs) {
        _rangeStartMs = startMs;
        _rangeEndMs = endMs;
        var win = endMs - startMs;
        var tw = timelineContainer.width;
        var fullRange = _fullEndMs - _fullStartMs;
        var mspp = (tw > 0 && fullRange > 0) ? (fullRange / tw) : 1;
        var tol = Math.max(mspp * 2, 1000);
        if (granularityMode === "day") {
            _canApply = Math.abs(win - 3600000) < tol;
        } else if (granularityMode === "hour") {
            _canApply = Math.abs(win - 60000) < tol;
        } else {
            _canApply = false;
        }
        updateTimelineWindow();
    }

    function applyDrill() {
        if (!_canApply)
            return;
        if (granularityMode === "day") {
            granularityMode = "hour";
            windowDurationMs = 3600000;
        } else if (granularityMode === "hour") {
            granularityMode = "minute";
            windowDurationMs = 60000;
        }
        var anchorMid = (_rangeStartMs + _rangeEndMs) / 2;
        var anchorDate = new Date(anchorMid);
        selectedAnchorDate = new Date(anchorDate.getFullYear(), anchorDate.getMonth(), anchorDate.getDate());
        selectedHour = anchorDate.getHours();
        _appliedStartMs = _rangeStartMs;
        _appliedEndMs = _rangeEndMs;
        _canApply = false;
        _timelineReady = false;
        _canReset = true;
        if (selectedDeviceId)
            refreshData(true);
        tlLoadTimer.start();
    }

    function resetDrill() {
        granularityMode = "day";
        windowDurationMs = 86400000;
        _appliedStartMs = 0;
        _appliedEndMs = 0;
        _canApply = false;
        _canReset = false;
        _timelineReady = false;
        if (selectedDeviceId)
            refreshData(true);
        tlLoadTimer.start();
    }

    function selectGranularity(mode) {
        granularityMode = mode;
        _appliedStartMs = 0;
        _appliedEndMs = 0;
        _canApply = false;
        _canReset = false;
        switch (mode) {
        case "minute":
            windowDurationMs = 60000;
            break;
        case "hour":
            windowDurationMs = 3600000;
            break;
        default:
            windowDurationMs = 86400000;
            break;
        }
        _timelineReady = false;
        if (selectedDeviceId)
            refreshData();
        tlLoadTimer.start();
    }

    function openDatePicker() {
        datePickerDialog.open();
    }

    function onDatePicked(year, month, day, hour) {
        selectedAnchorDate = new Date(year, month - 1, day);
        selectedHour = hour;
        _appliedStartMs = 0;
        _appliedEndMs = 0;
        _canApply = false;
        _canReset = false;
        _timelineReady = false;
        if (selectedDeviceId)
            refreshData();
        tlLoadTimer.start();
    }

    function selectMetric(idx) {
        selectedMetricIndex = idx;
        currentMetricLabel = metricLabels[idx];
        currentMetricUnit = metricUnits[idx];
        currentMetricColor = metricColors[idx];
        updateMainChart();
        if (fullTimelineData.length > 0)
            buildTimeline();
    }

    function loadSensorDevices() {
        var nl = [];
        var devs = DeviceModel.getSensorDevices() || DeviceModel.allDevices || [];
        for (var i = 0; i < devs.length; ++i) {
            nl.push({
                device_id: devs[i].device_id || "",
                device_name: devs[i].device_name || devs[i].device_id,
                device_type: devs[i].device_type || ""
            });
        }
        sensorDeviceList = nl;
    }

    function updateCurrentValues() {
        if (chartData.length === 0) {
            currentTempValue = currentHumiValue = currentLightValue = currentRainValue = "--";
            currentSmokeValue = currentLpgValue = currentAirValue = currentPressValue = "--";
            tempNormal = humiNormal = lightNormal = rainNormal = smokeNormal = lpgNormal = airNormal = pressNormal = true;
            return;
        }
        var t = 0, h = 0, li = 0, r = 0, s = 0, lp = 0, a = 0, p = 0;
        var foundTemp = false, foundHumi = false, foundLight = false, foundRain = false;
        var foundSmoke = false, foundLpg = false, foundAir = false, foundPress = false;
        for (var i = chartData.length - 1; i >= 0; --i) {
            var row = chartData[i];
            if (!foundTemp && typeof row.temperature === "number" && isFinite(row.temperature) && row.temperature !== 0) {
                t = row.temperature; foundTemp = true;
            }
            if (!foundHumi && typeof row.humidity === "number" && isFinite(row.humidity) && row.humidity !== 0) {
                h = row.humidity; foundHumi = true;
            }
            if (!foundLight && typeof row.light === "number" && isFinite(row.light) && row.light !== 0) {
                li = row.light; foundLight = true;
            }
            if (!foundRain && typeof row.rain === "number" && isFinite(row.rain) && row.rain !== 0) {
                r = row.rain; foundRain = true;
            }
            if (!foundSmoke && typeof row.smoke === "number" && isFinite(row.smoke) && row.smoke !== 0) {
                s = row.smoke; foundSmoke = true;
            }
            if (!foundLpg && typeof row.lpg === "number" && isFinite(row.lpg) && row.lpg !== 0) {
                lp = row.lpg; foundLpg = true;
            }
            if (!foundAir && typeof row.air_quality === "number" && isFinite(row.air_quality) && row.air_quality !== 0) {
                a = row.air_quality; foundAir = true;
            }
            if (!foundPress && typeof row.pressure === "number" && isFinite(row.pressure) && row.pressure !== 0) {
                p = row.pressure; foundPress = true;
            }
            if (foundTemp && foundHumi && foundLight && foundRain && foundSmoke && foundLpg && foundAir && foundPress)
                break;
        }
        currentTempValue = foundTemp ? t.toFixed(1) : "--";
        currentHumiValue = foundHumi ? h.toFixed(1) : "--";
        currentLightValue = foundLight ? li.toFixed(0) : "--";
        currentRainValue = foundRain ? r.toFixed(0) : "--";
        currentSmokeValue = foundSmoke ? s.toFixed(0) : "--";
        currentLpgValue = foundLpg ? lp.toFixed(0) : "--";
        currentAirValue = foundAir ? a.toFixed(0) : "--";
        currentPressValue = foundPress ? p.toFixed(1) : "--";
        tempNormal = !foundTemp || (t >= alertThresholds[0].min && t <= alertThresholds[0].max);
        humiNormal = !foundHumi || (h >= alertThresholds[1].min && h <= alertThresholds[1].max);
        lightNormal = !foundLight || (li >= alertThresholds[2].min && li <= alertThresholds[2].max);
        rainNormal = !foundRain || (r >= alertThresholds[3].min && r <= alertThresholds[3].max);
        smokeNormal = !foundSmoke || (s >= alertThresholds[4].min && s <= alertThresholds[4].max);
        lpgNormal = !foundLpg || (lp >= alertThresholds[5].min && lp <= alertThresholds[5].max);
        airNormal = !foundAir || (a >= alertThresholds[6].min && a <= alertThresholds[6].max);
        pressNormal = !foundPress || (p >= alertThresholds[7].min && p <= alertThresholds[7].max);
        if (foundTemp)
            checkAlert("temperature", "温度", t, "°C", tempNormal, alertThresholds[0], 3);
        if (foundHumi)
            checkAlert("humidity", "湿度", h, "%", humiNormal, alertThresholds[1], 3);
        if (foundSmoke)
            checkAlert("smoke", "烟雾", s, "ppm", smokeNormal, alertThresholds[4], 10);
        if (foundLpg)
            checkAlert("lpg", "液化气", lp, "ppm", lpgNormal, alertThresholds[5], 10);
        if (foundAir)
            checkAlert("air_quality", "空气质量", a, "AQI", airNormal, alertThresholds[6], 5);
        if (foundPress)
            checkAlert("pressure", "气压", p, " hPa", pressNormal, alertThresholds[7], 15);
    }

    function checkAlert(key, label, val, unit, ok, th, cooldownMin) {
        if (ok)
            return;
        var now = Date.now();
        var ak = selectedDeviceId + "_" + key;
        if (now - (lastAlertTimes[ak] || 0) < cooldownMin * 60000)
            return;
        var lvl = 2, msg = "";
        if (val < th.min)
            msg = label + " 过低: " + val + unit + " (<" + th.min + unit + ")";
        else if (val > th.max) {
            msg = label + " 过高: " + val + unit + " (>" + th.max + unit + ")";
            lvl = 3;
        }
        if (msg) {
            DatabaseManager.addAlert("sa_" + now, selectedDeviceId, msg, lvl, "sensor");
            lastAlertTimes[ak] = now;
        }
    }

    Timer {
        id: autoTimer
        interval: 10000
        repeat: true
        onTriggered: {
            if (!selectedDeviceId && sensorDeviceList.length > 0)
                selectedDeviceId = sensorDeviceList[0].device_id || "";
            if (selectedDeviceId && !_refreshing) {
                refreshData(false);
                if (!_timelineReady && SensorModel.count > 0)
                    tlLoadTimer.start();
            }
        }
    }
    Timer {
        id: tlLoadTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (selectedDeviceId)
                loadTimeline();
        }
    }
    Timer {
        id: dragSettleTimer
        interval: 180
        repeat: false
        property double _pendingS: 0
        property double _pendingE: 0
        onTriggered: applyFull(_pendingS, _pendingE)
    }

    Component.onCompleted: {
        loadSensorDevices();
        if (sensorDeviceList.length > 0) {
            selectedDeviceId = sensorDeviceList[0].device_id || "";
            refreshData();
            tlLoadTimer.start();
        }
        autoTimer.start();
    }

    Connections {
        target: SensorModel
        function onCountChanged() {
            if (_loadingTimeline) {
                buildTimeline();
                return;
            }
            if (_refreshing)
                return;
            chartData = buildChartData();
            updateCurrentValues();
            updateMainChart();
            updateTimelineWindow();
        }
    }
    Connections {
        target: DeviceModel
        function onCountChanged() {
            loadSensorDevices();
            if (!selectedDeviceId && sensorDeviceList.length > 0) {
                selectedDeviceId = sensorDeviceList[0].device_id || "";
                refreshData();
                tlLoadTimer.start();
            }
        }
    }

    header: ToolBar {
        height: 48 * sc
        background: Rectangle {
            color: "#0d1a2e"
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14 * sc
            anchors.rightMargin: 14 * sc
            spacing: 10 * sc
            Label {
                text: "📈 传感器监控"
                font.pixelSize: 15 * sc
                font.bold: true
                color: "#4fc3f7"
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                text: sensorDeviceList.length === 0 ? "无传感器设备" : "传感器"
                font.pixelSize: 11 * sc
                color: "#81c784"
            }
            Button {
                text: sensorDeviceList.length === 0 ? "🔍 重新搜索" : "↻ 刷新"
                flat: true
                font.pixelSize: 12 * sc
                onClicked: {
                    loadSensorDevices();
                    if (sensorDeviceList.length > 0 && !selectedDeviceId)
                        selectedDeviceId = sensorDeviceList[0].device_id || "";
                    if (selectedDeviceId) {
                        _timelineReady = false;
                        refreshData();
                        tlLoadTimer.start();
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8 * sc
        spacing: 6 * sc

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72 * sc
            color: "transparent"
            radius: 8 * sc
            RowLayout {
                anchors.fill: parent
                spacing: 5 * sc
                MiniTile {
                    ti: "🌡️"
                    lb: "温度"
                    vl: currentTempValue
                    unit: "°C"
                    cl: "#4fc3f7"
                    ok: tempNormal
                    idx: 0
                    active: selectedMetricIndex === 0
                    onClicked: selectMetric(0)
                }
                MiniTile {
                    ti: "💧"
                    lb: "湿度"
                    vl: currentHumiValue
                    unit: "%"
                    cl: "#81c784"
                    ok: humiNormal
                    idx: 1
                    active: selectedMetricIndex === 1
                    onClicked: selectMetric(1)
                }
                MiniTile {
                    ti: "☀️"
                    lb: "光照"
                    vl: currentLightValue
                    unit: " lux"
                    cl: "#ffd54f"
                    ok: lightNormal
                    idx: 2
                    active: selectedMetricIndex === 2
                    onClicked: selectMetric(2)
                }
                MiniTile {
                    ti: "🌧️"
                    lb: "雨滴"
                    vl: currentRainValue
                    unit: ""
                    cl: "#4dd0e1"
                    ok: rainNormal
                    idx: 3
                    active: selectedMetricIndex === 3
                    onClicked: selectMetric(3)
                }
                MiniTile {
                    ti: "🔥"
                    lb: "烟雾"
                    vl: currentSmokeValue
                    unit: " ppm"
                    cl: "#e57373"
                    ok: smokeNormal
                    idx: 4
                    active: selectedMetricIndex === 4
                    onClicked: selectMetric(4)
                }
                MiniTile {
                    ti: "🔧"
                    lb: "液化气"
                    vl: currentLpgValue
                    unit: " ppm"
                    cl: "#ffb74d"
                    ok: lpgNormal
                    idx: 5
                    active: selectedMetricIndex === 5
                    onClicked: selectMetric(5)
                }
                MiniTile {
                    ti: "🌬️"
                    lb: "空气质量"
                    vl: currentAirValue
                    unit: " AQI"
                    cl: "#ce93d8"
                    ok: airNormal
                    idx: 6
                    active: selectedMetricIndex === 6
                    onClicked: selectMetric(6)
                }
                MiniTile {
                    ti: "📊"
                    lb: "气压"
                    vl: currentPressValue
                    unit: " hPa"
                    cl: "#90a4ae"
                    ok: pressNormal
                    idx: 7
                    active: selectedMetricIndex === 7
                    onClicked: selectMetric(7)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34 * sc
            color: "transparent"
            RowLayout {
                anchors.fill: parent
                spacing: 6 * sc
                Item { Layout.fillWidth: true }

                Rectangle {
                    height: 28 * sc
                    width: 120 * sc
                    radius: 6 * sc
                    color: "#0d1629"
                    border.color: "#1e3050"
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2 * sc
                        spacing: 1 * sc
                        Button {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 36 * sc
                            flat: true
                            contentItem: Label {
                                text: "天"
                                font.pixelSize: 10 * sc
                                font.bold: granularityMode === "day"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: granularityMode === "day" ? "#ff9800" : "#6a8aaa"
                            }
                            background: Rectangle {
                                radius: 4 * sc
                                color: granularityMode === "day" ? "#2a1a00" : "transparent"
                            }
                            onClicked: selectGranularity("day")
                        }
                        Button {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 36 * sc
                            flat: true
                            contentItem: Label {
                                text: "时"
                                font.pixelSize: 10 * sc
                                font.bold: granularityMode === "hour"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: granularityMode === "hour" ? "#ff9800" : "#6a8aaa"
                            }
                            background: Rectangle {
                                radius: 4 * sc
                                color: granularityMode === "hour" ? "#2a1a00" : "transparent"
                            }
                            onClicked: selectGranularity("hour")
                        }
                        Button {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 36 * sc
                            flat: true
                            contentItem: Label {
                                text: "分"
                                font.pixelSize: 10 * sc
                                font.bold: granularityMode === "minute"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: granularityMode === "minute" ? "#ff9800" : "#6a8aaa"
                            }
                            background: Rectangle {
                                radius: 4 * sc
                                color: granularityMode === "minute" ? "#2a1a00" : "transparent"
                            }
                            onClicked: selectGranularity("minute")
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: 20 * sc
                    color: "#2a3a50"
                }

                Button {
                    flat: true
                    visible: _canApply && granularityMode !== "minute"
                    contentItem: Label {
                        text: granularityMode === "day" ? "💾 保存到小时" : (granularityMode === "hour" ? "💾 保存到分钟" : "💾 保存")
                        font.pixelSize: 11 * sc
                        color: "#81c784"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6 * sc
                        color: "#0a2810"
                        border.color: "#81c784"
                        border.width: 1
                    }
                    onClicked: applyDrill()
                }

                Button {
                    flat: true
                    visible: _canReset
                    contentItem: Label {
                        text: "↩ 回到全天"
                        font.pixelSize: 11 * sc
                        color: "#4fc3f7"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6 * sc
                        color: "#0a1a28"
                        border.color: "#4fc3f7"
                        border.width: 1
                    }
                    onClicked: resetDrill()
                }

                Rectangle {
                    width: 1
                    height: 20 * sc
                    color: "#2a3a50"
                }
                Button {
                    flat: true
                    contentItem: Label {
                        text: "📅 " + fmtFull(buildAnchorMs())
                        font.pixelSize: 11 * sc
                        color: "#ff9800"
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        radius: 6 * sc
                        color: "#2a1a00"
                        border.color: "#ff9800"
                        border.width: 1
                    }
                    onClicked: openDatePicker()
                }
                Item { Layout.fillWidth: true }
            }
        }

        Rectangle {
            id: chartArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#111827"
            radius: 8 * sc
            border.color: "#253555"

            GraphsView {
                id: mainGraph
                anchors.fill: parent
                anchors.margins: 6 * sc
                anchors.bottomMargin: 126 * sc
                theme: GraphsTheme {
                    theme: GraphsTheme.Theme.UserDefined
                    colorScheme: GraphsTheme.ColorScheme.Dark
                    backgroundColor: "transparent"
                    plotAreaBackgroundColor: "#0b101d"
                    grid.mainColor: "#294062"
                    grid.subColor: "#152040"
                    labelTextColor: "#5a7a9a"
                    axisX.mainColor: "#2a3a50"
                    axisY.mainColor: "#2a3a50"
                    seriesColors: [metricColors[selectedMetricIndex]]
                }
                DateTimeAxis {
                    id: xAxis
                    min: new Date(0)
                    max: new Date(86400000)
                    labelFormat: granularityMode === "minute" ? "MM-dd HH:mm:ss" : (granularityMode === "hour" ? "MM-dd HH:mm" : "HH:mm")
                    subTickCount: 0
                }
                ValueAxis {
                    id: yAxis
                    min: metricRanges[0][0]
                    max: metricRanges[0][1]
                    labelFormat: "%.1f"
                    titleText: currentMetricUnit
                    titleFont.pixelSize: 11 * sc
                    titleVisible: true
                    subTickCount: 0
                }
                LineSeries {
                    id: mainLine
                    width: 2.2
                    axisX: xAxis
                    axisY: yAxis
                    color: currentMetricColor
                }
                AreaSeries {
                    id: mainFill
                    axisX: xAxis
                    axisY: yAxis
                    upperSeries: mainLine
                    color: Qt.rgba(currentMetricColor.r, currentMetricColor.g, currentMetricColor.b, 0.25)
                    borderColor: Qt.rgba(currentMetricColor.r, currentMetricColor.g, currentMetricColor.b, 0.4)
                    borderWidth: 0.4
                    opacity: 1.0
                }
            }

            Item {
                id: chartCanvas
                anchors.fill: mainGraph

                Rectangle {
                    id: crosshairLine
                    visible: showHover
                    width: 1
                    height: parent.height
                    color: metricColors[selectedMetricIndex]
                    opacity: 0.3
                }

                Rectangle {
                    id: hoverTooltip
                    visible: showHover
                    x: Math.min(Math.max(hoverTipX, 4 * sc), chartCanvas.width - width - 4 * sc)
                    y: Math.min(Math.max(hoverTipY, 2 * sc), chartCanvas.height - height - 48 * sc)
                    width: 200 * sc
                    height: 40 * sc
                    radius: 8 * sc
                    color: "#dd0a1628"
                    border.color: metricColors[selectedMetricIndex]
                    border.width: 1.5
                    Column {
                        anchors.centerIn: parent
                        spacing: 2 * sc
                        Label {
                            text: currentMetricLabel + ": " + hoverDataValue.toFixed(1) + " " + currentMetricUnit
                            font.pixelSize: 12 * sc
                            font.bold: true
                            color: metricColors[selectedMetricIndex]
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Label {
                            text: hoverDataTime
                            font.pixelSize: 10 * sc
                            color: "#8a9ab0"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: function (mouse) {
                        var allPts = smoothData(chartData, metricKeys[selectedMetricIndex]);
                        if (allPts.length === 0) {
                            showHover = false;
                            return;
                        }
                        var w = chartCanvas.width;
                        if (w <= 0)
                            return;
                        var xMin = _rangeStartMs;
                        var xMax = _rangeEndMs;
                        var xRange = xMax - xMin;
                        if (xRange <= 0) {
                            showHover = false;
                            return;
                        }
                        var pts = [];
                        for (var pi = 0; pi < allPts.length; ++pi) {
                            if (allPts[pi].ms >= xMin && allPts[pi].ms <= xMax)
                                pts.push(allPts[pi]);
                        }
                        if (pts.length === 0) {
                            showHover = false;
                            return;
                        }
                        var targetMs = xMin + (mouse.x / w) * xRange;
                        var best = 0, bestD = Infinity;
                        for (var i = 0; i < pts.length; ++i) {
                            var d = Math.abs(pts[i].ms - targetMs);
                            if (d < bestD) {
                                bestD = d;
                                best = i;
                            }
                        }
                        hoverDataValue = pts[best].y;
                        hoverDataTime = fmtDateTime(pts[best].ms);
                        showHover = true;
                        hoverTipX = mouse.x + 10 * sc;
                        hoverTipY = Math.max(2 * sc, mouse.y - 52 * sc);
                        crosshairLine.x = mouse.x;
                    }
                    onExited: {
                        showHover = false;
                        crosshairLine.visible = false;
                    }
                }
            }

            Item {
                id: tlOuter
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 6 * sc
                height: 120 * sc

                Rectangle {
                    anchors.fill: parent
                    color: "#0d1629"
                    radius: 8 * sc
                    border.color: "#1e3050"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4 * sc
                        spacing: 2 * sc
                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: 10 * sc
                            color: "#5a7a9a"
                            text: "📅 " + fmtRangeLabel()
                        }

                        Item {
                            id: timelineContainer
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            GraphsView {
                                id: tlGraph
                                anchors.fill: parent
                                theme: GraphsTheme {
                                    theme: GraphsTheme.Theme.UserDefined
                                    colorScheme: GraphsTheme.ColorScheme.Dark
                                    backgroundColor: "transparent"
                                    plotAreaBackgroundColor: "#060d18"
                                    grid.mainColor: "#152040"
                                    grid.subColor: "#0a101e"
                                    labelTextColor: "#3a5a6a"
                                    seriesColors: [currentMetricColor]
                                }
                                DateTimeAxis {
                                    id: timelineXAxis
                                    min: new Date(0)
                                    max: new Date(86400000)
                                    labelFormat: granularityMode === "minute" ? "MM-dd HH:mm:ss" : (granularityMode === "hour" ? "MM-dd HH:mm" : "MM/dd")
                                    labelsVisible: true
                                    gridVisible: true
                                    subTickCount: 0
                                }
                                ValueAxis {
                                    id: timelineYAxis
                                    min: -1
                                    max: 50
                                    labelsVisible: false
                                    gridVisible: false
                                    subTickCount: 0
                                }
                                LineSeries {
                                    id: timelineLine
                                    width: 0.8
                                    axisX: timelineXAxis
                                    axisY: timelineYAxis
                                    color: currentMetricColor
                                }
                                AreaSeries {
                                    id: timelineFill
                                    axisX: timelineXAxis
                                    axisY: timelineYAxis
                                    upperSeries: timelineLine
                                    color: Qt.rgba(currentMetricColor.r, currentMetricColor.g, currentMetricColor.b, 0.15)
                                    borderColor: Qt.rgba(currentMetricColor.r, currentMetricColor.g, currentMetricColor.b, 0.25)
                                    borderWidth: 0.3
                                    opacity: 1.0
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 28 * sc
                                rotation: 180
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: "#0d1629"
                                    }
                                    GradientStop {
                                        position: 0.45
                                        color: "#0d1629"
                                    }
                                    GradientStop {
                                        position: 0.75
                                        color: "#0a1220"
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: "transparent"
                                    }
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 28 * sc
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: "#0d1629"
                                    }
                                    GradientStop {
                                        position: 0.45
                                        color: "#0d1629"
                                    }
                                    GradientStop {
                                        position: 0.75
                                        color: "#0a1220"
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: "transparent"
                                    }
                                }
                            }

                            Rectangle {
                                id: selWinBg
                                y: 1
                                height: parent.height - 2
                                radius: 4 * sc
                                color: Qt.rgba(currentMetricColor.r, currentMetricColor.g, currentMetricColor.b, 0.2)
                                opacity: 1.0
                                border.color: currentMetricColor
                                border.width: 1.5
                                Behavior on x {
                                    NumberAnimation {
                                        duration: 80
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 80
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                x: 0
                                width: 80
                            }

                            Rectangle {
                                id: leftGrip
                                z: 10
                                y: 1
                                height: parent.height - 2
                                width: 10 * sc
                                radius: 4 * sc
                                color: currentMetricColor
                                x: 0
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 2
                                    height: 18 * sc
                                    radius: 1
                                    color: "#0a1420"
                                }
                            }
                            Rectangle {
                                id: rightGrip
                                z: 10
                                y: 1
                                height: parent.height - 2
                                width: 10 * sc
                                radius: 4 * sc
                                color: currentMetricColor
                                x: 0
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 2
                                    height: 18 * sc
                                    radius: 1
                                    color: "#0a1420"
                                }
                            }

                            Label {
                                id: leftDateLabel
                                z: 10
                                text: _rangeStartMs > 0 ? fmtLabelDate(_rangeStartMs) : "--"
                                font.pixelSize: 10 * sc
                                font.bold: true
                                color: currentMetricColor
                                x: Math.max(2, leftGrip.x - implicitWidth - 6)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                id: rightDateLabel
                                z: 10
                                text: _rangeEndMs > 0 ? fmtLabelDate(_rangeEndMs) : "--"
                                font.pixelSize: 10 * sc
                                font.bold: true
                                color: currentMetricColor
                                x: Math.min(rightGrip.x + rightGrip.width + 6, parent.width - implicitWidth - 2)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            MouseArea {
                                id: tlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                property string _mode: ""
                                property real _mx: 0
                                property double _ms: 0
                                property double _me: 0
                                readonly property real _gripZone: 14

                                function _calcMsPerPx() {
                                    var tw = timelineContainer.width;
                                    if (tw <= 0)
                                        return 0;
                                    var fStart = _fullStartMs;
                                    var fEnd = _fullEndMs;
                                    if (!_timelineReady || fEnd <= fStart) {
                                        var fr = buildFullRange();
                                        fStart = fr.start;
                                        fEnd = fr.end;
                                    }
                                    if (fEnd <= fStart)
                                        return 0;
                                    return (fEnd - fStart) / tw;
                                }
                                function _detectZone(mx) {
                                    var sx = selWinBg.x, sw = selWinBg.width;
                                    if (mx >= sx - _gripZone && mx <= sx + _gripZone)
                                        return "left";
                                    if (mx >= sx + sw - _gripZone && mx <= sx + sw + _gripZone)
                                        return "right";
                                    return "";
                                }

                                cursorShape: {
                                    var z = _detectZone(mouseX);
                                    if (z === "left" || z === "right")
                                        return Qt.SizeHorCursor;
                                    return Qt.ArrowCursor;
                                }

                                onPressed: function (mouse) {
                                    _mx = mouse.x;
                                    _ms = _rangeStartMs;
                                    _me = _rangeEndMs;
                                    _mode = _detectZone(mouse.x);
                                }
                                onReleased: {
                                    if (_mode !== "") {
                                        dragSettleTimer._pendingS = _rangeStartMs;
                                        dragSettleTimer._pendingE = _rangeEndMs;
                                        dragSettleTimer.restart();
                                    }
                                    _mode = "";
                                }
                                onPositionChanged: function (mouse) {
                                    if (_mode === "")
                                        return;
                                    var mspp = _calcMsPerPx();
                                    if (mspp <= 0)
                                        return;
                                    var fStart = _fullStartMs;
                                    var fEnd = _fullEndMs;
                                    if (!_timelineReady || fEnd <= fStart) {
                                        var fr = buildFullRange();
                                        fStart = fr.start;
                                        fEnd = fr.end;
                                    }
                                    var dx = mouse.x - _mx;
                                    if (_mode === "left") {
                                        var ns = _ms + dx * mspp;
                                        if (ns < fStart) ns = fStart;
                                        if (ns > _me - 1000) ns = _me - 1000;
                                        applyPreview(ns, _me);
                                    } else if (_mode === "right") {
                                        var ne = _me + dx * mspp;
                                        if (ne > fEnd) ne = fEnd;
                                        if (ne < _ms + 1000) ne = _ms + 1000;
                                        applyPreview(_ms, ne);
                                    }
                                    updateMainChart();
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -60 * sc
                width: 260 * sc
                height: 90 * sc
                radius: 10 * sc
                color: "#1a1a30"
                border.color: "#3a3a5a"
                visible: chartData.length === 0
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4 * sc
                    Label {
                        text: sensorDeviceList.length === 0 ? "⚠ 未发现传感器设备" : "ℹ 暂无数据"
                        font.pixelSize: 14 * sc
                        font.bold: true
                        color: sensorDeviceList.length === 0 ? "#ff9800" : "#81c784"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: sensorDeviceList.length === 0 ? "等待UDP设备上报，或检查设备连接状态" : ("该设备暂无 " + currentMetricLabel + " 历史数据")
                        font.pixelSize: 11 * sc
                        color: "#8a9ab0"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Button {
                        text: sensorDeviceList.length === 0 ? "🔄 刷新设备列表" : "🔄 刷新数据"
                        flat: true
                        font.pixelSize: 11 * sc
                        Layout.alignment: Qt.AlignHCenter
                        contentItem: Label {
                            text: parent.text
                            font: parent.font
                            color: "#4fc3f7"
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: {
                            loadSensorDevices();
                            if (sensorDeviceList.length > 0 && !selectedDeviceId)
                                selectedDeviceId = sensorDeviceList[0].device_id || "";
                            if (selectedDeviceId) {
                                _timelineReady = false;
                                refreshData();
                                tlLoadTimer.start();
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: datePickerDialog
        title: granularityMode === "minute" ? "选择日期 — 分钟级" : (granularityMode === "hour" ? "选择日期 — 小时级" : "选择日期 — 天级")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 360 * sc
        height: 440 * sc
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property date _pickerDate: selectedAnchorDate
        property int _pickerHour: selectedHour
        property var _availableDays: []

        function _refreshAvailableDays() {
            if (!selectedDeviceId) return;
            var y = pickerMonthGrid.year;
            var m = pickerMonthGrid.month + 1;
            _availableDays = DatabaseManager.getAvailableDataDates(selectedDeviceId, y, m) || [];
        }

        onOpened: {
            _pickerDate = selectedAnchorDate;
            _pickerHour = selectedHour;
            pickerMonthGrid.month = _pickerDate.getMonth();
            pickerMonthGrid.year = _pickerDate.getFullYear();
            _refreshAvailableDays();
        }
        onAccepted: {
            var y = _pickerDate.getFullYear();
            var m = _pickerDate.getMonth() + 1;
            var d = _pickerDate.getDate();
            onDatePicked(y, m, d, _pickerHour);
        }
        onRejected: {
            _pickerDate = selectedAnchorDate;
            _pickerHour = selectedHour;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4 * sc
            spacing: 6 * sc

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30 * sc
                color: "#1a2a40"
                radius: 6 * sc
                Label {
                    anchors.centerIn: parent
                    text: {
                        var y = datePickerDialog._pickerDate.getFullYear();
                        var m = String(datePickerDialog._pickerDate.getMonth() + 1).padStart(2, '0');
                        var d = String(datePickerDialog._pickerDate.getDate()).padStart(2, '0');
                        var h = String(datePickerDialog._pickerHour).padStart(2, '0');
                        if (granularityMode === "minute")
                            return y + "/" + m + "/" + d + " " + h + ":00 — 分钟级精准";
                        if (granularityMode === "hour")
                            return y + "/" + m + "/" + d + " " + h + ":00 — 小时级聚焦";
                        return y + "/" + m + "/" + d + " — 全天概览";
                    }
                    font.pixelSize: 13 * sc
                    font.bold: true
                    color: "#ff9800"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4 * sc
                Button {
                    text: "◀"
                    flat: true
                    font.pixelSize: 12 * sc
                    onClicked: {
                        var m = pickerMonthGrid.month - 1;
                        var y = pickerMonthGrid.year;
                        if (m < 0) { m = 11; y--; }
                        pickerMonthGrid.month = m;
                        pickerMonthGrid.year = y;
                        datePickerDialog._refreshAvailableDays();
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: pickerMonthGrid.year + "年" + (pickerMonthGrid.month + 1) + "月"
                    font.pixelSize: 13 * sc
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                }
                Button {
                    text: "▶"
                    flat: true
                    font.pixelSize: 12 * sc
                    onClicked: {
                        var m = pickerMonthGrid.month + 1;
                        var y = pickerMonthGrid.year;
                        if (m > 11) { m = 0; y++; }
                        pickerMonthGrid.month = m;
                        pickerMonthGrid.year = y;
                        datePickerDialog._refreshAvailableDays();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: ["日", "一", "二", "三", "四", "五", "六"]
                    delegate: Label {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        font.pixelSize: 10 * sc
                        color: index === 0 || index === 6 ? "#5a7a9a" : "#8a9ab0"
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            MonthGrid {
                id: pickerMonthGrid
                Layout.fillWidth: true
                Layout.preferredHeight: 180 * sc
                month: datePickerDialog._pickerDate.getMonth()
                year: datePickerDialog._pickerDate.getFullYear()
                locale: Qt.locale("zh_CN")

                delegate: Rectangle {
                    required property int index
                    required property int day
                    required property int month
                    required property int year
                    width: pickerMonthGrid.width / 7
                    height: 28 * sc
                    radius: 4 * sc
                    property bool _inMonth: month === pickerMonthGrid.month && year === pickerMonthGrid.year
                    property bool _hasData: _inMonth && datePickerDialog._availableDays.indexOf(day) >= 0
                    property bool _picked: _inMonth && day === datePickerDialog._pickerDate.getDate() && _hasData
                    color: _picked ? "#ff9800" : "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: day
                        font.pixelSize: 12 * sc
                        font.bold: _picked
                        color: _picked ? "#ffffff" : (_hasData ? "#cccccc" : (_inMonth ? "#3a3a5a" : "#1a1a2e"))
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: _hasData
                        onClicked: {
                            if (_hasData)
                                datePickerDialog._pickerDate = new Date(year, month, day);
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: granularityMode === "day" ? "天视图无需选择小时（显示全天24h数据）" : "选择小时"
                font.pixelSize: 11 * sc
                color: "#7a9ab0"
                visible: granularityMode !== "day"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 1 * sc
                visible: granularityMode !== "day"
                Repeater {
                    model: 24
                    delegate: Button {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24 * sc
                        flat: true
                        text: String(index).padStart(2, '0')
                        font.pixelSize: 9 * sc
                        property bool _isSel: datePickerDialog._pickerHour === index
                        contentItem: Label {
                            text: parent.text
                            font: parent.font
                            horizontalAlignment: Text.AlignHCenter
                            color: parent._isSel ? "#ff9800" : "#6a8aaa"
                        }
                        background: Rectangle {
                            radius: 3 * sc
                            color: parent._isSel ? "#2a1a00" : "transparent"
                            border.color: parent._isSel ? "#ff9800" : "transparent"
                        }
                        onClicked: datePickerDialog._pickerHour = index
                    }
                }
            }
        }
    }

    component MiniTile: Rectangle {
        property string ti: ""
        property string lb: ""
        property string vl: ""
        property string unit: ""
        property color cl: "#fff"
        property bool ok: true
        property int idx: 0
        property bool active: false
        signal clicked
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 8 * sc
        color: active ? "#1a2840" : (ok ? "#0a1220" : "#1a1018")
        border.color: active ? cl : (ok ? "transparent" : "#ff5252")
        border.width: active ? 1.5 : (ok ? 0 : 1)
        readonly property string displayValue: vl === "--" ? "--" : (vl + unit)
        Column {
            anchors.centerIn: parent
            spacing: 2 * sc
            Label {
                text: ti
                font.pixelSize: 16 * sc
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Label {
                text: parent.parent.displayValue
                font.pixelSize: 14 * sc
                font.bold: true
                color: vl === "--" ? "#4a6a8a" : (ok ? cl : "#ff5252")
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Label {
                text: lb
                font.pixelSize: 9 * sc
                color: active ? cl : "#4a6a8a"
                font.bold: active
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
            hoverEnabled: true
            Rectangle {
                anchors.fill: parent
                radius: 8 * sc
                color: "#ffffff"
                opacity: parent.pressed ? 0.12 : (parent.containsMouse ? 0.05 : 0)
            }
        }
    }
}
