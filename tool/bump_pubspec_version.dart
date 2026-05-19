// APK 빌드 전 실행: pubspec.yaml version (이름+빌드번호) 증가
// 규칙: 표시 1.0.02.01~1.0.02.09 → 다음 1.0.03.01
//   pubspec: 1.0.02+1 … +9 → 1.0.03+1 (이름=major.minor.patch, +뒤=01~09)
// Android versionCode는 gradle에서 이름+빌드로 단조 증가 (0으로 리셋하지 않음).
import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final root = Directory.current;
  final pubspec = File.fromUri(root.uri.resolve('pubspec.yaml'));
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found (cwd: ${root.path})');
    exitCode = 1;
    return;
  }

  var text = pubspec.readAsStringSync();
  final re = RegExp(r'^version:\s*([\d.]+)\+(\d+)\s*$', multiLine: true);
  final m = re.firstMatch(text);
  if (m == null) {
    stderr.writeln(
      'Could not parse version: line must look like "version: 1.0.02+1"',
    );
    exitCode = 1;
    return;
  }

  var name = m.group(1)!;
  var build = int.parse(m.group(2)!);

  if (build < 9) {
    build++;
  } else {
    build = 1;
    final parts = name.split('.');
    if (parts.length < 3) {
      stderr.writeln('Expected major.minor.patch in version name');
      exitCode = 1;
      return;
    }
    final lastIdx = parts.length - 1;
    final lastOld = parts[lastIdx];
    final lastVal = int.tryParse(lastOld);
    if (lastVal == null) {
      stderr.writeln('Last version segment must be numeric: $lastOld');
      exitCode = 1;
      return;
    }
    final width = lastOld.length;
    parts[lastIdx] = (lastVal + 1).toString().padLeft(width, '0');
    name = parts.join('.');
  }

  final newLine = 'version: $name+$build';
  if (dryRun) {
    stdout.writeln('Would set: $newLine');
    stdout.writeln('Display: ${_displayLabel(name, build)}');
    return;
  }

  text = text.replaceFirst(re, newLine);
  pubspec.writeAsStringSync(text);
  stdout.writeln('Bumped pubspec to $newLine');
  stdout.writeln('Display: ${_displayLabel(name, build)}');
}

String _displayLabel(String name, int build) {
  return 'v$name.${build.toString().padLeft(2, '0')}';
}
