#pragma once

#include <QObject>
#include <QTcpSocket>
#include <QTimer>
#include <QVariantMap>
#include <QList>
#include <QPair>
#include <QFile>
#include <QMap>

class DatabaseManager;

enum TcpErrorCode
{
    TcpNoError = 0,
    TcpConnectionFailed = 2001,
    TcpDisconnected = 2002,
    TcpSendFailed = 2003,
    TcpTimeout = 2004,
    TcpFirmwareError = 2005
};

class TcpController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY connectionStatusChanged)
    Q_PROPERTY(bool isVideoConnected READ isVideoConnected NOTIFY cameraStreamToggled)
    Q_PROPERTY(QString targetIp READ targetIp CONSTANT)
    Q_PROPERTY(int targetPort READ targetPort CONSTANT)
    Q_PROPERTY(int videoPort READ videoPort CONSTANT)
    Q_PROPERTY(int queueSize READ queueSize NOTIFY connectionStatusChanged)

public:
    explicit TcpController(QObject *parent = nullptr);
    ~TcpController() override;

    Q_INVOKABLE void connectToDevice(const QString &ip, int port);
    Q_INVOKABLE void disconnectFromDevice();
    Q_INVOKABLE void connectToVideoStream(int videoPort);
    Q_INVOKABLE void connectToVideoStream(const QString &ip, int videoPort);
    Q_INVOKABLE void disconnectFromVideoStream();

    Q_INVOKABLE void sendControlCommand(const QString &commandId, const QString &device, const QString &action);
    Q_INVOKABLE void sendSceneCommand(const QString &commandId, const QString &sceneId);
    Q_INVOKABLE void sendScheduleCommand(const QString &commandId, const QString &scheduleData);
    Q_INVOKABLE void sendAlertCommand(const QString &commandId, const QString &alertAction);
    Q_INVOKABLE void sendVoiceText(const QString &text, bool isCommand);

Q_INVOKABLE void startFirmwareUpdate(const QString &firmwareFilePath);
    Q_INVOKABLE void cancelFirmwareUpdate();

    bool isConnected() const { return m_isConnected; }
    bool isVideoConnected() const { return m_videoConnected; }
    QString targetIp() const { return m_targetIp; }
    int targetPort() const { return m_targetPort; }
    int videoPort() const { return m_videoPort; }
    int queueSize() const { return m_commandQueue.size(); }
    qint64 getDeviceStateVersion(const QString &deviceId) const;
    void updateDeviceStateVersion(const QString &deviceId, qint64 version);

    void setDatabaseManager(DatabaseManager *db);

signals:
    void connectionStatusChanged(bool isConnected);
    void commandSuccess(const QString &commandId, const QString &message);
    void commandFailed(const QString &commandId, const QString &errorString);
    void alertReceived(const QString &alertId, const QString &deviceId, const QString &content, int level);
    void firmwareUpdateProgress(int progress);
    void firmwareUpdateComplete();
    void errorOccurred(int errorCode, const QString &errorString);
    void videoFrameReceived(const QString &base64Data, int width, int height, qint64 timestamp);
    void rawVideoFrameReceived(const QByteArray &jpegData, int width, int height);
    void cameraStreamToggled(bool enabled);
    void deviceControlled(const QString &deviceId, const QString &action);
    void deviceStateUpdated(const QString &deviceId, const QString &state);
    void gatewayDeviceListReceived(const QString &gatewayId, const QVariantList &devices);

private slots:
    void onConnected();
    void onDisconnected();
    void onReadyRead();
    void onErrorOccurred(QAbstractSocket::SocketError socketError);
    void onVideoConnected();
    void onVideoDisconnected();
    void onVideoReadyRead();
    void onVideoErrorOccurred(QAbstractSocket::SocketError socketError);
    void sendHeartbeat();
    void checkHeartbeatTimeout();
    void tryReconnect();
    void processCommandQueue();
    void sendNextFirmwareChunk();
    int findJsonBoundary(const QByteArray &buffer) const;

private:
    void enqueueCommand(const QVariantMap &command, int priority);
    void sortCommandQueue();
    void sendCommand(const QVariantMap &command);
    void handleIncomingData(const QByteArray &data);
void handleCommandResponse(const QJsonObject &jsonObj);
    void handleAlertPacket(const QJsonObject &jsonObj);
    void handleFirmwareResponse(const QJsonObject &jsonObj);
    void handleVideoFrame(const QJsonObject &jsonObj);
    void handleDeviceStatusPacket(const QJsonObject &jsonObj);
    bool sendFirmwareChunk(int chunkIndex);
    void resetConnectionState();
    void purgeStaleCommands();
    bool isCommandStale(const QVariantMap &command) const;

    QTcpSocket *m_tcpSocket;
    QTcpSocket *m_videoTcpSocket;
    bool m_isConnected;
    bool m_videoConnected;
    bool m_connectInProgress;
    QString m_targetIp;
    int m_targetPort;
    int m_videoPort;

    QList<QVariantMap> m_commandQueue;
    QVariantMap m_currentCommand;

    QTimer *m_heartbeatTimer;
    QTimer *m_heartbeatTimeout;
    QTimer *m_reconnectTimer;
    QTimer *m_stableConnectionTimer;
    int m_reconnectCount;

    DatabaseManager *m_databaseManager = nullptr;

    QFile *m_firmwareFile;
    int m_firmwareChunkSize;
    int m_firmwareTotalChunks;
    int m_firmwareCurrentChunk;

    QByteArray m_receiveBuffer;
    QByteArray m_videoReceiveBuffer;

    qint64 m_lastVideoFrameEmitTime = 0;
    int m_videoFrameSkipCount = 0;

    QList<QPair<QString, bool>> m_pendingVoiceTexts;
    void flushPendingVoiceTexts();

    static constexpr quint16 DefaultTcpPort = 9999;
    static constexpr int DefaultVideoPort = 9998;
    static constexpr int HeartbeatIntervalMs = 30000;
    static constexpr int HeartbeatTimeoutMs = 30000;
    static constexpr int ReconnectIntervalMs = 10000;
    static constexpr int MaxReconnectAttempts = 5;
    static constexpr int FirmwareChunkSize = 1048576;
static constexpr int CommandRetryCount = 3;
    static constexpr int MinVideoFrameIntervalMs = 66;
    static constexpr qint64 CommandStalenessThresholdMs = 10000;

    QMap<QString, qint64> m_deviceStateVersion;
};
