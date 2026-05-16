#ifndef VIDEORENDERTARGET_H
#define VIDEORENDERTARGET_H

#include <QQuickPaintedItem>
#include <QImage>
#include <QMutex>
#include <QByteArray>

class VideoRenderTarget : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)

public:
    enum FillMode
    {
        Stretch = 0,
        PreserveAspectFit = 1,
        PreserveAspectCrop = 2
    };
    Q_ENUM(FillMode)

    explicit VideoRenderTarget(QQuickItem *parent = nullptr);
    ~VideoRenderTarget() override;

    void paint(QPainter *painter) override;

    bool isActive() const { return m_active; }

public slots:
    void updateRawFrame(const QByteArray &jpegData);
    void updateBase64Frame(const QString &base64Data);
    void clearFrame();

signals:
    void activeChanged();
    void frameReceived();

private:
    QImage m_currentFrame;
    QMutex m_mutex;
    bool m_active = false;
};

#endif // VIDEORENDERTARGET_H