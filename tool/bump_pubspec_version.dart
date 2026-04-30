// APK 빌드 전 실행: pubspec.yaml 의 version (이름+빌드번호) 증가
// 규칙: +빌드번호를 1 증가. 9 다음은 패치 자리를 올리고 빌드는 0 (예: 1.0.00+9 → 1.0.01+0)
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
    stderr.writeln('Could not parse version: line must look like "version: 1.0.00+5"');
    exitCode = 1;
    return;
  }

  var name = m.group(1)!;
  var build = int.parse(m.group(2)!);

  build++;
  if (build > 9) {
    build = 0;
    final parts = name.split('.');
    if (parts.length < 2) {
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
    return;
  }

  text = text.replaceFirst(re, newLine);
  pubspec.writeAsStringSync(text);
  stdout.writeln('Bumped pubspec to $newLine');
}
