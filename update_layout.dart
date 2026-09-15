import 'dart:io';

void main() {
  final file = File('src/components/Layout.tsx');
  String content = file.readAsStringSync();

  if (!content.contains('MapPin')) {
    content = content.replaceFirst(
      "import { Bell, FileText, Settings, LogOut, FileSearch, Menu, X, Users, Ticket } from 'lucide-react';",
      "import { Bell, FileText, Settings, LogOut, FileSearch, Menu, X, Users, Ticket, MapPin } from 'lucide-react';"
    );
  }

  if (!content.contains("path: '/call-points'")) {
    content = content.replaceFirst(
      "{ name: '프로모션 코드 관리', path: '/promotion', icon: <Ticket size={20} /> },",
      "{ name: '프로모션 코드 관리', path: '/promotion', icon: <Ticket size={20} /> },\n    { name: '주변콜맵 관리', path: '/call-points', icon: <MapPin size={20} /> },"
    );
  }

  file.writeAsStringSync(content);
}
