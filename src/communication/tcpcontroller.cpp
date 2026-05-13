#include "tcpcontroller.h"
#include "../utils/jsonutils.h"
#include "../utils/md5utils.h"
#include "../models/databasemanager.h"
#include <algorithm>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHostAddress>
#include <QAbstractSocket>
#include <QBuffer>
#include <QByteArray>
#include <QCryptographicHash>
#include <QFileInfo>
#include <QDateTime>

static constexpr int CAMERA_WIDTH = 480;
static constexpr int CAMERA_HEIGHT = 360;

TcpController::TcpController(QObject *parent)
    : QObject(parent),
      m_tcpSocket(nullptr),
      m_videoTcpSocket(nullptr),
      m_isConnected(false),
      m_videoConnected(false),
      m_connectInProgress(false),
      m_targetPort(DefaultTcpPort),
      m_videoPort(DefaultVideoPort),
      m_reconnectCount(0),
      m_receiveBuffer(),
      m_videoReceiveBuffer(),
      m_firmwareFile(nullptr),
      m_firmwareChunkSize(FirmwareChunkSize),
      m_firmwareTotalChunks(0),
      m_firmwareCurrentChunk(0)
{
    m_tcpSocket = new QTcpSocket(this);
    m_tcpSocket->setSocketOption(QAbstractSocket::KeepAliveOption, 1);

    connect(m_tcpSocket, &QTcpSocket::connected, this, &TcpController::onConnected);
    connect(m_tcpSocket, &QTcpSocket::disconnected, this, &TcpController::onDisconnected);
    connect(m_tcpSocket, &QTcpSocket::readyRead, this, &TcpController::onReadyRead);
    connect(m_tcpSocket, &QTcpSocket::errorOccurred, this, &TcpController::onErrorOccurred);

    m_videoTcpSocket = new QTcpSocket(this);
    m_videoTcpSocket->setSocketOption(QAbstractSocket::KeepAliveOption, 1);

    connect(m_videoTcpSocket, &QTcpSocket::connected, this, &TcpController::onVideoConnected);
    connect(m_videoTcpSocket, &QTcpSocket::disconnected, this, &TcpController::onVideoDisconnected);
    connect(m_videoTcpSocket, &QTcpSocket::readyRead, this, &TcpController::onVideoReadyRead);
    connect(m_videoTcpSocket, &QTcpSocket::errorOccurred, this, &TcpController::onVideoErrorOccurred);

    m_heartbeatTimer = new QTimer(this);
    m_heartbeatTimer->setInterval(HeartbeatIntervalMs);
    connect(m_heartbeatTimer, &QTimer::timeout, this, &TcpController::sendHeartbeat);

    m_heartbeatTimeout = new QTimer(this);
    m_heartbeatTimeout->setSingleShot(true);
    m_heartbeatTimeout->setInterval(HeartbeatTimeoutMs);
    connect(m_heartbeatTimeout, &QTimer::timeout, this, &TcpController::checkHeartbeatTimeout);

    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setInterval(ReconnectIntervalMs);
    m_reconnectTimer->setSingleShot(true);
    connect(m_reconnectTimer, &QTimer::timeout, this, &TcpController::tryReconnect);

    m_stableConnectionTimer = new QTimer(this);
    m_stableConnectionTimer->setSingleShot(true);
    m_stableConnectionTimer->setInterval(5000);
    connect(m_stableConnectionTimer, &QTimer::timeout, this, [this]()
            {
        m_reconnectCount = 0;
        qDebug() << "TcpController: Connection stable, reconnect count reset";
    });
}

void TcpController::setDatabaseManager(DatabaseManager *db)
{
    m_databaseManager = db;
}

TcpController::~TcpController()
{
    disconnectFromDevice();
    if (m_firmwareFile)
    {
        if (m_firmwareFile->isOpen())
        {
            m_firmwareFile->close();
        }
        delete m_firmwareFile;
        m_firmwareFile = nullptr;
    }
}

void TcpController::connectToDevice(const QString &ip, int port)
{
    int resolvedPort = (port > 0) ? port : DefaultTcpPort;

    if (m_isConnected && m_targetIp == ip && m_targetPort == resolvedPort)
    {
        qDebug() << "TcpController: Already connected to" << ip << ":" << resolvedPort << "- skipping";
        return;
    }

    if (m_connectInProgress && m_targetIp == ip && m_targetPort == resolvedPort)
    {
        qDebug() << "TcpController: Connection already in progress to" << ip << ":" << resolvedPort << "- skipping";
        return;
    }

    QAbstractSocket::SocketState state = m_tcpSocket->state();
    if ((state == QAbstractSocket::ConnectingState || state == QAbstractSocket::HostLookupState)
        && m_targetIp == ip && m_targetPort == resolvedPort)
    {
        qDebug() << "TcpController: Already connecting to" << ip << ":" << resolvedPort << "- skipping";
        return;
    }

    m_targetIp = ip;
    m_targetPort = resolvedPort;
    m_reconnectCount = 0;

    if (m_tcpSocket->state() != QAbstractSocket::UnconnectedState)
    {
        m_tcpSocket->abort();
    }

    m_connectInProgress = true;
    qDebug() << "TcpController: Connecting to" << m_targetIp << ":" << m_targetPort;
    m_tcpSocket->connectToHost(QHostAddress(m_targetIp), m_targetPort);
}

void TcpController::disconnectFromDevice()
{
    qDebug() << "TcpController: Disconnecting from device";
    m_heartbeatTimer->stop();
    m_heartbeatTimeout->stop();
    m_reconnectTimer->stop();
    m_stableConnectionTimer->stop();
    m_tcpSocket->abort();
    disconnectFromVideoStream();

    if (m_firmwareFile)
    {
        if (m_firmwareFile->isOpen())
        {
            m_firmwareFile->close();
        }
        delete m_firmwareFile;
        m_firmwareFile = nullptr;
    }
    m_firmwareCurrentChunk = 0;
    m_firmwareTotalChunks = 0;

    resetConnectionState();
}

void TcpController::sendControlCommand(const QString &commandId, const QString &device, const QString &action)
{
    QVariantMap command;
    command.insert(QStringLiteral("type"), QStringLiteral("control"));
    command.insert(QStringLiteral("commandId"), commandId);
    command.insert(QStringLiteral("device"), device);
    command.insert(QStringLiteral("action"), action);
    command.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());
    command.insert(QStringLiteral("retryCount"), 0);

    enqueueCommand(command, 1);
}

void TcpController::sendSceneCommand(const QString &commandId, const QString &sceneId)
{
    QVariantMap sceneData = DatabaseManager::instance()->getScene(sceneId);

    QVariantMap command;
    command.insert(QStringLiteral("type"), QStringLiteral("scene"));
    command.insert(QStringLiteral("commandId"), commandId);
    command.insert(QStringLiteral("sceneId"), sceneId);
    command.insert(QStringLiteral("sceneName"), sceneData.value("scene_name").toString());
    command.insert(QStringLiteral("triggerType"), sceneData.value("trigger_type").toString());
    command.insert(QStringLiteral("triggerDeviceId"), sceneData.value("trigger_device_id").toString());
    command.insert(QStringLiteral("triggerSensorData"), sceneData.value("trigger_sensor_data").toString());
    command.insert(QStringLiteral("triggerTime"), sceneData.value("trigger_time").toString());
    command.insert(QStringLiteral("actions"), sceneData.value("actions").toString());
    command.insert(QStringLiteral("actionDevices"), sceneData.value("action_devices").toString());
    command.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());
    command.insert(QStringLiteral("retryCount"), 0);

    enqueueCommand(command, 2);
}

void TcpController::sendScheduleCommand(const QString &commandId, const QString &scheduleData)
{
    QVariantMap command;
    command.insert(QStringLiteral("type"), QStringLiteral("schedule"));
    command.insert(QStringLiteral("commandId"), commandId);
    command.insert(QStringLiteral("data"), scheduleData);
    command.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());
    command.insert(QStringLiteral("retryCount"), 0);

    enqueueCommand(command, 2);
}

void TcpController::sendAlertCommand(const QString &commandId, const QString &alertAction)
{
    QVariantMap command;
    command.insert(QStringLiteral("type"), QStringLiteral("alert_command"));
    command.insert(QStringLiteral("commandId"), commandId);
    command.insert(QStringLiteral("action"), alertAction);
    command.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());
    command.insert(QStringLiteral("retryCount"), 0);

    enqueueCommand(command, 0);
}

void TcpController::sendVoiceText(const QString &text, bool isCommand)
{
    if (!m_isConnected)
    {
        qDebug() << "TcpController: Not connected, queueing voice text for later";
        if (m_databaseManager)
            m_databaseManager->addConnectionLog("[VOICE] [WARN] 网关未连接，语音文本已加入待发送队列: " + text);
        m_pendingVoiceTexts.append({text, isCommand});
        return;
    }

    flushPendingVoiceTexts();

    QJsonObject obj;
    obj.insert(QStringLiteral("type"), QStringLiteral("voice_text"));
    obj.insert(QStringLiteral("text"), text);
    obj.insert(QStringLiteral("is_command"), isCommand);
    obj.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    qint64 written = m_tcpSocket->write(data);
    m_tcpSocket->flush();

    if (written <= 0)
    {
        qDebug() << "TcpController: Voice text write failed, queueing for retry";
        m_pendingVoiceTexts.append({text, isCommand});
        return;
    }

    qDebug() << "TcpController: Sent voice text:" << text << "(isCommand:" << isCommand << ")";
    if (m_databaseManager)
        m_databaseManager->addConnectionLog("[VOICE] [INFO] 语音文本已发送到网关: " + text + " (指令:" + (isCommand ? "是" : "否") + ")");
}

void TcpController::flushPendingVoiceTexts()
{
    if (m_pendingVoiceTexts.isEmpty())
        return;

    qDebug() << "TcpController: Flushing" << m_pendingVoiceTexts.size() << "pending voice texts";

    for (const auto &entry : m_pendingVoiceTexts)
    {
        const QString &voiceText = entry.first;
        bool isCmd = entry.second;

        QJsonObject obj;
        obj.insert(QStringLiteral("type"), QStringLiteral("voice_text"));
        obj.insert(QStringLiteral("text"), voiceText);
        obj.insert(QStringLiteral("is_command"), isCmd);
        obj.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());

        QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
        m_tcpSocket->write(data);
    }

    m_tcpSocket->flush();
    m_pendingVoiceTexts.clear();
}

void TcpController::startFirmwareUpdate(const QString &firmwareFilePath)
{
    if (!m_isConnected)
    {
        emit errorOccurred(TcpConnectionFailed, QStringLiteral("Not connected to device"));
        return;
    }

    if (m_firmwareFile && m_firmwareFile->isOpen())
    {
        m_firmwareFile->close();
        delete m_firmwareFile;
        m_firmwareFile = nullptr;
    }

    m_firmwareFile = new QFile(firmwareFilePath);
    if (!m_firmwareFile->open(QIODevice::ReadOnly))
    {
        delete m_firmwareFile;
        m_firmwareFile = nullptr;
        emit errorOccurred(TcpFirmwareError, QStringLiteral("Cannot open firmware file: ") + firmwareFilePath);
        return;
    }

    qint64 fileSize = m_firmwareFile->size();
    m_firmwareTotalChunks = static_cast<int>((fileSize + m_firmwareChunkSize - 1) / m_firmwareChunkSize);
    m_firmwareCurrentChunk = 0;

    qDebug() << "TcpController: Starting firmware update," << m_firmwareTotalChunks << "chunks," << fileSize << "bytes";

    QJsonObject initMsg;
    initMsg.insert(QStringLiteral("type"), QStringLiteral("firmware_init"));
    initMsg.insert(QStringLiteral("totalChunks"), m_firmwareTotalChunks);
    initMsg.insert(QStringLiteral("fileSize"), fileSize);
    initMsg.insert(QStringLiteral("fileName"), QFileInfo(firmwareFilePath).fileName());
    initMsg.insert(QStringLiteral("md5"), Md5Utils::computeMd5(m_firmwareFile->readAll()));
    m_firmwareFile->seek(0);

    QByteArray initData = QJsonDocument(initMsg).toJson(QJsonDocument::Compact);
    m_tcpSocket->write(initData);
    m_tcpSocket->flush();
}

void TcpController::cancelFirmwareUpdate()
{
    if (m_firmwareFile)
    {
        if (m_firmwareFile->isOpen())
        {
            m_firmwareFile->close();
        }
        delete m_firmwareFile;
        m_firmwareFile = nullptr;
    }
    m_firmwareCurrentChunk = 0;
    m_firmwareTotalChunks = 0;
    emit firmwareUpdateProgress(0);
    qDebug() << "TcpController: Firmware update cancelled";
}

void TcpController::onConnected()
{
    qDebug() << "TcpController: Connected to" << m_targetIp;
    m_isConnected = true;
    m_connectInProgress = false;
    m_reconnectTimer->stop();
    m_stableConnectionTimer->start();

    m_heartbeatTimer->start();
    m_heartbeatTimeout->stop();

    emit connectionStatusChanged(true);

    QJsonObject helloMsg;
    helloMsg.insert(QStringLiteral("type"), QStringLiteral("hello"));
    helloMsg.insert(QStringLiteral("commandId"), QStringLiteral("hello"));
    helloMsg.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());
    m_tcpSocket->write(QJsonDocument(helloMsg).toJson(QJsonDocument::Compact));

    if (!m_commandQueue.isEmpty())
    {
        qDebug() << "TcpController:" << m_commandQueue.size() << "pending commands in queue, processing...";
        processCommandQueue();
    }

    flushPendingVoiceTexts();
}

void TcpController::onDisconnected()
{
    qDebug() << "TcpController: Disconnected from" << m_targetIp;
    m_isConnected = false;
    m_connectInProgress = false;
    m_stableConnectionTimer->stop();
    m_heartbeatTimer->stop();
    m_heartbeatTimeout->stop();

    emit connectionStatusChanged(false);

    if (!m_currentCommand.isEmpty())
    {
        QString commandId = m_currentCommand.value(QStringLiteral("commandId")).toString();
        emit commandFailed(commandId, QStringLiteral("Connection lost"));
        m_currentCommand.clear();
    }

    if (m_reconnectCount < MaxReconnectAttempts)
    {
        qDebug() << "TcpController: Will try to reconnect in" << ReconnectIntervalMs << "ms";
        m_reconnectTimer->start();
    }
    else
    {
        emit errorOccurred(TcpConnectionFailed, QStringLiteral("Max reconnect attempts reached"));
    }
}

void TcpController::onReadyRead()
{
    m_receiveBuffer.append(m_tcpSocket->readAll());

    while (!m_receiveBuffer.isEmpty())
    {
        int boundaryPos = findJsonBoundary(m_receiveBuffer);
        if (boundaryPos < 0)
        {
            break;
        }

        QByteArray jsonBytes = m_receiveBuffer.left(boundaryPos);
        m_receiveBuffer = m_receiveBuffer.mid(boundaryPos);

        QJsonParseError parseError;
        QJsonDocument jsonDoc = QJsonDocument::fromJson(jsonBytes, &parseError);
        if (parseError.error == QJsonParseError::NoError && jsonDoc.isObject())
        {
            handleIncomingData(jsonBytes);
        }
        else
        {
            qDebug() << "TcpController: Malformed JSON at boundary:" << parseError.errorString();
        }
    }
}

int TcpController::findJsonBoundary(const QByteArray &buffer) const
{
    int braceCount = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < buffer.size(); ++i)
    {
        char c = buffer.at(i);
        if (escaped)
        {
            escaped = false;
            continue;
        }
        if (c == '\\')
        {
            escaped = true;
            continue;
        }
        if (c == '"')
        {
            inString = !inString;
            continue;
        }
        if (!inString)
        {
            if (c == '{')
            {
                braceCount++;
            }
            else if (c == '}')
            {
                braceCount--;
                if (braceCount == 0)
                {
                    return i + 1;
                }
            }
        }
    }
    return -1;
}

void TcpController::onErrorOccurred(QAbstractSocket::SocketError socketError)
{
    Q_UNUSED(socketError);
    qDebug() << "TcpController: Socket error:" << m_tcpSocket->errorString();

    if (m_isConnected)
    {
        emit errorOccurred(TcpDisconnected, m_tcpSocket->errorString());
    }
}

void TcpController::sendHeartbeat()
{
    if (!m_isConnected)
    {
        return;
    }

    QJsonObject heartbeatMsg;
    heartbeatMsg.insert(QStringLiteral("type"), QStringLiteral("heartbeat"));
    heartbeatMsg.insert(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch());

    m_tcpSocket->write(QJsonDocument(heartbeatMsg).toJson(QJsonDocument::Compact));
    m_tcpSocket->flush();

    m_heartbeatTimeout->start();
    qDebug() << "TcpController: Heartbeat sent";
}

void TcpController::checkHeartbeatTimeout()
{
    qDebug() << "TcpController: Heartbeat timeout, disconnecting";
    m_tcpSocket->abort();
}

void TcpController::tryReconnect()
{
    if (m_isConnected)
    {
        m_reconnectTimer->stop();
        return;
    }

    m_reconnectCount++;
    qDebug() << "TcpController: Reconnecting attempt" << m_reconnectCount << "/" << MaxReconnectAttempts;

    if (m_reconnectCount >= MaxReconnectAttempts)
    {
        m_reconnectTimer->stop();
        emit errorOccurred(TcpConnectionFailed, QStringLiteral("Max reconnect attempts reached"));
        return;
    }

    m_tcpSocket->connectToHost(QHostAddress(m_targetIp), m_targetPort);
    m_reconnectTimer->start();
}

void TcpController::processCommandQueue()
{
    if (!m_isConnected || m_commandQueue.isEmpty() || !m_currentCommand.isEmpty())
    {
        return;
    }

    sortCommandQueue();
    m_currentCommand = m_commandQueue.takeFirst();
    sendCommand(m_currentCommand);
}

void TcpController::enqueueCommand(const QVariantMap &command, int priority)
{
    QVariantMap cmd = command;
    cmd.insert(QStringLiteral("priority"), priority);
    m_commandQueue.append(cmd);

    qDebug() << "TcpController: Enqueued command with priority" << priority;

    if (m_isConnected && m_currentCommand.isEmpty())
    {
        processCommandQueue();
    }
}

void TcpController::sortCommandQueue()
{
    std::sort(m_commandQueue.begin(), m_commandQueue.end(),
              [](const QVariantMap &a, const QVariantMap &b)
              {
                  return a.value(QStringLiteral("priority")).toInt() < b.value(QStringLiteral("priority")).toInt();
              });
}

void TcpController::sendCommand(const QVariantMap &command)
{
    QJsonObject jsonObj = JsonUtils::fromVariantMap(command);
    QByteArray data = QJsonDocument(jsonObj).toJson(QJsonDocument::Compact);

    qDebug() << "TcpController: [SEND] Raw JSON:" << data.trimmed();
    qDebug() << "TcpController: [SEND] type=" << command.value("type").toString()
             << "device=" << command.value("device").toString()
             << "action=" << command.value("action").toString();

    qint64 bytesWritten = m_tcpSocket->write(data);
    if (bytesWritten > 0)
    {
        m_tcpSocket->flush();
        qDebug() << "TcpController: [SEND-OK] Wrote" << bytesWritten << "bytes to" << m_targetIp << ":" << m_targetPort;
    }
    else
    {
        QString commandId = command.value(QStringLiteral("commandId")).toString();
        qDebug() << "TcpController: [SEND-FAIL] write returned" << bytesWritten << "error:" << m_tcpSocket->errorString();
        emit commandFailed(commandId, m_tcpSocket->errorString());
        m_currentCommand.clear();
        processCommandQueue();
    }
}

void TcpController::handleIncomingData(const QByteArray &data)
{
    QJsonParseError parseError;
    QJsonDocument jsonDoc = QJsonDocument::fromJson(data, &parseError);

    if (parseError.error != QJsonParseError::NoError)
    {
        qDebug() << "TcpController: Invalid JSON:" << parseError.errorString();
        return;
    }

    if (!jsonDoc.isObject())
    {
        qDebug() << "TcpController: Expected JSON object";
        return;
    }

    QJsonObject jsonObj = jsonDoc.object();
    QString msgType = JsonUtils::getValue(jsonObj, QStringLiteral("type"));

    if (msgType.isEmpty())
    {
        return;
    }

    if (msgType == QStringLiteral("command_response"))
    {
        handleCommandResponse(jsonObj);
    }
    else if (msgType == QStringLiteral("alert"))
    {
        handleAlertPacket(jsonObj);
    }
    else if (msgType == QStringLiteral("firmware_ack"))
    {
        handleFirmwareResponse(jsonObj);
    }
    else if (msgType == QStringLiteral("heartbeat_ack"))
    {
        m_heartbeatTimeout->stop();
        qDebug() << "TcpController: Heartbeat acknowledged";
    }
    else if (msgType == QStringLiteral("video_frame"))
    {
        handleVideoFrame(jsonObj);
    }
    else if (msgType == QStringLiteral("voice_text_ack"))
    {
        qDebug() << "TcpController: Voice text acknowledged by gateway";
    }
    else if (msgType == QStringLiteral("scene_ack") || msgType == QStringLiteral("schedule_ack"))
    {
        qDebug() << "TcpController: Gateway acknowledged" << msgType;
    }
    else
    {
        qDebug() << "TcpController: Unknown message type from gateway:" << msgType;
    }
}

void TcpController::handleCommandResponse(const QJsonObject &jsonObj)
{
    QString commandId = JsonUtils::extractCommandId(jsonObj);
    QString status = JsonUtils::getValue(jsonObj, QStringLiteral("status"));
    QString message = JsonUtils::getValue(jsonObj, QStringLiteral("message"));

    if (commandId == QStringLiteral("hello") && status == QStringLiteral("success"))
    {
        int videoPort = JsonUtils::getIntValue(jsonObj, QStringLiteral("videoPort"), DefaultVideoPort);
        if (videoPort == DefaultVideoPort)
            videoPort = JsonUtils::getIntValue(jsonObj, QStringLiteral("video_port"), DefaultVideoPort);
        bool cameraAvailable = JsonUtils::getBoolValue(jsonObj, QStringLiteral("camera"), false);
        qDebug() << "TcpController: Hello response - camera:" << cameraAvailable << "videoPort:" << videoPort;
        if (cameraAvailable && !m_videoConnected)
        {
            qDebug() << "TcpController: Auto-connecting to video stream on port" << videoPort;
            connectToVideoStream(videoPort);
        }
        else if (!cameraAvailable)
        {
            qDebug() << "TcpController: Camera not available on gateway, video stream skipped";
        }
        else if (m_videoConnected)
        {
            qDebug() << "TcpController: Video stream already connected";
        }
    }

    if (status == QStringLiteral("success"))
    {
        if (commandId != QStringLiteral("hello"))
        {
            if (m_currentCommand.contains(QStringLiteral("device")) && m_currentCommand.contains(QStringLiteral("action")))
            {
                emit deviceControlled(m_currentCommand.value(QStringLiteral("device")).toString(),
                                      m_currentCommand.value(QStringLiteral("action")).toString());
            }
            emit commandSuccess(commandId, message);
        }
    }
    else
    {
        int retryCount = m_currentCommand.value(QStringLiteral("retryCount")).toInt();
        if (retryCount < CommandRetryCount)
        {
            QVariantMap retryCmd = m_currentCommand;
            retryCmd.insert(QStringLiteral("retryCount"), retryCount + 1);
            m_commandQueue.prepend(retryCmd);
            qDebug() << "TcpController: Retrying command" << commandId << "attempt" << (retryCount + 1);
        }
        else
        {
            emit commandFailed(commandId, message);
        }
    }

    m_currentCommand.clear();
    processCommandQueue();
}

void TcpController::handleAlertPacket(const QJsonObject &jsonObj)
{
    QString alertId = JsonUtils::getValue(jsonObj, QStringLiteral("alertId"));
    if (alertId.isEmpty())
        alertId = JsonUtils::getValue(jsonObj, QStringLiteral("alert_id"));
    QString deviceId = JsonUtils::extractDeviceId(jsonObj);
    QString content = JsonUtils::getValue(jsonObj, QStringLiteral("content"));
    int level = JsonUtils::getIntValue(jsonObj, QStringLiteral("level"), 0);

    if (deviceId.isEmpty())
    {
        qDebug() << "TcpController: Alert missing deviceId, ignoring";
        return;
    }

    emit alertReceived(alertId, deviceId, content, level);
    qDebug() << "TcpController: Alert received -" << alertId << "level" << level;
}

void TcpController::handleFirmwareResponse(const QJsonObject &jsonObj)
{
    QString status = JsonUtils::getValue(jsonObj, QStringLiteral("status"));
    int chunk = JsonUtils::getIntValue(jsonObj, QStringLiteral("chunk"), -1);

    if (status == QStringLiteral("ok") && chunk == m_firmwareCurrentChunk)
    {
        m_firmwareCurrentChunk++;
        int progress = (m_firmwareCurrentChunk * 100) / m_firmwareTotalChunks;
        emit firmwareUpdateProgress(progress);

        if (m_firmwareCurrentChunk >= m_firmwareTotalChunks)
        {
            emit firmwareUpdateComplete();
            qDebug() << "TcpController: Firmware update complete";
        }
        else
        {
            sendNextFirmwareChunk();
        }
    }
    else if (status == QStringLiteral("retry"))
    {
        qDebug() << "TcpController: Retrying firmware chunk" << chunk;
        sendFirmwareChunk(chunk);
    }
}

void TcpController::sendNextFirmwareChunk()
{
    if (!m_firmwareFile || !m_firmwareFile->isOpen())
    {
        emit errorOccurred(TcpFirmwareError, QStringLiteral("Firmware file not open"));
        return;
    }

    sendFirmwareChunk(m_firmwareCurrentChunk);
}

bool TcpController::sendFirmwareChunk(int chunkIndex)
{
    if (!m_firmwareFile || !m_firmwareFile->isOpen())
    {
        return false;
    }

    qint64 offset = static_cast<qint64>(chunkIndex) * m_firmwareChunkSize;
    m_firmwareFile->seek(offset);

    QByteArray chunkData = m_firmwareFile->read(m_firmwareChunkSize);
    if (chunkData.isEmpty())
    {
        emit errorOccurred(TcpFirmwareError, QStringLiteral("Failed to read firmware chunk"));
        return false;
    }

    QString chunkMd5 = Md5Utils::computeMd5(chunkData);

    QJsonObject chunkMsg;
    chunkMsg.insert(QStringLiteral("type"), QStringLiteral("firmware_chunk"));
    chunkMsg.insert(QStringLiteral("chunk"), chunkIndex);
    chunkMsg.insert(QStringLiteral("total"), m_firmwareTotalChunks);
    chunkMsg.insert(QStringLiteral("md5"), chunkMd5);
    chunkMsg.insert(QStringLiteral("data"), QString::fromLatin1(chunkData.toBase64()));

    QByteArray data = QJsonDocument(chunkMsg).toJson(QJsonDocument::Compact);
    qint64 bytesWritten = m_tcpSocket->write(data);
    m_tcpSocket->flush();

    if (bytesWritten > 0)
    {
        qDebug() << "TcpController: Sent firmware chunk" << chunkIndex << "/" << (m_firmwareTotalChunks - 1);
        return true;
    }

    return false;
}

void TcpController::resetConnectionState()
{
    m_isConnected = false;
    m_connectInProgress = false;
    m_reconnectCount = 0;
    m_currentCommand.clear();
    m_receiveBuffer.clear();
    emit connectionStatusChanged(false);
}

void TcpController::handleVideoFrame(const QJsonObject &jsonObj)
{
    QString base64Data = JsonUtils::getValue(jsonObj, QStringLiteral("data"));
    if (base64Data.isEmpty())
    {
        return;
    }

    int width = JsonUtils::getIntValue(jsonObj, QStringLiteral("width"), 640);
    int height = JsonUtils::getIntValue(jsonObj, QStringLiteral("height"), 480);
    qint64 timestamp = JsonUtils::getIntValue(jsonObj, QStringLiteral("timestamp"), 0);

    emit videoFrameReceived(base64Data, width, height, timestamp);
}

void TcpController::connectToVideoStream(int videoPort)
{
    connectToVideoStream(m_targetIp, videoPort);
}

void TcpController::connectToVideoStream(const QString &ip, int videoPort)
{
    if (m_videoConnected)
    {
        qDebug() << "TcpController: Video stream already connected";
        return;
    }

    if (ip.isEmpty())
    {
        qDebug() << "TcpController: Cannot connect to video stream - target IP is empty";
        return;
    }

    m_videoPort = videoPort > 0 ? videoPort : DefaultVideoPort;
    qDebug() << "TcpController: Connecting to video stream" << ip << ":" << m_videoPort;
    m_videoTcpSocket->connectToHost(QHostAddress(ip), m_videoPort);
}

void TcpController::disconnectFromVideoStream()
{
    if (m_videoTcpSocket->state() != QAbstractSocket::UnconnectedState)
    {
        m_videoTcpSocket->disconnectFromHost();
    }
    else
    {
        m_videoConnected = false;
        m_videoReceiveBuffer.clear();
        emit cameraStreamToggled(false);
    }
}

void TcpController::onVideoConnected()
{
    m_videoConnected = true;
    m_videoReceiveBuffer.clear();
    m_lastVideoFrameEmitTime = 0;
    m_videoFrameSkipCount = 0;
    qDebug() << "TcpController: Video stream connected to" << m_targetIp << ":" << m_videoPort;
    emit cameraStreamToggled(true);
}

void TcpController::onVideoDisconnected()
{
    bool wasConnected = m_videoConnected;
    m_videoConnected = false;
    m_videoReceiveBuffer.clear();
    m_lastVideoFrameEmitTime = 0;
    m_videoFrameSkipCount = 0;
    if (wasConnected)
    {
        qDebug() << "TcpController: Video stream disconnected";
        emit cameraStreamToggled(false);
    }
}

void TcpController::onVideoReadyRead()
{
    static int frameCount = 0;
    m_videoReceiveBuffer.append(m_videoTcpSocket->readAll());

    while (m_videoReceiveBuffer.size() >= 8)
    {
        static const quint8 MAGIC[] = {0xAA, 0xBB, 0xCC, 0xDD};

        bool foundMagic = true;
        for (int i = 0; i < 4; ++i)
        {
            if ((quint8)m_videoReceiveBuffer.at(i) != MAGIC[i])
            {
                foundMagic = false;
                break;
            }
        }

        if (!foundMagic)
        {
            m_videoReceiveBuffer.remove(0, 1);
            continue;
        }

        quint32 jpegLen = 0;
        for (int i = 0; i < 4; ++i)
        {
            jpegLen |= (quint8)m_videoReceiveBuffer.at(4 + i) << (i * 8);
        }

        int totalSize = 8 + (int)jpegLen;
        if (m_videoReceiveBuffer.size() < totalSize)
        {
            break;
        }

        QByteArray jpegData = m_videoReceiveBuffer.mid(8, jpegLen);
        m_videoReceiveBuffer.remove(0, totalSize);

        frameCount++;
        if (frameCount <= 3 || frameCount % 60 == 0)
        {
            qDebug() << "[VIDEO-PORT-9998] Frame #" << frameCount << "size:" << jpegData.size()
                     << "from socket:" << m_videoTcpSocket->peerName()
                     << ":" << m_videoTcpSocket->peerPort();
        }

        qint64 now = QDateTime::currentMSecsSinceEpoch();
        qint64 elapsed = now - m_lastVideoFrameEmitTime;
        if (elapsed >= MinVideoFrameIntervalUs)
        {
            m_lastVideoFrameEmitTime = now;
            if (m_videoFrameSkipCount > 0)
            {
                qDebug() << "[VIDEO-PORT-9998] Recovered from" << m_videoFrameSkipCount << "skipped frames";
                m_videoFrameSkipCount = 0;
            }
            emit rawVideoFrameReceived(jpegData, CAMERA_WIDTH, CAMERA_HEIGHT);
        }
        else
        {
            m_videoFrameSkipCount++;
            if (m_videoFrameSkipCount <= 3 || m_videoFrameSkipCount % 120 == 0)
            {
                qDebug() << "[VIDEO-PORT-9998] Frame throttled (skip #" << m_videoFrameSkipCount << ")";
            }
        }
    }
}

void TcpController::onVideoErrorOccurred(QAbstractSocket::SocketError socketError)
{
    Q_UNUSED(socketError)
    qDebug() << "TcpController: Video stream error:" << m_videoTcpSocket->errorString();
}
