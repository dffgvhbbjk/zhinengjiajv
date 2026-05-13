#include "energymodel.h"
#include "databasemanager.h"

EnergyModel *EnergyModel::s_instance = nullptr;

EnergyModel::EnergyModel(QObject *parent)
    : QAbstractListModel(parent), m_totalEnergy(0.0)
{
}

EnergyModel::~EnergyModel()
{
    if (s_instance == this)
    {
        s_instance = nullptr;
    }
}

EnergyModel *EnergyModel::instance()
{
    if (!s_instance)
    {
        s_instance = new EnergyModel();
    }
    return s_instance;
}

int EnergyModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return m_energyData.count();
}

QVariant EnergyModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
    {
        return {};
    }

    const QVariantMap &data = m_energyData.at(index.row());

    switch (role)
    {
    case TimestampRole:
        return data.value("timestamp");
    case DeviceIdRole:
        return data.value("device_id");
    case PowerRole:
        return data.value("power");
    case TemperatureRole:
        return data.value("temperature");
    case HumidityRole:
        return data.value("humidity");
    default:
        return {};
    }
}

QHash<int, QByteArray> EnergyModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[TimestampRole] = "timestamp";
    roles[DeviceIdRole] = "deviceId";
    roles[PowerRole] = "power";
    roles[TemperatureRole] = "temperature";
    roles[HumidityRole] = "humidity";
    return roles;
}

void EnergyModel::load(const QString &deviceId,
                       const QDateTime &startTime,
                       const QDateTime &endTime)
{
    beginResetModel();

    QDateTime start = startTime.isValid() ? startTime : QDateTime::currentDateTime().addDays(-7);
    QDateTime end = endTime.isValid() ? endTime : QDateTime::currentDateTime();

    m_currentDeviceId = deviceId;
    m_startTime = start;
    m_endTime = end;

    QVariantList dataList;
    if (deviceId.isEmpty())
    {
        QVariantList allDevices = DatabaseManager::instance()->getAllDevices();
        for (const QVariant &dev : allDevices)
        {
            QString devId = dev.toMap().value("device_id").toString();
            QVariantList devData = DatabaseManager::instance()->getEnergyData(devId, start, end);
            for (const QVariant &item : devData)
            {
                dataList.append(item);
            }
        }
    }
    else
    {
        dataList = DatabaseManager::instance()->getEnergyData(deviceId, start, end);
    }

    m_energyData.clear();
    for (const QVariant &item : dataList)
    {
        m_energyData.append(item.toMap());
    }

    calculateTotal();
    endResetModel();
    emit countChanged();
}

void EnergyModel::loadByDateRange(const QString &deviceId, int daysBack)
{
    QDateTime end = QDateTime::currentDateTime();
    QDateTime start = end.addDays(-daysBack);
    load(deviceId, start, end);
}

void EnergyModel::loadToday(const QString &deviceId)
{
    QDateTime now = QDateTime::currentDateTime();
    QDateTime start = now;
    start.setTime(QTime(0, 0, 0));
    load(deviceId, start, now);
}

void EnergyModel::clear()
{
    beginResetModel();
    m_energyData.clear();
    m_totalEnergy = 0.0;
    endResetModel();
    emit countChanged();
    emit totalEnergyChanged(0.0);
}

QVariantMap EnergyModel::getStatistics() const
{
    if (m_energyData.isEmpty())
    {
        return {};
    }

    double minPower = m_energyData.first().value("power").toDouble();
    double maxPower = minPower;
    double totalPower = 0.0;
    double avgTemperature = 0.0;
    double avgHumidity = 0.0;
    int tempCount = 0;
    int humCount = 0;

    for (const QVariantMap &data : m_energyData)
    {
        double power = data.value("power").toDouble();
        totalPower += power;

        if (power < minPower)
            minPower = power;
        if (power > maxPower)
            maxPower = power;

        double temp = data.value("temperature").toDouble();
        if (temp != 0)
        {
            avgTemperature += temp;
            tempCount++;
        }

        double hum = data.value("humidity").toDouble();
        if (hum != 0)
        {
            avgHumidity += hum;
            humCount++;
        }
    }

    QVariantMap stats;
    stats["minPower"] = minPower;
    stats["maxPower"] = maxPower;
    stats["avgPower"] = totalPower / m_energyData.count();
    stats["totalEnergy"] = m_totalEnergy;
    stats["avgTemperature"] = tempCount > 0 ? avgTemperature / tempCount : 0;
    stats["avgHumidity"] = humCount > 0 ? avgHumidity / humCount : 0;
    return stats;
}

void EnergyModel::calculateTotal()
{
    m_totalEnergy = 0.0;

    for (const QVariantMap &data : std::as_const(m_energyData))
    {
        m_totalEnergy += data.value("power").toDouble();
    }

    emit totalEnergyChanged(m_totalEnergy);
}
