#ifndef VOICECONTROLLER_H
#define VOICECONTROLLER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QString>
#include <QTimer>
#include <QBuffer>

class QAudioSource;
class QTextToSpeech;
class QNetworkReply;
class DatabaseManager;

class VoiceController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isListening READ isListening NOTIFY isListeningChanged)
    Q_PROPERTY(bool isProcessing READ isProcessing NOTIFY isProcessingChanged)
    Q_PROPERTY(QString recognizedText READ recognizedText NOTIFY recognizedTextChanged)

public:
    explicit VoiceController(QObject *parent = nullptr);
    ~VoiceController() override;

    void setDatabaseManager(DatabaseManager *db);

    bool isListening() const { return m_isListening; }
    bool isProcessing() const { return m_isProcessing; }
    QString recognizedText() const { return m_recognizedText; }

    Q_INVOKABLE void startListening();
    Q_INVOKABLE void stopListening();
    Q_INVOKABLE void speak(const QString &text);

signals:
    void isListeningChanged();
    void isProcessingChanged();
    void recognizedTextChanged();
    void recognitionComplete(const QString &text);
    void recognitionFailed(const QString &error);
    void speechComplete();
    void speechFailed(const QString &error);

private slots:
    void onTokenReply();
    void onRecognitionReply();

private:
    void finishProcessing(const QString &error = QString());
    void logError(const QString &message);
    void requestAccessToken();
    void sendRecognitionRequest(const QByteArray &audioData);
    void parseBaiduResponse(const QByteArray &response);
    void loadConfig();

private:
    bool m_isListening = false;
    bool m_isProcessing = false;
    QString m_recognizedText;

    static constexpr int MaxRecordingDurationMs = 10000;

    QString m_apiKey;
    QString m_secretKey;

    QNetworkAccessManager m_networkManager;
    QString m_accessToken;
    QTimer m_tokenRefreshTimer;
    QTimer m_recordingTimer;

    QAudioSource *m_audioSource = nullptr;
    QBuffer *m_audioBuffer = nullptr;
    QTextToSpeech *m_speechSynthesizer = nullptr;

    DatabaseManager *m_databaseManager = nullptr;

    QByteArray m_pendingAudioData;
    QNetworkReply *m_tokenReply = nullptr;
    QNetworkReply *m_recognitionReply = nullptr;
};

#endif // VOICECONTROLLER_H
