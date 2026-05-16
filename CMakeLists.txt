cmake_minimum_required(VERSION 3.16)

project(zhinengjiajv VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Quick
    QuickControls2
    Multimedia
    Network
    Sql
    Graphs
    TextToSpeech
)

add_compile_options(
    $<$<CXX_COMPILER_ID:GNU>:-Werror=return-type>
    $<$<CXX_COMPILER_ID:GNU>:-Werror=unused-result>
    $<$<CXX_COMPILER_ID:MSVC>:/WX>
)

qt_standard_project_setup(REQUIRES 6.10)

qt_add_executable(appzhinengjiajv
    src/main.cpp
    src/utils/md5utils.h
    src/utils/md5utils.cpp
    src/utils/jsonutils.h
    src/utils/jsonutils.cpp
    src/utils/timeutils.h
    src/utils/timeutils.cpp
    src/utils/weatherservice.h
    src/utils/weatherservice.cpp
    src/utils/locationservice.h
    src/utils/locationservice.cpp
    src/utils/networkmanager.h
    src/utils/networkmanager.cpp
src/utils/voicecontroller.h
    src/utils/voicecontroller.cpp
    src/utils/videorendertarget.h
    src/utils/videorendertarget.cpp
    src/communication/udpdiscoverer.h
    src/communication/udpdiscoverer.cpp
    src/communication/tcpcontroller.h
    src/communication/tcpcontroller.cpp
    src/communication/scenetriggerengine.h
    src/communication/scenetriggerengine.cpp
    src/models/databasemanager.h
    src/models/databasemanager.cpp
    src/models/sensormodel.h
    src/models/sensormodel.cpp
    src/models/devicemodel.h
    src/models/devicemodel.cpp
    src/models/scenemodel.h
    src/models/scenemodel.cpp
    src/models/energymodel.h
    src/models/energymodel.cpp
    src/models/alertmodel.h
    src/models/alertmodel.cpp
)

qt_add_qml_module(appzhinengjiajv
    URI zhinengjiajv
    VERSION 1.0
    QML_FILES
        qml/main.qml
        qml/pages/HomePage.qml
        qml/pages/DeviceControlPage.qml
        qml/pages/ScenePage.qml
        qml/pages/SceneEditPage.qml
        qml/pages/EnergyPage.qml
        qml/pages/SensorPage.qml
        qml/pages/SecurityPage.qml
        qml/pages/AlertCenterPage.qml
        qml/pages/SettingsPage.qml
        qml/pages/LogPage.qml
        qml/components/LogCard.qml
    RESOURCES
        resources/resources.qrc
)

set_target_properties(appzhinengjiajv PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.zhinengjiajv
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appzhinengjiajv PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    Qt6::Network
    Qt6::Sql
    Qt6::Graphs
    Qt6::TextToSpeech
)

include(GNUInstallDirs)
install(TARGETS appzhinengjiajv
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
