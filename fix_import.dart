import 'dart:io'; void main() { var f = File('lib/ui/overlay/quick_entry_ui.dart'); var s = f.readAsStringSync(); s = 'import \'dart:ui\' as ui;\n' + s; f.writeAsStringSync(s); print('done'); }
