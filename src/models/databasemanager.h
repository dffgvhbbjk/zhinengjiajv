#pragma once

#include <QObject>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QVariantMap>
#include <QVariantList>
#include <QDateTime>
#include <QDir>

class DatabaseManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString databasePath READ databasePath NOTIFY databaseOpened)
    Q_PROPERTY(bool open READ isOpen NOTIFY databaseOpened)

public:
    static DatabaseManager *instance();

    explicit DatabaseManager(QObject *parent = nullptr);
    ~DatabaseManager() override;

    Q_INVOKABLE bool initialize();
    Q_INVOKABLE QString databasePath() const { return m_dbPath; }
    Q_INVOKABLE bool isOpen() const;

    Q_INVOKABLE bool addDevice(const QString &deviceId, const QString &deviceName,
                               const QString &deviceType, const QString &ip,
                               int tcpPort, const QString &firmwareVersion);
    Q_INVOKABLE bool updateDevice(const QString &deviceId, const QVariantMap &deviceData);
    Q_INVOKABLE bool deleteDevice(const QString &deviceId);
    Q_INVOKABLE bool deleteMultipleDevices(const QStringList &deviceIds);
    Q_INVOKABLE bool deleteAllDevices();
    Q_INVOKABLE QVariantList getAllDevices() const;
    Q_INVOKABLE QVariantMap getDevice(const QString &deviceId) const;
    Q_INVOKABLE bool setDeviceOnline(const QString &deviceId, bool online);
    Q_INVOKABLE void setAllDevicesOffline();
    Q_INVOKABLE QVariantList searchDevices(const QString &keyword) const;
    Q_INVOKABLE QVariantList filterDevicesByStatus(bool online) const;
    Q_INVOKABLE QVariantList filterDevicesByType(const QString &type) const;
    Q_INVOKABLE QVariantList filterDevicesByRoom(const QString &room) const;

    Q_INVOKABLE bool addScene(const QString &sceneId, const QString &sceneName,
                              const QString &triggerType, const QString &triggerDeviceId,
                              const QString &triggerSensorData, const QString &triggerTime,
                              const QString &actions, const QString &actionDevices);
    Q_INVOKABLE bool updateScene(const QString &sceneId, const QVariantMap &sceneData);
    Q_INVOKABLE bool deleteScene(const QString &sceneId);
    Q_INVOKABLE QVariantList getAllScenes() const;
    Q_INVOKABLE QVariantMap getScene(const QString &sceneId) const;
    Q_INVOKABLE bool enableScene(const QString &sceneId, bool enabled);
    Q_INVOKABLE bool incrementSceneExecCount(const QString &sceneId);
    Q_INVOKABLE bool updateSceneLastExecuted(const QString &sceneId);

    Q_INVOKABLE bool addEnergyData(const QString &deviceId, double power,
                                   double temperature = 0, double humidity = 0,
                                   double pressure = 0);
    Q_INVOKABLE bool addSensorData(const QString &deviceId,
                                   double temperature = 0, double humidity = 0,
                                   double light = 0, double rain = 0,
                                   double smoke = 0, double lpg = 0,
                                   double air_quality = 0, double pressure = 0);

    Q_INVOKABLE bool updateSensorField(const QString &deviceId, const QString &field, double value);
    Q_INVOKABLE QVariantList getEnergyData(const QString &deviceId,
                                           const QDateTime &startTime,
                                           const QDateTime &endTime) const;
    Q_INVOKABLE double getEnergyTotal(const QString &deviceId,
                                      const QDateTime &startTime,
                                      const QDateTime &endTime) const;
    Q_INVOKABLE QVariantList getAvailableDataDates(const QString &deviceId, int year, int month) const;
    Q_INVOKABLE bool deleteEnergyDataOlderThan(const QDateTime &cutoffDate);

    Q_INVOKABLE bool addAlert(const QString &alertId, const QString &deviceId,
                              const QString &content, int level, const QString &alertType = QString());
    Q_INVOKABLE bool updateAlert(const QString &alertId, const QVariantMap &alertData);
    Q_INVOKABLE bool deleteAlert(const QString &alertId);
    Q_INVOKABLE bool deleteAllAlerts();
    Q_INVOKABLE QVariantList getAllAlerts(int limit = 100) const;
    Q_INVOKABLE QVariantList getUnreadAlerts() const;
    Q_INVOKABLE bool markAlertAsRead(const QString &alertId);

    Q_INVOKABLE bool addPendingCommand(const QString &commandId, const QString &commandData,
                                       const QString &targetIp, int priority = 1);
    Q_INVOKABLE bool deletePendingCommand(const QString &commandId);
    Q_INVOKABLE QVariantList getAllPendingCommands() const;
    Q_INVOKABLE int getPendingCommandCount() const;

    Q_INVOKABLE int getDeviceCount() const;
    Q_INVOKABLE int getAlertCount(bool unreadOnly = false) const;

    Q_INVOKABLE bool saveSetting(const QString &key, const QString &value);
    Q_INVOKABLE QString loadSetting(const QString &key, const QString &defaultValue = QString()) const;
    Q_INVOKABLE bool addConnectionLog(const QString &logMessage);
    Q_INVOKABLE QVariantList getConnectionLogs(int limit = 100) const;
    Q_INVOKABLE bool clearConnectionLogs();
    Q_INVOKABLE void cleanupOldLogs(int retentionDays = 7, int maxEntries = 10000);

signals:
    void databaseOpened();
    void deviceAdded(const QVariantMap &device);
    void deviceUpdated(const QVariantMap &device);
    void deviceDeleted(const QString &deviceId);

    void sceneAdded(const QVariantMap &scene);
    void sceneUpdated(const QVariantMap &scene);
    void sceneDeleted(const QString &sceneId);

    void energyDataAdded(const QString &deviceId, double power, const QDateTime &timestamp);

    void alertAdded(const QVariantMap &alert);
    void alertUpdated(const QVariantMap &alert);
    void alertDeleted(const QString &alertId);

private:
    bool createTables();
    bool executeQuery(const QString &sql, const QVariantMap &params = QVariantMap()) const;
    bool execute(QSqlQuery &query) const;
    QVariantMap queryToMap(QSqlQuery &query) const;
    QVariantList executeQueryToList(const QString &sql, const QVariantMap &params = QVariantMap()) const;
    bool deviceExists(const QString &deviceId) const;
    QString m_dbPath;
    QSqlDatabase m_db;

    static DatabaseManager *s_instance;
};
