#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QList>
#include <QString>
#include <QMap>
#include <QDateTime>

class TcpController;

class SceneTriggerEngine : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ isRunning NOTIFY runningChanged)

public:
    static SceneTriggerEngine *instance();

    bool isRunning() const { return m_running; }
    void setTcpController(TcpController *tcp) { m_tcpController = tcp; }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();

    // 外部调用：传感器数据到达时触发检查
    Q_INVOKABLE void onSensorDataReceived(const QString &deviceId, const QVariantMap &sensorData);

    // 外部调用：单字段传感器更新
    Q_INVOKABLE void onSensorFieldUpdated(const QString &deviceId, const QString &field, double value);

    // 外部调用：设备状态变化时触发检查
    Q_INVOKABLE void onDeviceStateChanged(const QString &deviceId, const QString &action);

    // 外部调用：天气数据更新时触发检查
    Q_INVOKABLE void onWeatherUpdated(const QVariantMap &weatherData);

    // 手动触发指定场景
    Q_INVOKABLE void triggerScene(const QString &sceneId);

signals:
    void runningChanged(bool running);
    void sceneTriggered(const QString &sceneId, const QString &sceneName);
    void sceneExecuted(const QString &sceneId, bool success, const QString &message);

private slots:
    void checkTimeTriggers();

private:
    explicit SceneTriggerEngine(QObject *parent = nullptr);
    ~SceneTriggerEngine() override;

    void evaluateAllScenes();
    void evaluateTimeScene(const QVariantMap &scene);
    void evaluateSensorScene(const QVariantMap &scene, const QString &deviceId, const QVariantMap &sensorData);
    void evaluateDeviceScene(const QVariantMap &scene, const QString &deviceId, const QString &action);
    void evaluateWeatherScene(const QVariantMap &scene, const QVariantMap &weatherData);
    bool checkSceneEffectiveWindow(const QVariantMap &scene);
    void executeScene(const QString &sceneId, const QString &sceneName, const QString &actions, const QString &actionDevices);
    void recordSceneExecution(const QString &sceneId, bool success, const QString &message);
    bool isInCooldown(const QString &sceneId) const;
    void refreshSceneCache();

    QTimer *m_timer;
    bool m_running;
    QVariantMap m_lastWeatherData;
    TcpController *m_tcpController;
    QMap<QString, QDateTime> m_lastTriggerTime;
    QVariantList m_cachedScenes;
    qint64 m_sceneCacheTimestamp;

    static constexpr int SceneTriggerCooldownSecs = 30;
    static constexpr int SceneCacheRefreshMs = 5000;

    static SceneTriggerEngine *s_instance;
};
