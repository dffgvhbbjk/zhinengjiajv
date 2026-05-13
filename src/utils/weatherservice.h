#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>

class WeatherService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString city READ city WRITE setCity NOTIFY cityChanged)
    Q_PROPERTY(QString weatherText READ weatherText NOTIFY weatherDataChanged)
    Q_PROPERTY(QString temperature READ temperature NOTIFY weatherDataChanged)
    Q_PROPERTY(QString humidity READ humidity NOTIFY weatherDataChanged)
    Q_PROPERTY(QString windDirection READ windDirection NOTIFY weatherDataChanged)
    Q_PROPERTY(QString windSpeed READ windSpeed NOTIFY weatherDataChanged)
    Q_PROPERTY(QString icon READ icon NOTIFY weatherDataChanged)
    Q_PROPERTY(QString lastUpdate READ lastUpdate NOTIFY weatherDataChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorOccurred)

public:
    explicit WeatherService(QObject *parent = nullptr);
    ~WeatherService() override;

    QString city() const { return m_city; }
    void setCity(const QString &city);
    void setCityCode(const QString &code);

    QString weatherText() const { return m_weatherText; }
    QString temperature() const { return m_temperature; }
    QString humidity() const { return m_humidity; }
    QString windDirection() const { return m_windDirection; }
    QString windSpeed() const { return m_windSpeed; }
    QString icon() const { return m_icon; }
    QString lastUpdate() const { return m_lastUpdate; }
    bool isLoading() const { return m_isLoading; }
    QString errorString() const { return m_errorString; }

    Q_INVOKABLE void fetchWeather();
    Q_INVOKABLE void fetchWeatherByLocation(double latitude, double longitude);

signals:
    void cityChanged();
    void weatherDataChanged();
    void loadingChanged();
    void errorOccurred(const QString &error);
    void weatherFetched();

private slots:
    void onReplyFinished(QNetworkReply *reply);
    void onAutoRefresh();

private:
    void parseWeatherData(const QByteArray &jsonData);
    void setLoading(bool loading);
    QString getWeatherTextFromCode(int code);
    QString translateWeatherText(const QString &englishText);

    QNetworkAccessManager *m_networkManager;
    QTimer *m_refreshTimer;
    QTimer *m_timeoutTimer;
    QNetworkReply *m_pendingReply = nullptr;
    QString m_apiKey;
    QString m_city;
    QString m_cityCode;
    double m_lastLat = 0.0;
    double m_lastLon = 0.0;
    QString m_weatherText;
    QString m_temperature;
    QString m_humidity;
    QString m_windDirection;
    QString m_windSpeed;
    QString m_icon;
    QString m_lastUpdate;
    bool m_isLoading;
    QString m_errorString;
};
