#pragma once

#include <QString>
#include <QDateTime>
#include <chrono>

class TimeUtils
{
public:
    static qint64 currentTimestamp();
    static qint64 currentTimestampMs();
    static QString timestampToDateTimeString(qint64 timestamp, const QString &format = QString());
    static QString currentDateTimeString(const QString &format = QString());
    static qint64 dateTimeStringToTimestamp(const QString &dateTimeStr, const QString &format = QString());
    static QString formatDuration(qint64 milliseconds);

    static QString getRelativeTimeString(qint64 timestamp);
    static qint64 getTimeDifferenceSeconds(qint64 timestamp1, qint64 timestamp2);
    static bool isToday(qint64 timestamp);
    static QString formatDate(qint64 timestamp);
    static QString formatTime(qint64 timestamp);
};
