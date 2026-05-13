#include "sensormodel.h"
#include "databasemanager.h"
#include <QDebug>

SensorModel *SensorModel::s_instance = nullptr;

SensorModel *SensorModel::instance()
{
    if (!s_instance)
    {
        s_instance = new SensorModel();
    }
    return s_instance;
}

SensorModel::SensorModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

SensorModel::~SensorModel()
{
    if (s_instance == this)
    {
        s_instance = nullptr;
    }
}

int SensorModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_sensorData.size();
}

QVariant SensorModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_sensorData.size())
        return QVariant();

    const QVariantMap &record = m_sensorData.at(index.row());

    switch (role)
    {
        case TimestampRole:
            return record.value("timestamp").toString();
        case DeviceIdRole:
            return record.value("device_id").toString();
        case TemperatureRole:
            return record.value("temperature").toDouble();
        case HumidityRole:
            return record.value("humidity").toDouble();
        case LightRole:
            return record.value("light").toDouble();
        case RainRole:
            return record.value("rain").toDouble();
        case SmokeRole:
            return record.value("smoke").toDouble();
        case LpgRole:
            return record.value("lpg").toDouble();
        case AirQualityRole:
            return record.value("air_quality").toDouble();
        case PressureRole:
            return record.value("pressure").toDouble();
        default:
            return QVariant();
    }
}

QHash<int, QByteArray> SensorModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[TimestampRole] = "timestamp";
    roles[DeviceIdRole] = "deviceId";
    roles[TemperatureRole] = "temperature";
    roles[HumidityRole] = "humidity";
    roles[LightRole] = "light";
    roles[RainRole] = "rain";
    roles[SmokeRole] = "smoke";
    roles[LpgRole] = "lpg";
    roles[AirQualityRole] = "airQuality";
    roles[PressureRole] = "pressure";
    return roles;
}

void SensorModel::load(const QString &deviceId,
                       const QDateTime &startTime,
                       const QDateTime &endTime)
{
    qDebug() << "================ SensorModel::load() 开始 ================";
    qDebug() << "  deviceId =" << deviceId;
    qDebug() << "  startTime =" << startTime.toString("yyyy-MM-dd HH:mm:ss");
    qDebug() << "  endTime =" << endTime.toString("yyyy-MM-dd HH:mm:ss");
    
    beginResetModel();
    m_currentDeviceId = deviceId;
    m_startTime = startTime;
    m_endTime = endTime;

    if (!deviceId.isEmpty())
    {
        qDebug() << "SensorModel::load() 正在查询数据库...";
        QVariantList dataList = DatabaseManager::instance()->getEnergyData(deviceId, startTime, endTime);
        qDebug() << "SensorModel::load() 查询到" << dataList.size() << "条数据";
        
        m_sensorData.clear();
        for (const QVariant &item : dataList)
        {
            m_sensorData.append(item.toMap());
        }
        
        if (dataList.size() > 0)
        {
            qDebug() << "SensorModel::load() 第一条数据时间戳 =" << m_sensorData.first()["timestamp"];
            qDebug() << "SensorModel::load() 最后一条数据时间戳 =" << m_sensorData.last()["timestamp"];
        }
    }
    else
    {
        qDebug() << "SensorModel::load() deviceId 为空，清空数据";
        m_sensorData.clear();
    }

    endResetModel();
    qDebug() << "SensorModel::load() 完成，m_sensorData.size =" << m_sensorData.size();
    qDebug() << "================ SensorModel::load() 结束 ================";
    emit countChanged();
}

void SensorModel::loadByDateRange(const QString &deviceId, int daysBack)
{
    QDateTime endTime = QDateTime::currentDateTime();
    QDateTime startTime = endTime.addDays(-daysBack);
    load(deviceId, startTime, endTime);
}

void SensorModel::loadToday(const QString &deviceId)
{
    QDateTime now = QDateTime::currentDateTime();
    QDateTime startOfDay = now.date().startOfDay();
    load(deviceId, startOfDay, now);
}

void SensorModel::clear()
{
    beginResetModel();
    m_sensorData.clear();
    m_currentDeviceId.clear();
    endResetModel();
    emit countChanged();
}

QVariantMap SensorModel::get(int index) const
{
    if (index >= 0 && index < m_sensorData.size())
    {
        return m_sensorData.at(index);
    }
    return QVariantMap();
}
