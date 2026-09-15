import 'dart:io';

void main() {
  final file = File('lib/screens/home_page.dart');
  var content = file.readAsStringSync();

  // 1. Add imports
  if (!content.contains('call_point_sync_service.dart')) {
    content = content.replaceFirst(
      "import '../services/settings_service.dart';",
      "import '../services/settings_service.dart';\nimport '../services/call_point_sync_service.dart';"
    );
  }

  // 2. Add state
  if (!content.contains('bool _hasMapUpdate = false;')) {
    content = content.replaceFirst(
      "bool _isCheckingUpdate = false;",
      "bool _isCheckingUpdate = false;\n  bool _hasMapUpdate = false;"
    );
  }

  // 3. Add check function
  if (!content.contains('_checkMapUpdate()')) {
    content = content.replaceFirst(
      "void _loadWeather() async {",
      """
  Future<void> _checkMapUpdate() async {
    try {
      bool hasUpdate = await CallPointSyncService.isUpdateAvailable();
      if (mounted) setState(() { _hasMapUpdate = hasUpdate; });
    } catch (e) {}
  }

  void _loadWeather() async {"""
    );
  }

  // 4. Call check in initState
  if (!content.contains('_checkMapUpdate();')) {
    content = content.replaceFirst(
      "_loadWeather();",
      "_loadWeather();\n      _checkMapUpdate();"
    );
  }

  // 5. Update Navigator.push to then()
  content = content.replaceAll(
    "Navigator.push(\n                      context,\n                      MaterialPageRoute(builder: (_) => const CallPointMapPage()),\n                    );",
    "Navigator.push(\n                      context,\n                      MaterialPageRoute(builder: (_) => const CallPointMapPage()),\n                    ).then((_) => _checkMapUpdate());"
  );
  content = content.replaceAll(
    "Navigator.push(\n                                context,\n                                MaterialPageRoute(\n                                  builder: (_) => const CallPointMapPage(),\n                                ),\n                              );",
    "Navigator.push(\n                                context,\n                                MaterialPageRoute(\n                                  builder: (_) => const CallPointMapPage(),\n                                ),\n                              ).then((_) => _checkMapUpdate());"
  );

  // 6. Update Map Icons with Badges
  content = content.replaceAll(
    "Icon(Icons.map, color: Color(0xFFFFC700), size: 20)",
    "Stack(clipBehavior: Clip.none, children: [const Icon(Icons.map, color: Color(0xFFFFC700), size: 20), if (_hasMapUpdate) Positioned(right: -2, top: -2, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))))])"
  );
  
  content = content.replaceAll(
    "Icon(\n                                Icons.map,\n                                color: Theme.of(context).primaryColor,\n                                size: isTablet ? 26 : 22,\n                              )",
    "Stack(clipBehavior: Clip.none, children: [Icon(Icons.map, color: Theme.of(context).primaryColor, size: isTablet ? 26 : 22), if (_hasMapUpdate) Positioned(right: -2, top: -2, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))))])"
  );

  file.writeAsStringSync(content);
}