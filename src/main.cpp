#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QtQml/qqml.h>
#include <QDateTime>
#include <QTimer>
#include <QtMath>
#include "communication/udpdiscoverer.h"
#include "communication/tcpcontroller.h"
#include "communication/scenetriggerengine.h"
#include "models/databasemanager.h"
#include "models/devicemodel.h"
#include "models/scenemodel.h"
#include "models/energymodel.h"
#include "models/sensormodel.h"
#include "models/alertmodel.h"
#include "utils/weatherservice.h"
#include "utils/locationservice.h"
#include "utils/networkmanager.h"
#include "utils/voicecontroller.h"
#include "utils/remotevideoimageprovider.h"

namespace Protocol
{
    constexpr quint16 UdpPort = 8888;
    constexpr quint16 TcpPort = 9999;
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    app.setApplicationName("智能家居控制系统");
    app.setOrganizationName("zhinengjiajv");
    app.setApplicationVersion("0.1.0");

    QQuickStyle::setStyle("Material");

    QQmlApplicationEngine engine;

    auto *videoProvider = new RemoteVideoImageProvider();
    engine.addImageProvider(QLatin1String("remotevideo"), videoProvider);

    auto *udpDiscoverer = new UdpDiscoverer(&engine);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "UdpDiscoverer", udpDiscoverer);

    auto *tcpController = new TcpController(&engine);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "TcpController", tcpController);

    QObject::connect(tcpController, &TcpController::videoFrameReceived,
                     [videoProvider](const QString &base64Data, int width, int height, qint64 timestamp)
                     {
        Q_UNUSED(width);
        Q_UNUSED(height);
        Q_UNUSED(timestamp);
        videoProvider->updateFrame(base64Data); });

    QObject::connect(tcpController, &TcpController::rawVideoFrameReceived,
                     [videoProvider](const QByteArray &jpegData, int width, int height)
                     {
        Q_UNUSED(width);
        Q_UNUSED(height);
        videoProvider->updateRawFrame(jpegData); });

    auto *databaseManager = DatabaseManager::instance();
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "DatabaseManager", databaseManager);

    auto *deviceModel = DeviceModel::instance();
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "DeviceModel", deviceModel);

    auto *sceneModel = SceneModel::instance();
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "SceneModel", sceneModel);

    auto *energyModel = EnergyModel::instance();
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "EnergyModel", energyModel);

    auto *sensorModel = SensorModel::instance();
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "SensorModel", sensorModel);

    auto *alertModel = AlertModel::instance();
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "AlertModel", alertModel);

    auto *sceneTriggerEngine = SceneTriggerEngine::instance();
    sceneTriggerEngine->setTcpController(tcpController);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "SceneTriggerEngine", sceneTriggerEngine);

    QObject::connect(udpDiscoverer, &UdpDiscoverer::discoveryStarted,
                     [databaseManager]()
                     { databaseManager->addConnectionLog("[UDP] [INFO] UDP 设备发现已启动 - 端口 8888"); });

    QObject::connect(&app, &QGuiApplication::aboutToQuit,
                     [databaseManager]()
                     { databaseManager->addConnectionLog("[SYSTEM] [INFO] 智能家居 UI 关闭 - " + QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss")); });

    auto *weatherService = new WeatherService(&engine);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "WeatherService", weatherService);

    auto *locationService = new LocationService(&engine);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "LocationService", locationService);

    auto *networkManager = new NetworkManager(&engine);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "NetworkManager", networkManager);

    auto *voiceController = new VoiceController(&engine);
    voiceController->setDatabaseManager(databaseManager);
    qmlRegisterSingletonInstance("zhinengjiajv", 1, 0, "VoiceController", voiceController);

    tcpController->setDatabaseManager(databaseManager);

    QObject::connect(networkManager, &NetworkManager::deviceFound,
                     tcpController, [tcpController](const QString &ip, const QString &name, const QString &type, int tcpPort)
                     {
        Q_UNUSED(name);
        Q_UNUSED(type);
        if (!tcpController->isConnected())
        {
            tcpController->connectToDevice(ip, tcpPort);
        } });

    QObject::connect(locationService, &LocationService::locationChanged,
                     weatherService, [weatherService, locationService]()
                     {
        weatherService->setCity(locationService->city());
        weatherService->setCityCode(locationService->cityCode());
        weatherService->fetchWeatherByLocation(locationService->latitude(), locationService->longitude()); });

    QTimer::singleShot(3000, weatherService, [weatherService, locationService]()
                       {
        if (qFuzzyIsNull(locationService->latitude()) && qFuzzyIsNull(locationService->longitude()))
            return;
        weatherService->fetchWeatherByLocation(locationService->latitude(), locationService->longitude()); });

    QObject::connect(databaseManager, &DatabaseManager::databaseOpened,
                     deviceModel, [deviceModel]()
                     { deviceModel->load(); });
    QObject::connect(databaseManager, &DatabaseManager::databaseOpened,
                     sceneModel, [sceneModel]()
                     { sceneModel->load(); });
    QObject::connect(databaseManager, &DatabaseManager::databaseOpened,
                     alertModel, [alertModel]()
                     { alertModel->load(); });
    QObject::connect(databaseManager, &DatabaseManager::databaseOpened,
                     sensorModel, [sensorModel]()
                     { sensorModel->clear(); });

    QObject::connect(udpDiscoverer, &UdpDiscoverer::deviceDiscovered,
                     tcpController, [tcpController, databaseManager, deviceModel](const QString &deviceId, const QString &deviceName, const QString &deviceType, const QString &ip, int tcpPort, const QString &firmwareVersion)
                     {
        Q_UNUSED(deviceName);
        Q_UNUSED(deviceType);
        Q_UNUSED(firmwareVersion);

        if (!tcpController->isConnected())
        {
            tcpController->connectToDevice(ip, tcpPort);
        }

        QVariantMap existing = databaseManager->getDevice(deviceId);
        if (existing.isEmpty())
        {
            databaseManager->addDevice(deviceId, deviceName, deviceType, ip, tcpPort, firmwareVersion);
            deviceModel->load();
        }
        else
        {
            databaseManager->setDeviceOnline(deviceId, true);
        } });

    QObject::connect(udpDiscoverer, &UdpDiscoverer::dataReceived,
                     databaseManager, [databaseManager](const QString &deviceId, const QVariantMap &data)
                     {
        double temperature = data.value(QStringLiteral("temperature")).toDouble();
        double humidity = data.value(QStringLiteral("humidity")).toDouble();
        double light = data.value(QStringLiteral("light")).toDouble();
        double rain = data.value(QStringLiteral("rain")).toDouble();
        double smoke = data.value(QStringLiteral("smoke")).toDouble();
        double lpg = data.value(QStringLiteral("lpg")).toDouble();
        double air_quality = data.value(QStringLiteral("air_quality")).toDouble();
        double pressure = data.value(QStringLiteral("pressure")).toDouble();

        databaseManager->addSensorData(deviceId, temperature, humidity,
                                       light, rain, smoke, lpg, air_quality, pressure); });

    QObject::connect(udpDiscoverer, &UdpDiscoverer::sensorFieldUpdated,
                     databaseManager, [databaseManager](const QString &deviceId, const QString &field, double value)
                     { databaseManager->updateSensorField(deviceId, field, value); });

    QObject::connect(udpDiscoverer, &UdpDiscoverer::deviceOffline,
                     databaseManager, [databaseManager](const QString &deviceId)
                     { databaseManager->setDeviceOnline(deviceId, false); });

    QObject::connect(tcpController, &TcpController::alertReceived,
                     databaseManager, [databaseManager](const QString &alertId, const QString &deviceId, const QString &content, int level)
                     { databaseManager->addAlert(alertId, deviceId, content, level, "tcp_alert"); });

    QObject::connect(udpDiscoverer, &UdpDiscoverer::dataReceived,
                     sceneTriggerEngine, [sceneTriggerEngine](const QString &deviceId, const QVariantMap &data)
                     { sceneTriggerEngine->onSensorDataReceived(deviceId, data); });

    QObject::connect(tcpController, &TcpController::deviceControlled,
                     sceneTriggerEngine, [sceneTriggerEngine](const QString &deviceId, const QString &action)
                     { sceneTriggerEngine->onDeviceStateChanged(deviceId, action); });

    QObject::connect(weatherService, &WeatherService::weatherFetched,
                     sceneTriggerEngine, [sceneTriggerEngine, weatherService]()
                     {
        QVariantMap weatherData;
        weatherData.insert("temperature", weatherService->temperature().toDouble());
        weatherData.insert("humidity", weatherService->humidity().toDouble());
        weatherData.insert("city", weatherService->city());
        weatherData.insert("icon", weatherService->icon());
        sceneTriggerEngine->onWeatherUpdated(weatherData); });

    QObject::connect(databaseManager, &DatabaseManager::databaseOpened,
                     sceneTriggerEngine, [sceneTriggerEngine]()
                     { sceneTriggerEngine->start(); });

    if (databaseManager->initialize())
    {
        databaseManager->addConnectionLog("[SYSTEM] [INFO] 智能家居 UI 启动 - 版本 " + app.applicationVersion() + " - " + QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss"));
        databaseManager->addConnectionLog("[SYSTEM] [INFO] 数据库初始化成功 - 路径: " + databaseManager->databasePath());
        databaseManager->setAllDevicesOffline();
    }

    QObject::connect(&app, &QGuiApplication::aboutToQuit,
                     sceneTriggerEngine, [sceneTriggerEngine]()
                     { sceneTriggerEngine->stop(); });

    QObject::connect(voiceController, &VoiceController::recognitionComplete,
                     tcpController, [voiceController, tcpController, databaseManager, sensorModel, energyModel, weatherService, sceneTriggerEngine](const QString &text)
                     {
        QString lowerText = text.toLower().trimmed();

        auto findDeviceByName = [&](const QString &typeKeyword) -> QVariantMap
        {
            QVariantList devices = databaseManager->getAllDevices();
            QVariantMap bestMatch;
            int bestScore = 0;
            for (const QVariant &dev : devices)
            {
                QVariantMap devMap = dev.toMap();
                QString devType = devMap.value("device_type").toString().toLower();
                QString devName = devMap.value("device_name").toString();
                QString devRoom = devMap.value("room").toString();

                if (!devType.contains(typeKeyword, Qt::CaseInsensitive))
                    continue;

                int score = 0;
                if (lowerText.contains(devName))
                    score += 100;
                if (devRoom.isEmpty() == false && lowerText.contains(devRoom))
                    score += 50;
                QString roomAndName = devRoom + devName;
                if (lowerText.contains(roomAndName))
                    score += 30;

                if (score > bestScore)
                {
                    bestScore = score;
                    bestMatch = devMap;
                }
            }
            return bestMatch;
        };

        auto controlDevice = [&](const QVariantMap &devMap, const QString &action, int cmdIndex)
        {
            QString cmdId = "voice_" + QString::number(QDateTime::currentMSecsSinceEpoch()) + "_" + QString::number(cmdIndex);
            tcpController->sendControlCommand(cmdId, devMap.value("device_id").toString(), action);
        };

        auto controlAllOfType = [&](const QString &typeKeyword, const QString &action) -> int
        {
            QVariantList devices = databaseManager->getAllDevices();
            int cmdIndex = 0;
            int count = 0;
            for (const QVariant &dev : devices)
            {
                QVariantMap devMap = dev.toMap();
                if (devMap.value("device_type").toString().contains(typeKeyword, Qt::CaseInsensitive))
                {
                    controlDevice(devMap, action, cmdIndex++);
                    count++;
                }
            }
            return count;
        };

        if (lowerText.contains("天气"))
        {
            QString wt = weatherService->weatherText();
            QString temp = weatherService->temperature();
            QString hum = weatherService->humidity();
            QString city = weatherService->city();

            if (wt.isEmpty() && temp.isEmpty())
            {
                voiceController->speak("天气数据暂未获取，请稍后再试");
            }
            else
            {
                QString info = QString("当前%1天气：%2，温度%3°C，湿度%4")
                    .arg(city.isEmpty() ? "" : city)
                    .arg(wt.isEmpty() ? "未知" : wt)
                    .arg(temp.isEmpty() ? "未知" : temp)
                    .arg(hum.isEmpty() ? "未知" : hum);
                voiceController->speak(info);
            }
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("温度") || lowerText.contains("湿度") || lowerText.contains("传感器"))
        {
            QString sensorDeviceId;
            QVariantList allDevices = databaseManager->getAllDevices();
            for (const QVariant &dev : allDevices)
            {
                QVariantMap devMap = dev.toMap();
                QString type = devMap.value("device_type").toString().toLower();
                if (type.contains(QStringLiteral("传感器")) || type.contains(QStringLiteral("sensor"))
                    || type.contains(QStringLiteral("温度")) || type.contains(QStringLiteral("temperature"))
                    || type.contains(QStringLiteral("湿度")) || type.contains(QStringLiteral("humidity"))
                    || type.contains(QStringLiteral("光照")) || type.contains(QStringLiteral("light"))
                    || type.contains(QStringLiteral("空气")) || type.contains(QStringLiteral("air")))
                {
                    sensorDeviceId = devMap.value("device_id").toString();
                    break;
                }
            }
            if (!sensorDeviceId.isEmpty())
                sensorModel->loadToday(sensorDeviceId);
            int count = sensorModel->rowCount();
            if (count > 0)
            {
                QVariantMap latest = sensorModel->get(count - 1);
                double tempVal = latest.value("temperature").toDouble();
                double humVal = latest.value("humidity").toDouble();
                double lightVal = latest.value("light").toDouble();
                double airVal = latest.value("air_quality").toDouble();

                QStringList parts;
                if (tempVal != 0 || lowerText.contains("温度"))
                    parts.append(QString("温度%1°C").arg(tempVal, 0, 'f', 1));
                if (humVal != 0 || lowerText.contains("湿度"))
                    parts.append(QString("湿度%1%").arg(humVal, 0, 'f', 1));
                if (lightVal != 0)
                    parts.append(QString("光照%1勒克斯").arg(lightVal, 0, 'f', 1));
                if (airVal != 0)
                    parts.append(QString("空气质量%1").arg(airVal, 0, 'f', 1));

                if (!parts.isEmpty())
                    voiceController->speak("最新传感器数据：" + parts.join("，"));
                else
                    voiceController->speak("暂未获取到传感器数据");
            }
            else
            {
                voiceController->speak("暂未获取到传感器数据");
            }
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("能耗") || lowerText.contains("用电") || lowerText.contains("电量"))
        {
            energyModel->load();
            QVariantMap stats = energyModel->getStatistics();
            double totalEnergy = energyModel->totalEnergy();
            int dataCount = energyModel->rowCount();

            if (dataCount > 0)
            {
                voiceController->speak(QString("近期总能耗%1千瓦时，共%2条记录").arg(totalEnergy, 0, 'f', 2).arg(dataCount));
            }
            else
            {
                voiceController->speak("暂未获取到能耗数据");
            }
            Q_UNUSED(stats);
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("开灯") || lowerText.contains("打开灯"))
        {
            QVariantMap matched = findDeviceByName("light");
            if (!matched.isEmpty())
            {
                controlDevice(matched, "turn_on", 0);
                QString name = matched.value("device_name").toString();
                voiceController->speak("已打开" + name);
            }
            else
            {
                int count = controlAllOfType("light", "turn_on");
                if (count == 0)
                    voiceController->speak("未找到灯光设备");
                else
                    voiceController->speak(QString("已为您打开%1个灯光设备").arg(count));
            }
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("关灯") || lowerText.contains("关闭灯"))
        {
            QVariantMap matched = findDeviceByName("light");
            if (!matched.isEmpty())
            {
                controlDevice(matched, "turn_off", 0);
                QString name = matched.value("device_name").toString();
                voiceController->speak("已关闭" + name);
            }
            else
            {
                int count = controlAllOfType("light", "turn_off");
                if (count == 0)
                    voiceController->speak("未找到灯光设备");
                else
                    voiceController->speak(QString("已为您关闭%1个灯光设备").arg(count));
            }
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("开空调") || lowerText.contains("打开空调"))
        {
            QVariantMap matched = findDeviceByName("air");
            if (matched.isEmpty())
                matched = findDeviceByName("ac");
            if (!matched.isEmpty())
            {
                controlDevice(matched, "turn_on", 0);
                QString name = matched.value("device_name").toString();
                voiceController->speak("已打开" + name);
            }
            else
            {
                int count = controlAllOfType("air", "turn_on");
                if (count == 0)
                    count = controlAllOfType("ac", "turn_on");
                if (count == 0)
                    voiceController->speak("未找到空调设备");
                else
                    voiceController->speak(QString("已为您打开%1个空调设备").arg(count));
            }
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("关空调") || lowerText.contains("关闭空调"))
        {
            QVariantMap matched = findDeviceByName("air");
            if (matched.isEmpty())
                matched = findDeviceByName("ac");
            if (!matched.isEmpty())
            {
                controlDevice(matched, "turn_off", 0);
                QString name = matched.value("device_name").toString();
                voiceController->speak("已关闭" + name);
            }
            else
            {
                int count = controlAllOfType("air", "turn_off");
                if (count == 0)
                    count = controlAllOfType("ac", "turn_off");
                if (count == 0)
                    voiceController->speak("未找到空调设备");
                else
                    voiceController->speak(QString("已为您关闭%1个空调设备").arg(count));
            }
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("打开所有设备") || lowerText.contains("全部打开"))
        {
            QVariantList devices = databaseManager->getAllDevices();
            int cmdIndex = 0;
            for (const QVariant &dev : devices)
            {
                QVariantMap devMap = dev.toMap();
                controlDevice(devMap, "turn_on", cmdIndex++);
            }
            voiceController->speak("已为您打开所有设备");
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("关闭所有设备") || lowerText.contains("全部关闭"))
        {
            QVariantList devices = databaseManager->getAllDevices();
            int cmdIndex = 0;
            for (const QVariant &dev : devices)
            {
                QVariantMap devMap = dev.toMap();
                controlDevice(devMap, "turn_off", cmdIndex++);
            }
            voiceController->speak("已为您关闭所有设备");
            tcpController->sendVoiceText(text, true);
        }
        else if (lowerText.contains("打开场景") || lowerText.contains("执行场景"))
        {
            QVariantList scenes = databaseManager->getAllScenes();
            for (const QVariant &scene : scenes)
            {
                QVariantMap sceneMap = scene.toMap();
                if (lowerText.contains(sceneMap.value("scene_name").toString()))
                {
                    QString sceneId = sceneMap.value("scene_id").toString();
                    QString sceneName = sceneMap.value("scene_name").toString();
                    sceneTriggerEngine->triggerScene(sceneId);
                    voiceController->speak("正在执行场景：" + sceneName);
                    tcpController->sendVoiceText(text, true);
                    return;
                }
            }
            voiceController->speak("未找到匹配的场景");
            tcpController->sendVoiceText(text, false);
        }
        else
        {
            voiceController->speak("收到消息：" + text);
            tcpController->sendVoiceText(text, false);
        } });

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []()
        { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    const QUrl url(QStringLiteral("qrc:/qt/qml/zhinengjiajv/qml/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl)
        {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);
    engine.load(url);

    qDebug() << "Smart Home Application Started";

    return app.exec();
}
