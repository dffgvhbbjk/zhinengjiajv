#include "md5utils.h"
#include <QCryptographicHash>

QString Md5Utils::computeMd5(const QString &input)
{
    return computeMd5(input.toUtf8());
}

QString Md5Utils::computeMd5(const QByteArray &data)
{
    return QCryptographicHash::hash(data, QCryptographicHash::Md5).toHex();
}

bool Md5Utils::verifyMd5(const QString &input, const QString &expectedMd5)
{
    return computeMd5(input).compare(expectedMd5, Qt::CaseInsensitive) == 0;
}
