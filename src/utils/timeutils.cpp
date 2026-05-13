#include "timeutils.h"

qint64 TimeUtils::currentTimestamp()
{
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

qint64 TimeUtils::currentTimestampMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

QString TimeUtils::timestampToDateTimeString(qint64 timestamp, const QString &format)
{
    QString fmt = format.isEmpty() ? "yyyy-MM-dd HH:mm:ss" : format;
    return QDateTime::fromSecsSinceEpoch(timestamp).toString(fmt);
}

QString TimeUtils::currentDateTimeString(const QString &format)
{
    QString fmt = format.isEmpty() ? "yyyy-MM-dd HH:mm:ss" : format;
    return QDateTime::currentDateTime().toString(fmt);
}

qint64 TimeUtils::dateTimeStringToTimestamp(const QString &dateTimeStr, const QString &format)
{
    QString fmt = format.isEmpty() ? "yyyy-MM-dd HH:mm:ss" : format;
    return QDateTime::fromString(dateTimeStr, fmt).toSecsSinceEpoch();
}

QString TimeUtils::formatDuration(qint64 milliseconds)
{
    qint64 seconds = milliseconds / 1000;
    qint64 minutes = seconds / 60;
    qint64 hours = minutes / 60;
    qint64 days = hours / 24;

    if (days > 0)
    {
        return QString("%1天%2小时")
            .arg(days)
            .arg(hours % 24);
    }
    else if (hours > 0)
    {
        return QString("%1小时%2分钟")
            .arg(hours)
            .arg(minutes % 60);
    }
    else if (minutes > 0)
    {
        return QString("%1分钟%2秒")
            .arg(minutes)
            .arg(seconds % 60);
    }
    else
    {
        return QString("%1秒").arg(seconds);
    }
}
