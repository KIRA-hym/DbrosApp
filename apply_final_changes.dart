import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File(r'C:\dbros_app\lib\screens\home_page.dart');
  var content = await file.readAsString(encoding: utf8);

  // 1. Add import
  if (!content.contains('ad_banner_widget.dart')) {
    content = content.replaceFirst(
      "import 'package:flutter/material.dart';",
      "import 'package:flutter/material.dart';\nimport '../widgets/ad_banner_widget.dart';"
    );
  }

  // 2. Replace AppBar
  final appBarStart = '          appBar: AppBar(';
  final appBarEnd = '          body: Stack(';
  final startIdx = content.indexOf(appBarStart);
  final endIdx = content.indexOf(appBarEnd);

  if (startIdx != -1 && endIdx != -1) {
    final newAppBarCode = '''          appBar: AppBar(
            backgroundColor: const Color(0xFF121418),
            elevation: 0,
            toolbarHeight: 70,
            leading: IconButton(
              icon: const Icon(Icons.account_circle, color: Colors.white, size: 40),
              onPressed: () {},
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Color(0xFFFFC700), size: 30),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
            ],
            titleSpacing: 0,
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
  }

  // 3. Insert AdBannerWidget in Tablet Layout
  content = content.replaceAll(
'''                                          SizedBox(
                                            height: 85,
                                            child: _buildRegisterRow(),
                                          ),
                                          SizedBox(height: sectionGap),
                                          Expanded(
                                            child: _buildYoutubeSection(),
                                          ),''',
'''                                          SizedBox(
                                            height: 85,
                                            child: _buildRegisterRow(),
                                          ),
                                          SizedBox(height: sectionGap),
                                          const AdBannerWidget(),
                                          SizedBox(height: sectionGap),
                                          Expanded(
                                            child: _buildYoutubeSection(),
                                          ),'''
  );

  // 4. Insert AdBannerWidget in Portrait Layout
  content = content.replaceAll(
'''                                  SizedBox(
                                    height: 85,
                                    child: _buildRegisterRow(),
                                  ),
                                  SizedBox(height: sectionGap),
                                  Expanded(
                                    child: _buildYoutubeSection(),
                                  ),''',
'''                                  SizedBox(
                                    height: 85,
                                    child: _buildRegisterRow(),
                                  ),
                                  SizedBox(height: sectionGap),
                                  const AdBannerWidget(),
                                  SizedBox(height: sectionGap),
                                  Expanded(
                                    child: _buildYoutubeSection(),
                                  ),'''
  );

  await file.writeAsString(content, encoding: utf8);
  print('Final changes applied.');
}
