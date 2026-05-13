#include "jsonutils.h"
#include "timeutils.h"
#include <QDebug>

QString JsonUtils::serialize(const QJsonObject &obj)
{
    QJsonDocument doc(obj);
    return QString::fromUtf8(doc.toJson(QJsonDocument::Compact));
}

QString JsonUtils::serialize(const QJsonArray &arr)
{
    QJsonDocument doc(arr);
    return QString::fromUtf8(doc.toJson(QJsonDocument::Compact));
}

QString JsonUtils::serialize(const QVariantMap &map)
{
    return serialize(fromVariantMap(map));
}

QJsonObject JsonUtils::deserializeObject(const QString &json)
{
    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (doc.isNull() || !doc.isObject())
    {
        qWarning() << "Invalid JSON object:" << json;
        return QJsonObject();
    }
    return doc.object();
}

QJsonArray JsonUtils::deserializeArray(const QString &json)
{
    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (doc.isNull() || !doc.isArray())
    {
        qWarning() << "Invalid JSON array:" << json;
        return QJsonArray();
    }
    return doc.array();
}

QVariantMap JsonUtils::toVariantMap(const QJsonObject &obj)
{
    return obj.toVariantMap();
}

QJsonObject JsonUtils::fromVariantMap(const QVariantMap &map)
{
    return QJsonObject::fromVariantMap(map);
}

bool JsonUtils::isValid(const QString &json)
{
    QJsonParseError error;
    QJsonDocument::fromJson(json.toUtf8(), &error);
    return error.error == QJsonParseError::NoError;
}

QString JsonUtils::getValue(const QJsonObject &obj, const QString &key, const QString &defaultValue)
{
    if (obj.contains(key) && obj.value(key).isString())
        return obj.value(key).toString();
    return defaultValue;
}

int JsonUtils::getIntValue(const QJsonObject &obj, const QString &key, int defaultValue)
{
    if (obj.contains(key) && obj.value(key).isDouble())
        return obj.value(key).toInt();
    return defaultValue;
}

double JsonUtils::getDoubleValue(const QJsonObject &obj, const QString &key, double defaultValue)
{
    if (obj.contains(key) && obj.value(key).isDouble())
        return obj.value(key).toDouble();
    return defaultValue;
}

bool JsonUtils::getBoolValue(const QJsonObject &obj, const QString &key, bool defaultValue)
{
    if (obj.contains(key) && obj.value(key).isBool())
        return obj.value(key).toBool();
    return defaultValue;
}

QJsonObject JsonUtils::createSmartHomeMessage(const QString &type, const QString &deviceId, const QVariantMap &data)
{
    QJsonObject obj;
    obj.insert(QStringLiteral("type"), type);
    obj.insert(QStringLiteral("deviceId"), deviceId);
    obj.insert(QStringLiteral("timestamp"), TimeUtils::currentTimestampMs());
    for (auto it = data.begin(); it != data.end(); ++it)
        obj.insert(it.key(), QJsonValue::fromVariant(it.value()));
    return obj;
}

bool JsonUtils::isSmartHomeMessage(const QJsonObject &obj)
{
    return obj.contains(QStringLiteral("type")) && obj.contains(QStringLiteral("deviceId"));
}

QString JsonUtils::extractDeviceId(const QJsonObject &obj)
{
    QString id = getValue(obj, QStringLiteral("deviceId"));
    if (id.isEmpty())
        id = getValue(obj, QStringLiteral("device_id"));
    return id;
}

QString JsonUtils::extractCommandId(const QJsonObject &obj)
{
    QString id = getValue(obj, QStringLiteral("commandId"));
    if (id.isEmpty())
        id = getValue(obj, QStringLiteral("command_id"));
    return id;
}

QString JsonUtils::extractMessageType(const QJsonObject &obj)
{
    return getValue(obj, QStringLiteral("type"));
}
