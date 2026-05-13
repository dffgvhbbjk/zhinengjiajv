#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <QList>
#include <QString>

class SceneModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum SceneRoles
    {
        SceneIdRole = Qt::UserRole + 1,
        SceneNameRole,
        TriggerTypeRole,
        TriggerDeviceIdRole,
        TriggerSensorDataRole,
        TriggerTimeRole,
        ActionsRole,
        ActionDevicesRole,
        IsEnabledRole,
        EffectiveDateRole,
        ExpireDateRole,
        EffectiveCountRole,
        LastExecutedAtRole,
        SceneStatusRole,
        CreatedAtRole
    };
    Q_ENUM(SceneRoles)

    static SceneModel *instance();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void load();
    Q_INVOKABLE QVariantMap getSceneById(const QString &sceneId);
    Q_INVOKABLE void filterByEnabled(bool enabled);
    Q_INVOKABLE void clearFilter();

signals:
    void countChanged();

private slots:
    void onSceneAdded(const QVariantMap &scene);
    void onSceneUpdated(const QVariantMap &scene);
    void onSceneDeleted(const QString &sceneId);

private:
    explicit SceneModel(QObject *parent = nullptr);
    ~SceneModel() override;

    QList<QVariantMap> m_scenes;
    QList<QVariantMap> m_filteredScenes;
    bool m_isFiltered;
    bool m_filterEnabled;

    void applyFilter();

    static SceneModel *s_instance;
};
