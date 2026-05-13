#include "voicecontroller.h"
#include "../models/databasemanager.h"
#include <QAudioSource>
#include <QAudioDevice>
#include <QAudioFormat>
#include <QMediaDevices>
#include <QIODevice>
#include <QBuffer>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrl>
#include <QTextToSpeech>
#include <QFile>
#include <QCoreApplication>
#include <QDir>

VoiceController::VoiceController(QObject *parent)
    : QObject(parent), m_audioBuffer(new QBuffer(this)), m_speechSynthesizer(new QTextToSpeech(this))
{
    loadConfig();

    m_tokenRefreshTimer.setSingleShot(true);
    m_tokenRefreshTimer.setInterval(3600000);
    connect(&m_tokenRefreshTimer, &QTimer::timeout, this, [this]()
            { requestAccessToken(); });
    requestAccessToken();

    m_recordingTimer.setSingleShot(true);
    m_recordingTimer.setInterval(MaxRecordingDurationMs);
    connect(&m_recordingTimer, &QTimer::timeout, this, [this]()
            {
        if (m_isListening)
        {
            qDebug() << "[VoiceController] Recording timeout reached, auto-stopping";
            stopListening();
        } });

    connect(m_speechSynthesizer, &QTextToSpeech::stateChanged, this, [this](QTextToSpeech::State state)
            {
        if (state == QTextToSpeech::Ready)
            emit speechComplete();
        else if (state == QTextToSpeech::Error)
            emit speechFailed(QStringLiteral("语音合成失败")); });
}

VoiceController::~VoiceController()
{
    stopListening();

    if (m_tokenReply)
    {
        m_tokenReply->abort();
        m_tokenReply->deleteLater();
        m_tokenReply = nullptr;
    }
    if (m_recognitionReply)
    {
        m_recognitionReply->abort();
        m_recognitionReply->deleteLater();
        m_recognitionReply = nullptr;
    }
}

void VoiceController::setDatabaseManager(DatabaseManager *db)
{
    m_databaseManager = db;
}

void VoiceController::loadConfig()
{
    QString configPath = QCoreApplication::applicationDirPath() + QStringLiteral("/voice_config.json");

    QFile configFile(configPath);
    if (!configFile.open(QIODevice::ReadOnly))
    {
        qDebug() << "[VoiceController] Config file not found at" << configPath << ", using defaults";
        logError(QStringLiteral("[VOICE] [INFO] 未找到语音配置文件，使用默认API密钥"));
        return;
    }

    QByteArray data = configFile.readAll();
    configFile.close();

    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError)
    {
        qWarning() << "[VoiceController] Config JSON parse error:" << parseError.errorString();
        return;
    }

    QJsonObject obj = doc.object();
    QString fileApiKey = obj.value(QStringLiteral("baidu_api_key")).toString();
    QString fileSecretKey = obj.value(QStringLiteral("baidu_secret_key")).toString();

    if (!fileApiKey.isEmpty() && !fileSecretKey.isEmpty())
    {
        m_apiKey = fileApiKey;
        m_secretKey = fileSecretKey;
        qDebug() << "[VoiceController] Config loaded from" << configPath;
        logError(QStringLiteral("[VOICE] [INFO] 语音配置文件已加载: ") + configPath);
    }
    else
    {
        qWarning() << "[VoiceController] Config file missing keys — voice recognition will not function";
    }
}

void VoiceController::startListening()
{
    if (m_isListening || m_isProcessing)
        return;

    m_recognizedText.clear();
    emit recognizedTextChanged();

    m_audioBuffer->buffer().clear();
    m_audioBuffer->open(QIODevice::WriteOnly);

    QAudioFormat format;
    format.setSampleRate(16000);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Int16);

    QAudioDevice inputDevice = QMediaDevices::defaultAudioInput();
    if (inputDevice.isNull())
    {
        emit recognitionFailed(QStringLiteral("未找到音频输入设备"));
        return;
    }

    m_audioSource = new QAudioSource(inputDevice, format, this);
    m_audioSource->start(m_audioBuffer);

    m_isListening = true;
    emit isListeningChanged();
    m_recordingTimer.start();
}

void VoiceController::stopListening()
{
    if (!m_isListening)
        return;

    if (m_audioSource)
    {
        m_audioSource->stop();
        delete m_audioSource;
        m_audioSource = nullptr;
    }

    m_isListening = false;
    emit isListeningChanged();
    m_isProcessing = true;
    emit isProcessingChanged();
    m_recordingTimer.stop();

    QByteArray audioData = m_audioBuffer->data();
    m_audioBuffer->close();

    qDebug() << "[VoiceController] Audio data size:" << audioData.size() << "bytes";
    qDebug() << "[VoiceController] Estimated duration:" << (audioData.size() / 32000.0) << "seconds";

    if (audioData.isEmpty())
    {
        finishProcessing(QStringLiteral("未检测到音频输入"));
        return;
    }

    int zeroCount = 0;
    int checkSamples = qMin(audioData.size() / 2, 1000);
    const qint16 *samples = reinterpret_cast<const qint16 *>(audioData.constData());
    for (int i = 0; i < checkSamples; ++i)
    {
        if (samples[i] == 0)
            zeroCount++;
    }
    double zeroRatio = static_cast<double>(zeroCount) / checkSamples;
    qDebug() << "[VoiceController] Zero samples ratio:" << (zeroRatio * 100) << "%";

    if (zeroRatio > 0.95)
    {
        logError(QStringLiteral("[VOICE] [ERROR] 录音中未检测到声音"));
        finishProcessing(QStringLiteral("录音中未检测到声音"));
        return;
    }

    if (m_apiKey.isEmpty() || m_secretKey.isEmpty())
    {
        logError(QStringLiteral("[VOICE] [ERROR] 语音API密钥未配置"));
        finishProcessing(QStringLiteral("语音API密钥未配置"));
        return;
    }

    m_pendingAudioData = audioData;

    if (m_accessToken.isEmpty())
    {
        requestAccessToken();
    }
    else
    {
        sendRecognitionRequest(m_pendingAudioData);
    }
}

void VoiceController::speak(const QString &text)
{
    if (m_speechSynthesizer)
        m_speechSynthesizer->say(text);
}

void VoiceController::finishProcessing(const QString &error)
{
    m_isProcessing = false;
    emit isProcessingChanged();
    if (!error.isEmpty())
        emit recognitionFailed(error);
}

void VoiceController::logError(const QString &message)
{
    if (m_databaseManager)
        m_databaseManager->addConnectionLog(message);
}

void VoiceController::requestAccessToken()
{
    if (m_apiKey.isEmpty() || m_secretKey.isEmpty())
        return;

    QString url = QStringLiteral("https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=%1&client_secret=%2")
        .arg(m_apiKey, m_secretKey);

    QNetworkRequest request{QUrl(url)};
    if (m_tokenReply)
    {
        m_tokenReply->abort();
        m_tokenReply->deleteLater();
        m_tokenReply = nullptr;
    }
    m_tokenReply = m_networkManager.get(request);
    connect(m_tokenReply, &QNetworkReply::finished, this, &VoiceController::onTokenReply);
}

void VoiceController::onTokenReply()
{
    if (!m_tokenReply)
        return;

    if (m_tokenReply->error() == QNetworkReply::NoError)
    {
        QJsonDocument doc = QJsonDocument::fromJson(m_tokenReply->readAll());
        if (doc.isObject())
        {
            m_accessToken = doc.object().value(QStringLiteral("access_token")).toString();
            if (!m_accessToken.isEmpty())
            {
                m_tokenRefreshTimer.start();
                qDebug() << "[VoiceController] Access token obtained successfully";
            }
        }
    }

    m_tokenReply->deleteLater();
    m_tokenReply = nullptr;

    if (m_accessToken.isEmpty())
    {
        logError(QStringLiteral("[VOICE] [ERROR] 获取访问令牌失败"));
        finishProcessing(QStringLiteral("获取访问令牌失败"));
        return;
    }

    if (!m_pendingAudioData.isEmpty())
    {
        sendRecognitionRequest(m_pendingAudioData);
    }
}

void VoiceController::sendRecognitionRequest(const QByteArray &audioData)
{
    qDebug() << "[VoiceController] Sending request to Baidu Speech API...";

    QJsonObject body;
    body.insert(QStringLiteral("format"), QStringLiteral("pcm"));
    body.insert(QStringLiteral("rate"), QJsonValue(QString::number(16000)));
    body.insert(QStringLiteral("channel"), 1);
    body.insert(QStringLiteral("cuid"), QStringLiteral("qt_smarthome"));
    body.insert(QStringLiteral("token"), m_accessToken);
    body.insert(QStringLiteral("dev_pid"), 1537);
    body.insert(QStringLiteral("speech"), QString::fromUtf8(audioData.toBase64()));
    body.insert(QStringLiteral("len"), static_cast<int>(audioData.size()));

    QNetworkRequest request{QUrl(QStringLiteral("https://vop.baidu.com/server_api"))};
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    if (m_recognitionReply)
    {
        m_recognitionReply->abort();
        m_recognitionReply->deleteLater();
        m_recognitionReply = nullptr;
    }
    m_recognitionReply = m_networkManager.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    m_pendingAudioData.clear();
    connect(m_recognitionReply, &QNetworkReply::finished, this, &VoiceController::onRecognitionReply);
}

void VoiceController::onRecognitionReply()
{
    if (!m_recognitionReply)
        return;

    if (m_recognitionReply->error() != QNetworkReply::NoError)
    {
        qWarning() << "[VoiceController] Network error:" << m_recognitionReply->errorString();
        finishProcessing(m_recognitionReply->errorString());
        m_recognitionReply->deleteLater();
        m_recognitionReply = nullptr;
        return;
    }

    QByteArray response = m_recognitionReply->readAll();
    m_recognitionReply->deleteLater();
    m_recognitionReply = nullptr;

    qDebug() << "[VoiceController] API response:" << response;

    parseBaiduResponse(response);
    m_isProcessing = false;
    emit isProcessingChanged();
}

void VoiceController::parseBaiduResponse(const QByteArray &response)
{
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(response, &parseError);

    if (parseError.error != QJsonParseError::NoError)
    {
        finishProcessing(QStringLiteral("JSON解析失败"));
        return;
    }

    QJsonObject obj = doc.object();
    int errNo = obj.value(QStringLiteral("err_no")).toInt();

    if (errNo != 0)
    {
        QString errMsg = obj.value(QStringLiteral("err_msg")).toString();
        logError(QStringLiteral("[VOICE] [ERROR] 识别失败: %1 (err_no=%2)").arg(errMsg).arg(errNo));
        finishProcessing(QStringLiteral("识别失败: %1").arg(errMsg));
        return;
    }

    QJsonArray result = obj.value(QStringLiteral("result")).toArray();
    if (result.isEmpty())
    {
        logError(QStringLiteral("[VOICE] [ERROR] 未识别到有效文本"));
        finishProcessing(QStringLiteral("未识别到有效文本"));
        return;
    }

    m_recognizedText = result.at(0).toString();
    emit recognizedTextChanged();
    logError(QStringLiteral("[VOICE] [INFO] 语音识别成功: %1").arg(m_recognizedText));
    emit recognitionComplete(m_recognizedText);
}
