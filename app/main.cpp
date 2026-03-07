#include <QtQml/QQmlApplicationEngine>
#include <QtGui/QGuiApplication>

#include <QQmlContext>
#include <QStringList>

#include <QtWidgets/QApplication>
#include <QIcon>
#include <QQuickStyle>

#include <QDebug>
#include <stdlib.h>

#include <QFontDatabase>
#include <QLoggingCategory>
#include <QDir>
#include <QFileInfo>
#include <QKeyEvent>
#include <QTextStream>

#include <fileio.h>
#include <monospacefontmanager.h>

namespace {


class KeyLogger : public QObject
{
public:
    using QObject::QObject;

    bool eventFilter(QObject* watched, QEvent* event) override
    {
        static bool remapping = false;

        if (event->type() != QEvent::KeyPress &&
            event->type() != QEvent::ShortcutOverride)
            return QObject::eventFilter(watched, event);

        auto* keyEvent = static_cast<QKeyEvent*>(event);
        auto modifiers = keyEvent->modifiers();
        if (!(modifiers & (Qt::ControlModifier | Qt::MetaModifier)))
            return QObject::eventFilter(watched, event);

        const bool isTerminalTarget =
            watched &&
            QString::fromLatin1(watched->metaObject()->className()).contains("TerminalDisplay");

        if (!remapping &&
            isTerminalTarget &&
            (modifiers & Qt::MetaModifier) &&
            !(modifiers & Qt::ControlModifier) &&
            keyEvent->key() != Qt::Key_Meta)
        {
            Qt::KeyboardModifiers remappedModifiers = modifiers;
            remappedModifiers &= ~Qt::MetaModifier;
            remappedModifiers |= Qt::ControlModifier;

            QKeyEvent remappedEvent(
                event->type(),
                keyEvent->key(),
                remappedModifiers,
                keyEvent->nativeScanCode(),
                keyEvent->nativeVirtualKey(),
                keyEvent->nativeModifiers(),
                keyEvent->text(),
                keyEvent->isAutoRepeat(),
                keyEvent->count());

            remapping = true;
            QCoreApplication::sendEvent(watched, &remappedEvent);
            remapping = false;
            return true;
        }

        return QObject::eventFilter(watched, event);
    }
};

}

QString getNamedArgument(QStringList args, QString name, QString defaultName)
{
    int index = args.indexOf(name);
    return (index != -1) ? args[index + 1] : QString(defaultName);
}

QString getNamedArgument(QStringList args, QString name)
{
    return getNamedArgument(args, name, "");
}

int main(int argc, char *argv[])
{
    // Some environmental variable are necessary on certain platforms.

    // This disables QT appmenu under Ubuntu, which is not working with QML apps.
    setenv("QT_QPA_PLATFORMTHEME", "", 1);

    // Disable Connections slot warnings
    QLoggingCategory::setFilterRules("qt.qml.connections.warning=false");

#if defined (Q_OS_LINUX)
    setenv("QSG_RENDER_LOOP", "threaded", 0);
#endif

#if defined(Q_OS_MAC)
    // This allows UTF-8 characters usage in OSX.
    setenv("LC_CTYPE", "UTF-8", 1);
#endif

    if (argc>1 && (!strcmp(argv[1],"-h") || !strcmp(argv[1],"--help"))) {
        QTextStream cout(stdout, QIODevice::WriteOnly);
        cout << "Usage: " << argv[0] << " [--default-settings] [--workdir <dir>] [--program <prog>] [-p|--profile <prof>] [--fullscreen] [-h|--help]" << endl;
        cout << "  --default-settings  Run cool-retro-term with the default settings" << endl;
        cout << "  --workdir <dir>     Change working directory to 'dir'" << endl;
        cout << "  -e <cmd>            Command to execute. This option will catch all following arguments, so use it as the last option." << endl;
        cout << "  -T <title>          Set window title to 'title'." << endl;
        cout << "  --fullscreen        Run cool-retro-term in fullscreen." << endl;
        cout << "  -p|--profile <prof> Run cool-retro-term with the given profile." << endl;
        cout << "  -h|--help           Print this help." << endl;
        cout << "  --verbose           Print additional information such as profiles and settings." << endl;
        return 0;
    }

    QString appVersion("1.2.0");

    if (argc>1 && (!strcmp(argv[1],"-v") || !strcmp(argv[1],"--version"))) {
        QTextStream cout(stdout, QIODevice::WriteOnly);
        cout << "cool-retro-term " << appVersion << endl;
        return 0;
    }

    QApplication::setAttribute(Qt::AA_MacDontSwapCtrlAndMeta, true);
    QApplication app(argc, argv);
    KeyLogger keyLogger;
    app.installEventFilter(&keyLogger);

    QQmlApplicationEngine engine;
    FileIO fileIO;
    MonospaceFontManager monospaceFontManager;

#if !defined(Q_OS_MAC)
    app.setWindowIcon(QIcon::fromTheme("cool-retro-term", QIcon(":../icons/32x32/cool-retro-term.png")));
#else
    app.setWindowIcon(QIcon(":../icons/32x32/cool-retro-term.png"));
#endif

    app.setOrganizationName("cool-retro-term");
    app.setOrganizationDomain("cool-retro-term");

    // Manage command line arguments from the cpp side
    QStringList args = app.arguments();

    // Manage default command
    QStringList cmdList;
    if (args.contains("-e")) {
        cmdList << args.mid(args.indexOf("-e") + 1);
    }
    QVariant command(cmdList.empty() ? QVariant() : cmdList[0]);
    QVariant commandArgs(cmdList.size() <= 1 ? QVariant() : QVariant(cmdList.mid(1)));
    engine.rootContext()->setContextProperty("appVersion", appVersion);
    engine.rootContext()->setContextProperty("defaultCmd", command);
    engine.rootContext()->setContextProperty("defaultCmdArgs", commandArgs);
    engine.rootContext()->setContextProperty(
                "storageNamespace",
                QFileInfo(QDir(QCoreApplication::applicationDirPath()).absolutePath()).absoluteFilePath());

    engine.rootContext()->setContextProperty("workdir", getNamedArgument(args, "--workdir", "$HOME"));
    engine.rootContext()->setContextProperty("fileIO", &fileIO);
    engine.rootContext()->setContextProperty("monospaceSystemFonts", monospaceFontManager.retrieveMonospaceFonts());

    engine.rootContext()->setContextProperty("devicePixelRatio", app.devicePixelRatio());

    // Sprite directory for the Image Overlay (OSC 99 sprite rendering)
    QString spriteDir = QDir::homePath() + "/.config/cool-retro-term/sprites";
    engine.rootContext()->setContextProperty("spriteDirectory", QUrl::fromLocalFile(spriteDir).toString());

    // Manage import paths for Linux and OSX.
    QStringList importPathList = engine.importPathList();
    importPathList.prepend(QCoreApplication::applicationDirPath() + "/qmltermwidget");
    importPathList.prepend(QCoreApplication::applicationDirPath() + "/../PlugIns");
    importPathList.prepend(QCoreApplication::applicationDirPath() + "/../../../qmltermwidget");
    engine.setImportPathList(importPathList);

    engine.load(QUrl(QStringLiteral ("qrc:/main.qml")));

    if (engine.rootObjects().isEmpty()) {
        qDebug() << "Cannot load QML interface";
        return EXIT_FAILURE;
    }

    // Quit the application when the engine closes.
    QObject::connect((QObject*) &engine, SIGNAL(quit()), (QObject*) &app, SLOT(quit()));

    return app.exec();
}
