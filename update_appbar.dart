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
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: SizedBox(
              height: 70, // Match toolbar height
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: padding,
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(20),
                      child: const Icon(Icons.account_circle, color: Colors.white, size: 40),
                    ),
                  ),
                  SizedBox(
                    height: titleFontSize + 40,
                    child: Image.asset(
                      'assets/title.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    right: padding,
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(20),
                      child: const Icon(Icons.notifications_none, color: Color(0xFFFFC700), size: 30),
                    ),
                  ),
                ],
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
