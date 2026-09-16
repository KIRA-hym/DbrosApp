
import 'dart:io';

void main() {
  final file = File('lib/screens/settings_page.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst('      const AiPremiumSection(),\n', '');
  
  final target = '''          ValueListenableBuilder<String>(
            valueListenable: SettingsService.addressSearchModeNotifier,
            builder: (context, currentMode, _) {''';
            
  final endTarget = '''                  onChanged: (val) {
                    if (val != null) SettingsService.setAddressSearchMode(val);
                  },
                ),
              );
            },
          ),''';
          
  if (content.contains(endTarget)) {
    content = content.replaceFirst(endTarget, endTarget + '\n          const AiPremiumSection(),');
  } else {
    print('Target not found!');
  }
  
  file.writeAsStringSync(content);
}

