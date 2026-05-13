#include "weatherservice.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrlQuery>
#include <QDateTime>
#include <QDebug>

WeatherService::WeatherService(QObject *parent)
    : QObject(parent), m_networkManager(new QNetworkAccessManager(this)), m_refreshTimer(new QTimer(this)), m_timeoutTimer(new QTimer(this)), m_isLoading(false), m_lastLat(0.0), m_lastLon(0.0)
{
    m_refreshTimer->setInterval(1800000);
    m_refreshTimer->setSingleShot(false);
    connect(m_refreshTimer, &QTimer::timeout, this, &WeatherService::onAutoRefresh);
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, &WeatherService::onReplyFinished);

    m_timeoutTimer->setSingleShot(true);
    m_timeoutTimer->setInterval(15000);
    connect(m_timeoutTimer, &QTimer::timeout, this, [this]()
            {
        if (m_pendingReply) {
            qWarning() << "WeatherService: 请求超时, 取消";
            m_pendingReply->abort();
            m_pendingReply = nullptr;
            setLoading(false);
        } });

    m_city = QStringLiteral("北京");
    m_cityCode = QStringLiteral("101010100");
}

WeatherService::~WeatherService()
{
    if (m_pendingReply)
    {
        m_pendingReply->abort();
        m_pendingReply = nullptr;
    }
}

void WeatherService::setCity(const QString &city)
{
    if (m_city == city)
        return;
    m_city = city;
    emit cityChanged();
}

void WeatherService::setCityCode(const QString &code)
{
    if (m_cityCode == code)
        return;
    m_cityCode = code;
}

void WeatherService::setLoading(bool loading)
{
    if (m_isLoading == loading)
        return;
    m_isLoading = loading;
    emit loadingChanged();
}

void WeatherService::fetchWeather()
{
    if (m_isLoading)
    {
        qDebug() << "WeatherService: 正在加载中, 跳过重复请求";
        return;
    }
    if (m_city.isEmpty())
    {
        qWarning() << "WeatherService: 城市名为空";
        return;
    }

    setLoading(true);

    QUrl url;
    url.setScheme(QStringLiteral("http"));
    url.setHost(QStringLiteral("wttr.in"));
    url.setPath(QStringLiteral("/") + m_city);
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("format"), QStringLiteral("j1"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "curl/7.0");

    qDebug() << "获取天气数据(城市):" << m_city << "url:" << url.toString();

    if (m_pendingReply)
        m_pendingReply->abort();
    m_pendingReply = m_networkManager->get(request);
    m_timeoutTimer->start();
}

void WeatherService::fetchWeatherByLocation(double latitude, double longitude)
{
    if (m_isLoading)
    {
        qDebug() << "WeatherService: 正在加载中, 跳过重复请求";
        return;
    }

    m_lastLat = latitude;
    m_lastLon = longitude;
    setLoading(true);

    QUrl url;
    url.setScheme(QStringLiteral("http"));
    url.setHost(QStringLiteral("wttr.in"));
    url.setPath(QStringLiteral("/%1,%2")
                    .arg(latitude, 0, 'f', 3)
                    .arg(longitude, 0, 'f', 3));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("format"), QStringLiteral("j1"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "curl/7.0");

    qDebug() << "获取天气数据(坐标):" << latitude << "," << longitude
             << "url:" << url.toString();

    if (m_pendingReply)
        m_pendingReply->abort();
    m_pendingReply = m_networkManager->get(request);
    m_timeoutTimer->start();
}

void WeatherService::onReplyFinished(QNetworkReply *reply)
{
    m_timeoutTimer->stop();

    if (reply != m_pendingReply)
    {
        reply->deleteLater();
        return;
    }
    m_pendingReply = nullptr;

    if (reply->error() != QNetworkReply::NoError)
    {
        m_errorString = reply->errorString();
        qWarning() << "WeatherService: 网络请求失败:" << m_errorString
                   << "| code:" << reply->error()
                   << "| url:" << reply->url().toString();
        reply->deleteLater();
        emit errorOccurred(m_errorString);
        setLoading(false);
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    qDebug() << "WeatherService: 收到" << data.size() << "字节响应";

    parseWeatherData(data);
    setLoading(false);
}

void WeatherService::onAutoRefresh()
{
    if (m_isLoading)
        return;
    if (m_lastLat != 0.0 || m_lastLon != 0.0)
        fetchWeatherByLocation(m_lastLat, m_lastLon);
    else
        fetchWeather();
}

void WeatherService::parseWeatherData(const QByteArray &jsonData)
{
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(jsonData, &parseError);

    if (parseError.error != QJsonParseError::NoError)
    {
        qWarning() << "WeatherService: JSON解析失败:" << parseError.errorString();
        setLoading(false);
        m_errorString = QStringLiteral("天气数据格式错误");
        emit errorOccurred(m_errorString);
        return;
    }

    QJsonObject root = doc.object();

    // ---- wttr.in 格式 ----
    if (root.contains(QStringLiteral("current_condition")))
    {
        QJsonArray conditions = root[QStringLiteral("current_condition")].toArray();
        if (conditions.isEmpty())
        {
            qWarning() << "WeatherService: current_condition 为空";
            setLoading(false);
            m_errorString = QStringLiteral("天气数据为空");
            emit errorOccurred(m_errorString);
            return;
        }

        QJsonObject current = conditions[0].toObject();

        m_temperature = QString::number(current[QStringLiteral("temp_C")].toString().toDouble(), 'f', 1);
        m_humidity = current[QStringLiteral("humidity")].toString();

        QJsonArray weatherDescArr = current[QStringLiteral("weatherDesc")].toArray();
        m_weatherText = weatherDescArr.isEmpty()
                            ? QStringLiteral("--")
                            : translateWeatherText(weatherDescArr[0].toObject()[QStringLiteral("value")].toString().trimmed());

        QString windDir = current[QStringLiteral("winddir16Point")].toString();
        QString windSpd = QString::number(current[QStringLiteral("windspeedKmph")].toString().toDouble(), 'f', 0);
        m_windDirection = windDir.isEmpty() ? QStringLiteral("--") : windDir;
        m_windSpeed = windSpd.isEmpty() ? QStringLiteral("--") : windSpd + QStringLiteral(" km/h");

        QJsonArray iconArr = current[QStringLiteral("weatherIconUrl")].toArray();
        m_icon = iconArr.isEmpty() ? QString() : iconArr[0].toObject()[QStringLiteral("value")].toString();

        int code = current[QStringLiteral("weatherCode")].toString().toInt();
        if (code > 0 && m_weatherText.isEmpty())
            m_weatherText = getWeatherTextFromCode(code);

        m_lastUpdate = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss"));

        qDebug() << "WeatherService: 天气更新(wttr.in)"
                 << "temp:" << m_temperature << "humi:" << m_humidity
                 << "text:" << m_weatherText << "wind:" << m_windDirection << m_windSpeed;
        emit weatherFetched();
        emit weatherDataChanged();
        return;
    }

    // ---- Open-Meteo 格式 (备用) ----
    if (root.contains(QStringLiteral("current_weather")))
    {
        QJsonObject current = root[QStringLiteral("current_weather")].toObject();
        m_temperature = QString::number(current[QStringLiteral("temperature")].toDouble(), 'f', 1);
        m_humidity = QStringLiteral("--");
        m_windDirection = QString::number(current[QStringLiteral("winddirection")].toDouble());
        m_windSpeed = QString::number(current[QStringLiteral("windspeed")].toDouble(), 'f', 1) + QStringLiteral(" km/h");

        int code = current[QStringLiteral("weathercode")].toInt();
        m_weatherText = getWeatherTextFromCode(code);
        m_icon.clear();

        m_lastUpdate = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss"));

        qDebug() << "WeatherService: 天气更新(Open-Meteo)"
                 << "temp:" << m_temperature << "text:" << m_weatherText;
        emit weatherFetched();
        emit weatherDataChanged();
        return;
    }

    qWarning() << "WeatherService: 无法识别的API响应格式";
    m_errorString = QStringLiteral("无法识别的天气数据格式");
    setLoading(false);
    emit errorOccurred(m_errorString);
}

QString WeatherService::getWeatherTextFromCode(int code)
{
    switch (code)
    {
    case 0:
        return QStringLiteral("晴");
    case 1:
        return QStringLiteral("少云");
    case 2:
        return QStringLiteral("多云");
    case 3:
        return QStringLiteral("阴");
    case 45:
        return QStringLiteral("轻雾");
    case 48:
        return QStringLiteral("雾凇");
    case 51:
        return QStringLiteral("小毛毛雨");
    case 53:
        return QStringLiteral("中毛毛雨");
    case 55:
        return QStringLiteral("大毛毛雨");
    case 56:
        return QStringLiteral("冻毛毛雨");
    case 57:
        return QStringLiteral("大冻毛毛雨");
    case 61:
        return QStringLiteral("小雨");
    case 63:
        return QStringLiteral("中雨");
    case 65:
        return QStringLiteral("大雨");
    case 66:
        return QStringLiteral("冻雨(轻)");
    case 67:
        return QStringLiteral("冻雨(重)");
    case 71:
        return QStringLiteral("小雪");
    case 73:
        return QStringLiteral("中雪");
    case 75:
        return QStringLiteral("大雪");
    case 77:
        return QStringLiteral("雪粒");
    case 80:
        return QStringLiteral("阵雨(轻)");
    case 81:
        return QStringLiteral("阵雨(中)");
    case 82:
        return QStringLiteral("阵雨(大)");
    case 85:
        return QStringLiteral("阵雪(轻)");
    case 86:
        return QStringLiteral("阵雪(大)");
    case 95:
        return QStringLiteral("雷暴");
    case 96:
        return QStringLiteral("冰雹(轻)");
    case 99:
        return QStringLiteral("冰雹(大)");
    default:
        return QStringLiteral("未知");
    }
}

QString WeatherService::translateWeatherText(const QString &englishText)
{
    QString lower = englishText.toLower().trimmed();

    if (lower.contains(QStringLiteral("clear")) || lower.contains(QStringLiteral("sunny")))
        return QStringLiteral("晴");
    if (lower.contains(QStringLiteral("partly cloudy")))
        return QStringLiteral("多云");
    if (lower.contains(QStringLiteral("cloudy")) || lower.contains(QStringLiteral("overcast")))
        return QStringLiteral("阴");
    if (lower.contains(QStringLiteral("light rain")) || lower.contains(QStringLiteral("drizzle")))
        return QStringLiteral("小雨");
    if (lower.contains(QStringLiteral("moderate rain")))
        return QStringLiteral("中雨");
    if (lower.contains(QStringLiteral("heavy rain")))
        return QStringLiteral("大雨");
    if (lower.contains(QStringLiteral("thunder")))
        return QStringLiteral("雷阵雨");
    if (lower.contains(QStringLiteral("snow")) || lower.contains(QStringLiteral("ice")))
        return QStringLiteral("雪");
    if (lower.contains(QStringLiteral("fog")) || lower.contains(QStringLiteral("mist")))
        return QStringLiteral("雾");
    if (lower.contains(QStringLiteral("haze")) || lower.contains(QStringLiteral("smoke")))
        return QStringLiteral("霾");
    if (lower.contains(QStringLiteral("patchy rain")))
        return QStringLiteral("阵雨");

    return englishText;
}