#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QUdpSocket>
#include <QHostAddress>
#include <QNetworkInterface>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>

class NetworkManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList localInterfaces READ localInterfaces NOTIFY localInterfacesChanged)
    Q_PROPERTY(QVariantList discoveredDevices READ discoveredDevices NOTIFY discoveredDevicesChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)

public:
    explicit NetworkManager(QObject *parent = nullptr);
    ~NetworkManager() override;

    Q_INVOKABLE void refreshLocalInterfaces();
    Q_INVOKABLE void startDeviceDiscovery(int udpPort = 8888);
    Q_INVOKABLE void stopDeviceDiscovery();
    Q_INVOKABLE void clearDiscoveredDevices();

    QVariantList localInterfaces() const { return m_localInterfaces; }
    QVariantList discoveredDevices() const { return m_discoveredDevices; }
    bool isScanning() const { return m_isScanning; }

signals:
    void localInterfacesChanged();
    void discoveredDevicesChanged();
    void scanningChanged();
    void deviceFound(const QString &ip, const QString &name, const QString &type, int tcpPort);

private slots:
    void onReadyRead();
    void scanTimeout();

private:
    void collectLocalInterfaces();
    void sendDiscoveryBroadcast();
    void processDiscoveryResponse(const QByteArray &data, const QHostAddress &sender);
    void addOrUpdateDevice(const QJsonObject &jsonObj, const QHostAddress &senderIp);
    bool isDuplicateDevice(const QString &ip) const;

    QUdpSocket *m_scanSocket;
    QTimer *m_scanTimer;
    QTimer *m_scanTimeoutTimer;
    QVariantList m_localInterfaces;
    QVariantList m_discoveredDevices;
    bool m_isScanning;
    int m_scanUdpPort;
    int m_scanRetryCount;

    static constexpr int ScanResponsePort = 8889;
    static constexpr int MaxScanRetries = 3;
    static constexpr int ScanRetryIntervalMs = 2000;
    static constexpr int ScanTimeoutMs = 8000;
};
