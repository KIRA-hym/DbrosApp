import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File(r'C:\dbros_app\lib\screens\home_page.dart');
  var content = await file.readAsString(encoding: utf8);

  final startMarker = '          appBar: AppBar(';
  final endMarker = '          body: Stack(';

  final startIdx = content.indexOf(startMarker);
  final endIdx = content.indexOf(endMarker);

  if (startIdx == -1 || endIdx == -1) {
    print('Markers not found');
    exit(1);
  }

  final newAppBarCode = '''          appBar: AppBar(
            backgroundColor: const Color(0xFF121418),
            elevation: 0,
            toolbarHeight: 70,
            leading: IconButton(
              icon: const Icon(Icons.account_circle, color: Colors.white, size: 30),
              onPressed: () {},
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 30),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
            ],
            titleSpacing: 0,
            centerTitle: true,
            title: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  height: titleFontSize + 40,
                  child: Image.asset(
                    'assets/title.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const Positioned(
                  bottom: -5,
                  left: 45,
                  child: Text(
                    '운행 일지 관리',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
''';

  content = content.substring(0, startIdx) + newAppBarCode + content.substring(endIdx);
  await file.writeAsString(content, encoding: utf8);
  print('AppBar replaced.');
}
