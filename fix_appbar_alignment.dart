import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File(r'C:\dbros_app\lib\screens\home_page.dart');
  var content = await file.readAsString(encoding: utf8);

  final appBarStart = '          appBar: AppBar(';
  final appBarEnd = '          body: Stack(';
  final startIdx = content.indexOf(appBarStart);
  final endIdx = content.indexOf(appBarEnd);

  if (startIdx != -1 && endIdx != -1) {
    final newAppBarCode = '''          appBar: AppBar(
            backgroundColor: const Color(0xFF121418),
            elevation: 0,
            toolbarHeight: 70,
            leadingWidth: padding + 40,
            leading: Padding(
              padding: EdgeInsets.only(left: padding),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(20),
                  child: const Icon(Icons.account_circle, color: Colors.white, size: 40),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: padding),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {},
                    borderRadius: BorderRadius.circular(20),
                    child: const Icon(Icons.notifications_none, color: Color(0xFFFFC700), size: 30),
                  ),
                ),
              ),
            ],
            centerTitle: true,
            title: SizedBox(
              height: titleFontSize + 40,
              child: Image.asset(
                'assets/title.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
''';
    content = content.substring(0, startIdx) + newAppBarCode + content.substring(endIdx);
    await file.writeAsString(content, encoding: utf8);
    print('AppBar updated successfully.');
  } else {
    print('Failed to find AppBar boundaries.');
  }
}
