#include "databasemanager.h"
#include <QDebug>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QSqlRecord>
#include <QDate>
#include <QTime>

DatabaseManager *DatabaseManager::s_instance = nullptr;

DatabaseManager *DatabaseManager::instance()
{
    if (!s_instance)
    {
        s_instance = new DatabaseManager();
    }
    return s_instance;
}

DatabaseManager::DatabaseManager(QObject *parent)
    : QObject(parent)
{
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/MySmartHome";
    QDir().mkpath(dataDir);
    m_dbPath = dataDir + "/database.db";
}

DatabaseManager::~DatabaseManager()
{
    if (m_db.isOpen())
    {
        m_db.close();
    }
    if (s_instance == this)
    {
        s_instance = nullptr;
    }
}

bool DatabaseManager::initialize()
{
    const QString connectionName = QStringLiteral("SmartHomeConnection");

    if (QSqlDatabase::contains(connectionName))
    {
        m_db = QSqlDatabase::database(connectionName);
        if (m_db.isOpen())
        {
            qDebug() << "DatabaseManager: Database already initialized at" << m_dbPath;
            return true;
        }
    }
    else
    {
        m_db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
        m_db.setDatabaseName(m_dbPath);
    }

    if (!m_db.open())
    {
        qCritical() << "DatabaseManager: Failed to open database:" << m_db.lastError().text();
        return false;
    }

    qDebug() << "DatabaseManager: Database opened at" << m_dbPath;

    if (!createTables())
    {
        qCritical() << "DatabaseManager: Failed to create tables";
        return false;
    }

    cleanupOldLogs();

    qDebug() << "DatabaseManager: Database initialized successfully";
    emit databaseOpened();
    return true;
}

bool DatabaseManager::isOpen() const
{
    return m_db.isOpen() && m_db.isValid();
}

bool DatabaseManager::createTables()
{
    QStringList createQueries;

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS devices (
            device_id TEXT PRIMARY KEY,
            device_name TEXT NOT NULL,
            device_type TEXT NOT NULL,
            room TEXT DEFAULT '',
            ip TEXT NOT NULL,
            tcp_port INTEGER DEFAULT 9999,
            firmware_version TEXT,
            is_online INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )";

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS scenes (
            scene_id TEXT PRIMARY KEY,
            scene_name TEXT NOT NULL,
            trigger_type TEXT NOT NULL DEFAULT 'manual',
            trigger_device_id TEXT DEFAULT '',
            trigger_sensor_data TEXT DEFAULT '',
            trigger_time TEXT DEFAULT '',
            actions TEXT NOT NULL,
            action_devices TEXT DEFAULT '[]',
            is_enabled INTEGER DEFAULT 1,
            effective_date TEXT DEFAULT '',
            expire_date TEXT DEFAULT '',
            effective_count INTEGER DEFAULT 0,
            last_executed_at TEXT DEFAULT '',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )";

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS energy_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            power REAL DEFAULT 0,
            temperature REAL DEFAULT 0,
            humidity REAL DEFAULT 0,
            light REAL DEFAULT 0,
            rain REAL DEFAULT 0,
            smoke REAL DEFAULT 0,
            lpg REAL DEFAULT 0,
            air_quality REAL DEFAULT 0,
            pressure REAL DEFAULT 0,
            timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    )";

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS alerts (
            alert_id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            content TEXT NOT NULL,
            level INTEGER NOT NULL,
            alert_type TEXT,
            is_read INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    )";

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS pending_commands (
            command_id TEXT PRIMARY KEY,
            command_data TEXT NOT NULL,
            target_ip TEXT NOT NULL,
            priority INTEGER DEFAULT 1,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )";

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS settings (
            setting_key TEXT PRIMARY KEY,
            setting_value TEXT NOT NULL,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )";

    createQueries << R"(
        CREATE TABLE IF NOT EXISTS connection_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            log_message TEXT NOT NULL,
            log_timestamp TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )";

    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    for (const QString &sql : createQueries)
    {
        QSqlQuery query(db);
        if (!query.exec(sql))
        {
            qCritical() << "DatabaseManager: Failed to create table:" << query.lastError().text();
            return false;
        }
    }

    struct AlterInfo {
        QString table;
        QString column;
    };

    QList<AlterInfo> alterInfos = {
        {"devices",     "room"},
        {"energy_data", "light"},
        {"energy_data", "rain"},
        {"energy_data", "smoke"},
        {"energy_data", "lpg"},
        {"energy_data", "air_quality"},
        {"energy_data", "pressure"},
    };

    for (const auto &info : alterInfos)
    {
        QSqlQuery checkQuery(db);
        checkQuery.prepare("SELECT COUNT(*) FROM pragma_table_info(:table) WHERE name = :column");
        checkQuery.bindValue(":table", info.table);
        checkQuery.bindValue(":column", info.column);

        if (checkQuery.exec() && checkQuery.next() && checkQuery.value(0).toInt() > 0)
            continue;

        QString alterSql = QString("ALTER TABLE %1 ADD COLUMN %2").arg(info.table, info.column);
        if (info.table == "devices")
            alterSql += " TEXT DEFAULT ''";
        else
            alterSql += " REAL DEFAULT 0";

        QSqlQuery alterQuery(db);
        if (alterQuery.exec(alterSql))
            qDebug() << "DatabaseManager: Added column successfully:" << alterSql;
        else
            qWarning() << "DatabaseManager: Failed to add column:" << alterSql << alterQuery.lastError().text();
    }

    return true;
}

bool DatabaseManager::executeQuery(const QString &sql, const QVariantMap &params) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare(sql);

    for (auto it = params.constBegin(); it != params.constEnd(); ++it)
    {
        query.bindValue(":" + it.key(), it.value());
    }

    if (!query.exec())
    {
        qWarning() << "DatabaseManager: Query failed:" << query.lastError().text()
                   << "SQL:" << sql;
        return false;
    }

    return true;
}

bool DatabaseManager::execute(QSqlQuery &query) const
{
    if (!query.exec())
    {
        qWarning() << "DatabaseManager: Query execution failed:" << query.lastError().text();
        return false;
    }
    return true;
}

QVariantMap DatabaseManager::queryToMap(QSqlQuery &query) const
{
    QVariantMap result;
    QSqlRecord record = query.record();
    for (int i = 0; i < record.count(); ++i)
    {
        result.insert(record.fieldName(i), query.value(i));
    }
    return result;
}

QVariantList DatabaseManager::executeQueryToList(const QString &sql, const QVariantMap &params) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare(sql);

    for (auto it = params.constBegin(); it != params.constEnd(); ++it)
    {
        query.bindValue(":" + it.key(), it.value());
    }

    QVariantList result;
    if (query.exec())
    {
        while (query.next())
        {
            result.append(queryToMap(query));
        }
    }
    else
    {
        qWarning() << "DatabaseManager: Query failed:" << query.lastError().text()
                   << "SQL:" << sql;
    }
    return result;
}

// ======================== Device Operations ========================

bool DatabaseManager::addDevice(const QString &deviceId, const QString &deviceName,
                                const QString &deviceType, const QString &ip,
                                int tcpPort, const QString &firmwareVersion)
{
    bool isNew = !deviceExists(deviceId);

    QString sql = R"(
        INSERT OR REPLACE INTO devices (device_id, device_name, device_type, ip, tcp_port, firmware_version, is_online, updated_at)
        VALUES (:device_id, :device_name, :device_type, :ip, :tcp_port, :firmware_version, 1, CURRENT_TIMESTAMP)
    )";

    QVariantMap params;
    params.insert("device_id", deviceId);
    params.insert("device_name", deviceName);
    params.insert("device_type", deviceType);
    params.insert("ip", ip);
    params.insert("tcp_port", tcpPort);
    params.insert("firmware_version", firmwareVersion);

    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap device = getDevice(deviceId);
        if (isNew)
            emit deviceAdded(device);
        else
            emit deviceUpdated(device);
    }
    return success;
}

bool DatabaseManager::updateDevice(const QString &deviceId, const QVariantMap &deviceData)
{
    if (deviceData.isEmpty())
    {
        return false;
    }

    QStringList setClauses;
    QVariantMap params;
    params.insert("device_id", deviceId);

    for (auto it = deviceData.constBegin(); it != deviceData.constEnd(); ++it)
    {
        setClauses.append(it.key() + " = :" + it.key());
        params.insert(it.key(), it.value());
    }

    setClauses.append("updated_at = CURRENT_TIMESTAMP");

    QString sql = "UPDATE devices SET " + setClauses.join(", ") + " WHERE device_id = :device_id";

    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap device = getDevice(deviceId);
        emit deviceUpdated(device);
    }
    return success;
}

bool DatabaseManager::deleteDevice(const QString &deviceId)
{
    QString sql = "DELETE FROM devices WHERE device_id = :device_id";
    QVariantMap params;
    params.insert("device_id", deviceId);

    bool success = executeQuery(sql, params);
    if (success)
    {
        emit deviceDeleted(deviceId);
    }
    return success;
}

QVariantList DatabaseManager::getAllDevices() const
{
    return executeQueryToList("SELECT * FROM devices ORDER BY device_name");
}

QVariantMap DatabaseManager::getDevice(const QString &deviceId) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare("SELECT * FROM devices WHERE device_id = :device_id");
    query.bindValue(":device_id", deviceId);

    if (query.exec() && query.next())
    {
        return queryToMap(query);
    }
    return QVariantMap();
}

bool DatabaseManager::setDeviceOnline(const QString &deviceId, bool online)
{
    QString sql = R"(
        UPDATE devices SET is_online = :is_online, updated_at = CURRENT_TIMESTAMP
        WHERE device_id = :device_id
    )";

    QVariantMap params;
    params.insert("is_online", online ? 1 : 0);
    params.insert("device_id", deviceId);

    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap device = getDevice(deviceId);
        emit deviceUpdated(device);
    }
    return success;
}

void DatabaseManager::setAllDevicesOffline()
{
    QString sql = R"(
        UPDATE devices SET is_online = 0, updated_at = CURRENT_TIMESTAMP
    )";

    executeQuery(sql, QVariantMap());
    qDebug() << "DatabaseManager: All devices set to offline";
}

bool DatabaseManager::deviceExists(const QString &deviceId) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare("SELECT COUNT(*) FROM devices WHERE device_id = :device_id");
    query.bindValue(":device_id", deviceId);
    if (query.exec() && query.next())
        return query.value(0).toInt() > 0;
    return false;
}

bool DatabaseManager::deleteMultipleDevices(const QStringList &deviceIds)
{
    if (deviceIds.isEmpty())
        return true;

    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    db.transaction();

    for (const QString &id : deviceIds)
    {
        QSqlQuery query(db);
        query.prepare("DELETE FROM energy_data WHERE device_id = :id");
        query.bindValue(":id", id);
        query.exec();

        query.prepare("DELETE FROM alerts WHERE device_id = :id");
        query.bindValue(":id", id);
        query.exec();

        query.prepare("DELETE FROM devices WHERE device_id = :id");
        query.bindValue(":id", id);
        if (!query.exec())
        {
            db.rollback();
            qWarning() << "DatabaseManager: Batch delete failed at device:" << id;
            return false;
        }
        emit deviceDeleted(id);
    }

    db.commit();
    qDebug() << "DatabaseManager: Batch deleted" << deviceIds.size() << "devices";
    return true;
}

bool DatabaseManager::deleteAllDevices()
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    db.transaction();

    QSqlQuery query(db);
    query.exec("DELETE FROM energy_data");
    query.exec("DELETE FROM alerts");
    if (!query.exec("DELETE FROM devices"))
    {
        db.rollback();
        qWarning() << "DatabaseManager: Delete all devices failed:" << query.lastError().text();
        return false;
    }

    db.commit();
    qDebug() << "DatabaseManager: All devices deleted";
    return true;
}

QVariantList DatabaseManager::searchDevices(const QString &keyword) const
{
    if (keyword.trimmed().isEmpty())
        return getAllDevices();

    QString sql = R"(
        SELECT * FROM devices
        WHERE device_name LIKE :kw
           OR device_id LIKE :kw
           OR ip LIKE :kw
           OR room LIKE :kw
           OR device_type LIKE :kw
        ORDER BY device_name
    )";
    QVariantMap params;
    params.insert("kw", "%" + keyword + "%");

    return executeQueryToList(sql, params);
}

QVariantList DatabaseManager::filterDevicesByStatus(bool online) const
{
    QString sql = "SELECT * FROM devices WHERE is_online = :status ORDER BY device_name";
    QVariantMap params;
    params.insert("status", online ? 1 : 0);

    return executeQueryToList(sql, params);
}

QVariantList DatabaseManager::filterDevicesByType(const QString &type) const
{
    if (type.isEmpty())
        return getAllDevices();

    QString sql = "SELECT * FROM devices WHERE device_type = :type ORDER BY device_name";
    QVariantMap params;
    params.insert("type", type);

    return executeQueryToList(sql, params);
}

QVariantList DatabaseManager::filterDevicesByRoom(const QString &room) const
{
    if (room.isEmpty())
        return getAllDevices();

    QString sql = "SELECT * FROM devices WHERE room = :room ORDER BY device_name";
    QVariantMap params;
    params.insert("room", room);

    return executeQueryToList(sql, params);
}

// ======================== Scene Operations ========================

bool DatabaseManager::addScene(const QString &sceneId, const QString &sceneName,
                               const QString &triggerType, const QString &triggerDeviceId,
                               const QString &triggerSensorData, const QString &triggerTime,
                               const QString &actions, const QString &actionDevices)
{
    QString sql = R"(
        INSERT OR REPLACE INTO scenes (
            scene_id, scene_name, trigger_type, trigger_device_id,
            trigger_sensor_data, trigger_time, actions, action_devices,
            is_enabled
        )
        VALUES (
            :scene_id, :scene_name, :trigger_type, :trigger_device_id,
            :trigger_sensor_data, :trigger_time, :actions, :action_devices,
            1
        )
    )";

    QVariantMap params;
    params.insert("scene_id", sceneId);
    params.insert("scene_name", sceneName);
    params.insert("trigger_type", triggerType);
    params.insert("trigger_device_id", triggerDeviceId);
    params.insert("trigger_sensor_data", triggerSensorData);
    params.insert("trigger_time", triggerTime);
    params.insert("actions", actions);
    params.insert("action_devices", actionDevices);

    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap scene = getScene(sceneId);
        emit sceneAdded(scene);
    }
    return success;
}

bool DatabaseManager::updateScene(const QString &sceneId, const QVariantMap &sceneData)
{
    if (sceneData.isEmpty())
    {
        return false;
    }

    QStringList setClauses;
    QVariantMap params;
    params.insert("scene_id", sceneId);

    for (auto it = sceneData.constBegin(); it != sceneData.constEnd(); ++it)
    {
        setClauses.append(it.key() + " = :" + it.key());
        params.insert(it.key(), it.value());
    }

    setClauses.append("updated_at = CURRENT_TIMESTAMP");

    QString sql = "UPDATE scenes SET " + setClauses.join(", ") + " WHERE scene_id = :scene_id";

    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap scene = getScene(sceneId);
        emit sceneUpdated(scene);
    }
    return success;
}

bool DatabaseManager::deleteScene(const QString &sceneId)
{
    QString sql = "DELETE FROM scenes WHERE scene_id = :scene_id";
    QVariantMap params;
    params.insert("scene_id", sceneId);

    bool success = executeQuery(sql, params);
    if (success)
    {
        emit sceneDeleted(sceneId);
    }
    return success;
}

QVariantList DatabaseManager::getAllScenes() const
{
    return executeQueryToList("SELECT * FROM scenes ORDER BY scene_name");
}

QVariantMap DatabaseManager::getScene(const QString &sceneId) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare("SELECT * FROM scenes WHERE scene_id = :scene_id");
    query.bindValue(":scene_id", sceneId);

    if (query.exec() && query.next())
    {
        return queryToMap(query);
    }
    return QVariantMap();
}

bool DatabaseManager::enableScene(const QString &sceneId, bool enabled)
{
    QString sql = "UPDATE scenes SET is_enabled = :is_enabled, updated_at = CURRENT_TIMESTAMP WHERE scene_id = :scene_id";

    QVariantMap params;
    params.insert("is_enabled", enabled ? 1 : 0);
    params.insert("scene_id", sceneId);

    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap scene = getScene(sceneId);
        emit sceneUpdated(scene);
    }
    return success;
}

bool DatabaseManager::incrementSceneExecCount(const QString &sceneId)
{
    QString sql = "UPDATE scenes SET effective_count = effective_count + 1, last_executed_at = :now WHERE scene_id = :scene_id";
    QVariantMap params;
    params.insert("now", QDateTime::currentDateTime().toString(Qt::ISODate));
    params.insert("scene_id", sceneId);
    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap scene = getScene(sceneId);
        emit sceneUpdated(scene);
    }
    return success;
}

bool DatabaseManager::updateSceneLastExecuted(const QString &sceneId)
{
    QString sql = "UPDATE scenes SET last_executed_at = :now WHERE scene_id = :scene_id";
    QVariantMap params;
    params.insert("now", QDateTime::currentDateTime().toString(Qt::ISODate));
    params.insert("scene_id", sceneId);
    bool success = executeQuery(sql, params);
    if (success)
    {
        QVariantMap scene = getScene(sceneId);
        emit sceneUpdated(scene);
    }
    return success;
}

// ======================== Energy Data Operations ========================

bool DatabaseManager::addEnergyData(const QString &deviceId, double power,
                                    double temperature, double humidity,
                                    double pressure)
{
    QString sql = R"(
        INSERT INTO energy_data (device_id, power, temperature, humidity, pressure, timestamp)
        VALUES (:device_id, :power, :temperature, :humidity, :pressure, CURRENT_TIMESTAMP)
    )";

    QVariantMap params;
    params.insert("device_id", deviceId);
    params.insert("power", power);
    params.insert("temperature", temperature);
    params.insert("humidity", humidity);
    params.insert("pressure", pressure);

    bool success = executeQuery(sql, params);
    if (success)
    {
        emit energyDataAdded(deviceId, power, QDateTime::currentDateTime());
    }
    return success;
}

bool DatabaseManager::addSensorData(const QString &deviceId,
                                    double temperature, double humidity,
                                    double light, double rain,
                                    double smoke, double lpg,
                                    double air_quality, double pressure)
{
    qDebug() << "DatabaseManager::addSensorData() 开始，deviceId =" << deviceId
             << "temperature =" << temperature
             << "humidity =" << humidity
             << "light =" << light
             << "rain =" << rain
             << "smoke =" << smoke
             << "lpg =" << lpg
             << "air_quality =" << air_quality
             << "pressure =" << pressure;

    QString sql = R"(
        INSERT INTO energy_data (device_id, power, temperature, humidity, light, rain, smoke, lpg, air_quality, pressure, timestamp)
        VALUES (:device_id, :power, :temperature, :humidity, :light, :rain, :smoke, :lpg, :air_quality, :pressure, CURRENT_TIMESTAMP)
    )";

    QVariantMap params;
    params.insert("device_id", deviceId);
    params.insert("power", 0.0);
    params.insert("temperature", temperature);
    params.insert("humidity", humidity);
    params.insert("light", light);
    params.insert("rain", rain);
    params.insert("smoke", smoke);
    params.insert("lpg", lpg);
    params.insert("air_quality", air_quality);
    params.insert("pressure", pressure);

    bool success = executeQuery(sql, params);
    if (success)
    {
        qDebug() << "DatabaseManager::addSensorData() 成功，数据已存入数据库";
        emit energyDataAdded(deviceId, 0, QDateTime::currentDateTime());
    }
    else
    {
        qWarning() << "DatabaseManager::addSensorData() 失败！";
    }
    return success;
}

bool DatabaseManager::updateSensorField(const QString &deviceId, const QString &field, double value)
{
    static const QStringList validSensorFields = {
        QStringLiteral("temperature"), QStringLiteral("humidity"),
        QStringLiteral("light"), QStringLiteral("rain"),
        QStringLiteral("smoke"), QStringLiteral("lpg"),
        QStringLiteral("air_quality"), QStringLiteral("pressure")
    };

    if (!validSensorFields.contains(field))
    {
        qDebug() << "DatabaseManager::updateSensorField: invalid field" << field;
        return false;
    }

    QSqlQuery query;
    static const int mergeWindowSec = 2;

    QString findSql = QStringLiteral(
        "SELECT id FROM energy_data WHERE device_id = :did "
        "AND timestamp >= datetime('now', :window) ORDER BY id DESC LIMIT 1");
    query.prepare(findSql);
    query.bindValue(QStringLiteral(":did"), deviceId);
    query.bindValue(QStringLiteral(":window"), QStringLiteral("-%1 seconds").arg(mergeWindowSec));

    int existingId = -1;
    if (query.exec() && query.next())
    {
        existingId = query.value(0).toInt();
    }

    if (existingId > 0)
    {
        QString updateSql = QStringLiteral("UPDATE energy_data SET %1 = :val WHERE id = :id").arg(field);
        query.prepare(updateSql);
        query.bindValue(QStringLiteral(":val"), value);
        query.bindValue(QStringLiteral(":id"), existingId);
        return execute(query);
    }
    else
    {
        QString insertSql = QStringLiteral("INSERT INTO energy_data (device_id, %1) VALUES (:did, :val)").arg(field);
        query.prepare(insertSql);
        query.bindValue(QStringLiteral(":did"), deviceId);
        query.bindValue(QStringLiteral(":val"), value);
        return execute(query);
    }
}

QVariantList DatabaseManager::getEnergyData(const QString &deviceId,
                                            const QDateTime &startTime,
                                            const QDateTime &endTime) const
{
    QString sql = R"(
        SELECT * FROM energy_data
        WHERE device_id = :device_id
          AND timestamp >= :start_time
          AND timestamp <= :end_time
        ORDER BY timestamp ASC
    )";
    QVariantMap params;
    params.insert("device_id", deviceId);
    params.insert("start_time", startTime.toString("yyyy-MM-dd HH:mm:ss"));
    params.insert("end_time", endTime.toString("yyyy-MM-dd HH:mm:ss"));

    return executeQueryToList(sql, params);
}

double DatabaseManager::getEnergyTotal(const QString &deviceId,
                                       const QDateTime &startTime,
                                       const QDateTime &endTime) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare(R"(
        SELECT SUM(power) FROM energy_data
        WHERE device_id = :device_id
          AND timestamp >= :start_time
          AND timestamp <= :end_time
    )");
    query.bindValue(":device_id", deviceId);
    query.bindValue(":start_time", startTime.toString("yyyy-MM-dd HH:mm:ss"));
    query.bindValue(":end_time", endTime.toString("yyyy-MM-dd HH:mm:ss"));

    if (query.exec() && query.next())
    {
        return query.value(0).toDouble();
    }
    return 0.0;
}

QVariantList DatabaseManager::getAvailableDataDates(const QString &deviceId, int year, int month) const
{
    QVariantList result;
    QDate firstDay(year, month, 1);
    QDateTime startTime(firstDay, QTime(0, 0, 0));
    QDateTime endTime(firstDay.addMonths(1).addDays(-1), QTime(23, 59, 59));

    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare(R"(
        SELECT DISTINCT CAST(strftime('%d', timestamp) AS INTEGER) AS day
        FROM energy_data
        WHERE device_id = :device_id
          AND timestamp >= :start_time
          AND timestamp <= :end_time
        ORDER BY day
    )");
    query.bindValue(":device_id", deviceId);
    query.bindValue(":start_time", startTime.toString("yyyy-MM-dd HH:mm:ss"));
    query.bindValue(":end_time", endTime.toString("yyyy-MM-dd HH:mm:ss"));

    if (query.exec()) {
        while (query.next()) {
            result.append(query.value(0).toInt());
        }
    }
    return result;
}

bool DatabaseManager::deleteEnergyDataOlderThan(const QDateTime &cutoffDate)
{
    QString sql = "DELETE FROM energy_data WHERE timestamp < :cutoff_date";
    QVariantMap params;
    params.insert("cutoff_date", cutoffDate.toString("yyyy-MM-dd HH:mm:ss"));

    return executeQuery(sql, params);
}

// ======================== Alert Operations ========================

bool DatabaseManager::addAlert(const QString &alertId, const QString &deviceId,
                               const QString &content, int level, const QString &alertType)
{
    QString sql = R"(
        INSERT OR REPLACE INTO alerts (alert_id, device_id, content, level, alert_type, is_read, created_at)
        VALUES (:alert_id, :device_id, :content, :level, :alert_type, 0, CURRENT_TIMESTAMP)
    )";

    QVariantMap params;
    params.insert("alert_id", alertId);
    params.insert("device_id", deviceId);
    params.insert("content", content);
    params.insert("level", level);
    params.insert("alert_type", alertType);

    bool success = executeQuery(sql, params);
    if (success)
    {
        QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
        QSqlQuery query(db);
        query.prepare("SELECT * FROM alerts WHERE alert_id = :alert_id");
        query.bindValue(":alert_id", alertId);
        if (query.exec() && query.next())
        {
            emit alertAdded(queryToMap(query));
        }
    }
    return success;
}

bool DatabaseManager::updateAlert(const QString &alertId, const QVariantMap &alertData)
{
    if (alertData.isEmpty())
    {
        return false;
    }

    QStringList setClauses;
    QVariantMap params;
    params.insert("alert_id", alertId);

    for (auto it = alertData.constBegin(); it != alertData.constEnd(); ++it)
    {
        setClauses.append(it.key() + " = :" + it.key());
        params.insert(it.key(), it.value());
    }

    QString sql = "UPDATE alerts SET " + setClauses.join(", ") + " WHERE alert_id = :alert_id";

    bool success = executeQuery(sql, params);
    if (success)
    {
        QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
        QSqlQuery query(db);
        query.prepare("SELECT * FROM alerts WHERE alert_id = :alert_id");
        query.bindValue(":alert_id", alertId);
        if (query.exec() && query.next())
        {
            emit alertUpdated(queryToMap(query));
        }
    }
    return success;
}

bool DatabaseManager::deleteAlert(const QString &alertId)
{
    QString sql = "DELETE FROM alerts WHERE alert_id = :alert_id";
    QVariantMap params;
    params.insert("alert_id", alertId);

    bool success = executeQuery(sql, params);
    if (success)
    {
        emit alertDeleted(alertId);
    }
    return success;
}

bool DatabaseManager::deleteAllAlerts()
{
    bool success = executeQuery("DELETE FROM alerts");
    if (success)
    {
        // 发射信号通知所有告警已删除
        QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
        QSqlQuery query(db);
        query.prepare("SELECT alert_id FROM alerts");
        // 表已清空, 只需要通知模型刷新
    }
    return success;
}

QVariantList DatabaseManager::getAllAlerts(int limit) const
{
    QString sql = "SELECT * FROM alerts ORDER BY created_at DESC LIMIT :limit";
    QVariantMap params;
    params.insert("limit", limit);

    return executeQueryToList(sql, params);
}

QVariantList DatabaseManager::getUnreadAlerts() const
{
    return executeQueryToList("SELECT * FROM alerts WHERE is_read = 0 ORDER BY created_at DESC");
}

bool DatabaseManager::markAlertAsRead(const QString &alertId)
{
    QString sql = "UPDATE alerts SET is_read = 1 WHERE alert_id = :alert_id";
    QVariantMap params;
    params.insert("alert_id", alertId);

    bool success = executeQuery(sql, params);
    if (success)
    {
        QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
        QSqlQuery query(db);
        query.prepare("SELECT * FROM alerts WHERE alert_id = :alert_id");
        query.bindValue(":alert_id", alertId);
        if (query.exec() && query.next())
        {
            emit alertUpdated(queryToMap(query));
        }
    }
    return success;
}

// ======================== Pending Command Operations ========================

bool DatabaseManager::addPendingCommand(const QString &commandId, const QString &commandData,
                                        const QString &targetIp, int priority)
{
    QString sql = R"(
        INSERT OR REPLACE INTO pending_commands (command_id, command_data, target_ip, priority, created_at)
        VALUES (:command_id, :command_data, :target_ip, :priority, CURRENT_TIMESTAMP)
    )";

    QVariantMap params;
    params.insert("command_id", commandId);
    params.insert("command_data", commandData);
    params.insert("target_ip", targetIp);
    params.insert("priority", priority);

    return executeQuery(sql, params);
}

bool DatabaseManager::deletePendingCommand(const QString &commandId)
{
    QString sql = "DELETE FROM pending_commands WHERE command_id = :command_id";
    QVariantMap params;
    params.insert("command_id", commandId);

    return executeQuery(sql, params);
}

QVariantList DatabaseManager::getAllPendingCommands() const
{
    return executeQueryToList("SELECT * FROM pending_commands ORDER BY priority ASC, created_at ASC");
}

int DatabaseManager::getPendingCommandCount() const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare("SELECT COUNT(*) FROM pending_commands");

    if (query.exec() && query.next())
    {
        return query.value(0).toInt();
    }
    return 0;
}

// ======================== Statistics ========================

int DatabaseManager::getDeviceCount() const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare("SELECT COUNT(*) FROM devices");

    if (query.exec() && query.next())
    {
        return query.value(0).toInt();
    }
    return 0;
}

int DatabaseManager::getAlertCount(bool unreadOnly) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    if (unreadOnly)
    {
        query.prepare("SELECT COUNT(*) FROM alerts WHERE is_read = 0");
    }
    else
    {
        query.prepare("SELECT COUNT(*) FROM alerts");
    }

    if (query.exec() && query.next())
    {
        return query.value(0).toInt();
    }
    return 0;
}

// ======================== Settings Operations ========================

bool DatabaseManager::saveSetting(const QString &key, const QString &value)
{
    QString sql = R"(
        INSERT INTO settings (setting_key, setting_value, updated_at)
        VALUES (:key, :value, CURRENT_TIMESTAMP)
        ON CONFLICT(setting_key) DO UPDATE SET
            setting_value = excluded.setting_value,
            updated_at = CURRENT_TIMESTAMP
    )";

    QVariantMap params;
    params.insert("key", key);
    params.insert("value", value);

    return executeQuery(sql, params);
}

QString DatabaseManager::loadSetting(const QString &key, const QString &defaultValue) const
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    query.prepare("SELECT setting_value FROM settings WHERE setting_key = :key");
    query.bindValue(":key", key);

    if (query.exec() && query.next())
    {
        return query.value(0).toString();
    }
    return defaultValue;
}

// ======================== Connection Logs Operations ========================

bool DatabaseManager::addConnectionLog(const QString &logMessage)
{
    QString sql = R"(
        INSERT INTO connection_logs (log_message, log_timestamp)
        VALUES (:message, CURRENT_TIMESTAMP)
    )";

    QVariantMap params;
    params.insert("message", logMessage);

    return executeQuery(sql, params);
}

QVariantList DatabaseManager::getConnectionLogs(int limit) const
{
    QString sql = R"(
        SELECT id, log_message, log_timestamp FROM connection_logs
        ORDER BY log_timestamp DESC
        LIMIT :limit
    )";
    QVariantMap params;
    params.insert("limit", limit);

    return executeQueryToList(sql, params);
}

void DatabaseManager::cleanupOldLogs(int retentionDays, int maxEntries)
{
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    if (!db.isOpen())
    {
        qWarning() << "DatabaseManager::cleanupOldLogs: Database not open";
        return;
    }

    QDateTime cutoffDate = QDateTime::currentDateTime().addDays(-retentionDays);
    QSqlQuery deleteOldQuery(db);
    deleteOldQuery.prepare("DELETE FROM connection_logs WHERE log_timestamp < :cutoff");
    deleteOldQuery.bindValue(":cutoff", cutoffDate.toString(Qt::ISODate));
    if (deleteOldQuery.exec())
        qDebug() << "DatabaseManager: Cleaned logs older than" << cutoffDate.toString(Qt::ISODate);

    QSqlQuery countQuery(db);
    if (countQuery.exec("SELECT COUNT(*) FROM connection_logs") && countQuery.next())
    {
        int total = countQuery.value(0).toInt();
        if (total > maxEntries)
        {
            QSqlQuery deleteExcessQuery(db);
            deleteExcessQuery.prepare(
                "DELETE FROM connection_logs WHERE id IN ("
                "SELECT id FROM connection_logs ORDER BY log_timestamp ASC LIMIT :excess"
                ")");
            deleteExcessQuery.bindValue(":excess", total - maxEntries);
            if (deleteExcessQuery.exec())
                qDebug() << "DatabaseManager: Trimmed" << (total - maxEntries) << "excess logs";
        }
    }
}

bool DatabaseManager::clearConnectionLogs()
{
    return executeQuery("DELETE FROM connection_logs");
}
