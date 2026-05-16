#include "scenetriggerengine.h"
#include "../models/databasemanager.h"
#include "tcpcontroller.h"
#include "../utils/jsonutils.h"
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

SceneTriggerEngine *SceneTriggerEngine::s_instance = nullptr;

SceneTriggerEngine::SceneTriggerEngine(QObject *parent)
    : QObject(parent), m_timer(nullptr), m_running(false), m_sceneCacheTimestamp(0), m_tcpController(nullptr)
{
    m_timer = new QTimer(this);
    m_timer->setInterval(1000); // 每秒检查一次定时场景
    m_timer->setSingleShot(false);
    connect(m_timer, &QTimer::timeout, this, &SceneTriggerEngine::checkTimeTriggers);
}

SceneTriggerEngine::~SceneTriggerEngine()
{
    if (s_instance == this)
    {
        s_instance = nullptr;
    }
}

SceneTriggerEngine *SceneTriggerEngine::instance()
{
    if (!s_instance)
    {
        s_instance = new SceneTriggerEngine();
    }
    return s_instance;
}

void SceneTriggerEngine::start()
{
    if (m_running)
        return;
    m_running = true;
    m_timer->start();
    checkTimeTriggers();
    qDebug() << "[场景引擎] 场景触发引擎已启动";
    emit runningChanged(true);
}

void SceneTriggerEngine::stop()
{
    if (!m_running)
        return;
    m_running = false;
    m_timer->stop();
    qDebug() << "[场景引擎] 场景触发引擎已停止";
    emit runningChanged(false);
}

void SceneTriggerEngine::checkTimeTriggers()
{
    refreshSceneCache();

    for (int i = 0; i < m_cachedScenes.size(); ++i)
    {
        QVariantMap scene = m_cachedScenes.at(i).toMap();
        QString triggerType = scene.value("trigger_type").toString();

        if (triggerType != "time")
            continue;

        evaluateTimeScene(scene);
    }
}

void SceneTriggerEngine::onSensorFieldUpdated(const QString &deviceId, const QString &field, double value)
{
    if (!m_running)
        return;

    QVariantMap sensorData;
    sensorData[field] = value;
    onSensorDataReceived(deviceId, sensorData);
}

void SceneTriggerEngine::onSensorDataReceived(const QString &deviceId, const QVariantMap &sensorData)
{
    if (!m_running)
        return;

    refreshSceneCache();

    for (int i = 0; i < m_cachedScenes.size(); ++i)
    {
        QVariantMap scene = m_cachedScenes.at(i).toMap();
        QString triggerType = scene.value("trigger_type").toString();

        if (triggerType != "sensor")
            continue;

        evaluateSensorScene(scene, deviceId, sensorData);
    }
}

void SceneTriggerEngine::onDeviceStateChanged(const QString &deviceId, const QString &action)
{
    if (!m_running)
        return;

    refreshSceneCache();

    for (int i = 0; i < m_cachedScenes.size(); ++i)
    {
        QVariantMap scene = m_cachedScenes.at(i).toMap();
        QString triggerType = scene.value("trigger_type").toString();

        if (triggerType != "device")
            continue;

        evaluateDeviceScene(scene, deviceId, action);
    }
}

void SceneTriggerEngine::onWeatherUpdated(const QVariantMap &weatherData)
{
    if (!m_running)
        return;

    m_lastWeatherData = weatherData;

    refreshSceneCache();

    for (int i = 0; i < m_cachedScenes.size(); ++i)
    {
        QVariantMap scene = m_cachedScenes.at(i).toMap();
        QString triggerType = scene.value("trigger_type").toString();

        if (triggerType != "weather")
            continue;

        evaluateWeatherScene(scene, weatherData);
    }
}

void SceneTriggerEngine::triggerScene(const QString &sceneId)
{
    QVariantMap scene = DatabaseManager::instance()->getScene(sceneId);
    if (scene.isEmpty())
    {
        qDebug() << "[场景引擎] 场景不存在:" << sceneId;
        return;
    }

    QString sceneName = scene.value("scene_name").toString();
    QString actions = scene.value("actions").toString();
    QString actionDevices = scene.value("action_devices").toString();

    qDebug() << "[场景引擎] 手动触发场景:" << sceneName << "(" << sceneId << ")";
    executeScene(sceneId, sceneName, actions, actionDevices);
}

void SceneTriggerEngine::evaluateTimeScene(const QVariantMap &scene)
{
    QString triggerTime = scene.value("trigger_time").toString();
    if (triggerTime.isEmpty())
        return;

    // 检查是否在生效时间窗口内
    if (!checkSceneEffectiveWindow(scene))
        return;

    // 比较当前时间
    QString currentTime = QDateTime::currentDateTime().toString("HH:mm");
    if (currentTime == triggerTime)
    {
        // 防止同一分钟重复触发
        QString lastExecutedAt = scene.value("last_executed_at").toString();
        if (!lastExecutedAt.isEmpty())
        {
            QDateTime lastExec = QDateTime::fromString(lastExecutedAt, Qt::ISODate);
            if (lastExec.isValid() && lastExec.toString("HH:mm") == currentTime)
                return; // 已经触发过了
        }

        QString sceneId = scene.value("scene_id").toString();
        QString sceneName = scene.value("scene_name").toString();
        QString actions = scene.value("actions").toString();
        QString actionDevices = scene.value("action_devices").toString();

        qDebug() << "[场景引擎] 定时触发:" << sceneName << "(" << triggerTime << ")";
        executeScene(sceneId, sceneName, actions, actionDevices);
    }
}

void SceneTriggerEngine::evaluateSensorScene(const QVariantMap &scene, const QString &deviceId, const QVariantMap &sensorData)
{
    if (!checkSceneEffectiveWindow(scene))
        return;

    QString triggerSensorData = scene.value("trigger_sensor_data").toString();

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(triggerSensorData.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return;

    QJsonObject sensorObj = doc.object();
    QString sensorDeviceId = sensorObj.value("sensorDeviceId").toString();
    if (sensorDeviceId != deviceId)
        return;

    QString sensorType = sensorObj.value("sensorType").toString();
    QString op = sensorObj.value("operator").toString();
    double threshold = sensorObj.value("threshold").toDouble();

    if (!sensorData.contains(sensorType))
        return;

    double currentValue = sensorData.value(sensorType).toDouble();
    bool triggered = false;

    if (op == ">")       triggered = currentValue > threshold;
    else if (op == ">=") triggered = currentValue >= threshold;
    else if (op == "<")  triggered = currentValue < threshold;
    else if (op == "<=") triggered = currentValue <= threshold;
    else if (op == "==") triggered = qFuzzyCompare(currentValue, threshold);
    else return;

    if (!triggered)
        return;

    QString sceneId = scene.value("scene_id").toString();
    QString sceneName = scene.value("scene_name").toString();
    QString actions = scene.value("actions").toString();
    QString actionDevices = scene.value("action_devices").toString();

    qDebug() << "[场景引擎] 传感器触发:" << sceneName << "(设备:" << deviceId << ", 类型:" << sensorType << op << threshold << ")";
    executeScene(sceneId, sceneName, actions, actionDevices);
}

void SceneTriggerEngine::evaluateDeviceScene(const QVariantMap &scene, const QString &deviceId, const QString &action)
{
    if (!checkSceneEffectiveWindow(scene))
        return;

    QString triggerDeviceId = scene.value("trigger_device_id").toString();
    QString triggerAction = scene.value("trigger_time").toString();

    if (triggerDeviceId != deviceId)
        return;

    // "change" 表示任意状态变化都触发
    if (triggerAction.isEmpty() || triggerAction == "change")
    {
        // 匹配任意变化
    }
    else
    {
        // 兼容不同命名：on=turn_on, off=turn_off, open=turn_on, close=turn_off
        QString normTrigger = triggerAction.toLower();
        QString normAction = action.toLower();
        bool match = (normAction == normTrigger)
                  || (normTrigger == "on"  && (normAction == "turn_on"  || normAction == "open"))
                  || (normTrigger == "off" && (normAction == "turn_off" || normAction == "close"))
                  || (normTrigger == "open"  && (normAction == "turn_on"  || normAction == "on"))
                  || (normTrigger == "close" && (normAction == "turn_off" || normAction == "off"));
        if (!match)
            return;
    }

    QString sceneId = scene.value("scene_id").toString();
    QString sceneName = scene.value("scene_name").toString();
    QString actions = scene.value("actions").toString();
    QString actionDevices = scene.value("action_devices").toString();

    qDebug() << "[场景引擎] 设备状态触发:" << sceneName << "(设备:" << deviceId << ", 动作:" << action << ")";
    executeScene(sceneId, sceneName, actions, actionDevices);
}

void SceneTriggerEngine::evaluateWeatherScene(const QVariantMap &scene, const QVariantMap &weatherData)
{
    if (!checkSceneEffectiveWindow(scene))
        return;

    QString triggerSensorData = scene.value("trigger_sensor_data").toString();

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(triggerSensorData.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return;

    QJsonObject sensorObj = doc.object();
    bool hasCondition = false;

    if (sensorObj.contains(QStringLiteral("rain")) && weatherData.contains(QStringLiteral("rain")))
    {
        hasCondition = true;
        bool isRaining = weatherData.value(QStringLiteral("rain")).toBool();
        bool triggerRain = sensorObj.value(QStringLiteral("rain")).toBool();
        if (isRaining != triggerRain)
            return;
    }

    if (sensorObj.contains(QStringLiteral("temperature")) && weatherData.contains(QStringLiteral("temperature")))
    {
        hasCondition = true;
        double currentTemp = weatherData.value(QStringLiteral("temperature")).toDouble();
        double threshold = sensorObj.value(QStringLiteral("temperature")).toDouble();
        QString op = sensorObj.value(QStringLiteral("operator")).toString();

        if (op == QStringLiteral(">"))         { if (currentTemp <= threshold) return; }
        else if (op == QStringLiteral("<"))    { if (currentTemp >= threshold) return; }
        else if (op == QStringLiteral(">="))   { if (currentTemp < threshold) return; }
        else if (op == QStringLiteral("<="))   { if (currentTemp > threshold) return; }
    }

    if (!hasCondition)
        return;

    QString sceneId = scene.value("scene_id").toString();
    QString sceneName = scene.value("scene_name").toString();
    QString actions = scene.value("actions").toString();
    QString actionDevices = scene.value("action_devices").toString();

    qDebug() << "[场景引擎] 天气触发:" << sceneName;
    executeScene(sceneId, sceneName, actions, actionDevices);
}

bool SceneTriggerEngine::checkSceneEffectiveWindow(const QVariantMap &scene)
{
    // 检查场景是否启用
    if (!scene.value("is_enabled").toBool())
        return false;

    QDateTime now = QDateTime::currentDateTime();

    // 检查生效日期
    QString effectiveDate = scene.value("effective_date").toString();
    if (!effectiveDate.isEmpty())
    {
        QDateTime effective = QDateTime::fromString(effectiveDate, Qt::ISODate);
        if (effective.isValid() && now < effective)
            return false;
    }

    // 检查过期日期
    QString expireDate = scene.value("expire_date").toString();
    if (!expireDate.isEmpty())
    {
        QDateTime expire = QDateTime::fromString(expireDate, Qt::ISODate);
        if (expire.isValid() && now > expire)
            return false;
    }

    return true;
}

void SceneTriggerEngine::refreshSceneCache()
{
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_sceneCacheTimestamp > SceneCacheRefreshMs)
    {
        m_cachedScenes = DatabaseManager::instance()->getAllScenes();
        m_sceneCacheTimestamp = now;
    }
}

void SceneTriggerEngine::executeScene(const QString &sceneId, const QString &sceneName, const QString &actions, const QString &actionDevices)
{
    Q_UNUSED(actions);
    Q_UNUSED(actionDevices);

    if (isInCooldown(sceneId))
    {
        qDebug() << "[场景引擎] 场景" << sceneName << "在冷却期内，跳过执行";
        return;
    }

    qDebug() << "[场景引擎] 执行场景:" << sceneName << "(" << sceneId << ")";

    if (!m_tcpController)
    {
        qWarning() << "[场景引擎] TcpController 未设置，无法发送场景命令";
        recordSceneExecution(sceneId, false, QStringLiteral("TcpController未设置"));
        return;
    }

    if (!m_tcpController->isConnected())
    {
        qWarning() << "[场景引擎] 网关未连接，跳过场景:" << sceneName;
        return;
    }

    m_lastTriggerTime[sceneId] = QDateTime::currentDateTime();

    QString cmdId = "trigger_" + QString::number(QDateTime::currentMSecsSinceEpoch());
    m_tcpController->sendSceneCommand(cmdId, sceneId);

    QString nowStr = QDateTime::currentDateTime().toString(Qt::ISODate);

    emit sceneTriggered(sceneId, sceneName);

    for (int i = 0; i < m_cachedScenes.size(); ++i)
    {
        QVariantMap cached = m_cachedScenes.at(i).toMap();
        if (cached.value("scene_id").toString() == sceneId)
        {
            cached["last_executed_at"] = nowStr;
            m_cachedScenes[i] = cached;
            break;
        }
    }

    recordSceneExecution(sceneId, true, QStringLiteral("场景执行成功"));
    emit sceneExecuted(sceneId, true, QStringLiteral("场景执行成功"));

    qDebug() << "[场景引擎] 场景" << sceneName << "已发送执行命令";
}

bool SceneTriggerEngine::isInCooldown(const QString &sceneId) const
{
    if (!m_lastTriggerTime.contains(sceneId))
        return false;

    qint64 elapsed = m_lastTriggerTime.value(sceneId).secsTo(QDateTime::currentDateTime());
    return elapsed < SceneTriggerCooldownSecs;
}

void SceneTriggerEngine::recordSceneExecution(const QString &sceneId, bool success, const QString &message)
{
    QVariantMap fields;
    fields["last_executed_at"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    fields["scene_status"] = success ? QStringLiteral("success") : QStringLiteral("failed");
    fields["status_message"] = message;

    DatabaseManager *db = DatabaseManager::instance();
    db->updateScene(sceneId, fields);
}
