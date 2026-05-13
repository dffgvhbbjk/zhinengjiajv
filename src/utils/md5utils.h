#pragma once

#include <QString>
#include <QByteArray>

class Md5Utils
{
public:
    static QString computeMd5(const QString &input);
    static QString computeMd5(const QByteArray &data);
    static bool verifyMd5(const QString &input, const QString &expectedMd5);
};
