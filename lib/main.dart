import 'dart:io';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/install_modpack_button.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/selector.dart';
import 'package:mcmodpackmanager_reborn/open_modpacks_folder.dart';
import 'package:mcmodpackmanager_reborn/settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:protocol_handler/protocol_handler.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await GetStorage.init();
  WidgetsFlutterBinding.ensureInitialized();
  dataCollectionInit();
  // Register a custom protocol
  // For macOS platform needs to declare the scheme in ios/Runner/Info.plist
  if (Platform.isWindows || Platform.isMacOS) {
    await protocolHandler.register('curseforge');
    await protocolHandler.register('mcmodpackmanager');
  } else {
    // Linux can use arguments from the cli
    for (String arg in args) {
      if (arg.startsWith("curseforge://install")) {
        GetStorage().writeInMemory("curseforgeArgument", arg);
      }
    }
  }
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: false,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    minimumSize: Size(1024, 576),
    fullScreen: false,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  var tempDir = await getTemporaryDirectory();

  for (var file in tempDir.listSync()) {
    if (file.path.split("/").last.split("\\").last.startsWith("modpack-") &&
        file.path.endsWith(".zip")) {
      file.delete();
    }
  }

  debugPrint(await generateUserAgent());

  if (GetStorage().read("clipIcons") == null) {
    GetStorage().writeInMemory("clipIcons", true);
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      return ThemeProvider(darkTheme: darkDynamic, lightTheme: lightDynamic);
    });
  }
}

class ThemeProvider extends StatefulWidget {
  const ThemeProvider(
      {super.key, required this.darkTheme, required this.lightTheme});

  final ColorScheme? darkTheme;
  final ColorScheme? lightTheme;

  @override
  State<ThemeProvider> createState() => _ThemeProviderState();
}

class _ThemeProviderState extends State<ThemeProvider> {
  bool shouldUseMaterial3 = true;

  String locale = GetStorage().read("locale") ?? "native";

  @override
  void initState() {
    super.initState();

    setLocale(GetStorage().read("locale") ?? "native");
    debugPrint("Initiated $locale");
  }

  void setLocale(String value) async {
    debugPrint((await getApplicationSupportDirectory()).path);
    bool hasBeenSet = false;
    for (var loc in AppLocalizations.supportedLocales) {
      if (loc.languageCode == value && value != "native") {
        GetStorage().write("locale", value);
        setState(() {
          locale = value;
          debugPrint("Locale set");
          hasBeenSet = true;
        });
      }
    }
    if (!hasBeenSet && value != "native") {
      GetStorage().write("locale", "en");
      setState(() {
        locale = "en";
        debugPrint("Locale set");
        hasBeenSet = true;
      });
    } else if (value == "native") {
      final String defaultLocale = Platform.localeName
          .split("_")
          .first; // Returns locale string in the form 'en_US'
      debugPrint("System locale is \"$defaultLocale\"");
      setLocale(defaultLocale);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (GetStorage().read("minecraftFolder") == null) {
      debugPrint("Mc folder is null");
      GetStorage()
          .write("minecraftFolder", getMinecraftFolder(onInit: true).path);
    }

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale.fromSubtags(languageCode: locale),
      defaultTransition: Transition.rightToLeft,
      home: MinecraftModpackManager(
        setLocale: setLocale,
      ),
      darkTheme: ThemeData.from(
        useMaterial3: shouldUseMaterial3,
        colorScheme: (widget.darkTheme ?? const ColorScheme.dark()),
      ),
      theme: ThemeData.from(
        useMaterial3: shouldUseMaterial3,
        colorScheme: (widget.lightTheme ?? const ColorScheme.light()),
      ),
    );
  }
}

class MinecraftModpackManager extends StatefulWidget {
  const MinecraftModpackManager({super.key, required this.setLocale});

  final Function(String locale) setLocale;

  @override
  State<MinecraftModpackManager> createState() =>
      _MinecraftModpackManagerState();
}

class _MinecraftModpackManagerState extends State<MinecraftModpackManager>
    with ProtocolListener {
  @override
  void dispose() {
    protocolHandler.removeListener(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    protocolHandler.addListener(this);
  }

  @override
  void onProtocolUrlReceived(String url) {
    String log = 'Url received: $url)';
    debugPrint(log);
    Uri uri = Uri.parse(url);
    try {
      // Example: curseforge://install?addonId=238222&fileId=4473386
      int modId = int.parse(uri.queryParameters["addonId"]!);
      int fileId = int.parse(uri.queryParameters["fileId"]!);
      installModByProtocol(modId, fileId, protocolFail);
    } catch (e) {
      protocolFail();
    }
  }

  void protocolFail() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(AppLocalizations.of(context)!.unsupportedDownload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (GetStorage().read("curseforgeArgument") != null && Platform.isLinux) {
      debugPrint("curseforge protocol received");
      onProtocolUrlReceived(GetStorage().read("curseforgeArgument"));
      debugPrint("curseforge protocol removed");
      GetStorage().remove("curseforgeArgument");
    }

    return Scaffold(
      appBar: AppBar(),
      endDrawer: Drawer(
        width: 350,
        child: Settings(
          setLocale: widget.setLocale,
        ),
      ),
      body: Center(
        child: ListView(
          // crossAxisAlignment: CrossAxisAlignment.center,
          // mainAxisAlignment: MainAxisAlignment.center,
          padding: const EdgeInsets.symmetric(vertical: 50),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 15),
              child: SvgPicture.asset(
                "assets/icons/logo.svg",
                height: 128,
              ),
            ),
            const Selector(),
            const OpenModpacksFolder(),
            const ModpackInstaller()
          ],
        ),
      ),
    );
  }
}
