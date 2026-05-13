---
name: "qt6-qml-dev"
description: "Qt6/QML development helper for C++ and QML code patterns, best practices, and project structure. Invoke when writing Qt6/QML code, creating components, or modifying Qt projects."
---

# Qt6/QML Development Skill

This skill provides guidance for developing Qt6 Quick applications with QML and C++ integration, following modern Qt6 best practices.

## When to Invoke

- Writing or modifying QML components
- Creating C++ classes for Qt6 applications
- Setting up CMake build configuration for Qt6
- Implementing C++/QML integration
- Adding new Qt modules or dependencies
- Creating custom QML types registered from C++
- Troubleshooting Qt6/QML issues
- Adding network communication code

## Qt6 Critical Pitfalls (Learned from Experience)

### 1. Qt 5 APIs Removed in Qt 6
| Qt 5 API | Qt 6 Replacement | Error Message |
|----------|------------------|---------------|
| `QNetworkConfigurationManager` | `QNetworkInformation` or timer-based polling | `QNetworkConfigurationManager: No such file or directory` |
| `QNetworkSession` | Built into `QNetworkAccessManager` | `QNetworkSession: No such file or directory` |
| Qt Charts (`QtCharts::QChartView`) | Qt Graphs (`QtGraphs::BarSeries` etc.) | `ChartView is not a type` |
| `QDesktopWidget` | `QScreen`, `QGuiApplication::screens()` | `QDesktopWidget: No such file or directory` |
| `QRegExp` | `QRegularExpression` | Warning: deprecated |

### 2. Common QML Type Errors
| Non-existent Type | Correct Replacement | Error |
|-------------------|--------------------|-------|
| `Card` | `Rectangle` with color/radius | `Card is not a type` |
| `ChartView` | Use Qt Graphs module types | `ChartView is not a type` |
| `BarSeries` (in Qt Quick) | Qt Graphs `BarSeries` (different API) | `BarSeries is not a type` |

**Qt Graphs vs Qt Charts**: Qt Graphs is the Qt 6 replacement for Qt Charts. They have completely different APIs and import statements.

### 3. QML Property Assignment Errors
- `BarSeries`, `LineSeries`, `PieSeries` etc. do NOT inherit from `Item`
- They cannot use `anchors`, `width`, `height`, or `Layout` attached properties
- Must wrap them in an `Item` container if layout is needed
- Example:
```qml
// WRONG
BarSeries {
    anchors.fill: parent  // Error: Cannot assign to non-existent property 'anchors'
    Layout.preferredHeight: 300  // Error: Layout attached property must be attached to Item
}

// CORRECT
Item {
    Layout.preferredWidth: 400
    Layout.preferredHeight: 300
    BarSeries {
        // BarSeries fills the parent Item automatically
    }
}
```

### 4. Material Style Color Errors
- `Material.white`, `Material.Grey` are NOT directly assignable to color properties
- Use: `Material.color(Material.Grey)`, `Material.color(Material.White)`
- Or direct color strings: `"#ffffff"`, `"grey"`

## Project Structure

```
project/
├── CMakeLists.txt          # Main build configuration
├── main.cpp                # Application entry point
├── src/                    # C++ source files
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
└── build/                  # Build output (not version controlled)
```

## CMake Configuration Pattern

```cmake
cmake_minimum_required(VERSION 3.16)

project(projectname VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick QuickControls2 Network)

add_compile_options(
    $<$<CXX_COMPILER_ID:GNU>:-Werror=return-type>
    $<$<CXX_COMPILER_ID:GNU>:-Werror=unused-result>
    $<$<CXX_COMPILER_ID:MSVC>:/WX>
)

qt_standard_project_setup(REQUIRES 6.10)

qt_add_executable(appname
    main.cpp
    src/utils/utils.h src/utils/utils.cpp
)

qt_add_qml_module(appname
    URI projectname
    VERSION 1.0
    QML_FILES qml/main.qml
)

target_link_libraries(appname
    PRIVATE Qt6::Core Qt6::Quick Qt6::QuickControls2 Qt6::Network
)
```

### CMake Rules
- Do NOT set `CMAKE_PREFIX_PATH` - Qt Creator handles this
- Do NOT set `CMAKE_C_COMPILER` or `CMAKE_CXX_COMPILER` - Qt Creator handles this
- Do NOT set `CMAKE_BUILD_TYPE` - Qt Creator handles this
- Split multiple GCC options into separate `add_compile_options` lines

## C++ Code Patterns

### Entry Point (main.cpp)
```cpp
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    
    QQuickStyle::setStyle("Material");
    
    QQmlApplicationEngine engine;
    
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    
    engine.loadFromModule("projectname", "Main");
    
    return app.exec();
}
```

### Utility Class Pattern
```cpp
// utils.h
#pragma once
#include <QString>

class MyUtils
{
public:
    static QString doSomething(const QString &input);
};

// utils.cpp
#include "utils.h"

QString MyUtils::doSomething(const QString &input)
{
    return input.toUpper();
}
```

### Network Communication Class Pattern
```cpp
// communicator.h
#pragma once
#include <QObject>
#include <QUdpSocket>
#include <QTimer>
#include <QMap>
#include <QDateTime>
#include <QVariantMap>

class Communicator : public QObject
{
    Q_OBJECT
    QML_ELEMENT  // For QML access

public:
    explicit Communicator(QObject *parent = nullptr);

signals:
    void dataReceived(const QString &deviceId, const QVariantMap &data);
    void deviceDiscovered(const QString &deviceId);
    void deviceOffline(const QString &deviceId);
    void errorOccurred(int code, const QString &message);

public slots:
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void sendRequest(const QString &ip);

private slots:
    void onReadyRead();
    void checkTimeouts();

private:
    QUdpSocket *m_socket;
    QTimer *m_timer;
    QMap<QString, QDateTime> m_deviceTimes;
};
```

### Network Change Detection (Qt 6 Compatible)
```cpp
// DON'T use QNetworkConfigurationManager (removed in Qt 6)
// Use one of these approaches:

// Option 1: Timer-based polling
void checkNetwork() {
    auto addresses = QNetworkInterface::allAddresses();
    // Compare with previous state
}

// Option 2: QNetworkInformation (Qt 6.2+)
#include <QNetworkInformation>
auto *info = QNetworkInformation::instance();
connect(info, &QNetworkInformation::reachabilityChanged,
        this, &MyClass::onReachabilityChanged);
```

## QML Code Patterns

### Basic Component
```qml
import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 800
    height: 600
    title: qsTr("My App")
    
    // Use Rectangle instead of Card (Card doesn't exist)
    Rectangle {
        width: 200
        height: 100
        color: "#212121"
        radius: 8
        border.color: "#424242"
        
        Label {
            anchors.centerIn: parent
            text: qsTr("Hello World")
            color: "#ffffff"
        }
    }
}
```

### Device Card Pattern
```qml
// Use Rectangle as a card component
Rectangle {
    width: 250
    height: 150
    color: "#2c2c2c"
    radius: 12
    
    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8
        
        Label {
            text: deviceName
            font.bold: true
            color: "#ffffff"
        }
        
        Label {
            text: "Status: " + (isOnline ? "Online" : "Offline")
            color: isOnline ? "#4caf50" : "#f44336"
        }
    }
}
```

### Qt Graphs (Replacement for Qt Charts)
```qml
import QtQuick
import QtGraphs

Item {
    width: 400
    height: 300
    
    BarSeries {
        id: barSeries
        
        BarSet {
            label: "Temperature"
            values: [20, 22, 24, 23, 25]
        }
    }
    
    ChartView {
        anchors.fill: parent
        // Note: Qt Graphs ChartView may have different API than Qt Charts
    }
}
```

## Qt Modules Quick Reference

| Module | CMake Target | QML Import | Common Uses |
|--------|-------------|------------|-------------|
| Quick | `Qt6::Quick` | `import QtQuick` | Basic QML, Item, Rectangle |
| QuickControls2 | `Qt6::QuickControls2` | `import QtQuick.Controls` | Buttons, Labels, Dialogs |
| Network | `Qt6::Network` | - | QUdpSocket, QTcpSocket |
| Multimedia | `Qt6::Multimedia` | `import QtMultimedia` | Audio, Video |
| Sql | `Qt6::Sql` | - | QSqlDatabase |
| Graphs | `Qt6::Graphs` | `import QtGraphs` | Charts, Data viz |

## Build & Debug Workflow

1. **修改代码后**: 保存文件
2. **构建**: Ctrl+B (Qt Creator)
3. **运行**: Ctrl+R (Qt Creator)
4. **调试**: F5 (Qt Creator)

### When Build Fails
1. Clean project (右键 → Clean)
2. Run CMake (右键 → Run CMake)
3. Rebuild (右键 → Rebuild)
4. Check error messages for Qt 5 API usage
5. Verify QML types exist in Qt Quick Controls 2

## Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `QNetworkConfigurationManager: No such file` | Qt 5 API removed in Qt 6 | Use `QNetworkInformation` or timer polling |
| `Card is not a type` | Card doesn't exist in Qt Quick Controls 2 | Use `Rectangle` with color/radius |
| `ChartView is not a type` | Using Qt Charts (deprecated) | Use Qt Graphs module |
| `Cannot assign to non-existent property 'anchors'` | Component doesn't inherit Item | Wrap in `Item` container |
| `Layout attached property must be attached to Item` | Same as above | Same solution |
| `Unable to assign [undefined] to QColor` | Using undefined Material color | Use `Material.color(Material.Grey)` |
| `Module 'X' contains no type named 'Y'` | Wrong module URI or type name | Check QML import and type name |
| `No "Debug" CMake configuration found` | Missing build type | Qt Creator sets this, don't override |

## Advanced Qt6 Pitfalls (Learned from Real Projects)

### Lambda Capture in QObject::connect
- Lambda used in `QObject::connect` **must explicitly capture** all external variables
- Example:
```cpp
// WRONG: databaseManager not captured
QObject::connect(src, &Src::signal, ctx, [tcpController](args...) {
    databaseManager->doSomething(); // Error!
});

// CORRECT: capture all used variables
QObject::connect(src, &Src::signal, ctx, [tcpController, databaseManager](args...) {
    databaseManager->doSomething();
});
```

### QSqlQuery Copy is Deprecated in Qt 6
- `QSqlQuery::QSqlQuery(const QSqlQuery&)` is deprecated
- Do NOT copy QSqlQuery objects
- Create new QSqlQuery inside the function instead:
```cpp
// WRONG
QVariantList queryToList(const QSqlQuery &query) const {
    QSqlQuery mutableQuery = query; // Deprecated!
    while (mutableQuery.next()) { ... }
}

// CORRECT
QVariantList executeQueryToList(const QString &sql, const QVariantMap &params) const {
    QSqlQuery query;
    query.prepare(sql);
    // bind params...
    if (query.exec()) { while (query.next()) { ... } }
    return result;
}
```

### QSqlRecord Requires Explicit Include
- `QSqlRecord` is NOT auto-included by `QSqlDatabase`
- Must `#include <QSqlRecord>` when using `query.record()`

### std::sort Requires <algorithm>
- Always `#include <algorithm>` when using `std::sort`, `std::find`, etc.

### TCP Sticky Packet / Fragmentation Handling
- TCP is a stream protocol; `readyRead` may deliver multiple JSON messages concatenated or one message split across multiple reads
- **Must** use a receive buffer + JSON boundary detection
```cpp
// WRONG: no buffering
void onReadyRead() {
    QByteArray data = m_socket->readAll();
    handleData(data); // May miss or merge messages
}

// CORRECT: buffer + boundary detection
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

### QFile Memory Management
- `new QFile(path)` without a parent must be manually `delete`d
- Always check and clean up old QFile before creating new one
- Must also delete in destructor and disconnect functions

### Reconnect Timer Must Be SingleShot
- Reconnect timers with `setSingleShot(false)` will fire infinitely
- Use `setSingleShot(true)` and manually `start()` after each failed attempt:
```cpp
m_reconnectTimer->setSingleShot(true);
// In tryReconnect():
m_socket->connectToHost(...);
m_reconnectTimer->start(); // Fires once after interval if connection fails
```

### QML Component Property Naming
- When extending `Rectangle`, do NOT use built-in property names like `color`, `title`, `value`
- Use prefixed names: `accentColor`, `cardTitle`, `cardValue`

### QML Single Root + Inline Components
- A `.qml` file can only have ONE root component
- Additional components must be declared with `component` keyword INSIDE the root:
```qml
// WRONG: multiple roots
ApplicationWindow { ... }
Rectangle { id: custom } // SYNTAX ERROR!

// CORRECT: inline component inside root
ApplicationWindow {
    id: root
    component MyCard : Rectangle { ... }
}
```

### QML Model Binding Performance
- Calling functions in `model:` property causes re-execution on every render
- Cache results in a property and refresh manually:
```qml
// WRONG: re-executed every render
model: DatabaseManager.getData(device, new Date(), new Date())

// CORRECT: cached property
property var dataModel: []
function refresh() { dataModel = DatabaseManager.getData(...) }
model: dataModel
```

### Database Connection Naming
- Use named connections: `QSqlDatabase::addDatabase("QSQLITE", "ConnectionName")`
- Avoid default connection name to prevent conflicts between modules
