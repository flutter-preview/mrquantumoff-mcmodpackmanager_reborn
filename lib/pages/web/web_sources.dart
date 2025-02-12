// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/pages/web/filter_mods.dart';
import 'package:mcmodpackmanager_reborn/pages/web/generate_user_agent.dart';
import 'dart:convert';
import 'package:mcmodpackmanager_reborn/pages/web/mod/mod.dart';

class UserAgentClient extends http.BaseClient {
  final String userAgent;
  final http.Client _inner;

  UserAgentClient(this.userAgent, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['user-agent'] = userAgent;
    request.headers['X-API-Key'] =
        const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
    return _inner.send(request);
  }
}

class WebSourcesPage extends StatefulWidget {
  const WebSourcesPage({super.key, this.filterOn = false});

  final bool filterOn;

  @override
  State<WebSourcesPage> createState() => _WebSourcesPageState();
}

class _WebSourcesPageState extends State<WebSourcesPage> {
  TextEditingController searchFieldController = TextEditingController();
  List<Widget> searchResults = [];
  bool areButtonsEnabled = true;

  void setSearchResults(List<Widget> newSearchResults) {
    setState(() {
      searchResults = newSearchResults;
    });
  }

  void setAreButtonsEnabled(bool newAreButtonsEnabled) {
    setState(() {
      areButtonsEnabled = newAreButtonsEnabled;
    });
  }

  Future<List<Mod>> searchMods(
      String searchText, ModClass modsClass, ModSource modSource) async {
    List<Mod> widgets = [];

    if (modSource == ModSource.curseForge) {
      String rawUri =
          'https://api.curseforge.com/v1/mods/search?gameId=432&searchFilter=$searchText&sortOrder=desc&classId=${modsClass.value}';

      if (modsClass == ModClass.shaderPack) {
        rawUri = '$rawUri&categoryId=4547';
      }

      if (widget.filterOn) {
        rawUri = '$rawUri&gameVersion=${GetStorage().read("lastUsedVersion")}';
      }
      if (widget.filterOn && modsClass == ModClass.mod) {
        rawUri = '$rawUri&modLoaderType=${GetStorage().read("lastUsedAPI")}';
      }

      Uri uri = Uri.parse(rawUri);
      debugPrint(uri.toString());
      http.Response response = await http.get(uri, headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      });
      Map responseJson = json.decode(response.body);
      for (var mod in responseJson["data"]) {
        try {
          String name = mod["name"];
          String summary = mod["summary"];
          int modId = mod["id"];

          String modIconUrl =
              "https://github.com/mrquantumoff/mcmodpackmanager_reborn/raw/master/assets/icons/logo.png";
          int downloadCount = mod["downloadCount"];
          try {
            String mModIconUrl = mod["logo"]["thumbnailUrl"].toString().trim();
            if (mModIconUrl == "") {
              throw Exception("No proper icon");
            }
            Uri.parse(mModIconUrl);
            modIconUrl = mModIconUrl;
            // ignore: empty_catches
          } catch (e) {}
          String slug = mod["slug"];
          widgets.add(
            Mod(
              description: summary,
              name: name,
              id: modId.toString(),
              modIconUrl: modIconUrl,
              slug: slug,
              setAreParentButtonsActive: setAreButtonsEnabled,
              downloadCount: downloadCount,
              source: ModSource.curseForge,
              modClass: modsClass,
            ),
          );
        } catch (e) {
          debugPrint("$e");
        }
      }
    } else {
      String modType = modsClass.name.toLowerCase();
      modType = modType.replaceAll("shaderpack", "shader");
      debugPrint(modType);
      String facets = '["project_type:$modType"]';

      if (widget.filterOn) {
        facets =
            '$facets, ["versions:${GetStorage().read("lastUsedVersion")}"]';
      }
      if (widget.filterOn && modsClass == ModClass.mod) {
        facets = '$facets, ["categories:${GetStorage().read("lastUsedAPI")}"]';
      }
      String rawUri =
          'https://api.modrinth.com/v2/search?query=$searchText&limit=50&facets=[$facets]';
      Uri uri = Uri.parse(
        rawUri,
      );
      http.Response response = await http.get(uri, headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      });
      Map responseJson = json.decode(response.body);
      if (responseJson["hits"] != null) {
        for (var mod in responseJson["hits"]) {
          String name = mod["title"];
          String desc = mod["description"];
          int downloadCount = mod["downloads"];
          String id = mod["project_id"];
          String slug = mod["slug"];
          String icon =
              "https://github.com/mrquantumoff/mcmodpackmanager_reborn/raw/master/assets/icons/logo256.png";
          // Not all mods have icons

          try {
            String mModIconUrl = mod["icon_url"].toString().trim();
            if (mModIconUrl == "") {
              throw Exception("No proper icon");
            }
            Uri.parse(mModIconUrl);
            icon = mModIconUrl;
            // ignore: empty_catches
          } catch (e) {}

          widgets.add(
            Mod(
              description: desc,
              name: name,
              id: id,
              slug: slug,
              modIconUrl: icon,
              setAreParentButtonsActive: setAreButtonsEnabled,
              downloadCount: downloadCount,
              source: ModSource.modRinth,
              modClass: modsClass,
            ),
          );
        }
      }
    }

    widgets.sort((a, b) {
      return (a.downloadCount > b.downloadCount) ? 0 : 1;
    });
    return widgets;
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    // areButtonsEnabled = false;
    // searchFieldController.dispose();
    // searchResults = [];
  }

  void searchModsFunction() async {
    if (searchFieldController.text.trim() == "") return;
    bool isCurseForgeAllowed = await checkCurseForge();
    setSearchResults(
      searchResults = [
        Container(
            margin: const EdgeInsets.only(top: 50, left: 20, right: 20),
            child: const LinearProgressIndicator())
      ],
    );

    String searchText =
        Uri.encodeQueryComponent(searchFieldController.text.trim());
    debugPrint(searchText);
    List<Mod> mods = [];
    List<Mod> resourcePacks = [];
    List<Mod> shaderPacks = [];
    List<Mod> modsModrinth = [];
    List<Mod> resourcePacksModrinth = [];
    List<Mod> shaderPacksModrinth = [];
    if (GetStorage().read("curseForge") && isCurseForgeAllowed) {
      mods = await searchMods(searchText, ModClass.mod, ModSource.curseForge);
      resourcePacks = await searchMods(
          searchText, ModClass.resourcePack, ModSource.curseForge);
      shaderPacks = await searchMods(
          searchText, ModClass.shaderPack, ModSource.curseForge);
    }
    if (GetStorage().read("modrinth")) {
      modsModrinth =
          await searchMods(searchText, ModClass.mod, ModSource.modRinth);
      resourcePacksModrinth = await searchMods(
          searchText, ModClass.resourcePack, ModSource.modRinth);
      shaderPacksModrinth =
          await searchMods(searchText, ModClass.shaderPack, ModSource.modRinth);
    }
    List<Mod> widgets = mods +
        resourcePacks +
        modsModrinth +
        resourcePacksModrinth +
        shaderPacksModrinth +
        shaderPacks;
    widgets.sort((a, b) {
      return b.downloadCount.compareTo(a.downloadCount);
    });
    setSearchResults(widgets);
  }

  Future<bool> checkCurseForge() async {
    final String apiKey =
        const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
    http.Response res = await http.get(
      Uri.parse("https://api.curseforge.com/v1/games"),
      headers: {"User-Agent": await generateUserAgent(), "X-API-Key": apiKey},
    );
    bool isValid = false;

    if (res.statusCode == 200 && GetStorage().read("curseForge")) {
      var data = json.decode(res.body);
      for (var game in data["data"]) {
        if (game["id"] == 432) {
          isValid = true;
        }
      }

      if (!isValid && GetStorage().read("curseForge")) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noEternalKey),
          ),
        );
      }
    }
    if (!isValid) {
      debugPrint(
          "The broken ETERNAL API KEY IS ${const String.fromEnvironment("ETERNAL_API_KEY")}");
    }
    return isValid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.filterOn
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Get.back(),
              ),
            )
          : null,
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 16),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(right: 20),
                      child: TextField(
                        decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText:
                                AppLocalizations.of(context)!.searchForMods),
                        controller: searchFieldController,
                        onSubmitted: (String val) => searchModsFunction(),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: searchModsFunction,
                    icon: const Icon(Icons.search),
                    label: Text(AppLocalizations.of(context)!.search),
                  ),
                  !widget.filterOn
                      ? TextButton.icon(
                          onPressed: () async {
                            Get.to(() => const FilterMods());
                          },
                          icon: const Icon(Icons.filter_alt),
                          label: Text(AppLocalizations.of(context)!.filter),
                        )
                      : Container(),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 15),
            ),
            Expanded(
              child: ListView(
                children: searchResults,
              ),
            )
          ],
        ),
      ),
    );
  }
}
