#pragma once

#include <QString>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QVariantMap>
#include <QVariantList>

class JsonUtils
{
public:
    static QString serialize(const QJsonObject &obj);
    static QString serialize(const QJsonArray &arr);
    static QString serialize(const QVariantMap &map);
    static QJsonObject deserializeObject(const QString &json);
    static QJsonArray deserializeArray(const QString &json);
    static QVariantMap toVariantMap(const QJsonObject &obj);
    static QJsonObject fromVariantMap(const QVariantMap &map);
    static bool isValid(const QString &json);

    static QString getValue(const QJsonObject &obj, const QString &key, const QString &defaultValue = QString());
    static int getIntValue(const QJsonObject &obj, const QString &key, int defaultValue = 0);
    static double getDoubleValue(const QJsonObject &obj, const QString &key, double defaultValue = 0.0);
    static bool getBoolValue(const QJsonObject &obj, const QString &key, bool defaultValue = false);
    static QJsonObject createSmartHomeMessage(const QString &type, const QString &deviceId, const QVariantMap &data);
    static bool isSmartHomeMessage(const QJsonObject &obj);
    static QString extractDeviceId(const QJsonObject &obj);
    static QString extractCommandId(const QJsonObject &obj);
    static QString extractMessageType(const QJsonObject &obj);
};
