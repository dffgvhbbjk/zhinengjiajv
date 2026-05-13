#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <QList>
#include <QString>
#include <QDateTime>

class SensorModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum SensorRoles
    {
        TimestampRole = Qt::UserRole + 1,
        DeviceIdRole,
        TemperatureRole,
        HumidityRole,
        LightRole,
        RainRole,
        SmokeRole,
        LpgRole,
        AirQualityRole,
        PressureRole
    };
    Q_ENUM(SensorRoles)

    static SensorModel *instance();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void load(const QString &deviceId = QString(),
                          const QDateTime &startTime = QDateTime(),
                          const QDateTime &endTime = QDateTime());
    Q_INVOKABLE void loadByDateRange(const QString &deviceId, int daysBack = 7);
    Q_INVOKABLE void loadToday(const QString &deviceId);
    Q_INVOKABLE void clear();
    Q_INVOKABLE QVariantMap get(int index) const;

signals:
    void countChanged();

private:
    explicit SensorModel(QObject *parent = nullptr);
    ~SensorModel() override;

    QList<QVariantMap> m_sensorData;
    QString m_currentDeviceId;
    QDateTime m_startTime;
    QDateTime m_endTime;

    static SensorModel *s_instance;
};
