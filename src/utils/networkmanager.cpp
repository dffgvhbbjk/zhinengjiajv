#include "networkmanager.h"
#include <QDebug>
#include <QJsonArray>

NetworkManager::NetworkManager(QObject *parent)
    : QObject(parent), m_scanSocket(nullptr), m_scanTimer(nullptr), m_scanTimeoutTimer(nullptr),
      m_isScanning(false), m_scanUdpPort(8888), m_scanRetryCount(0)
{
    m_scanSocket = new QUdpSocket(this);

    m_scanTimer = new QTimer(this);
    m_scanTimer->setSingleShot(false);

    m_scanTimeoutTimer = new QTimer(this);
    m_scanTimeoutTimer->setSingleShot(true);
    m_scanTimeoutTimer->setInterval(ScanTimeoutMs);

    connect(m_scanTimer, &QTimer::timeout, this, &NetworkManager::sendDiscoveryBroadcast);
    connect(m_scanTimeoutTimer, &QTimer::timeout, this, &NetworkManager::scanTimeout);

    collectLocalInterfaces();
}

NetworkManager::~NetworkManager()
{
    stopDeviceDiscovery();
}

void NetworkManager::refreshLocalInterfaces()
{
    collectLocalInterfaces();
}

void NetworkManager::startDeviceDiscovery(int udpPort)
{
    if (m_isScanning)
    {
        stopDeviceDiscovery();
    }

    m_scanUdpPort = udpPort;
    m_scanRetryCount = 0;
    m_discoveredDevices.clear();
    emit discoveredDevicesChanged();

    const int responsePort = 8889;
    if (!m_scanSocket->bind(QHostAddress::AnyIPv4, responsePort, QUdpSocket::ShareAddress))
    {
        qWarning() << "NetworkManager: Failed to bind scan response port" << responsePort;
        return;
    }

    connect(m_scanSocket, &QUdpSocket::readyRead, this, &NetworkManager::onReadyRead);

    m_isScanning = true;
    emit scanningChanged();

    sendDiscoveryBroadcast();
    m_scanTimer->start(ScanRetryIntervalMs);
    m_scanTimeoutTimer->start();

    qDebug() << "NetworkManager: Started device discovery, listening on port" << responsePort;
}

void NetworkManager::stopDeviceDiscovery()
{
    m_isScanning = false;
    emit scanningChanged();

    m_scanTimer->stop();
    m_scanTimeoutTimer->stop();

    disconnect(m_scanSocket, &QUdpSocket::readyRead, this, &NetworkManager::onReadyRead);
    m_scanSocket->close();

    qDebug() << "NetworkManager: Stopped device discovery";
}

void NetworkManager::clearDiscoveredDevices()
{
    m_discoveredDevices.clear();
    emit discoveredDevicesChanged();
}

void NetworkManager::onReadyRead()
{
    while (m_scanSocket->hasPendingDatagrams())
    {
        QByteArray data;
        QHostAddress sender;
        quint16 senderPort;

        data.resize(m_scanSocket->pendingDatagramSize());
        m_scanSocket->readDatagram(data.data(), data.size(), &sender, &senderPort);

        processDiscoveryResponse(data, sender);
    }
}

void NetworkManager::scanTimeout()
{
    if (m_scanRetryCount < MaxScanRetries)
    {
        m_scanRetryCount++;
        sendDiscoveryBroadcast();
        m_scanTimeoutTimer->start();
    }
    else
    {
        stopDeviceDiscovery();
    }
}

void NetworkManager::collectLocalInterfaces()
{
    m_localInterfaces.clear();

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces)
    {
        if (!(iface.flags() & QNetworkInterface::IsUp) ||
            !(iface.flags() & QNetworkInterface::IsRunning) ||
            iface.flags() & QNetworkInterface::IsLoopBack)
        {
            continue;
        }

        const QList<QNetworkAddressEntry> entries = iface.addressEntries();
        for (const QNetworkAddressEntry &entry : entries)
        {
            if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol)
            {
                QVariantMap ifaceData;
                ifaceData[QStringLiteral("name")] = iface.humanReadableName();
                ifaceData[QStringLiteral("ip")] = entry.ip().toString();
                ifaceData[QStringLiteral("netmask")] = entry.netmask().toString();
                ifaceData[QStringLiteral("mac")] = iface.hardwareAddress();
                ifaceData[QStringLiteral("type")] = iface.type() == QNetworkInterface::Ethernet ? "Ethernet" : "WiFi";
                m_localInterfaces.append(ifaceData);
            }
        }
    }

    emit localInterfacesChanged();
}

void NetworkManager::sendDiscoveryBroadcast()
{
    if (!m_isScanning)
        return;

    QVariantMap discoveryPacket;
    discoveryPacket[QStringLiteral("type")] = QStringLiteral("discovery_request");
    discoveryPacket[QStringLiteral("timestamp")] = QDateTime::currentMSecsSinceEpoch();

    QJsonObject jsonObj = QJsonObject::fromVariantMap(discoveryPacket);
    QByteArray data = QJsonDocument(jsonObj).toJson(QJsonDocument::Compact);

    QHostAddress broadcastAddr(QHostAddress::Broadcast);
    qint64 bytesSent = m_scanSocket->writeDatagram(data, broadcastAddr, m_scanUdpPort);

    if (bytesSent > 0)
    {
        qDebug() << "NetworkManager: Sent discovery broadcast";
    }
}

void NetworkManager::processDiscoveryResponse(const QByteArray &data, const QHostAddress &sender)
{
    if (sender.isNull() || sender.isLoopback())
        return;

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
    {
        qDebug() << "NetworkManager: Invalid JSON from" << sender.toString() << error.errorString();
        return;
    }

    QJsonObject jsonObj = doc.object();
    QString msgType = jsonObj[QStringLiteral("type")].toString();

    qDebug() << "NetworkManager: Received" << msgType << "from" << sender.toString();

    if (msgType == QStringLiteral("device_discovery") ||
        msgType == QStringLiteral("discovery_response"))
    {
        addOrUpdateDevice(jsonObj, sender);
    }
    else
    {
        qDebug() << "NetworkManager: Ignoring message type:" << msgType;
    }
}

void NetworkManager::addOrUpdateDevice(const QJsonObject &jsonObj, const QHostAddress &senderIp)
{
    QString ip = senderIp.toString();

    QString deviceId = jsonObj[QStringLiteral("deviceId")].toString();
    if (deviceId.isEmpty())
        deviceId = jsonObj[QStringLiteral("device_id")].toString();

    QString deviceName = jsonObj[QStringLiteral("deviceName")].toString();
    if (deviceName.isEmpty())
        deviceName = jsonObj[QStringLiteral("device_name")].toString();

    QString deviceType = jsonObj[QStringLiteral("deviceType")].toString();
    if (deviceType.isEmpty())
        deviceType = jsonObj[QStringLiteral("device_type")].toString();

    int tcpPort = jsonObj[QStringLiteral("tcpPort")].toInt();
    if (tcpPort == 0)
        tcpPort = jsonObj[QStringLiteral("tcp_port")].toInt(9999);

    QString firmware = jsonObj[QStringLiteral("firmwareVersion")].toString();
    if (firmware.isEmpty())
        firmware = jsonObj[QStringLiteral("firmware_version")].toString();

    if (isDuplicateDevice(ip))
    {
        qDebug() << "NetworkManager: Duplicate device" << ip;
        return;
    }

    QVariantMap deviceData;
    deviceData[QStringLiteral("ip")] = ip;
    deviceData[QStringLiteral("deviceId")] = deviceId;
    deviceData[QStringLiteral("deviceName")] = deviceName.isEmpty() ? ip : deviceName;
    deviceData[QStringLiteral("deviceType")] = deviceType;
    deviceData[QStringLiteral("tcpPort")] = tcpPort;
    deviceData[QStringLiteral("firmware")] = firmware;
    deviceData[QStringLiteral("signal")] = 100;
    deviceData[QStringLiteral("secured")] = true;

    m_discoveredDevices.append(deviceData);
    emit discoveredDevicesChanged();
    emit deviceFound(ip, deviceName, deviceType, tcpPort);

    qDebug() << "NetworkManager: Discovered device" << deviceName << "at" << ip << "port" << tcpPort;
}

bool NetworkManager::isDuplicateDevice(const QString &ip) const
{
    for (const QVariant &device : m_discoveredDevices)
    {
        QVariantMap data = device.toMap();
        if (data[QStringLiteral("ip")].toString() == ip)
            return true;
    }
    return false;
}
