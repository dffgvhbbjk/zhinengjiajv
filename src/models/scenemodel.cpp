#include "scenemodel.h"
#include "databasemanager.h"
#include <QDateTime>

SceneModel *SceneModel::s_instance = nullptr;

SceneModel::SceneModel(QObject *parent)
    : QAbstractListModel(parent), m_isFiltered(false), m_filterEnabled(false)
{
    DatabaseManager *db = DatabaseManager::instance();
    connect(db, &DatabaseManager::sceneAdded, this, &SceneModel::onSceneAdded);
    connect(db, &DatabaseManager::sceneUpdated, this, &SceneModel::onSceneUpdated);
    connect(db, &DatabaseManager::sceneDeleted, this, &SceneModel::onSceneDeleted);
}

SceneModel::~SceneModel()
{
    if (s_instance == this)
    {
        s_instance = nullptr;
    }
}

SceneModel *SceneModel::instance()
{
    if (!s_instance)
    {
        s_instance = new SceneModel();
    }
    return s_instance;
}

int SceneModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return m_isFiltered ? m_filteredScenes.count() : m_scenes.count();
}

QVariant SceneModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
    {
        return {};
    }

    const QVariantMap &scene = m_isFiltered ? m_filteredScenes.at(index.row()) : m_scenes.at(index.row());

    switch (role)
    {
    case SceneIdRole:
        return scene.value("scene_id");
    case SceneNameRole:
        return scene.value("scene_name");
    case TriggerTypeRole:
        return scene.value("trigger_type");
    case TriggerDeviceIdRole:
        return scene.value("trigger_device_id");
    case TriggerSensorDataRole:
        return scene.value("trigger_sensor_data");
    case TriggerTimeRole:
        return scene.value("trigger_time");
    case ActionsRole:
        return scene.value("actions");
    case ActionDevicesRole:
        return scene.value("action_devices");
    case IsEnabledRole:
        return scene.value("is_enabled").toBool();
    case EffectiveDateRole:
        return scene.value("effective_date");
    case ExpireDateRole:
        return scene.value("expire_date");
    case EffectiveCountRole:
        return scene.value("effective_count").toInt();
    case LastExecutedAtRole:
        return scene.value("last_executed_at");
    case SceneStatusRole:
    {
        bool enabled = scene.value("is_enabled").toBool();
        if (!enabled)
            return 0;
        
        QString effectiveDate = scene.value("effective_date").toString();
        QString expireDate = scene.value("expire_date").toString();
        QDateTime now = QDateTime::currentDateTime();
        
        if (!effectiveDate.isEmpty())
        {
            QDateTime effective = QDateTime::fromString(effectiveDate, Qt::ISODate);
            if (effective.isValid() && now < effective)
                return 1;
        }
        
        if (!expireDate.isEmpty())
        {
            QDateTime expire = QDateTime::fromString(expireDate, Qt::ISODate);
            if (expire.isValid() && now > expire)
                return 3;
        }
        
        return 2;
    }
    case CreatedAtRole:
        return scene.value("created_at");
    default:
        return {};
    }
}

QHash<int, QByteArray> SceneModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[SceneIdRole] = "sceneId";
    roles[SceneNameRole] = "sceneName";
    roles[TriggerTypeRole] = "triggerType";
    roles[TriggerDeviceIdRole] = "triggerDeviceId";
    roles[TriggerSensorDataRole] = "triggerSensorData";
    roles[TriggerTimeRole] = "triggerTime";
    roles[ActionsRole] = "actions";
    roles[ActionDevicesRole] = "actionDevices";
    roles[IsEnabledRole] = "isEnabled";
    roles[EffectiveDateRole] = "effectiveDate";
    roles[ExpireDateRole] = "expireDate";
    roles[EffectiveCountRole] = "effectiveCount";
    roles[LastExecutedAtRole] = "lastExecutedAt";
    roles[SceneStatusRole] = "sceneStatus";
    roles[CreatedAtRole] = "createdAt";
    return roles;
}

void SceneModel::load()
{
    beginResetModel();
    QVariantList dataList = DatabaseManager::instance()->getAllScenes();
    m_scenes.clear();
    for (const QVariant &item : dataList)
    {
        m_scenes.append(item.toMap());
    }
    m_isFiltered = false;
    m_filteredScenes.clear();
    m_filterEnabled = false;
    endResetModel();
    emit countChanged();
}

QVariantMap SceneModel::getSceneById(const QString &sceneId)
{
    return DatabaseManager::instance()->getScene(sceneId);
}

void SceneModel::filterByEnabled(bool enabled)
{
    m_filterEnabled = enabled;
    m_isFiltered = true;
    applyFilter();
}

void SceneModel::clearFilter()
{
    if (!m_isFiltered)
    {
        return;
    }

    beginResetModel();
    m_isFiltered = false;
    m_filteredScenes.clear();
    m_filterEnabled = false;
    endResetModel();
    emit countChanged();
}

void SceneModel::onSceneAdded(const QVariantMap &scene)
{
    int row = m_scenes.count();
    beginInsertRows(QModelIndex(), row, row);
    m_scenes.append(scene);
    endInsertRows();
    emit countChanged();

    if (m_isFiltered)
    {
        applyFilter();
    }
}

void SceneModel::onSceneUpdated(const QVariantMap &scene)
{
    QString sceneId = scene.value("scene_id").toString();

    for (int i = 0; i < m_scenes.count(); ++i)
    {
        if (m_scenes.at(i).value("scene_id") == sceneId)
        {
            m_scenes[i] = scene;
            QModelIndex index = createIndex(i, 0);
            QList<int> changedRoles = {SceneIdRole, SceneNameRole, TriggerTypeRole, TriggerDeviceIdRole,
                                       TriggerSensorDataRole, TriggerTimeRole, ActionsRole, ActionDevicesRole,
                                       IsEnabledRole, EffectiveDateRole, ExpireDateRole,
                                       EffectiveCountRole, LastExecutedAtRole, SceneStatusRole, CreatedAtRole};
            emit dataChanged(index, index, changedRoles);

            if (m_isFiltered)
            {
                applyFilter();
            }
            return;
        }
    }
}

void SceneModel::onSceneDeleted(const QString &sceneId)
{
    for (int i = 0; i < m_scenes.count(); ++i)
    {
        if (m_scenes.at(i).value("scene_id") == sceneId)
        {
            beginRemoveRows(QModelIndex(), i, i);
            m_scenes.removeAt(i);
            endRemoveRows();
            emit countChanged();

            if (m_isFiltered)
            {
                applyFilter();
            }
            return;
        }
    }
}

void SceneModel::applyFilter()
{
    beginResetModel();
    m_filteredScenes.clear();

    for (const QVariantMap &scene : std::as_const(m_scenes))
    {
        bool match = m_filterEnabled ? scene.value("is_enabled").toBool() : !scene.value("is_enabled").toBool();

        if (match)
        {
            m_filteredScenes.append(scene);
        }
    }

    endResetModel();
    emit countChanged();
}
