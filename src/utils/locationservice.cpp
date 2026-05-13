#include "locationservice.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QDebug>

LocationService::LocationService(QObject *parent)
    : QObject(parent), m_networkManager(new QNetworkAccessManager(this)), m_timeoutTimer(new QTimer(this)), m_latitude(39.9042), m_longitude(116.4074), m_city("北京"), m_cityCode("101010100"), m_isLocating(false)
{
    m_timeoutTimer->setSingleShot(true);
    m_timeoutTimer->setInterval(8000);
    connect(m_timeoutTimer, &QTimer::timeout, this, &LocationService::onTimeout);
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, &LocationService::onReplyFinished);

    m_cityList = {
        QVariantMap{{"name", "北京"}, {"code", "101010100"}, {"lat", 39.9042}, {"lon", 116.4074}},
        QVariantMap{{"name", "上海"}, {"code", "101020100"}, {"lat", 31.2304}, {"lon", 121.4737}},
        QVariantMap{{"name", "广州"}, {"code", "101280101"}, {"lat", 23.1291}, {"lon", 113.2644}},
        QVariantMap{{"name", "深圳"}, {"code", "101280601"}, {"lat", 22.5431}, {"lon", 114.0579}},
        QVariantMap{{"name", "杭州"}, {"code", "101210101"}, {"lat", 30.2741}, {"lon", 120.1551}},
        QVariantMap{{"name", "南京"}, {"code", "101190101"}, {"lat", 32.0603}, {"lon", 118.7969}},
        QVariantMap{{"name", "成都"}, {"code", "101270101"}, {"lat", 30.5728}, {"lon", 104.0668}},
        QVariantMap{{"name", "重庆"}, {"code", "101040100"}, {"lat", 29.5630}, {"lon", 106.5516}},
        QVariantMap{{"name", "武汉"}, {"code", "101200101"}, {"lat", 30.5928}, {"lon", 114.3055}},
        QVariantMap{{"name", "西安"}, {"code", "101110101"}, {"lat", 34.3416}, {"lon", 108.9398}},
        QVariantMap{{"name", "天津"}, {"code", "101030100"}, {"lat", 39.3434}, {"lon", 117.3616}},
        QVariantMap{{"name", "苏州"}, {"code", "101190401"}, {"lat", 31.2989}, {"lon", 120.5853}},
        QVariantMap{{"name", "长沙"}, {"code", "101250101"}, {"lat", 28.2282}, {"lon", 112.9388}},
        QVariantMap{{"name", "郑州"}, {"code", "101180101"}, {"lat", 34.7466}, {"lon", 113.6253}},
        QVariantMap{{"name", "青岛"}, {"code", "101120201"}, {"lat", 36.0671}, {"lon", 120.3826}},
        QVariantMap{{"name", "大连"}, {"code", "101070201"}, {"lat", 38.9140}, {"lon", 121.6147}},
        QVariantMap{{"name", "厦门"}, {"code", "101230201"}, {"lat", 24.4798}, {"lon", 118.0894}},
        QVariantMap{{"name", "昆明"}, {"code", "101290101"}, {"lat", 25.0406}, {"lon", 102.7125}},
        QVariantMap{{"name", "济南"}, {"code", "101120101"}, {"lat", 36.6512}, {"lon", 117.1209}},
        QVariantMap{{"name", "合肥"}, {"code", "101220101"}, {"lat", 31.8206}, {"lon", 117.2272}},
        QVariantMap{{"name", "哈尔滨"}, {"code", "101050101"}, {"lat", 45.8038}, {"lon", 126.5350}},
        QVariantMap{{"name", "沈阳"}, {"code", "101070101"}, {"lat", 41.8057}, {"lon", 123.4315}},
        QVariantMap{{"name", "长春"}, {"code", "101060101"}, {"lat", 43.8171}, {"lon", 125.3235}},
        QVariantMap{{"name", "石家庄"}, {"code", "101090101"}, {"lat", 38.0428}, {"lon", 114.5149}},
        QVariantMap{{"name", "太原"}, {"code", "101100101"}, {"lat", 37.8706}, {"lon", 112.5489}},
        QVariantMap{{"name", "呼和浩特"}, {"code", "101080101"}, {"lat", 40.8424}, {"lon", 111.7490}},
        QVariantMap{{"name", "兰州"}, {"code", "101160101"}, {"lat", 36.0611}, {"lon", 103.8343}},
        QVariantMap{{"name", "西宁"}, {"code", "101150101"}, {"lat", 36.6171}, {"lon", 101.7782}},
        QVariantMap{{"name", "银川"}, {"code", "101170101"}, {"lat", 38.4872}, {"lon", 106.2309}},
        QVariantMap{{"name", "乌鲁木齐"}, {"code", "101130101"}, {"lat", 43.8256}, {"lon", 87.6168}},
        QVariantMap{{"name", "拉萨"}, {"code", "101140101"}, {"lat", 29.6500}, {"lon", 91.1000}},
        QVariantMap{{"name", "南宁"}, {"code", "101300101"}, {"lat", 22.8170}, {"lon", 108.3665}},
        QVariantMap{{"name", "贵阳"}, {"code", "101260101"}, {"lat", 26.6470}, {"lon", 106.6302}},
        QVariantMap{{"name", "海口"}, {"code", "101310101"}, {"lat", 20.0440}, {"lon", 110.1999}},
        QVariantMap{{"name", "福州"}, {"code", "101230101"}, {"lat", 26.0745}, {"lon", 119.2965}},
        QVariantMap{{"name", "南昌"}, {"code", "101240101"}, {"lat", 28.6820}, {"lon", 115.8579}},
        QVariantMap{{"name", "无锡"}, {"code", "101190201"}, {"lat", 31.4910}, {"lon", 120.3119}},
        QVariantMap{{"name", "宁波"}, {"code", "101210401"}, {"lat", 29.8683}, {"lon", 121.5440}},
        QVariantMap{{"name", "佛山"}, {"code", "101280800"}, {"lat", 23.0218}, {"lon", 113.1219}},
        QVariantMap{{"name", "东莞"}, {"code", "101281601"}, {"lat", 23.0208}, {"lon", 113.7518}},
        QVariantMap{{"name", "珠海"}, {"code", "101280701"}, {"lat", 22.2707}, {"lon", 113.5767}},
        QVariantMap{{"name", "惠州"}, {"code", "101280301"}, {"lat", 23.1107}, {"lon", 114.4157}},
        QVariantMap{{"name", "中山"}, {"code", "101281701"}, {"lat", 22.5159}, {"lon", 113.3926}},
        QVariantMap{{"name", "江门"}, {"code", "101281101"}, {"lat", 22.5786}, {"lon", 113.0816}},
        QVariantMap{{"name", "肇庆"}, {"code", "101280901"}, {"lat", 23.0469}, {"lon", 112.4650}},
        QVariantMap{{"name", "汕头"}, {"code", "101280501"}, {"lat", 23.3541}, {"lon", 116.6820}},
        QVariantMap{{"name", "湛江"}, {"code", "101281001"}, {"lat", 21.2707}, {"lon", 110.3594}},
        QVariantMap{{"name", "温州"}, {"code", "101210701"}, {"lat", 27.9938}, {"lon", 120.6994}},
        QVariantMap{{"name", "绍兴"}, {"code", "101210501"}, {"lat", 30.0297}, {"lon", 120.5802}},
        QVariantMap{{"name", "嘉兴"}, {"code", "101210301"}, {"lat", 30.7710}, {"lon", 120.7555}},
        QVariantMap{{"name", "金华"}, {"code", "101210901"}, {"lat", 29.0781}, {"lon", 119.6521}},
        QVariantMap{{"name", "台州"}, {"code", "101210601"}, {"lat", 28.6561}, {"lon", 121.4206}},
        QVariantMap{{"name", "常州"}, {"code", "101191101"}, {"lat", 31.8101}, {"lon", 119.9741}},
        QVariantMap{{"name", "南通"}, {"code", "101190501"}, {"lat", 31.9796}, {"lon", 120.8937}},
        QVariantMap{{"name", "徐州"}, {"code", "101190801"}, {"lat", 34.2058}, {"lon", 117.2841}},
        QVariantMap{{"name", "扬州"}, {"code", "101190601"}, {"lat", 32.3942}, {"lon", 119.4129}},
        QVariantMap{{"name", "镇江"}, {"code", "101190301"}, {"lat", 32.1896}, {"lon", 119.4250}},
        QVariantMap{{"name", "盐城"}, {"code", "101190701"}, {"lat", 33.3495}, {"lon", 120.1616}},
        QVariantMap{{"name", "泰州"}, {"code", "101191201"}, {"lat", 32.4555}, {"lon", 119.9255}},
        QVariantMap{{"name", "淮安"}, {"code", "101190901"}, {"lat", 33.5511}, {"lon", 119.0215}},
        QVariantMap{{"name", "连云港"}, {"code", "101191001"}, {"lat", 34.5967}, {"lon", 119.2216}},
        QVariantMap{{"name", "芜湖"}, {"code", "101220301"}, {"lat", 31.3525}, {"lon", 118.4329}},
        QVariantMap{{"name", "蚌埠"}, {"code", "101220201"}, {"lat", 32.9163}, {"lon", 117.3895}},
        QVariantMap{{"name", "安庆"}, {"code", "101220601"}, {"lat", 30.5429}, {"lon", 117.0636}},
        QVariantMap{{"name", "烟台"}, {"code", "101120501"}, {"lat", 37.4645}, {"lon", 121.4479}},
        QVariantMap{{"name", "威海"}, {"code", "101121301"}, {"lat", 37.5131}, {"lon", 122.1204}},
        QVariantMap{{"name", "潍坊"}, {"code", "101120601"}, {"lat", 36.7068}, {"lon", 119.1618}},
        QVariantMap{{"name", "淄博"}, {"code", "101120301"}, {"lat", 36.8131}, {"lon", 118.0548}},
        QVariantMap{{"name", "临沂"}, {"code", "101120901"}, {"lat", 35.1047}, {"lon", 118.3565}},
        QVariantMap{{"name", "洛阳"}, {"code", "101180901"}, {"lat", 34.6181}, {"lon", 112.4536}},
        QVariantMap{{"name", "南阳"}, {"code", "101180701"}, {"lat", 32.9908}, {"lon", 112.5285}},
        QVariantMap{{"name", "开封"}, {"code", "101180801"}, {"lat", 34.7972}, {"lon", 114.3073}},
        QVariantMap{{"name", "新乡"}, {"code", "101180301"}, {"lat", 35.3030}, {"lon", 113.9268}},
        QVariantMap{{"name", "许昌"}, {"code", "101180401"}, {"lat", 34.0357}, {"lon", 113.8523}},
        QVariantMap{{"name", "平顶山"}, {"code", "101180501"}, {"lat", 33.7661}, {"lon", 113.1926}},
        QVariantMap{{"name", "信阳"}, {"code", "101180601"}, {"lat", 32.1251}, {"lon", 114.0688}},
        QVariantMap{{"name", "驻马店"}, {"code", "101181601"}, {"lat", 32.9780}, {"lon", 114.0228}},
        QVariantMap{{"name", "周口"}, {"code", "101181401"}, {"lat", 33.6258}, {"lon", 114.6970}},
        QVariantMap{{"name", "商丘"}, {"code", "101181001"}, {"lat", 34.4142}, {"lon", 115.6564}},
        QVariantMap{{"name", "安阳"}, {"code", "101180201"}, {"lat", 36.0977}, {"lon", 114.3924}},
        QVariantMap{{"name", "焦作"}, {"code", "101181101"}, {"lat", 35.2156}, {"lon", 113.2418}},
        QVariantMap{{"name", "濮阳"}, {"code", "101181301"}, {"lat", 35.7618}, {"lon", 115.0293}},
        QVariantMap{{"name", "漯河"}, {"code", "101181501"}, {"lat", 33.5814}, {"lon", 114.0168}},
        QVariantMap{{"name", "三门峡"}, {"code", "101181701"}, {"lat", 34.7726}, {"lon", 111.2003}},
        QVariantMap{{"name", "宜昌"}, {"code", "101200901"}, {"lat", 30.6908}, {"lon", 111.2864}},
        QVariantMap{{"name", "襄阳"}, {"code", "101200201"}, {"lat", 32.0090}, {"lon", 112.1224}},
        QVariantMap{{"name", "荆州"}, {"code", "101200801"}, {"lat", 30.3348}, {"lon", 112.2407}},
        QVariantMap{{"name", "黄石"}, {"code", "101200601"}, {"lat", 30.1995}, {"lon", 115.0389}},
        QVariantMap{{"name", "十堰"}, {"code", "101201001"}, {"lat", 32.6292}, {"lon", 110.7980}},
        QVariantMap{{"name", "孝感"}, {"code", "101200401"}, {"lat", 30.9174}, {"lon", 113.9169}},
        QVariantMap{{"name", "湘潭"}, {"code", "101250201"}, {"lat", 27.8297}, {"lon", 112.9441}},
        QVariantMap{{"name", "株洲"}, {"code", "101250301"}, {"lat", 27.8275}, {"lon", 113.1339}},
        QVariantMap{{"name", "衡阳"}, {"code", "101250401"}, {"lat", 26.8934}, {"lon", 112.5720}},
        QVariantMap{{"name", "岳阳"}, {"code", "101251001"}, {"lat", 29.3571}, {"lon", 113.1292}},
        QVariantMap{{"name", "常德"}, {"code", "101250601"}, {"lat", 29.0317}, {"lon", 111.6985}},
        QVariantMap{{"name", "郴州"}, {"code", "101250501"}, {"lat", 25.7705}, {"lon", 113.0149}},
        QVariantMap{{"name", "绵阳"}, {"code", "101270401"}, {"lat", 31.4675}, {"lon", 104.6786}},
        QVariantMap{{"name", "德阳"}, {"code", "101272001"}, {"lat", 31.1270}, {"lon", 104.3979}},
        QVariantMap{{"name", "宜宾"}, {"code", "101271101"}, {"lat", 28.7513}, {"lon", 104.6433}},
        QVariantMap{{"name", "南充"}, {"code", "101270501"}, {"lat", 30.8378}, {"lon", 106.1107}},
        QVariantMap{{"name", "泸州"}, {"code", "101271001"}, {"lat", 28.8718}, {"lon", 105.4423}},
        QVariantMap{{"name", "达州"}, {"code", "101270601"}, {"lat", 31.2086}, {"lon", 107.4678}},
        QVariantMap{{"name", "乐山"}, {"code", "101271401"}, {"lat", 29.5521}, {"lon", 103.7656}},
        QVariantMap{{"name", "遵义"}, {"code", "101260201"}, {"lat", 27.7213}, {"lon", 106.9272}},
        QVariantMap{{"name", "桂林"}, {"code", "101300501"}, {"lat", 25.2736}, {"lon", 110.2900}},
        QVariantMap{{"name", "柳州"}, {"code", "101300301"}, {"lat", 24.3254}, {"lon", 109.4155}},
        QVariantMap{{"name", "泉州"}, {"code", "101230501"}, {"lat", 24.8741}, {"lon", 118.6759}},
        QVariantMap{{"name", "漳州"}, {"code", "101230601"}, {"lat", 24.5135}, {"lon", 117.6473}},
        QVariantMap{{"name", "莆田"}, {"code", "101230401"}, {"lat", 25.4540}, {"lon", 119.0077}},
        QVariantMap{{"name", "吉林"}, {"code", "101060201"}, {"lat", 43.8378}, {"lon", 126.5496}},
        QVariantMap{{"name", "大庆"}, {"code", "101050901"}, {"lat", 46.5907}, {"lon", 125.1030}},
        QVariantMap{{"name", "齐齐哈尔"}, {"code", "101050201"}, {"lat", 47.3540}, {"lon", 123.9182}},
        QVariantMap{{"name", "秦皇岛"}, {"code", "101091101"}, {"lat", 39.9355}, {"lon", 119.5996}},
        QVariantMap{{"name", "保定"}, {"code", "101090201"}, {"lat", 38.8738}, {"lon", 115.4648}},
        QVariantMap{{"name", "唐山"}, {"code", "101090501"}, {"lat", 39.6305}, {"lon", 118.1802}},
        QVariantMap{{"name", "邯郸"}, {"code", "101091001"}, {"lat", 36.6256}, {"lon", 114.5390}},
        QVariantMap{{"name", "包头"}, {"code", "101080201"}, {"lat", 40.6582}, {"lon", 109.8402}},
        QVariantMap{{"name", "鄂尔多斯"}, {"code", "101080701"}, {"lat", 39.6083}, {"lon", 109.7809}},
        QVariantMap{{"name", "三亚"}, {"code", "101310201"}, {"lat", 18.2528}, {"lon", 109.5120}},
        QVariantMap{{"name", "北海"}, {"code", "101301301"}, {"lat", 21.4813}, {"lon", 109.1201}},
        QVariantMap{{"name", "丽江"}, {"code", "101291401"}, {"lat", 26.8754}, {"lon", 100.2296}},
        QVariantMap{{"name", "大理"}, {"code", "101290201"}, {"lat", 25.6065}, {"lon", 100.2676}},
        QVariantMap{{"name", "曲靖"}, {"code", "101290401"}, {"lat", 25.4900}, {"lon", 103.7978}},
        QVariantMap{{"name", "咸阳"}, {"code", "101110200"}, {"lat", 34.3293}, {"lon", 108.7089}},
        QVariantMap{{"name", "宝鸡"}, {"code", "101110901"}, {"lat", 34.3619}, {"lon", 107.2379}},
        QVariantMap{{"name", "延安"}, {"code", "101110300"}, {"lat", 36.5852}, {"lon", 109.4897}},
        QVariantMap{{"name", "汉中"}, {"code", "101110801"}, {"lat", 33.0676}, {"lon", 107.0238}}};
}

void LocationService::locate()
{
    if (m_isLocating)
        return;

    setLocating(true);

    QUrl url("https://api.map.baidu.com/location/ip");
    QUrlQuery query;
    query.addQueryItem("ak", "veBBJZxVZhg7unBOtJkkXNUXNIVBxjyJ");
    query.addQueryItem("coor", "bd09ll");
    url.setQuery(query);

    QNetworkRequest request(url);
    m_networkManager->get(request);

    m_timeoutTimer->start();

    qDebug() << "开始 IP 定位 (百度)...";
}

void LocationService::onReplyFinished(QNetworkReply *reply)
{
    m_timeoutTimer->stop();

    if (reply->error() != QNetworkReply::NoError)
    {
        qWarning() << "百度定位失败:" << reply->errorString();
        reply->deleteLater();
        setLocating(false);
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);

    if (parseError.error != QJsonParseError::NoError)
    {
        qWarning() << "JSON解析失败:" << parseError.errorString();
        setLocating(false);
        return;
    }

    QJsonObject root = doc.object();
    if (root["status"].toInt() != 0)
    {
        qWarning() << "百度定位失败 status:" << root["status"].toInt();
        setLocating(false);
        return;
    }

    QJsonObject content = root["content"].toObject();
    QJsonObject addrDetail = content["address_detail"].toObject();
    QJsonObject point = content["point"].toObject();

    QString cityName = addrDetail["city"].toString();
    double lat = point["y"].toString().toDouble();
    double lon = point["x"].toString().toDouble();

    setLocating(false);
    processLocation(lat, lon, cityName);
}

void LocationService::onTimeout()
{
    if (m_isLocating)
    {
        setLocating(false);
        qWarning() << "定位超时";
    }
}

void LocationService::selectCity(const QString &cityName)
{
    for (const QVariant &item : m_cityList)
    {
        QVariantMap city = item.toMap();
        if (city["name"].toString() == cityName)
        {
            updateLocation(cityName, city["lat"].toDouble(), city["lon"].toDouble(), city["code"].toString());
            return;
        }
    }
    qWarning() << "未找到城市:" << cityName;
}

void LocationService::selectCityByIndex(int index)
{
    if (index < 0 || index >= m_cityList.size())
        return;

    QVariantMap city = m_cityList[index].toMap();
    updateLocation(city["name"].toString(), city["lat"].toDouble(), city["lon"].toDouble(), city["code"].toString());
}

void LocationService::setLocating(bool locating)
{
    if (m_isLocating == locating)
        return;
    m_isLocating = locating;
    emit locatingChanged();
}

void LocationService::updateLocation(const QString &cityName, double lat, double lon, const QString &code)
{
    m_city = cityName;
    m_latitude = lat;
    m_longitude = lon;
    m_cityCode = code;
    emit locationChanged();

    qDebug() << "切换到城市:" << cityName << lat << lon << code;
}

void LocationService::processLocation(double lat, double lon, const QString &cityName)
{
    QString cn = cityName;

    cn.remove(QRegularExpression("[市地区]$"));
    cn.remove(QRegularExpression(" Shi$"));
    cn.remove(QRegularExpression(" Qu$"));

    qDebug() << "IP定位坐标:" << lat << "," << lon << "城市:" << cn;

    for (const QVariant &item : std::as_const(m_cityList))
    {
        QVariantMap cityData = item.toMap();
        QString knownName = cityData["name"].toString();
        if (knownName == cn || cn.contains(knownName) || knownName.contains(cn))
        {
            updateLocation(knownName, cityData["lat"].toDouble(),
                           cityData["lon"].toDouble(), cityData["code"].toString());
            qDebug() << "定位成功(城市名匹配):" << knownName;
            return;
        }
    }

    qWarning() << "城市名未在列表中:" << cn;
}
