#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <QList>
#include <QString>
#include <QDateTime>

class EnergyModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(double totalEnergy READ totalEnergy NOTIFY totalEnergyChanged)

public:
    enum EnergyRoles
    {
        TimestampRole = Qt::UserRole + 1,
        DeviceIdRole,
        PowerRole,
        TemperatureRole,
        HumidityRole
    };
    Q_ENUM(EnergyRoles)

    static EnergyModel *instance();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE double totalEnergy() const { return m_totalEnergy; }

    Q_INVOKABLE void load(const QString &deviceId = QString(),
                          const QDateTime &startTime = QDateTime(),
                          const QDateTime &endTime = QDateTime());
    Q_INVOKABLE void loadByDateRange(const QString &deviceId, int daysBack = 7);
    Q_INVOKABLE void loadToday(const QString &deviceId);
    Q_INVOKABLE void clear();
    Q_INVOKABLE QVariantMap getStatistics() const;

signals:
    void countChanged();
    void totalEnergyChanged(double total);

private:
    explicit EnergyModel(QObject *parent = nullptr);
    ~EnergyModel() override;

    QList<QVariantMap> m_energyData;
    double m_totalEnergy;
    QString m_currentDeviceId;
    QDateTime m_startTime;
    QDateTime m_endTime;

    void calculateTotal();

    static EnergyModel *s_instance;
};
