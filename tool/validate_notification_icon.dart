// 빌드 전 검사: app_notification_icon (벡터 XML 또는 density PNG) 손상 여부
import 'dart:io';

const _vectorRel = 'android/app/src/main/res/drawable/app_notification_icon.xml';
const _pngDensities = [
  'drawable-mdpi',
  'drawable-hdpi',
  'drawable-xhdpi',
  'drawable-xxhdpi',
  'drawable-xxxhdpi',
];

void main(List<String> args) {
  final root = Directory.current;
  final vectorFile = File.fromUri(root.uri.resolve(_vectorRel));
  if (vectorFile.existsSync()) {
    _validateVector(vectorFile);
    return;
  }

  final errors = <String>[];
  var found = 0;
  for (final density in _pngDensities) {
    final png = File.fromUri(
      root.uri.resolve('android/app/src/main/res/$density/app_notification_icon.png'),
    );
    if (!png.existsSync()) continue;
    found++;
    final len = png.lengthSync();
    if (len < 80) {
      errors.add('$density PNG too small ($len bytes)');
    }
  }

  if (found == 0) {
    stderr.writeln('ERROR: no app_notification_icon.xml or drawable-*/app_notification_icon.png');
    exitCode = 1;
    return;
  }
  if (errors.isNotEmpty) {
    stderr.writeln('Invalid notification icon PNGs:');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('OK: notification icon PNG set ($found densities)');
}

void _validateVector(File iconFile) {
  final text = iconFile.readAsStringSync();
  final errors = <String>[];

  if (text.contains('NaN') || text.contains('nan')) {
    errors.add('pathData contains NaN (icon generation likely crashed mid-write)');
  }
  if (!text.contains('<vector')) {
    errors.add('not a vector drawable');
  }
  final pathData = RegExp(r'pathData="([^"]*)"')
      .allMatches(text)
      .map((m) => m.group(1)!)
      .toList();
  if (pathData.isEmpty) {
    errors.add('no pathData found');
  } else {
    for (final pd in pathData) {
      if (pd.trim().length < 8) {
        errors.add('pathData too short or empty: "$pd"');
      }
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Invalid notification icon ($_vectorRel):');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    stderr.writeln('');
    stderr.writeln('Restore: git checkout HEAD -- $_vectorRel');
    stderr.writeln('Or regenerate: .\\tools\\generate_notification_icon.ps1');
    exitCode = 1;
    return;
  }

  stdout.writeln('OK: notification icon vector looks valid');
}
