
import "dart:io";

void main() {
  final file = File("lib/screens/settings_page.dart");
  var content = file.readAsStringSync();
  
  final target = """
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
""";

  final replacement = """
                  trailing: GestureDetector(
                    onTap: () {
                      String next = 'both';
                      if (currentMode == 'both') next = 'history';
                      else if (currentMode == 'history') next = 'address';
                      else next = 'both';
                      SettingsService.setAddressSearchMode(next);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).primaryColor),
                      ),
                      child: Text(
                        currentMode == 'history' ? '과거 기록만' : (currentMode == 'address' ? '기본 주소만' : '기록+주소 (기본)'),
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
""";

  if (content.contains(target.trim())) {
    content = content.replaceFirst(target.trim(), replacement.trim());
    file.writeAsStringSync(content);
    print("Success settings_page.dart fix");
  } else {
    print("Failed to find DropdownButton in settings_page.dart");
  }
}
