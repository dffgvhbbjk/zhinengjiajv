# Project Rules: 智能家居 (Smart Home) - Qt6/QML

## Project Overview

- **Project Type**: Qt6 Quick Application with QML
- **Build System**: CMake (version 3.16+)
- **Qt Version**: Qt 6.10.2
- **Compiler**: MinGW 64-bit (Qt自带)
- **IDE**: Qt Creator
- **Language**: C++20, QML
- **Qt Install Path**: `C:/QT_6/6.10.2/mingw_64/`

## Directory Structure

```
zhinengjiajv/
├── CMakeLists.txt          # Main CMake build configuration
├── src/                    # C++ source files
│   ├── main.cpp            # Application entry point
│   ├── utils/              # Utility classes
│   ├── communication/      # Network communication
│   ├── models/             # Data models
│   └── logic/              # Business logic
├── qml/                    # QML components
│   ├── main.qml            # Root QML component
│   ├── pages/              # Page components
│   └── components/         # Reusable components
├── resources/              # Images, fonts, etc.
│   ├── resources.qrc
│   ├── images/
│   └── fonts/
├── build/                  # Build output (not version controlled)
└── .qtcreator/             # Qt Creator IDE settings
```

## Build Commands

- **Configure/Build/Run**: 只能通过 Qt Creator IDE 进行（Ctrl+B 构建，Ctrl+R 运行）
- **绝对禁止**使用命令行 CMake 构建（系统 CMake 不识别 Qt 路径）
- **Target**: `appzhinengjiajv`

## CMake 规则（重要！）

### 绝对禁止的操作

- **禁止**在 CMakeLists.txt 中设置 `CMAKE_PREFIX_PATH`
- **禁止**在 CMakeLists.txt 中设置 `CMAKE_C_COMPILER` 或 `CMAKE_CXX_COMPILER`
- **禁止**在 CMakeLists.txt 中设置 `CMAKE_BUILD_TYPE`
- **禁止**修改 CMake 生成器配置
- **禁止**尝试通过命令行运行 CMake 构建

### 正确的 CMakeLists.txt 结构

```cmake
cmake_minimum_required(VERSION 3.16)

project(zhinengjiajv VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick QuickControls2 Multimedia Network Sql Graphs)

add_compile_options(
    $<$<CXX_COMPILER_ID:GNU>:-Werror=return-type>
    $<$<CXX_COMPILER_ID:GNU>:-Werror=unused-result>
    $<$<CXX_COMPILER_ID:MSVC>:/WX>
)

qt_standard_project_setup(REQUIRES 6.10)

qt_add_executable(appzhinengjiajv ...)
qt_add_qml_module(appzhinengjiajv ...)
target_link_libraries(appzhinengjiajv PRIVATE Qt6::Core Qt6::Quick ...)
```

### add_compile_options 语法

- **必须**将多个 GCC 选项分开写，不能合并到一行：
  - 正确: `$<$<CXX_COMPILER_ID:GNU>:-Werror=return-type>` + `$<$<CXX_COMPILER_ID:GNU>:-Werror=unused-result>`
  - 错误: `$<$<CXX_COMPILER_ID:GNU>:-Werror=return-type -Werror=unused-result>`

## Qt6 API 规则（重要！）

### 已弃用/已移除的 Qt5 API（Qt 6 中不可使用）

- **QNetworkConfigurationManager** - Qt 6 中已移除，使用 `QNetworkInformation` 替代
- **QNetworkSession** - Qt 6 中已移除
- **Qt Charts** - 已弃用，使用 **Qt Graphs** 替代
- **QDesktopWidget** - 使用 `QScreen` 替代
- **QRegExp** - 使用 `QRegularExpression` 替代

### Qt 6.10 推荐模块

- `Core`, `Quick`, `QuickControls2`, `Multimedia`, `Network`, `Sql`, `Graphs`

### 网络变更检测

- 不要依赖 `QNetworkConfigurationManager::configurationChanged`
- 使用定时器定期检查 `QNetworkInterface::allAddresses()` 或 `QNetworkInformation`
- 或者在离线检测定时器中一并处理

## QML 组件规则

### 存在的 QML 类型（Qt Quick Controls 2）

- 可用的基础类型: `Item`, `Rectangle`, `Text`, `Label`, `Button`, `TextField`, `ProgressBar`, `Slider`, `Switch`, `CheckBox`, `RadioButton`, `ComboBox`, `ListView`, `GridView`, `ScrollView`, `TabBar`, `TabButton`, `ToolBar`, `ToolButton`, `Drawer`, `Dialog`, `Popup`, `Menu`, `MenuItem`, `SplitView`, `StackLayout`, `SwipeView`, `Page`, `Frame`, `GroupBox`, `StackView`, `ApplicationWindow`, `Pane`

### 不存在的 QML 类型（常见错误）

- **Card** - 不存在，使用 `Rectangle` 替代
- **ChartView** - 不存在，使用 Qt Graphs 模块
- **BarSeries** - 是 Qt Charts 的，Qt Graphs 使用不同 API

### Material 颜色

- 不能直接使用 `Material.white`, `Material.Grey` 等
- 使用直接的颜色字符串: `"#ffffff"`, `"grey"`, `Material.color(Material.Grey)`

## 代码约定

### C++ 代码

- 使用 C++20 标准
- 遵循 Qt 命名规范:
  - 类名: PascalCase
  - 函数/方法: camelCase
  - 成员变量: m_camelCase
  - 信号/槽: camelCase
- 优先使用 `QString` 而非 `std::string`
- 使用现代信号/槽函数指针语法

### QML 代码

- 文件名与组件名一致（PascalCase）
- 属性使用 camelCase
- 保持 UI 逻辑在 QML，业务逻辑在 C++

## 开发指南

- 始终使用 Qt Creator IDE 进行构建和运行
- 构建失败时先 **清理** → **执行 CMake** → **重新构建**
- 修改头文件后必须重新构建（MOC 需要重新生成）
- 分离 UI (QML) 和业务逻辑 (C++)
- 使用 `Q_PROPERTY` 宏使 C++ 属性可在 QML 中绑定
- 使用 `QML_ELEMENT` 宏注册自定义 QML 类型

## 错误处理

### 遇到编译错误时的处理流程

1. 检查是否是 Qt 5 API（Qt 6 中已移除）
2. 检查是否是 QML 类型不存在
3. 清理构建目录，重新执行 CMake
4. 通过 Qt Creator 重新构建（不用命令行）

---

## C++ 常见错误规则（从实际项目中总结）

### 1. Lambda 捕获规则

- Lambda 中使用的外部变量**必须显式捕获**，不能使用未捕获的变量
- 示例：

  ```cpp
  // 错误：databaseManager 未捕获
  QObject::connect(udpDiscoverer, &UdpDiscoverer::deviceDiscovered,
                   tcpController, [tcpController](const QString &deviceId, ...) {
      databaseManager->addDevice(deviceId, ...); // Error: not captured!
  });

  // 正确：显式捕获所有使用的变量
  QObject::connect(udpDiscoverer, &UdpDiscoverer::deviceDiscovered,
                   tcpController, [tcpController, databaseManager](const QString &deviceId, ...) {
      databaseManager->addDevice(deviceId, ...);
  });
  ```

### 2. Qt 6 中 `QSqlQuery` 不可拷贝

- `QSqlQuery::QSqlQuery(const QSqlQuery&)` 在 Qt 6 中已弃用
- **不能**用 `QSqlQuery mutableQuery = query;` 方式拷贝
- 应该创建新查询对象，在内部执行SQL
- 示例：

  ```cpp
  // 错误：拷贝 QSqlQuery
  QVariantList queryToList(const QSqlQuery &query) const {
      QSqlQuery mutableQuery = query; // 弃用警告
      while (mutableQuery.next()) { ... }
  }

  // 正确：内部创建新查询
  QVariantList executeQueryToList(const QString &sql, const QVariantMap &params) const {
      QSqlQuery query;
      query.prepare(sql);
      // 绑定参数...
      if (query.exec()) { while (query.next()) { ... } }
      return result;
  }
  ```

### 3. `QSqlRecord` 需要显式包含头文件

- `QSqlRecord` 不在 `QSqlDatabase` 头文件中自动包含
- 使用 `QSqlRecord` 时必须 `#include <QSqlRecord>`

### 4. `std::sort` 需要 `#include <algorithm>`

- 使用 `std::sort` 等 STL 算法时必须包含 `<algorithm>`

### 5. TCP 数据粘包/分包处理

- TCP 是流式协议，`readyRead` 可能一次收到多个 JSON 粘在一起，也可能一个 JSON 被拆成多次收到
- **必须**使用接收缓冲区 + JSON 边界定位算法
- 示例：

  ```cpp
  // 错误：直接 readAll() 处理
  void onReadyRead() {
      QByteArray data = m_socket->readAll();
      handleData(data); // 可能粘包/分包
  }

  // 正确：使用缓冲区 + 边界定位
  void onReadyRead() {
      m_buffer.append(m_socket->readAll());
      while (!m_buffer.isEmpty()) {
          int pos = findJsonBoundary(m_buffer);
          if (pos < 0) break;
          QByteArray json = m_buffer.left(pos);
          m_buffer = m_buffer.mid(pos);
          handleData(json);
      }
  }
  ```

### 6. `QFile` 内存管理

- `new QFile(path)` 如果不设置 parent，必须手动 `delete`
- 每次 `new` 前检查旧对象是否存在并清理
- 析构函数中必须正确释放

### 7. 重连定时器必须用 SingleShot

- 重连定时器如果设置为周期定时器 (`singleShot=false`)，会无限循环触发
- **必须**设置为 `singleShot(true)`，在重连失败时手动 `start()`
- 示例：

  ```cpp
  // 错误：周期定时器
  m_reconnectTimer->setSingleShot(false); // 会无限重连

  // 正确：单次定时器 + 手动重启
  m_reconnectTimer->setSingleShot(true);
  // 在 tryReconnect() 中:
  m_tcpSocket->connectToHost(...);
  m_reconnectTimer->start(); // 如果连接失败，10秒后再次触发
  ```

### 8. QML 组件属性名避免冲突

- 自定义组件继承自 `Rectangle` 时，**不能**用 `color`、`title`、`value` 等内置属性名作为自定义属性
- 必须使用前缀区分：`accentColor`、`cardTitle`、`cardValue`

### 9. QML 文件只能有一个根组件

- 一个 `.qml` 文件只能有一个顶级根组件
- 后续组件必须使用 `component` 关键字声明为内联组件，且必须在根组件**内部**
- 示例：

  ```qml
  // 错误：多个根组件
  ApplicationWindow { ... }
  Rectangle { id: customComp } // 语法错误！

  // 正确：内联组件
  ApplicationWindow {
      id: root
      ...
      component CustomComp : Rectangle { ... }
  }
  ```

### 10. QML model 绑定避免复杂计算

- 在 `ListView` 的 `model` 属性中直接调用函数会**每次渲染都执行**
- 应该用 property 缓存结果，手动刷新
- 示例：

  ```qml
  // 错误：每次渲染都调用
  model: DatabaseManager.getEnergyData(device, new Date(), new Date())

  // 正确：property 缓存
  property var energyData: []
  function refresh() { energyData = DatabaseManager.getEnergyData(...) }
  model: energyData
  ```

---

## QML 组件规则（补充）

### 内联组件规则

- Qt 6.2+ 支持 `component` 关键字定义内联组件
- 必须在根组件**内部**声明
- 组件名首字母大写（PascalCase），不能与现有 QML 类型重名
- 示例：
  ```qml
  ApplicationWindow {
      id: root
      component MyCard : Rectangle { ... }
      component MyButton : Button { ... }
  }
  ```

### 数据库连接命名

- 使用 `QSqlDatabase::addDatabase("QSQLITE", "ConnectionName")` 命名连接
- 避免使用默认连接名，防止多模块冲突

---

## C++ Model 类常见错误（从实际项目中总结）

### 11. `QVariantList` 不可直接赋值给 `QList<QVariantMap>`

- `DatabaseManager::getAllDevices()`、`getAllScenes()`、`getAllAlerts()` 返回 `QVariantList`
- **不能**直接赋值给 `QList<QVariantMap>` 成员变量
- 必须循环转换：

  ```cpp
  // 错误：类型不匹配
  m_devices = DatabaseManager::instance()->getAllDevices(); // Error!

  // 正确：循环转换
  QVariantList dataList = DatabaseManager::instance()->getAllDevices();
  m_devices.clear();
  for (const QVariant &item : dataList)
  {
      m_devices.append(item.toMap());
  }
  ```

### 12. 枚举值删除后必须同步清理所有引用

- 从 enum 中移除值后，.cpp 文件中所有使用该值的地方必须同步删除
- 示例：`ResolvedRole` 从 AlertRoles 中删除后：
  - `data()` 方法中的 `case ResolvedRole:`
  - `roleNames()` 中的 `roles[ResolvedRole]`
  - `onAlertUpdated()` 中 `dataChanged()` 的 roles 列表
- 否则会导致编译错误：`'ResolvedRole' was not declared in this scope`

### 13. `dataChanged()` 的 roles 参数必须显式构造 `QList<int>`

- Qt 6 中 `dataChanged()` 的第三个参数是 `const QList<int> &`
- **不能**直接用花括号初始化列表：`emit dataChanged(idx, idx, {Role1, Role2})`
- 必须先构造 `QList<int>`：

  ```cpp
  // 错误：花括号列表无法转换为 QList<int>
  emit dataChanged(index, index, {Role1, Role2, Role3});

  // 正确：显式构造 QList<int>
  QList<int> changedRoles = {Role1, Role2, Role3};
  emit dataChanged(index, index, changedRoles);
  ```

---

## QML Model 绑定常见错误（从实际项目中总结）

### 11. ListView delegate 中 `parent.width` 为 null

- ListView 的 delegate 在实例化时 `parent` 可能为 null
- **不能**使用 `width: parent.width`
- **必须**使用 `width: ListView.view.width`

  ```qml
  // 错误：TypeError: Cannot read property 'width' of null
  delegate: Rectangle {
      width: parent.width
  }

  // 正确
  delegate: Rectangle {
      width: ListView.view.width
  }
  ```

### 12. Switch 绑定循环（Binding loop）

- 当 `checked: model.isEnabled` 且 `onCheckedChanged` 中调用 `Model.load()` 时，会导致 binding loop
- `Model.load()` 重置模型数据 → `model.isEnabled` 变化 → `checked` 重新赋值 → 触发 `onCheckedChanged` → 循环
- **必须**使用 `Component.onCompleted` 设置初始值 + `onToggled` 处理用户交互：

  ```qml
  // 错误：binding loop
  Switch {
      checked: model.isEnabled
      onCheckedChanged: {
          DatabaseManager.enableScene(model.sceneId, checked);
          SceneModel.load();
      }
  }

  // 正确：使用 Component.onCompleted + onToggled
  Switch {
      Component.onCompleted: checked = model.isEnabled
      onToggled: {
          DatabaseManager.enableScene(model.sceneId, checked);
          SceneModel.load();
      }
  }
  ```

### 13. QML delegate 中必须使用 `model.` 前缀访问角色

- ListView/GridView/Repeater 的 delegate 中访问模型角色时**必须**使用 `model.xxx` 前缀
- 直接使用角色名（如 `deviceName`、`isRead`）在部分情况下会报 undefined
- 对于可能为 undefined 的值，使用 `model.xxx || ""` 提供默认值：

  ```qml
  // 错误：可能报 undefined
  Label { text: content }
  Label { text: timestamp }

  // 正确：使用 model. 前缀 + 默认值
  Label { text: model.content || "" }
  Label { text: qsTr("时间: %1").arg(model.timestamp || "") }
  ```

### 14. ComboBox 不支持 `valueRole` 属性

- Qt Quick Controls 2 的 ComboBox **没有** `valueRole` 属性
- 只有 `textRole` 用于显示文本
- 需要获取其他值时，通过 `model.data(model.index(idx, 0), Model.Role)` 或添加辅助方法

  ```qml
  // 错误：valueRole 不存在
  ComboBox {
      model: DeviceModel
      textRole: "deviceName"
      valueRole: "deviceId"  // 无效！
  }

  // 正确：使用 Q_INVOKABLE 辅助方法
  Button {
      onClicked: {
          var deviceId = DeviceModel.deviceIdAt(comboBox.currentIndex);
      }
  }
  ```

### 15. `Material.foreground` 在 Button 上无效

- `Material.foreground` 是 attached property，在 Button 等控件上设置会被忽略
- 需要使用其他方式改变按钮文字颜色，或移除该属性

  ```qml
  // 错误：无效果
  Button {
      text: "告警"
      Material.foreground: "#ff5252"  // 无效
  }

  // 正确：移除或使用其他样式方法
  Button {
      id: alertButton
      text: "告警"
      property bool hasAlerts: count > 0
  }
  ```

### 16. Repeater delegate 宽度避免使用 `parent.width`

- Repeater 的 delegate 中 `parent` 可能为 null 或指向错误对象
- 应该引用具体页面组件：`width: devicePage.width`

  ```qml
  // 可能出错
  Repeater {
      delegate: DeviceCard {
          width: parent.width
      }
  }

  // 正确
  Repeater {
      delegate: DeviceCard {
          width: devicePage.width
      }
  }
  ```

### 17. 不存在的 QML 类型（从实际项目运行错误中总结）

- **`Card`** - 不存在，用 `Rectangle + radius + border + Material.elevation`
- **`PullToRefresh`** - 不存在，用自定义刷新按钮 + 动画替代
- **`Marquee`** - 不存在，用 `ListView + SequentialAnimation + NumberAnimation` 横向滚动替代
- **`Snackbar`** - 不存在，用 `Rectangle + NumberAnimation` 淡入淡出 + Timer 自动消失替代
- **`ChartView` / `BarSeries`** - Qt Charts 已弃用，使用 Qt Graphs 模块
- **`GradientAnimation`** - **不存在！** Qt Quick 没有 GradientAnimation 类型

### 18. `GridView` 没有 `spacing` 属性

- `GridView` 是网格布局，只有 `cellWidth` 和 `cellHeight`
- `spacing` 是 `ListView`、`GridLayout` 等的属性
- 如需间距，在 delegate 中减小实际尺寸：

  ```qml
  // 错误：GridView 没有 spacing
  GridView {
      spacing: 8  // Error: Cannot assign to non-existent property "spacing"
  }

  // 正确：通过减小 delegate 尺寸实现间距
  GridView {
      cellWidth: width / 2
      cellHeight: 100
      delegate: Rectangle {
          width: (deviceGrid.width / 2) - 16  // 减去间距
          height: 90
      }
  }
  ```

### 19. RowLayout/ColumnLayout 中禁止 `Layout.preferredWidth: parent.width * N`

- 在 RowLayout 子元素中使用 `Layout.preferredWidth: parent.width * 0.55` 会导致 **Recursive rearrange** 错误
- 原因：Layout 系统计算子元素宽度时依赖父元素宽度，而父元素宽度又依赖子元素宽度 → 无限循环
- **必须**改用 `anchors` 定位或固定比例的 Item 容器：

  ```qml
  // 错误：递归布局！
  RowLayout {
      ColumnLayout {
          Layout.preferredWidth: parent.width * 0.55  // Recursive rearrange!
      }
  }

  // 正确：用 anchors 替代 Layout 百分比
  Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 280

      Item {
          anchors.fill: parent

          Rectangle {
              id: leftCard
              anchors.left: parent.left
              anchors.right: parent.horizontalCenter
              anchors.rightMargin: 8
              // ...
          }

          Rectangle {
              id: rightCard
              anchors.right: parent.right
              anchors.left: parent.horizontalCenter
              anchors.leftMargin: 8
              // ...
          }
      }
  }
  ```

### 20. MouseArea 内部子元素引用 `pressed` / `containsMouse` 必须加 `parent.` 前缀

- MouseArea 内部的 Rectangle 中直接写 `pressed` 或 `containsMouse` 会报 `ReferenceError: pressed is not defined`
- 这些属性属于 MouseArea 本体，子元素必须通过 `parent.pressed` 访问：

  ```qml
  // 错误：ReferenceError: pressed is not defined
  component QuickButton : Rectangle {
      MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          Rectangle {
              anchors.fill: parent
              opacity: pressed ? 0.2 : (containsMouse ? 0.08 : 0)  // Error!
          }
      }
  }

  // 正确：使用 parent.pressed / parent.containsMouse
  component QuickButton : Rectangle {
      MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          Rectangle {
              anchors.fill: parent
              opacity: parent.pressed ? 0.2 : (parent.containsMouse ? 0.08 : 0)
          }
      }
  }
  ```

### 21. 内嵌 Rectangle 中 `parent.radius` 可能返回 undefined

- 在 MouseArea 内部创建的 Rectangle 中，`parent.radius` 引用的可能是 MouseArea（它没有 radius 属性）
- 导致 `Unable to assign [undefined] to double` 错误
- **必须**硬编码 radius 值或使用具体数值：

  ```qml
  // 错误：parent.radius 为 undefined
  MouseArea {
      anchors.fill: parent
      Rectangle {
          anchors.fill: parent
          radius: parent.radius  // Unable to assign [undefined] to double!
      }
  }

  // 正确：硬编码与外层一致的值
  MouseArea {
      anchors.fill: parent
      Rectangle {
          anchors.fill: parent
          radius: 14  // 与外部 Rectangle 的 radius 一致
      }
  }
  ```

### 22. `ApplicationWindow` 没有 `currentIndex` 属性

- `ApplicationWindow` 不是 StackView/Layout，没有内置页面索引
- 需要在 main.qml 中暴露 TabBar/StackLayout 的索引：

  ```qml
  // main.qml 中添加 property alias
  ApplicationWindow {
      property alias tabBarCurrentIndex: tabBar.currentIndex
      // ...
  }

  // 子页面中访问
  function navigateToPage(index) {
      if (Window.window)
          Window.window.tabBarCurrentIndex = index;
  }
  ```

### 23. 内联组件不支持嵌套声明

- Qt QML 中 `component` 关键字定义的内联组件**不能嵌套**
- 即不能在一个内联组件内部再定义另一个 `component`
- 所有 `component` 必须平级声明在根组件下：

  ```qml
  // 错误：Nested inline components are not supported
  component ParentComp : Rectangle {
      component ChildComp : Rectangle { ... }  // Error!
  }

  // 正确：所有内联组件平级
  Page {
      component ChildComp : Rectangle { ... }
      component ParentComp : Rectangle {
          ChildComp { ... }  // 使用已声明的组件
      }
  }
  ```

---

## QML 致命错误规则（从 ScenePage/SceneEditPage 实际开发中总结）

### 24. `Maximum call stack size exceeded` — 无限递归的三大根因

#### 根因一：信号链循环（最常见！）

- **问题**: `DeviceModel.load()` 触发 `countChanged` → handler 中又调用 `refreshDeviceList()` → 再次触发模型重置 → 循环
- **必须**使用**防重入锁**保护所有信号处理函数：

  ```qml
  property bool _refreshing: false

  Component.onCompleted: {
      _refreshing = true;        // 加锁
      DeviceModel.load();
      _refreshing = false;       // 解锁
      refreshDeviceList();
  }

  Connections {
      target: DeviceModel
      function onCountChanged() {
          if (_refreshing) return;  // 快速返回，打断循环
          refreshDeviceList();
      }
  }

  function refreshDeviceList() {
      if (_refreshing) return;       // 第一层守卫
      _refreshing = true;             // 第二层守卫
      DeviceModel.clearFilter();
      // ...
      _refreshing = false;
  }
  ```

- **所有调用 `Model.load()` 的地方都必须加锁**：Component.onCompleted、onCommandFailed 回滚、刷新按钮等

#### 根因二：Slider/SpinBox 双向绑定死循环

- **问题**: `value: xxx` 绑定 + `onValueChanged` 赋值回同一变量 → A→B→A→∞

  ```qml
  // ❌ 死循环！
  Slider {
      value: brightnessValue              // A: value ← brightnessValue
      onValueChanged: brightnessValue = Math.round(value)  // B: brightnessValue ← value → 回到A
  }

  // ✅ 正确：初始化用 Component.onCompleted，用户操作用 onMoved
  Slider {
      Component.onCompleted: value = brightnessValue   // 只执行一次
      onMoved: {                                         // 只在用户拖动时触发
          brightnessValue = Math.round(value);
          sendCommand(...);
      }
  }
  ```

- **同样适用于 SpinBox**：`value: tempValue` 改为 `Component.onCompleted: value = tempValue`

#### 根因三：`implicitWidth` 布局循环

- **问题**: 父元素宽度依赖子元素 `implicitWidth`，子元素布局又依赖父宽度 → 无限递归

  ```qml
  // ❌ 循环！父宽=子.implicitWidth+N → 子重新计算 → 父重算 → ∞
  Rectangle {
      width: childLabel.implicitWidth + 28    // 依赖子元素
      Label { id: childLabel; text: "..." }  // 子依赖父布局
  }

  // ✅ 正确：用固定值或纯数学计算（不依赖其他元素）
  Rectangle {
      width: text.length * 14 + padding     // 纯数学，无依赖链
      Label { text: "..." }
  }
  ```

- **禁止在 delegate 中使用 `parent.width`**（规则 #11 已有），同理也**禁止 `xxx.implicitWidth` 计算父尺寸**

### 25. 动画与属性绑定互斥（Animation-Binding Conflict）

- **绝对禁止**对同一个属性同时使用 **绑定表达式** 和 **动画（Behavior/SequentialAnimation）**

  ```qml
  // ❌ 致死冲突！绑定设 scale=1.0，动画改成1.3，绑定又重置...
  Rectangle {
      scale: pressed ? 0.97 : 1.0           // 绑定 A
      Behavior on scale { NumberAnimation {} }  // 动画 B 抢夺控制权 → 循环!
      SequentialAnimation on scale { running: true; loops: Animation.Infinite; ... }  // 更糟！
  }

  // ✅ 二选一：要么纯绑定，要么纯动画，不能混用
  // 方案A：纯绑定（无动画）
  Rectangle { scale: pressed ? 0.97 : 1.0 }

  // 方案B：纯动画（无绑定），用状态机驱动
  Rectangle {
      id: card
      states: [
          State { name: "pressed"; PropertyChanges { target: card; property: "scale"; value: 0.97 } },
          State { name: "normal"; PropertyChanges { target: card; property: "scale"; value: 1.0 } }
      ]
      transitions: Transition { NumberAnimation { property: "scale"; duration: 150 } }
  }
  ```

- **Behavior on color 也可能参与循环**：如果 color 是由多个条件动态计算的，加 Behavior 会导致反复触发

### 26. MouseArea 内部子元素的属性访问规则（补充）

- **已确认安全写法**（规则 #20）：
  - `parent.pressed` — ✅ 正确
  - `parent.containsMouse` — ✅ 正确
  - `toolBtnMouse.pressed` — ✅ 用具体 id 引用

- **禁止**在 MouseArea 内部直接写裸 `pressed`/`containsMouse`（会报 ReferenceError）

- **额外注意**：MouseArea 内部的 Rectangle 不能引用 `parent.radius`（可能是 MouseArea 没有 radius 属性），必须硬编码数值

### 27. `Rectangle` 不支持的属性列表（持续更新）

| 属性名                | 正确归属                            | 错误示例                                    |
| --------------------- | ----------------------------------- | ------------------------------------------- |
| `horizontalAlignment` | **Label / Text**                    | `Rectangle { horizontalAlignment: ... }` ❌ |
| `text`                | **Label / TextEdit / TextField**    | `Rectangle { text: "..." }` ❌              |
| `font.*`              | **Label / Text**                    | `Rectangle { font.pixelSize: 14 }` ❌       |
| `icon.*`              | **Button / ToolButton**             | `Rectangle { icon.source: "..." }` ❌       |
| `model`               | **ListView / GridView / Repeater**  | `Rectangle { model: [...] }` ❌             |
| `checked`             | **Switch / CheckBox / RadioButton** | `Rectangle { checked: true }` ❌            |
| `value`               | **Slider / SpinBox / ProgressBar**  | `Rectangle { value: 50 }` ❌                |

### 28. 同一对象禁止重复声明 `id`

```qml
// ❌ 编译错误或运行时异常
MouseArea {
    id: toolBtnMouse
    id: toolBtnHover         // 重复id！
}

// ✅ 一个 id，多处引用
MouseArea {
    id: toolBtnMouse
}
// 其他地方用 toolBtnMouse.pressed / toolBtnMouse.containsMouse
```

### 29. `font.size` 不是合法 QML 属性

- Qt Quick 中 Label/Text 的字体大小属性是 `font.pixelSize`
- `font.size` 是 **Qt Widgets (QWidget)** 的属性，QML 中不存在
- 错误表现：属性被静默忽略，文字大小不变

### 30. CMake `qt_add_qml_module` 的 QML_FILES 格式规范

- **必须**将所有 QML 文件统一放在一个 `QML_FILES` 关键字下：

  ```cmake
  qt_add_qml_module(appzhinengjiajv
      URI zhinengjiajv
      VERSION 1.0
      QML_FILES                          # ← 一个关键字
          qml/main.qml
          qml/pages/HomePage.qml          # ← 统一缩进
          qml/pages/DeviceControlPage.qml
          qml/pages/ScenePage.qml         # ← 新文件加在这里
          qml/pages/SceneEditPage.qml     # ← 新文件加在这里
      RESOURCES
          resources/resources.qrc
  )
  ```

- **禁止**拆成多个 `QML_FILES` 块（会导致 ninja 构建失败）
- **禁止**不一致的缩进（CMake 对缩进敏感）

### 31. 新增 QML 页面的完整接入流程

当创建新的 `.qml` 页面文件时，必须完成以下 **3 步**：

1. **CMakeLists.txt 注册文件**
2. **main.qml 中实例化页面**
3. **验证无循环依赖**

```cmake
# Step 1: CMakeLists.txt - 在 QML_FILES 下添加
QML_FILES
    qml/main.qml
    qml/pages/NewPage.qml    # ← 添加这行
```

```qml
// Step 2: main.qml - StackLayout 或 TabBar 中使用
StackLayout {
    HomePage { }
    NewPage {                 # ← 直接使用
        id: newPageInstance
        onBackRequested: tabBar.currentIndex = 0
    }
}
```

```bash
# Step 3: 必须按顺序构建
# ① Run CMake（扫描新QML文件）
# ② Clean Project
# ③ Rebuild (Ctrl+B)
# ④ Run (Ctrl+R)
```

### 32. 设备控制页开发模式参考（DeviceControlPage Pattern）

- **页面结构**: ColumnLayout 三段式（顶部筛选 + 中间网格 + 底部工具栏）
- **设备卡片**: Loader 动态加载不同类型的控制组件
- **乐观更新策略**: 用户操作先更新 UI → 发送命令 → 成功确认 / 失败回滚
- **批量操作**: var 数组存储选中 deviceId，工具栏统一按钮触发
- **防抖设计**: 所有 Model 操作加 `_refreshing` 锁防止信号风暴

---

## QML 致命错误规则补充（从 ScenePage/SceneEditPage 开发实战中总结）

### 33. Page 类型不支持 Rectangle 独有属性

- **Page** 继承自 Item（不是 Rectangle），因此**不支持**以下属性：
  - `radius` — 圆角半径（Rectangle专属）
  - `color` — 背景色（Rectangle专属，Page用background设置）
  - `clip` — 裁剪（Rectangle专属）
  - `border.*` — 边框样式（Rectangle专属）

  ```qml
  // ❌ 错误！Page没有radius和clip属性
  SceneEditPage {
      radius: 16      // Cannot assign to non-existent property "radius"
      clip: true       // Cannot assign to non-existent property "clip"
  }

  // ✅ 正确方案1：直接使用（不设圆角）
  SceneEditPage {
      width: 900
      height: 700
  }

  // ✅ 正确方案2：外层Rectangle包裹实现圆角
  Rectangle {
      width: 900
      height: 700
      radius: 16
      clip: true
      color: "#1a1a2e"

      SceneEditPage {
          anchors.fill: parent
      }
  }
  ```

### 34. MouseArea.drag 没有 `keys` 属性

- **MouseArea.drag** 和 **Drag 附加属性**是两个不同的拖拽系统：
  - `MouseArea.drag.target/axis/threshold` — 用于物理移动UI元素（**无keys属性**）
  - `Drag.keys/dragType/mimeData` — 用于MVC数据拖拽（如ListView项重排）

  ```qml
  // ❌ 错误！MouseArea.drag没有keys
  MouseArea {
      drag.target: myItem
      drag.axis: Drag.YAxis
      drag.keys: ["my-key"]   // Cannot assign to non-existent property "keys"
  }

  // ✅ 正确用法：物理移动UI元素
  MouseArea {
      drag.target: actionDelegate
      drag.axis: Drag.YAxis
      // 不需要keys
  }

  // ✅ 正确用法：数据拖拽（Drag附加属性）
  Rectangle {
      id: dragSource
      Drag.active: dragArea.dragging
      Drag.keys: ["text-data"]  // 这里才有keys
      Drag.mimeData: { "text": "Hello" }

      MouseArea {
          id: dragArea
          anchors.fill: parent
      }
  }
  ```

### 35. 禁止手动声明 property 自动生成的 changed 信号

- 当声明 `property var xxx` 时，QML引擎会**自动生成** `xxxChanged()` 信号
- **绝对禁止**再手动声明同名的signal，会导致编译错误：

  ```qml
  // ❌ 错误！Duplicate signal name
  property var triggerConditions: []
  signal triggerConditionsChanged  // 与自动生成的冲突！

  property var actionsList: []
  signal actionsListChanged         // 同样的问题！
  ```

  ```qml
  // ✅ 正确：只声明property，不声明changed信号
  property var triggerConditions: []   // 自动有 triggerConditionsChanged()
  property var actionsList: []          // 自动有 actionsListChanged()

  // 可以在代码中调用这些自动生成的信号
  function addCondition() {
      triggerConditions.push(newCond);
      triggerConditionsChanged();  // ✅ 合法！调用自动生成的信号
  }
  ```

### 36. TextField 双向绑定导致无限循环（致命BUG）

- **问题根源**：TextField的`text`属性绑定 + `onTextChanged`修改同一变量 → 形成闭环

  ```qml
  // ❌ 致命循环！违反规则#12/#25
  TextField {
      text: root.sceneName                  // 绑定A：text ← sceneName
      onTextChanged: root.sceneName = text   // 赋值B：sceneName ← text → 回到A → ∞
  }
  ```

- **正确模式**（事件驱动而非绑定驱动）：

  ```qml
  // ✅ 方案1：初始化 + 失焦保存（推荐）
  TextField {
      id: nameField
      placeholderText: qsTr("输入场景名称...")

      Component.onCompleted: text = root.sceneName   // 初始化时设置一次
      onEditingFinished: root.sceneName = text        // 用户编辑完成后保存
  }

  // ✅ 方案2：只读显示（不需要用户输入时）
  Label {
      text: root.sceneName  // 单向绑定，安全
  }
  ```

- **适用范围**：此规则同样适用于SpinBox、ComboBox等输入控件

### 37. Timer 必须在 Dialog/Page 销毁前停止

- **问题**：Dialog关闭后如果Timer仍在运行会导致：
  - 内存泄漏（Timer持有对已销毁对象的引用）
  - 控制台警告："Cannot call methods on deleted object"
  - 潜在的程序崩溃

  ```qml
  // ❌ 错误！Dialog关闭后Timer仍在运行
  Dialog {
      id: myDialog
      Timer {
          id: progressTimer
          interval: 200
          repeat: true
          onTriggered: { /* 更新dialog中的UI */ }
      }
      onOpened: progressTimer.start()
      // 缺少onClosed停止逻辑！
  }

  // ✅ 正确：确保所有Timer在关闭时停止
  Dialog {
      id: executionDialog
      Timer {
          id: progressTimer
          interval: 200
          repeat: true
          onTriggered: { /* ... */ }
      }
      Timer {
          id: delayCloseTimer
          interval: 1500
          repeat: false
          onTriggered: executionDialog.close()
      }

      onClosed: {
          progressTimer.stop();      // ✅ 停止进度定时器
          delayCloseTimer.stop();     // ✅ 停止延迟关闭定时器
          // 重置状态
          root._executingSceneId = "";
          root._executionProgress = 0.0;
      }
  }
  ```

### 38. ListView/GridView delegate 中避免使用不稳定的 parent 引用

- **问题**：delegate中的`parent`在某些情况下可能为null或指向错误的对象

  ```qml
  // ❌ 危险！parent可能不稳定
  delegate: Rectangle {
      Layout.maximumWidth: parent.width - 16  // parent可能是null
  }

  // ✅ 安全：使用具体组件ID或固定数值
  delegate: Rectangle {
      id: sceneCard
      Layout.maximumWidth: sceneCard.width - 150  // 引用自身
      // 或
      Layout.maximumWidth: ListView.view.width - 24  // 引用ListView
  }
  ```

### 39. ComboBox.currentIndex 避免使用函数表达式

- **问题**：在`currentIndex`中使用函数表达式会在每次渲染时重新执行，影响性能且可能不稳定

  ```qml
  // ❌ 性能差！每次渲染都重新计算
  ComboBox {
      currentIndex: {
          var typeMap = {"time": 0, "sensor": 1, ...};
          return typeMap[modelData["type"]] || 4;
      }
  }

  // ✅ 正确：提取为独立函数 + Component.onCompleted初始化
  ComboBox {
      id: conditionTypeCombo
      Component.onCompleted: currentIndex = getTypeIndex(modelData["type"])
      onActivated: function(index) { /* ... */ }
  }

  // 在页面级别定义辅助函数
  function getTypeIndex(typeStr) {
      var typeMap = {"time": 0, "sensor": 1, "device": 2, "weather": 3, "custom": 4};
      return typeMap[typeStr] !== undefined ? typeMap[typeStr] : 4;
  }
  ```

### 40. parseActions/parseConditions 函数中的死代码陷阱

- **问题**：多层if嵌套时，内层条件可能与外层矛盾导致代码永远不会执行

  ```javascript
  // ❌ 致命逻辑错误！内层if永远为false
  function parseActions(actionsData) {
      if (!actionsData || (typeof actionsData === 'string' && actionsData.trim() === "")) {
          // 外层已经排除 trim()==="" 的情况
          if (typeof actionsData === 'string' && actionsData.trim() !== "") {
              // 这个if永远为false！因为外层条件已经过滤了
              var items = trimmed.split(",");
          }
          return;  // 直接return了，下面的代码也不执行
      }

      // 这里的数组处理代码也可能不会执行
      if (Array.isArray(actionsData)) { ... }
  }

  // ✅ 正确：清晰的分支判断，每个分支独立return
  function parseActions(actionsData) {
      root.actionsList = [];

      if (!actionsData)
          return;  // 空值提前退出

      if (typeof actionsData === 'string') {
          var trimmed = actionsData.trim();
          if (trimmed === "")
              return;  // 空字符串提前退出

          // 字符串解析逻辑
          var items = trimmed.split(",");
          for (var i = 0; i < items.length; i++) {
              var item = items[i].trim();
              if (item) {
                  root.actionsList.push({
                      "id": "action_" + Date.now() + "_" + i,
                      "description": item,
                      "delay": 0
                  });
              }
          }
          return;  // 处理完退出
      }

      // 数组类型处理
      if (Array.isArray(actionsData)) {
          for (var j = 0; j < actionsData.length; j++) {
              // 数组元素解析逻辑
          }
      }
  }
  ```

### 41. SpinBox 初始化值的正确方式

- **问题**：SpinBox的`value`绑定可能导致与`onValueModified`形成循环

  ```qml
  // ❌ 有潜在风险
  SpinBox {
      value: modelData["delay"] || 0           // 绑定
      onValueModified: updateAction(model.index, "delay", value)  // 修改
  }

  // ✅ 推荐：Component.onCompleted初始化
  SpinBox {
      from: 0
      to: 10000
      stepSize: 100
      value: modelData["delay"] || 0            // 默认值
      Component.onCompleted: value = modelData["delay"] || 0  // 初始化覆盖
      onValueModified: root.updateAction(model.index, "delay", value)
  }
  ```

### 42. 场景页开发最佳实践总结（ScenePage/SceneEditPage Pattern）

#### 数据流架构

```
ScenePage (展示层)
    ↓ navigateToEdit(sceneData)
SceneEditPage (编辑层)
    ↓ saveScene(sceneData)/cancelEdit/deleteScene(id)
main.qml (协调层)
    ↓ 调用DatabaseManager API
DatabaseManager (持久层)
    ↓ 触发load()
SceneModel (模型层)
    ↓ countChanged信号
ScenePage (自动刷新)
```

#### 防护机制清单

| 机制                                  | 用途                       | 实现方式                                          |
| ------------------------------------- | -------------------------- | ------------------------------------------------- |
| `_refreshing`锁                       | 防止信号风暴               | 所有Model.load()前后加锁                          |
| `Component.onCompleted`               | 避免Switch/SpinBox绑定循环 | 初始化控件状态                                    |
| `onToggled/onMoved/onEditingFinished` | 响应用户交互               | 替代onCheckedChanged/onValueChanged/onTextChanged |
| `Dialog.onClosed`                     | 清理资源                   | 停止所有Timer、重置状态                           |
| `confirmDeleteDialog`                 | 防止误操作                 | 二次确认删除操作                                  |

#### 常见错误速查表

| 错误信息                                          | 原因                                  | 解决方案                         |
| ------------------------------------------------- | ------------------------------------- | -------------------------------- |
| `Cannot assign to non-existent property "radius"` | Page不支持Rectangle属性               | 移除radius/clip或用Rectangle包裹 |
| `Duplicate signal name`                           | 手动声明property自动生成的changed信号 | 删除手动声明的signal             |
| `Maximum call stack size exceeded`                | 绑定循环或信号循环                    | 使用防重入锁+事件驱动模式        |
| `Cannot assign to non-existent property "keys"`   | MouseArea.drag无keys属性              | 删除drag.keys或改用Drag附加属性  |
| `propOnCompose is not a property`                 | 使用了不存在的QML属性                 | 删除该属性行                     |
| `Type XXX unavailable`                            | 子组件编译错误                        | 检查子QML文件的语法错误          |
| `Type XXX is not a type`                          | 未在CMakeLists.txt注册QML文件         | 在QML_FILES下添加文件路径        |

---

## QML 致命错误规则（从 DeviceControlPage 实际开发中总结）

### 24. `Maximum call stack size exceeded` — 无限递归的三大根因

#### 根因一：信号链循环（最常见！）

- **问题**: `DeviceModel.load()` 触发 `countChanged` → handler 中又调用 `refreshDeviceList()` → 再次触发模型重置 → 循环
- **必须**使用**防重入锁**保护所有信号处理函数：

  ```qml
  property bool _refreshing: false

  Component.onCompleted: {
      _refreshing = true;        // 加锁
      DeviceModel.load();
      _refreshing = false;       // 解锁
      refreshDeviceList();
  }

  Connections {
      target: DeviceModel
      function onCountChanged() {
          if (_refreshing) return;  // 快速返回，打断循环
          refreshDeviceList();
      }
  }

  function refreshDeviceList() {
      if (_refreshing) return;       // 第一层守卫
      _refreshing = true;             // 第二层守卫
      DeviceModel.clearFilter();
      // ...
      _refreshing = false;
  }
  ```

- **所有调用 `Model.load()` 的地方都必须加锁**：Component.onCompleted、onCommandFailed 回滚、刷新按钮等

#### 根因二：Slider/SpinBox 双向绑定死循环

- **问题**: `value: xxx` 绑定 + `onValueChanged` 赋值回同一变量 → A→B→A→∞

  ```qml
  // ❌ 死循环！
  Slider {
      value: brightnessValue              // A: value ← brightnessValue
      onValueChanged: brightnessValue = Math.round(value)  // B: brightnessValue ← value → 回到A
  }

  // ✅ 正确：初始化用 Component.onCompleted，用户操作用 onMoved
  Slider {
      Component.onCompleted: value = brightnessValue   // 只执行一次
      onMoved: {                                         // 只在用户拖动时触发
          brightnessValue = Math.round(value);
          sendCommand(...);
      }
  }
  ```

- **同样适用于 SpinBox**：`value: tempValue` 改为 `Component.onCompleted: value = tempValue`

#### 根因三：`implicitWidth` 布局循环

- **问题**: 父元素宽度依赖子元素 `implicitWidth`，子元素布局又依赖父宽度 → 无限递归

  ```qml
  // ❌ 循环！父宽=子.implicitWidth+N → 子重新计算 → 父重算 → ∞
  Rectangle {
      width: childLabel.implicitWidth + 28    // 依赖子元素
      Label { id: childLabel; text: "..." }  // 子依赖父布局
  }

  // ✅ 正确：用固定值或纯数学计算（不依赖其他元素）
  Rectangle {
      width: text.length * 14 + padding     // 纯数学，无依赖链
      Label { text: "..." }
  }
  ```

- **禁止在 delegate 中使用 `parent.width`**（规则 #11 已有），同理也**禁止 `xxx.implicitWidth` 计算父尺寸**

### 25. 动画与属性绑定互斥（Animation-Binding Conflict）

- **绝对禁止**对同一个属性同时使用 **绑定表达式** 和 **动画（Behavior/SequentialAnimation）**

  ```qml
  // ❌ 致死冲突！绑定设 scale=1.0，动画改成1.3，绑定又重置...
  Rectangle {
      scale: pressed ? 0.97 : 1.0           // 绑定 A
      Behavior on scale { NumberAnimation {} }  // 动画 B 抢夺控制权 → 循环!
      SequentialAnimation on scale { running: true; loops: Animation.Infinite; ... }  // 更糟！
  }

  // ✅ 二选一：要么纯绑定，要么纯动画，不能混用
  // 方案A：纯绑定（无动画）
  Rectangle { scale: pressed ? 0.97 : 1.0 }

  // 方案B：纯动画（无绑定），用状态机驱动
  Rectangle {
      id: card
      states: [
          State { name: "pressed"; PropertyChanges { target: card; property: "scale"; value: 0.97 } },
          State { name: "normal"; PropertyChanges { target: card; property: "scale"; value: 1.0 } }
      ]
      transitions: Transition { NumberAnimation { property: "scale"; duration: 150 } }
  }
  ```

- **Behavior on color 也可能参与循环**：如果 color 是由多个条件动态计算的，加 Behavior 会导致反复触发

### 26. MouseArea 内部子元素的属性访问规则（补充）

- **已确认安全写法**（规则 #20）：
  - `parent.pressed` — ✅ 正确
  - `parent.containsMouse` — ✅ 正确
  - `toolBtnMouse.pressed` — ✅ 用具体 id 引用

- **禁止**在 MouseArea 内部直接写裸 `pressed`/`containsMouse`（会报 ReferenceError）

- **额外注意**：MouseArea 内部的 Rectangle 不能引用 `parent.radius`（可能是 MouseArea 没有 radius 属性），必须硬编码数值

### 27. `Rectangle` 不支持的属性列表（持续更新）

| 属性名                | 正确归属                            | 错误示例                                    |
| --------------------- | ----------------------------------- | ------------------------------------------- |
| `horizontalAlignment` | **Label / Text**                    | `Rectangle { horizontalAlignment: ... }` ❌ |
| `text`                | **Label / TextEdit / TextField**    | `Rectangle { text: "..." }` ❌              |
| `font.*`              | **Label / Text**                    | `Rectangle { font.pixelSize: 14 }` ❌       |
| `icon.*`              | **Button / ToolButton**             | `Rectangle { icon.source: "..." }` ❌       |
| `model`               | **ListView / GridView / Repeater**  | `Rectangle { model: [...] }` ❌             |
| `checked`             | **Switch / CheckBox / RadioButton** | `Rectangle { checked: true }` ❌            |
| `value`               | **Slider / SpinBox / ProgressBar**  | `Rectangle { value: 50 }` ❌                |

### 28. 同一对象禁止重复声明 `id`

```qml
// ❌ 编译错误或运行时异常
MouseArea {
    id: toolBtnMouse
    id: toolBtnHover         // 重复id！
}

// ✅ 一个 id，多处引用
MouseArea {
    id: toolBtnMouse
}
// 其他地方用 toolBtnMouse.pressed / toolBtnMouse.containsMouse
```

### 29. `font.size` 不是合法 QML 属性

- Qt Quick 中 Label/Text 的字体大小属性是 `font.pixelSize`
- `font.size` 是 **Qt Widgets (QWidget)** 的属性，QML 中不存在
- 错误表现：属性被静默忽略，文字大小不变

### 30. CMake `qt_add_qml_module` 的 QML_FILES 格式规范

- **必须**将所有 QML 文件统一放在一个 `QML_FILES` 关键字下：

  ```cmake
  qt_add_qml_module(appzhinengjiajv
      URI zhinengjiajv
      VERSION 1.0
      QML_FILES                          # ← 一个关键字
          qml/main.qml
          qml/pages/HomePage.qml          # ← 统一缩进
          qml/pages/DeviceControlPage.qml # ← 新文件加在这里
      RESOURCES
          resources/resources.qrc
  )
  ```

- **禁止**拆成多个 `QML_FILES` 块（会导致 ninja 构建失败）
- **禁止**不一致的缩进（CMake 对缩进敏感）

### 31. 新增 QML 页面的完整接入流程

当创建新的 `.qml` 页面文件时，必须完成以下 **3 步**：

1. **CMakeLists.txt 注册文件**
2. **main.qml 中实例化页面**
3. **验证无循环依赖**

```cmake
# Step 1: CMakeLists.txt - 在 QML_FILES 下添加
QML_FILES
    qml/main.qml
    qml/pages/NewPage.qml    # ← 添加这行
```

```qml
// Step 2: main.qml - StackLayout 或 TabBar 中使用
StackLayout {
    HomePage { }
    NewPage {                 // ← 直接使用
        id: newPageInstance
        onBackRequested: tabBar.currentIndex = 0
    }
}
```

```bash
# Step 3: 必须按顺序构建
# ① Run CMake（扫描新QML文件）
# ② Clean Project
# ③ Rebuild (Ctrl+B)
# ④ Run (Ctrl+R)
```

### 32. 设备控制页开发模式参考（DeviceControlPage Pattern）

- **页面结构**: ColumnLayout 三段式（顶部筛选 + 中间网格 + 底部工具栏）
- **设备卡片**: Loader 动态加载不同类型的控制组件
- **乐观更新策略**: 用户操作先更新 UI → 发送命令 → 成功确认 / 失败回滚
- **批量操作**: var 数组存储选中 deviceId，工具栏统一按钮触发
- **防抖设计**: 所有 Model 操作加 `_refreshing` 锁防止信号风暴
