import 'dart:io';

void main() {
  final file = File('src/App.tsx');
  String content = file.readAsStringSync();

  if (!content.contains("import CallPoints from './pages/CallPoints';")) {
    content = content.replaceFirst(
      "import PromotionCodes from './pages/PromotionCodes';",
      "import PromotionCodes from './pages/PromotionCodes';\nimport CallPoints from './pages/CallPoints';"
    );
  }

  if (!content.contains('<Route path="call-points" element={<CallPoints />} />')) {
    content = content.replaceFirst(
      '<Route path="promotion" element={<PromotionCodes />} />',
      '<Route path="promotion" element={<PromotionCodes />} />\n            <Route path="call-points" element={<CallPoints />} />'
    );
  }

  file.writeAsStringSync(content);
}
