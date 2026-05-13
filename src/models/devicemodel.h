#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <QList>
#include <QString>

class DeviceModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QVariantList allDevices READ allDevices NOTIFY countChanged)

public:
    enum DeviceRoles
    {
        DeviceIdRole = Qt::UserRole + 1,
        DeviceNameRole,
        DeviceTypeRole,
        RoomRole,
        IpRole,
        PortRole,
        StatusRole,
        LastOnlineTimeRole
    };
    Q_ENUM(DeviceRoles)

    static DeviceModel *instance();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void load();
    Q_INVOKABLE QVariantMap getDeviceById(const QString &deviceId);
    Q_INVOKABLE QString deviceIdAt(int index) const;
    Q_INVOKABLE void filterByRoom(const QString &room);
    Q_INVOKABLE void filterByType(const QString &type);
    Q_INVOKABLE void filterByStatus(bool online);
    Q_INVOKABLE void clearFilter();
    Q_INVOKABLE void clearStatusFilter();
    Q_INVOKABLE void search(const QString &keyword);
    Q_INVOKABLE bool deleteMultipleDevices(const QStringList &deviceIds);
    Q_INVOKABLE bool deleteAllDevices();
    Q_INVOKABLE QVariantList getSensorDevices() const;

    QVariantList allDevices() const;

signals:
    void countChanged();

private slots:
    void onDeviceAdded(const QVariantMap &device);
    void onDeviceUpdated(const QVariantMap &device);
    void onDeviceDeleted(const QString &deviceId);

private:
    explicit DeviceModel(QObject *parent = nullptr);
    ~DeviceModel() override;

    QList<QVariantMap> m_devices;
    QList<QVariantMap> m_filteredDevices;
    QString m_searchKeyword;
    QString m_filterRoom;
    QString m_filterType;
    bool m_filterOnline;
    bool m_hasStatusFilter;
    bool m_isFiltered;

    void applyAllFilters();

    static DeviceModel *s_instance;
};
