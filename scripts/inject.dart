
import "dart:io";

void main() {
  final file = File("lib/screens/settings_page.dart");
  var lines = file.readAsLinesSync();
  int idx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains("SettingsService.setShowFloatingButtons(value);")) {
      idx = i + 3;
      break;
    }
  }
  
  if (idx != -1) {
    final injection = """
            // 주소 자동완성 방식
            ValueListenableBuilder<String>(
              valueListenable: SettingsService.addressSearchModeNotifier,
              builder: (context, currentMode, _) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('주소 자동완성 방식', style: TextStyle(color: Colors.white)),
                  subtitle: Text('입력 시 추천해 주는 기준 선택', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: DropdownButton<String>(
                    value: currentMode,
                    dropdownColor: Theme.of(context).cardTheme.color,
                    style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14, fontWeight: FontWeight.bold),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'both', child: Text('기록+주소 (기본)')),
                      DropdownMenuItem(value: 'history', child: Text('과거 기록만')),
                      DropdownMenuItem(value: 'address', child: Text('기본 주소만')),
                    ],
                    onChanged: (val) {
                      if (val != null) SettingsService.setAddressSearchMode(val);
                    },
                  ),
                );
              },
            ),
""";
    lines.insert(idx, injection);
    file.writeAsStringSync(lines.join("\n"));
    print("Success");
  } else {
    print("Failed to find index");
  }
}
