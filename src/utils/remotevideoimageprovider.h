#ifndef REMOTEVIDEOIMAGEPROVIDER_H
#define REMOTEVIDEOIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QImage>
#include <QMutex>
#include <QByteArray>

class RemoteVideoImageProvider : public QQuickImageProvider
{
public:
    RemoteVideoImageProvider()
        : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        Q_UNUSED(id);
        Q_UNUSED(requestedSize);

        QMutexLocker locker(&m_mutex);

        QImage img;
        if (!m_currentRawJpeg.isEmpty())
        {
            img.loadFromData(m_currentRawJpeg, "JPEG");
        }
        else if (!m_currentBase64.isEmpty())
        {
            QByteArray jpegData = QByteArray::fromBase64(m_currentBase64.toUtf8());
            img.loadFromData(jpegData, "JPEG");
        }

        if (size)
        {
            *size = img.size();
        }

        return img;
    }

    void updateFrame(const QString &base64Data)
    {
        QMutexLocker locker(&m_mutex);
        m_currentBase64 = base64Data;
        m_currentRawJpeg.clear();
    }

    void updateRawFrame(const QByteArray &jpegData)
    {
        QMutexLocker locker(&m_mutex);
        m_currentRawJpeg = jpegData;
        m_currentBase64.clear();
    }

private:
    QMutex m_mutex;
    QString m_currentBase64;
    QByteArray m_currentRawJpeg;
};

#endif // REMOTEVIDEOIMAGEPROVIDER_H
