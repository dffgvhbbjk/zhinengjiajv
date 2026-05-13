#include "devicemodel.h"
#include "databasemanager.h"

DeviceModel *DeviceModel::s_instance = nullptr;

DeviceModel::DeviceModel(QObject *parent)
    : QAbstractListModel(parent), m_isFiltered(false), m_filterOnline(true), m_hasStatusFilter(false)
{
    DatabaseManager *db = DatabaseManager::instance();
    connect(db, &DatabaseManager::deviceAdded, this, &DeviceModel::onDeviceAdded);
    connect(db, &DatabaseManager::deviceUpdated, this, &DeviceModel::onDeviceUpdated);
    connect(db, &DatabaseManager::deviceDeleted, this, &DeviceModel::onDeviceDeleted);
}

DeviceModel::~DeviceModel()
{
    if (s_instance == this)
        s_instance = nullptr;
}

DeviceModel *DeviceModel::instance()
{
    if (!s_instance)
        s_instance = new DeviceModel();
    return s_instance;
}

int DeviceModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_isFiltered ? m_filteredDevices.count() : m_devices.count();
}

QVariant DeviceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
        return {};

    const QVariantMap &device = m_isFiltered ? m_filteredDevices.at(index.row()) : m_devices.at(index.row());

    switch (role)
    {
    case DeviceIdRole:   return device.value("device_id");
    case DeviceNameRole: return device.value("device_name");
    case DeviceTypeRole: return device.value("device_type");
    case RoomRole:       return device.value("room");
    case IpRole:         return device.value("ip");
    case PortRole:       return device.value("tcp_port");
    case StatusRole:     return device.value("is_online");
    case LastOnlineTimeRole: return device.value("last_online_time");
    default:             return {};
    }
}

QHash<int, QByteArray> DeviceModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[DeviceIdRole]   = "deviceId";
    roles[DeviceNameRole] = "deviceName";
    roles[DeviceTypeRole] = "deviceType";
    roles[RoomRole]       = "room";
    roles[IpRole]         = "ip";
    roles[PortRole]       = "port";
    roles[StatusRole]     = "status";
    roles[LastOnlineTimeRole] = "lastOnlineTime";
    return roles;
}

void DeviceModel::load()
{
    beginResetModel();
    QVariantList dataList = DatabaseManager::instance()->getAllDevices();
    m_devices.clear();
    for (const QVariant &item : dataList)
        m_devices.append(item.toMap());
    m_isFiltered = false;
    m_filteredDevices.clear();
    m_searchKeyword.clear();
    m_filterRoom.clear();
    m_filterType.clear();
    m_hasStatusFilter = false;
    endResetModel();
    emit countChanged();
}

QVariantMap DeviceModel::getDeviceById(const QString &deviceId)
{
    return DatabaseManager::instance()->getDevice(deviceId);
}

QString DeviceModel::deviceIdAt(int index) const
{
    if (index >= 0 && index < rowCount())
    {
        if (m_isFiltered)
            return m_filteredDevices.at(index).value("device_id").toString();
        return m_devices.at(index).value("device_id").toString();
    }
    return QString();
}

QVariantList DeviceModel::allDevices() const
{
    QVariantList result;
    for (const QMap<QString, QVariant> &device : m_devices)
        result.append(QVariant::fromValue(device));
    return result;
}

void DeviceModel::filterByRoom(const QString &room)
{
    if (m_filterRoom == room)
        return;
    m_filterRoom = room;
    applyAllFilters();
}

void DeviceModel::filterByType(const QString &type)
{
    if (m_filterType == type)
        return;
    m_filterType = type;
    applyAllFilters();
}

void DeviceModel::filterByStatus(bool online)
{
    if (m_filterOnline == online && m_hasStatusFilter)
        return;
    m_filterOnline = online;
    m_hasStatusFilter = true;
    applyAllFilters();
}

void DeviceModel::search(const QString &keyword)
{
    m_searchKeyword = keyword.trimmed();
    applyAllFilters();
}

void DeviceModel::clearFilter()
{
    if (!m_isFiltered
        && m_searchKeyword.isEmpty()
        && m_filterRoom.isEmpty()
        && m_filterType.isEmpty()
        && !m_hasStatusFilter)
        return;

    m_searchKeyword.clear();
    m_filterRoom.clear();
    m_filterType.clear();
    m_hasStatusFilter = false;
    applyAllFilters();
}

void DeviceModel::clearStatusFilter()
{
    if (!m_hasStatusFilter)
        return;
    m_hasStatusFilter = false;
    applyAllFilters();
}

bool DeviceModel::deleteMultipleDevices(const QStringList &deviceIds)
{
    return DatabaseManager::instance()->deleteMultipleDevices(deviceIds);
}

bool DeviceModel::deleteAllDevices()
{
    return DatabaseManager::instance()->deleteAllDevices();
}

QVariantList DeviceModel::getSensorDevices() const
{
    QStringList sensorTypeKeywords = {"sensor", "环境", "temperature", "humidity", "传感器", "监测", "gateway"};
    QVariantList result;
    for (const QVariantMap &device : m_devices) {
        QString dtype = device.value("device_type").toString().toLower();
        QString dname = device.value("device_name").toString().toLower();
        bool isSensor = false;
        for (const QString &kw : sensorTypeKeywords) {
            if (dtype.contains(kw) || dname.contains(kw)) {
                isSensor = true;
                break;
            }
        }
        if (isSensor)
            result.append(QVariant::fromValue(device));
    }
    return result;
}

void DeviceModel::onDeviceAdded(const QVariantMap &device)
{
    int row = m_devices.count();
    beginInsertRows(QModelIndex(), row, row);
    m_devices.append(device);
    endInsertRows();
    emit countChanged();

    if (m_isFiltered)
        applyAllFilters();
}

void DeviceModel::onDeviceUpdated(const QVariantMap &device)
{
    QString deviceId = device.value("device_id").toString();

    for (int i = 0; i < m_devices.count(); ++i)
    {
        if (m_devices.at(i).value("device_id") == deviceId)
        {
            m_devices[i] = device;
            QModelIndex index = createIndex(i, 0);
            emit dataChanged(index, index, {DeviceIdRole, DeviceNameRole, DeviceTypeRole,
                                            RoomRole, IpRole, PortRole, StatusRole, LastOnlineTimeRole});

            if (m_isFiltered)
                applyAllFilters();
            return;
        }
    }
}

void DeviceModel::onDeviceDeleted(const QString &deviceId)
{
    for (int i = 0; i < m_devices.count(); ++i)
    {
        if (m_devices.at(i).value("device_id") == deviceId)
        {
            beginRemoveRows(QModelIndex(), i, i);
            m_devices.removeAt(i);
            endRemoveRows();
            emit countChanged();

            if (m_isFiltered)
                applyAllFilters();
            return;
        }
    }
}

void DeviceModel::applyAllFilters()
{
    beginResetModel();
    m_filteredDevices.clear();

    for (const QVariantMap &device : std::as_const(m_devices))
    {
        bool match = true;
        QString name = device.value("device_name").toString();
        QString id   = device.value("device_id").toString();
        QString ip   = device.value("ip").toString();
        QString room = device.value("room").toString();
        QString type = device.value("device_type").toString();
        int online   = device.value("is_online").toInt();

        if (!m_searchKeyword.isEmpty())
        {
            QString kw = m_searchKeyword;
            match = match && (name.contains(kw, Qt::CaseInsensitive)
                           || id.contains(kw, Qt::CaseInsensitive)
                           || ip.contains(kw, Qt::CaseInsensitive)
                           || room.contains(kw, Qt::CaseInsensitive)
                           || type.contains(kw, Qt::CaseInsensitive));
        }

        if (!m_filterRoom.isEmpty())
            match = match && (room == m_filterRoom);

        if (!m_filterType.isEmpty())
            match = match && (type == m_filterType);

        if (m_hasStatusFilter)
            match = match && (online == (m_filterOnline ? 1 : 0));

        if (match)
            m_filteredDevices.append(device);
    }

    m_isFiltered = !m_searchKeyword.isEmpty() || !m_filterRoom.isEmpty()
                   || !m_filterType.isEmpty() || m_hasStatusFilter;
    endResetModel();
    emit countChanged();
}
