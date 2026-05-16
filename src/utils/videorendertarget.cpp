#include "videorendertarget.h"
#include <QPainter>
#include <QBuffer>

VideoRenderTarget::VideoRenderTarget(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setPerformanceHint(QQuickPaintedItem::FastFBOResizing, true);
}

VideoRenderTarget::~VideoRenderTarget()
{
}

void VideoRenderTarget::paint(QPainter *painter)
{
    QSizeF itemSize = boundingRect().size();
    if (itemSize.isEmpty() || itemSize.width() <= 0 || itemSize.height() <= 0)
    {
        painter->fillRect(boundingRect(), QColor(10, 18, 32));
        return;
    }

    QImage frame;
    {
        QMutexLocker locker(&m_mutex);
        frame = m_currentFrame;
    }

    if (frame.isNull())
    {
        painter->fillRect(boundingRect(), QColor(10, 18, 32));
        return;
    }

    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(boundingRect(), frame);
}

void VideoRenderTarget::updateRawFrame(const QByteArray &jpegData)
{
    if (jpegData.isEmpty())
        return;

    QImage img;
    if (!img.loadFromData(jpegData, "JPEG"))
        return;

    {
        QMutexLocker locker(&m_mutex);
        m_currentFrame = img;
    }

    bool wasActive = m_active;
    m_active = true;
    if (!wasActive)
        emit activeChanged();

    emit frameReceived();
    update();
}

void VideoRenderTarget::updateBase64Frame(const QString &base64Data)
{
    if (base64Data.isEmpty())
        return;

    QByteArray jpegData = QByteArray::fromBase64(base64Data.toUtf8());
    updateRawFrame(jpegData);
}

void VideoRenderTarget::clearFrame()
{
    {
        QMutexLocker locker(&m_mutex);
        m_currentFrame = QImage();
    }
    m_active = false;
    emit activeChanged();
    update();
}