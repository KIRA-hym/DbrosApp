import 'dart:io';

void main() {
  final file = File('lib/screens/settings_page.dart');
  String rawCode = file.readAsStringSync();
  String code = rawCode.replaceAll('\r\n', '\n');

  // 1. Replace the list button
  final btnStartStr = '      Container(\n        key: _keyFeeInsurance,\n        child: _buildListManageButton(\n          title: \'수수료 및 보험료 설정\',\n          icon: Icons.monetization_on_outlined,\n          onTap: _showFeeInsuranceDialog,\n        ),\n      ),';
  if (code.contains(btnStartStr)) {
    final replacementBtn = '''      Container(
        key: _keyFeeInsurance,
        child: Column(
          children: [
            _buildListManageButton(
              title: '수수료 설정',
              icon: Icons.monetization_on_outlined,
              onTap: _showFeeDialog,
            ),
            _buildListManageButton(
              title: '보험료 설정',
              icon: Icons.shield_outlined,
              onTap: _showInsuranceDialog,
            ),
          ],
        ),
      ),''';
    code = code.replaceFirst(btnStartStr, replacementBtn);
  } else {
    print("Could not find the button container to replace.");
  }

  // 2. Replace _showFeeInsuranceDialog with two dialogs
  final dialogStartIdx = code.indexOf('  void _showFeeInsuranceDialog() {');
  if (dialogStartIdx != -1) {
    final dialogEndStr = 'ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("수수료 및 보험료가 저장되었습니다.")));\n                    }\n                  },\n                  child: Text("저장", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),\n                ),\n              ],\n            );\n          }\n        );\n      }\n    );';
    final dialogEndIdx = code.indexOf(dialogEndStr, dialogStartIdx);
    
    if (dialogEndIdx != -1) {
      final realEnd = dialogEndIdx + dialogEndStr.length + 5; // To capture '  }\n\n' roughly
      
      final replacementDialogs = '''  void _showFeeDialog() {
    AppGlassDialog.show<void>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.monetization_on_outlined,
        title: "수수료 설정",
        contentWidget: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("기본 수수료율 (%)", style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _baseFeeCon,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF2C2F3D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              label: '취소',
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              label: '저장',
              filled: true,
              onPressed: () async {
                await SettingsService.setBaseFeeRate(double.tryParse(_baseFeeCon.text) ?? 20.0);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("수수료 설정이 저장되었습니다.")));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showInsuranceDialog() {
    AppGlassDialog.show<void>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.shield_outlined,
        title: "보험료 설정",
        contentWidget: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<String>(
                  title: const Text("적용 안 함", style: TextStyle(color: Colors.white)),
                  value: 'none',
                  groupValue: _insuranceType,
                  activeColor: Theme.of(context).primaryColor,
                  onChanged: (val) {
                    setDialogState(() => _insuranceType = val!);
                    setState(() => _insuranceType = val!);
                  },
                ),
                RadioListTile<String>(
                  title: const Text("건당 보험료", style: TextStyle(color: Colors.white)),
                  value: 'per_trip',
                  groupValue: _insuranceType,
                  activeColor: Theme.of(context).primaryColor,
                  onChanged: (val) {
                    setDialogState(() => _insuranceType = val!);
                    setState(() => _insuranceType = val!);
                  },
                ),
                if (_insuranceType == 'per_trip')
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                    child: TextField(
                      controller: _perTripInsCon,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "1건당 차감 금액 (원)",
                        labelStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF2C2F3D),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
              ],
            );
          }
        ),
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              label: '취소',
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              label: '저장',
              filled: true,
              onPressed: () async {
                await SettingsService.setInsuranceType(_insuranceType);
                await SettingsService.setPerTripInsurance(int.tryParse(_perTripInsCon.text) ?? 0);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("보험료 설정이 저장되었습니다.")));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
''';
      // Find the exact span to replace
      final endBound = code.indexOf('}', dialogEndIdx) + 1; // get the closing brace of the method
      final actualEnd = code.indexOf('}', endBound) + 1; // wait, let's just use string replace.
      
      // Let's replace the whole method substring
      // find the end of the method by looking for the next Widget _buildAppConvenienceSettings()
      final nextMethodIdx = code.indexOf('  Widget _buildAppConvenienceSettings() {', dialogStartIdx);
      if (nextMethodIdx != -1) {
        code = code.substring(0, dialogStartIdx) + replacementDialogs + code.substring(nextMethodIdx);
        print("Replaced dialog methods.");
      } else {
        print("Could not find the next method.");
      }
    } else {
      print("Could not find dialog end string.");
    }
  } else {
    print("Could not find _showFeeInsuranceDialog start.");
  }

  if (rawCode.contains('\r\n')) {
    code = code.replaceAll('\n', '\r\n');
  }

  file.writeAsStringSync(code);
}
