#include "alertmodel.h"
#include "databasemanager.h"
#include <QStringList>

AlertModel *AlertModel::s_instance = nullptr;

AlertModel::AlertModel(QObject *parent)
    : QAbstractListModel(parent), m_isFiltered(false), m_filterLevel(-1), m_filterUnreadOnly(false)
{
    DatabaseManager *db = DatabaseManager::instance();
    connect(db, &DatabaseManager::alertAdded, this, &AlertModel::onAlertAdded);
    connect(db, &DatabaseManager::alertUpdated, this, &AlertModel::onAlertUpdated);
    connect(db, &DatabaseManager::alertDeleted, this, &AlertModel::onAlertDeleted);
}

AlertModel::~AlertModel()
{
    if (s_instance == this)
    {
        s_instance = nullptr;
    }
}

AlertModel *AlertModel::instance()
{
    if (!s_instance)
    {
        s_instance = new AlertModel();
    }
    return s_instance;
}

int AlertModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return m_isFiltered ? m_filteredAlerts.count() : m_alerts.count();
}

QVariant AlertModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
    {
        return {};
    }

    const QVariantMap &alert = m_isFiltered ? m_filteredAlerts.at(index.row()) : m_alerts.at(index.row());

    switch (role)
    {
    case AlertIdRole:
        return alert.value("alert_id");
    case DeviceIdRole:
        return alert.value("device_id");
    case ContentRole:
        return alert.value("content");
    case LevelRole:
        return alert.value("level");
    case AlertTypeRole:
        return alert.value("alert_type");
    case IsReadRole:
        return alert.value("is_read");
    case TimestampRole:
        return alert.value("created_at");
    default:
        return {};
    }
}

QHash<int, QByteArray> AlertModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[AlertIdRole] = "alertId";
    roles[DeviceIdRole] = "deviceId";
    roles[ContentRole] = "content";
    roles[LevelRole] = "level";
    roles[AlertTypeRole] = "alertType";
    roles[IsReadRole] = "isRead";
    roles[TimestampRole] = "timestamp";
    return roles;
}

int AlertModel::unreadCount() const
{
    return calculateUnreadCount();
}

void AlertModel::load(int limit)
{
    beginResetModel();
    m_alerts.clear();

    QVariantList alertList = DatabaseManager::instance()->getAllAlerts(limit);
    for (const QVariant &alert : alertList)
    {
        m_alerts.append(alert.toMap());
    }

    m_isFiltered = false;
    m_filteredAlerts.clear();
    m_filterLevel = -1;
    m_filterType.clear();
    m_filterUnreadOnly = false;
    endResetModel();
    emit countChanged();
    emit unreadCountChanged();
}

void AlertModel::loadAll()
{
    beginResetModel();
    m_alerts.clear();

    QVariantList alertList = DatabaseManager::instance()->getAllAlerts(99999);
    for (const QVariant &alert : alertList)
    {
        m_alerts.append(alert.toMap());
    }

    m_isFiltered = false;
    m_filteredAlerts.clear();
    m_filterLevel = -1;
    m_filterType.clear();
    m_filterUnreadOnly = false;
    endResetModel();
    emit countChanged();
    emit unreadCountChanged();
}

void AlertModel::loadUnreadOnly()
{
    beginResetModel();
    m_alerts.clear();

    QVariantList alertList = DatabaseManager::instance()->getUnreadAlerts();
    for (const QVariant &alert : alertList)
    {
        m_alerts.append(alert.toMap());
    }

    m_isFiltered = false;
    m_filteredAlerts.clear();
    m_filterUnreadOnly = true;
    endResetModel();
    emit countChanged();
    emit unreadCountChanged();
}

void AlertModel::filterByLevel(int level)
{
    m_filterLevel = level;
    m_isFiltered = true;
    applyFilter();
}

void AlertModel::filterByType(const QString &type)
{
    m_filterType = type;
    m_isFiltered = true;
    applyFilter();
}

void AlertModel::clearFilter()
{
    if (!m_isFiltered && !m_filterUnreadOnly)
    {
        return;
    }

    m_isFiltered = false;
    m_filterLevel = -1;
    m_filterType.clear();
    m_filterUnreadOnly = false;
    load();
}

bool AlertModel::markAsRead(const QString &alertId)
{
    bool success = DatabaseManager::instance()->markAlertAsRead(alertId);
    if (success)
    {
        for (int i = 0; i < m_alerts.count(); ++i)
        {
            if (m_alerts.at(i).value("alert_id") == alertId)
            {
                QVariantMap alert = m_alerts[i];
                alert["is_read"] = true;
                m_alerts[i] = alert;

                QModelIndex index = createIndex(i, 0);
                emit dataChanged(index, index, {IsReadRole});

                emit unreadCountChanged();
                break;
            }
        }

        if (m_isFiltered)
        {
            applyFilter();
        }
    }
    return success;
}

bool AlertModel::markAllAsRead()
{
    bool allSuccess = true;
    for (const QVariantMap &alert : std::as_const(m_alerts))
    {
        if (!alert.value("is_read").toBool())
        {
            QString alertId = alert.value("alert_id").toString();
            if (!DatabaseManager::instance()->markAlertAsRead(alertId))
            {
                allSuccess = false;
            }
        }
    }

    if (allSuccess)
    {
        for (int i = 0; i < m_alerts.count(); ++i)
        {
            QVariantMap alert = m_alerts[i];
            if (!alert.value("is_read").toBool())
            {
                alert["is_read"] = true;
                m_alerts[i] = alert;
            }
        }
        emit dataChanged(index(0, 0), index(m_alerts.count() - 1, 0), {IsReadRole});
        emit unreadCountChanged();
    }

    return allSuccess;
}

bool AlertModel::markMultipleAsRead(const QStringList &alertIds)
{
    if (alertIds.isEmpty())
        return false;

    QSet<QString> idSet(alertIds.begin(), alertIds.end());
    bool allSuccess = true;

    for (int i = 0; i < m_alerts.count(); ++i)
    {
        if (idSet.contains(m_alerts.at(i).value("alert_id").toString())
            && !m_alerts.at(i).value("is_read").toBool())
        {
            QString alertId = m_alerts[i].value("alert_id").toString();
            if (!DatabaseManager::instance()->markAlertAsRead(alertId))
            {
                allSuccess = false;
            }
        }
    }

    if (allSuccess)
    {
        for (int i = 0; i < m_alerts.count(); ++i)
        {
            if (idSet.contains(m_alerts.at(i).value("alert_id").toString()))
            {
                QVariantMap alert = m_alerts[i];
                alert["is_read"] = true;
                m_alerts[i] = alert;
            }
        }

        if (m_isFiltered)
        {
            applyFilter();
        }
        else
        {
            emit dataChanged(index(0, 0), index(m_alerts.count() - 1, 0), {IsReadRole});
        }

        emit unreadCountChanged();
    }

    return allSuccess;
}

bool AlertModel::deleteAlert(const QString &alertId)
{
    return DatabaseManager::instance()->deleteAlert(alertId);
}

bool AlertModel::deleteMultipleAlerts(const QStringList &alertIds)
{
    if (alertIds.isEmpty())
        return false;

    bool allSuccess = true;

    for (const QString &id : alertIds)
    {
        if (!DatabaseManager::instance()->deleteAlert(id))
        {
            allSuccess = false;
        }
    }

    if (m_isFiltered)
    {
        applyFilter();
    }

    return allSuccess;
}

bool AlertModel::deleteAllAlerts()
{
    bool success = DatabaseManager::instance()->deleteAllAlerts();
    if (success)
    {
        beginResetModel();
        m_alerts.clear();
        m_filteredAlerts.clear();
        m_isFiltered = false;
        m_filterLevel = -1;
        m_filterType.clear();
        m_filterUnreadOnly = false;
        endResetModel();
        emit countChanged();
        emit unreadCountChanged();
    }
    return success;
}

void AlertModel::onAlertAdded(const QVariantMap &alert)
{
    int row = m_alerts.count();
    beginInsertRows(QModelIndex(), row, row);
    m_alerts.append(alert);
    endInsertRows();
    emit countChanged();
    emit unreadCountChanged();

    if (m_isFiltered)
    {
        applyFilter();
    }
}

void AlertModel::onAlertUpdated(const QVariantMap &alert)
{
    QString alertId = alert.value("alert_id").toString();

    for (int i = 0; i < m_alerts.count(); ++i)
    {
        if (m_alerts.at(i).value("alert_id") == alertId)
        {
            m_alerts[i] = alert;
            QModelIndex index = createIndex(i, 0);
            QList<int> changedRoles = {AlertIdRole, DeviceIdRole, ContentRole, LevelRole, AlertTypeRole, IsReadRole, TimestampRole};
            emit dataChanged(index, index, changedRoles);

            emit unreadCountChanged();

            if (m_isFiltered)
            {
                applyFilter();
            }
            return;
        }
    }
}

void AlertModel::onAlertDeleted(const QString &alertId)
{
    for (int i = 0; i < m_alerts.count(); ++i)
    {
        if (m_alerts.at(i).value("alert_id") == alertId)
        {
            beginRemoveRows(QModelIndex(), i, i);
            m_alerts.removeAt(i);
            endRemoveRows();
            emit countChanged();
            emit unreadCountChanged();

            if (m_isFiltered)
            {
                applyFilter();
            }
            return;
        }
    }
}

void AlertModel::applyFilter()
{
    beginResetModel();
    m_filteredAlerts.clear();

    for (const QVariantMap &alert : std::as_const(m_alerts))
    {
        bool match = true;

        if (m_filterUnreadOnly)
        {
            match = match && !alert.value("is_read").toBool();
        }

        if (m_filterLevel >= 0)
        {
            match = match && (alert.value("level").toInt() == m_filterLevel);
        }

        if (!m_filterType.isEmpty())
        {
            match = match && (alert.value("alert_type").toString() == m_filterType);
        }

        if (match)
        {
            m_filteredAlerts.append(alert);
        }
    }

    endResetModel();
    emit countChanged();
}

int AlertModel::calculateUnreadCount() const
{
    int count = 0;
    for (const QVariantMap &alert : m_alerts)
    {
        if (!alert.value("is_read").toBool())
        {
            count++;
        }
    }
    return count;
}
