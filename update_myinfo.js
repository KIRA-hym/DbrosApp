const fs = require('fs');

const filePath = 'C:\\dbros_app\\lib\\screens\\my_info_page.dart';
let content = fs.readFileSync(filePath, 'utf-8');

// 1. Add import
if (!content.includes("import 'cs_inquiry_page.dart';")) {
    content = content.replace(
        "import '../services/font_size_service.dart';",
        "import '../services/font_size_service.dart';\nimport 'cs_inquiry_page.dart';"
    );
}

// 2. Add Customer Support Button
const target = 'const SizedBox(height: 64),';
const csButton = `const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CsInquiryPage()),
                  );
                },
                icon: const Icon(Icons.headset_mic, color: Colors.white),
                label: Text(
                  '고객지원 (이메일 문의)',
                  style: TextStyle(
                    fontSize: FontSizeService.getScaledFontSize(16),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2F36), // 어두운 색상으로 차별화
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),`;

if (!content.includes('고객지원 (이메일 문의)')) {
    content = content.replace(target, csButton);
}

fs.writeFileSync(filePath, content, 'utf-8');
console.log('my_info_page.dart updated with CS button');
