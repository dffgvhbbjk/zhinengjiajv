#pragma once

#include <QObject>
#include <QUdpSocket>
#include <QTimer>
#include <QMap>
#include <QDateTime>
#include <QVariantMap>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>

// 错误码枚举
enum UdpErrorCode
{
    UdpNoError = 0,
    UdpBindFailed = 1001,
    UdpNetworkError = 1002,
    UdpInvalidData = 1003,
    UdpChecksumFailed = 1004
};

class UdpDiscoverer : public QObject
{
    Q_OBJECT

public:
    explicit UdpDiscoverer(QObject *parent = nullptr);
    ~UdpDiscoverer() override;

    void loadKnownDevicesFromDatabase();
    Q_INVOKABLE void startDiscovery();
    Q_INVOKABLE void stopDiscovery();
    Q_INVOKABLE void requestDataRefresh(const QString &ip);

    bool isRunning() const { return m_running; }
    int onlineDeviceCount() const { return m_deviceLastSeen.size(); }

signals:
    void deviceDiscovered(const QString &deviceId, const QString &deviceName,
                          const QString &deviceType, const QString &ip,
                          int tcpPort, const QString &firmwareVersion);

    void dataReceived(const QString &deviceId, const QVariantMap &data);

    void sensorFieldUpdated(const QString &deviceId, const QString &field, double value);

    void deviceOffline(const QString &deviceId);

    void errorOccurred(int errorCode, const QString &errorString);

    void discoveryStarted();
    void discoveryStopped();

private slots:
    void onReadyRead();
    void checkDeviceTimeouts();
    void checkNetworkChange();

private:
    bool bindUdpSocket();
    void processIncomingData(const QByteArray &data, const QHostAddress &senderIp);
    bool handleDiscoveryPacket(const QJsonObject &jsonObj, const QHostAddress &senderIp);
    bool handleSensorDataPacket(const QJsonObject &jsonObj);
    bool handleSensorUpdatePacket(const QJsonObject &jsonObj);
    void updateDeviceLastSeen(const QString &deviceId);
    bool validateMd5Checksum(const QJsonObject &jsonObj);
    void restartOnNetworkChange();

    QUdpSocket *m_udpSocket;
    QMap<QString, QDateTime> m_deviceLastSeen;
    QTimer *m_offlineCheckTimer;
    QTimer *m_networkCheckTimer;
    QList<QHostAddress> m_lastKnownAddresses;
    bool m_running;

    static constexpr quint16 UdpPort = 8888;
    static constexpr int OfflineTimeoutSeconds = 30;
    static constexpr int OfflineCheckIntervalMs = 5000;
    static constexpr int NetworkCheckIntervalMs = 10000;
};
