#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>
#include <QVariantList>

class LocationService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double latitude READ latitude NOTIFY locationChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY locationChanged)
    Q_PROPERTY(QString city READ city NOTIFY locationChanged)
    Q_PROPERTY(QString cityCode READ cityCode NOTIFY locationChanged)
    Q_PROPERTY(bool isLocating READ isLocating NOTIFY locatingChanged)
    Q_PROPERTY(QVariantList cityList READ cityList CONSTANT)

public:
    explicit LocationService(QObject *parent = nullptr);

    Q_INVOKABLE void locate();
    Q_INVOKABLE void selectCity(const QString &cityName);
    Q_INVOKABLE void selectCityByIndex(int index);

    double latitude() const { return m_latitude; }
    double longitude() const { return m_longitude; }
    QString city() const { return m_city; }
    QString cityCode() const { return m_cityCode; }
    bool isLocating() const { return m_isLocating; }
    QVariantList cityList() const { return m_cityList; }

signals:
    void locationChanged();
    void locatingChanged();

private slots:
    void onReplyFinished(QNetworkReply *reply);
    void onTimeout();

private:
    void setLocating(bool locating);
    void updateLocation(const QString &cityName, double lat, double lon, const QString &code);
    void processLocation(double lat, double lon, const QString &cityName);

    QNetworkAccessManager *m_networkManager;
    QTimer *m_timeoutTimer;
    double m_latitude;
    double m_longitude;
    QString m_city;
    QString m_cityCode;
    bool m_isLocating;
    QVariantList m_cityList;
};
