#include "udpdiscoverer.h"
#include "../utils/jsonutils.h"
#include "../models/databasemanager.h"
#include <QSqlQuery>
#include <QSqlError>
#include "../utils/md5utils.h"
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QAbstractSocket>

UdpDiscoverer::UdpDiscoverer(QObject *parent)
    : QObject(parent), m_udpSocket(nullptr), m_offlineCheckTimer(nullptr), m_networkCheckTimer(nullptr), m_running(false)
{
    m_udpSocket = new QUdpSocket(this);
    m_offlineCheckTimer = new QTimer(this);
    m_offlineCheckTimer->setInterval(OfflineCheckIntervalMs);
    connect(m_offlineCheckTimer, &QTimer::timeout, this, &UdpDiscoverer::checkDeviceTimeouts);

    m_networkCheckTimer = new QTimer(this);
    m_networkCheckTimer->setInterval(NetworkCheckIntervalMs);
    connect(m_networkCheckTimer, &QTimer::timeout, this, &UdpDiscoverer::checkNetworkChange);

    connect(m_udpSocket, &QUdpSocket::readyRead, this, &UdpDiscoverer::onReadyRead);
    connect(m_udpSocket, &QUdpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError error)
            {
        if (error != QAbstractSocket::SocketError::SocketTimeoutError) {
            emit errorOccurred(UdpNetworkError, m_udpSocket->errorString());
        } });

    m_lastKnownAddresses = QNetworkInterface::allAddresses();
}

UdpDiscoverer::~UdpDiscoverer()
{
    stopDiscovery();
}

void UdpDiscoverer::startDiscovery()
{
    if (m_running)
    {
        qDebug() << "UdpDiscoverer: Already running, ignoring start request";
        return;
    }

    qDebug() << "UdpDiscoverer: Starting device discovery on port" << UdpPort;

    if (!bindUdpSocket())
    {
        qDebug() << "UdpDiscoverer: Failed to bind UDP socket";
        return;
    }

    m_running = true;
    m_offlineCheckTimer->start();
    m_networkCheckTimer->start();
    emit discoveryStarted();
    qDebug() << "UdpDiscoverer: Discovery started successfully";
}

void UdpDiscoverer::stopDiscovery()
{
    if (!m_running)
        return;

    qDebug() << "UdpDiscoverer: Stopping discovery";

    m_offlineCheckTimer->stop();
    m_networkCheckTimer->stop();
    m_udpSocket->close();
    m_running = false;
    m_deviceLastSeen.clear();

    emit discoveryStopped();
    qDebug() << "UdpDiscoverer: Discovery stopped";
}

void UdpDiscoverer::requestDataRefresh(const QString &ip)
{
    if (!m_running)
    {
        qDebug() << "UdpDiscoverer: Not running, cannot send refresh request";
        return;
    }

    QJsonObject requestObj;
    requestObj.insert(QStringLiteral("type"), QStringLiteral("data_refresh_request"));
    requestObj.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());

    QByteArray data = QJsonDocument(requestObj).toJson(QJsonDocument::Compact);

    qint64 bytesWritten = m_udpSocket->writeDatagram(data, QHostAddress(ip), UdpPort);
    if (bytesWritten > 0)
    {
        qDebug() << "UdpDiscoverer: Sent refresh request to" << ip;
    }
    else
    {
        emit errorOccurred(UdpNetworkError, QStringLiteral("Failed to send refresh request: ") + m_udpSocket->errorString());
    }
}

bool UdpDiscoverer::bindUdpSocket()
{
    m_udpSocket->close();

    if (!m_udpSocket->bind(QHostAddress::AnyIPv4, UdpPort, QAbstractSocket::ShareAddress))
    {
        QString errorMsg = QStringLiteral("Failed to bind UDP port %1: %2").arg(UdpPort).arg(m_udpSocket->errorString());
        emit errorOccurred(UdpBindFailed, errorMsg);
        return false;
    }

    qDebug() << "UdpDiscoverer: Successfully bound to port" << UdpPort;
    return true;
}

void UdpDiscoverer::onReadyRead()
{
    while (m_udpSocket->hasPendingDatagrams())
    {
        QByteArray datagram;
        datagram.resize(m_udpSocket->pendingDatagramSize());
        QHostAddress senderIp;
        quint16 senderPort;

        qint64 receivedBytes = m_udpSocket->readDatagram(datagram.data(), datagram.size(), &senderIp, &senderPort);
        if (receivedBytes > 0)
        {
            processIncomingData(datagram, senderIp);
        }
    }
}

void UdpDiscoverer::processIncomingData(const QByteArray &data, const QHostAddress &senderIp)
{
    QJsonParseError parseError;
    QJsonDocument jsonDoc = QJsonDocument::fromJson(data, &parseError);

    if (parseError.error != QJsonParseError::NoError)
    {
        qDebug() << "UdpDiscoverer: Invalid JSON received from" << senderIp.toString()
                 << "-" << parseError.errorString();
        return;
    }

    if (!jsonDoc.isObject())
    {
        qDebug() << "UdpDiscoverer: Expected JSON object from" << senderIp.toString();
        return;
    }

    QJsonObject jsonObj = jsonDoc.object();
    QString msgType = JsonUtils::extractMessageType(jsonObj);

    if (msgType.isEmpty())
    {
        qDebug() << "UdpDiscoverer: Missing 'type' field from" << senderIp.toString();
        return;
    }

    if (msgType == QStringLiteral("device_discovery"))
    {
        handleDiscoveryPacket(jsonObj, senderIp);
    }
    else if (msgType == QStringLiteral("sensor_data"))
        {
            handleSensorDataPacket(jsonObj);
        }
        else if (msgType == QStringLiteral("sensor_update"))
        {
            handleSensorUpdatePacket(jsonObj);
        }
    else if (msgType == QStringLiteral("discovery_request") || msgType == QStringLiteral("discovery_response"))
    {
        // NetworkManager 的扫描请求/响应，忽略
    }
    else
    {
        qDebug() << "UdpDiscoverer: Unknown message type:" << msgType;
    }
}

bool UdpDiscoverer::handleDiscoveryPacket(const QJsonObject &jsonObj, const QHostAddress &senderIp)
{
    if (!validateMd5Checksum(jsonObj))
    {
        qDebug() << "UdpDiscoverer: MD5 checksum validation failed for discovery packet";
        return false;
    }

    QString deviceId = JsonUtils::getValue(jsonObj, QStringLiteral("device_id"));
    QString deviceName = JsonUtils::getValue(jsonObj, QStringLiteral("device_name"));
    QString deviceType = JsonUtils::getValue(jsonObj, QStringLiteral("device_type"));
    int tcpPort = JsonUtils::getIntValue(jsonObj, QStringLiteral("tcp_port"), 9999);
    QString firmwareVersion = JsonUtils::getValue(jsonObj, QStringLiteral("firmware_version"));

    if (deviceId.isEmpty())
    {
        qDebug() << "UdpDiscoverer: Received discovery packet without device_id";
        return false;
    }

    bool isNewDevice = !m_deviceLastSeen.contains(deviceId);

    updateDeviceLastSeen(deviceId);

    if (isNewDevice)
    {
        qDebug() << "UdpDiscoverer: New device discovered -" << deviceId << "(" << deviceName << ")";
        emit deviceDiscovered(deviceId, deviceName, deviceType,
                              senderIp.toString(), tcpPort, firmwareVersion);
    }
    else
    {
        qDebug() << "UdpDiscoverer: Device heartbeat -" << deviceId;
        DatabaseManager::instance()->setDeviceOnline(deviceId, true);
    }

    return true;
}

bool UdpDiscoverer::handleSensorDataPacket(const QJsonObject &jsonObj)
{
    if (!validateMd5Checksum(jsonObj))
    {
        qDebug() << "UdpDiscoverer: MD5 checksum validation failed for sensor data packet";
        return false;
    }

    QString deviceId = JsonUtils::extractDeviceId(jsonObj);
    if (deviceId.isEmpty())
    {
        qDebug() << "UdpDiscoverer: Received sensor data without device_id";
        return false;
    }

    double temp = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("temperature"), 0.0);
    double humi = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("humidity"), 0.0);
    double light = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("light"), 0.0);
    double rain = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("rain"), 0.0);
    double smoke = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("smoke"), 0.0);
    double lpg = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("lpg"), 0.0);
    double airQuality = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("air_quality"), 0.0);
    double pressure = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("pressure"), 0.0);

    qDebug().noquote() << "UdpDiscoverer: Sensor data -" << deviceId
                       << "temp:" << temp << "C humi:" << humi << "%"
                       << "light:" << light << "rain:" << rain
                       << "smoke:" << smoke << "lpg:" << lpg
                       << "aqi:" << airQuality << "press:" << pressure;

    updateDeviceLastSeen(deviceId);
    DatabaseManager::instance()->setDeviceOnline(deviceId, true);

    QVariantMap dataMap = JsonUtils::toVariantMap(jsonObj);
    emit dataReceived(deviceId, dataMap);


    return true;
}

bool UdpDiscoverer::handleSensorUpdatePacket(const QJsonObject &jsonObj)
{
    if (!validateMd5Checksum(jsonObj))
    {
        qDebug() << "UdpDiscoverer: MD5 checksum validation failed for sensor update packet";
        return false;
    }

    QString deviceId = JsonUtils::extractDeviceId(jsonObj);
    QString field = JsonUtils::getValue(jsonObj, QStringLiteral("field"));
    double value = JsonUtils::getDoubleValue(jsonObj, QStringLiteral("value"), 0.0);
    qint64 version = JsonUtils::getIntValue(jsonObj, QStringLiteral("version"), 0);

    if (deviceId.isEmpty() || field.isEmpty())
    {
        qDebug() << "UdpDiscoverer: Invalid sensor update packet - missing deviceId or field";
        return false;
    }

    updateDeviceLastSeen(deviceId);
    DatabaseManager::instance()->setDeviceOnline(deviceId, true);

    emit sensorFieldUpdated(deviceId, field, value, version);
    return true;
}

void UdpDiscoverer::updateDeviceLastSeen(const QString &deviceId)
{
    m_deviceLastSeen[deviceId] = QDateTime::currentDateTime();
}

bool UdpDiscoverer::validateMd5Checksum(const QJsonObject &jsonObj)
{
    if (!jsonObj.contains(QStringLiteral("checksum")))
    {
        qDebug() << "UdpDiscoverer: No checksum field, skipping validation";
        return true;
    }

    QString providedChecksum = JsonUtils::getValue(jsonObj, QStringLiteral("checksum"));

    QJsonObject checkObj = jsonObj;
    checkObj.remove(QStringLiteral("checksum"));

    QJsonObject normalizedObj;
    for (auto it = checkObj.constBegin(); it != checkObj.constEnd(); ++it)
    {
        QJsonValue val = it.value();
        if (val.isDouble())
        {
            double d = val.toDouble();
            if (qIsFinite(d) && !qIsNaN(d) && d == static_cast<double>(static_cast<qint64>(d)))
            {
                normalizedObj.insert(it.key(), static_cast<qint64>(d));
            }
            else
            {
                normalizedObj.insert(it.key(), val);
            }
        }
        else
        {
            normalizedObj.insert(it.key(), val);
        }
    }

    QString dataStr = QJsonDocument(normalizedObj).toJson(QJsonDocument::Compact);
    QString calculatedChecksum = Md5Utils::computeMd5(dataStr);

    bool isValid = providedChecksum.compare(calculatedChecksum, Qt::CaseInsensitive) == 0;

    if (!isValid)
    {
        qDebug().noquote() << "UdpDiscoverer: MD5 mismatch - provided:" << providedChecksum << "calculated:" << calculatedChecksum;
        qDebug().noquote() << "UdpDiscoverer: JSON used for checksum:" << dataStr;
    }

    return isValid;
}

void UdpDiscoverer::checkDeviceTimeouts()
{
    QDateTime now = QDateTime::currentDateTime();
    QStringList offlineDevices;

    for (auto it = m_deviceLastSeen.constBegin(); it != m_deviceLastSeen.constEnd(); ++it)
    {
        if (it.value().secsTo(now) >= OfflineTimeoutSeconds)
        {
            offlineDevices.append(it.key());
        }
    }

    for (const QString &deviceId : offlineDevices)
    {
        qDebug() << "UdpDiscoverer: Device offline -" << deviceId;
        emit deviceOffline(deviceId);
        m_deviceLastSeen.remove(deviceId);
    }
}

void UdpDiscoverer::checkNetworkChange()
{
    QList<QHostAddress> currentAddresses = QNetworkInterface::allAddresses();

    bool hasChanged = (currentAddresses.size() != m_lastKnownAddresses.size());
    if (!hasChanged)
    {
        for (const QHostAddress &addr : currentAddresses)
        {
            if (!m_lastKnownAddresses.contains(addr))
            {
                hasChanged = true;
                break;
            }
        }
    }

    if (hasChanged && m_running)
    {
        qDebug() << "UdpDiscoverer: Network change detected, restarting...";
        restartOnNetworkChange();
        m_lastKnownAddresses = currentAddresses;
    }
}

void UdpDiscoverer::restartOnNetworkChange()
{
    qDebug() << "UdpDiscoverer: Restarting UDP socket due to network change";
    m_udpSocket->close();

    if (!bindUdpSocket())
    {
        emit errorOccurred(UdpBindFailed, QStringLiteral("Failed to rebind after network change"));
        return;
    }

    qDebug() << "UdpDiscoverer: Successfully restarted after network change";
}

void UdpDiscoverer::loadKnownDevicesFromDatabase()
{
    m_deviceLastSeen.clear();
    QSqlDatabase db = QSqlDatabase::database("SmartHomeConnection");
    QSqlQuery query(db);
    if (query.exec("SELECT device_id FROM devices")) {
        while (query.next()) {
            QString deviceId = query.value(0).toString();
            if (!deviceId.isEmpty()) {
                m_deviceLastSeen[deviceId] = QDateTime::currentDateTime();
            }
        }
        qDebug() << "UdpDiscoverer: Loaded" << m_deviceLastSeen.size() << "known devices from database";
    } else {
        qDebug() << "UdpDiscoverer: Failed to load known devices:" << query.lastError().text();
    }
}
