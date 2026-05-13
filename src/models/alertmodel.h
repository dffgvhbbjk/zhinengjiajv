#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <QList>
#include <QString>
#include <QDateTime>

class AlertModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)

public:
    enum AlertRoles
    {
        AlertIdRole = Qt::UserRole + 1,
        DeviceIdRole,
        ContentRole,
        LevelRole,
        AlertTypeRole,
        IsReadRole,
        TimestampRole
    };
    Q_ENUM(AlertRoles)

    static AlertModel *instance();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int unreadCount() const;

    Q_INVOKABLE void load(int limit = 100);
    Q_INVOKABLE void loadAll();
    Q_INVOKABLE void loadUnreadOnly();
    Q_INVOKABLE void filterByLevel(int level);
    Q_INVOKABLE void filterByType(const QString &type);
    Q_INVOKABLE void clearFilter();
    Q_INVOKABLE bool markAsRead(const QString &alertId);
    Q_INVOKABLE bool markMultipleAsRead(const QStringList &alertIds);
    Q_INVOKABLE bool markAllAsRead();
    Q_INVOKABLE bool deleteAlert(const QString &alertId);
    Q_INVOKABLE bool deleteMultipleAlerts(const QStringList &alertIds);
    Q_INVOKABLE bool deleteAllAlerts();

signals:
    void countChanged();
    void unreadCountChanged();

private slots:
    void onAlertAdded(const QVariantMap &alert);
    void onAlertUpdated(const QVariantMap &alert);
    void onAlertDeleted(const QString &alertId);

private:
    explicit AlertModel(QObject *parent = nullptr);
    ~AlertModel() override;

    QList<QVariantMap> m_alerts;
    QList<QVariantMap> m_filteredAlerts;
    bool m_isFiltered;
    int m_filterLevel;
    QString m_filterType;
    bool m_filterUnreadOnly;

    void applyFilter();
    int calculateUnreadCount() const;

    static AlertModel *s_instance;
};
