import 'dart:io';

void main() {
  final file = File('lib/ui/overlay/quick_entry_popup_form.dart');
  var content = file.readAsStringSync();

  // 1. Add import
  content = content.replaceFirst(
    "import '../../utils/drive_time_format.dart';",
    "import '../../utils/drive_time_format.dart';\nimport '../../widgets/pulse_animation_wrapper.dart';"
  );

  // 2. Fix the mic settings dialog
  content = content.replaceFirst(
    "content: const Text('음성 인식을 위해 마이크 권한이 필요합니다.\\n오버레이 창을 닫고 앱 본체를 열어 권한을 허용해주세요.', style: TextStyle(color: Colors.grey)),\n          actions: [\n            TextButton(\n              onPressed: () => Navigator.pop(context),\n              child: const Text('확인', style: TextStyle(color: Color(0xFFFFC700))),\n            ),\n          ],",
    "content: const Text('음성 인식을 위해 마이크 권한이 필요합니다.\\n설정 화면으로 이동하여 마이크 권한을 허용해 주세요.', style: TextStyle(color: Colors.grey)),\n          actions: [\n            TextButton(\n              onPressed: () => Navigator.pop(context),\n              child: const Text('취소', style: TextStyle(color: Colors.grey)),\n            ),\n            TextButton(\n              onPressed: () {\n                Navigator.pop(context);\n                openAppSettings();\n              },\n              child: const Text('설정으로 이동', style: TextStyle(color: Color(0xFFFFC700))),\n            ),\n          ],"
  );

  // 3. Wrap origin mic
  content = content.replaceFirst(
    "suffixIcon: IconButton(\n                                          icon: Icon(\n                                            (_isListening && _activeSttField == 'origin') \n                                                ? Icons.mic \n                                                : Icons.mic_none,\n                                            color: (_isListening && _activeSttField == 'origin') \n                                                ? Colors.redAccent \n                                                : const Color(0xFF666666),\n                                          ),\n                                          onPressed: () => _toggleListening('origin'),\n                                        ),",
    "suffixIcon: PulseAnimationWrapper(\n                                          isActive: _isListening && _activeSttField == 'origin',\n                                          child: IconButton(\n                                            icon: Icon(\n                                              (_isListening && _activeSttField == 'origin') \n                                                  ? Icons.mic \n                                                  : Icons.mic_none,\n                                              color: (_isListening && _activeSttField == 'origin') \n                                                  ? Colors.redAccent \n                                                  : const Color(0xFF666666),\n                                            ),\n                                            onPressed: () => _toggleListening('origin'),\n                                          ),\n                                        ),"
  );

  // 4. Wrap dest mic
  content = content.replaceFirst(
    "suffixIcon: IconButton(\n                                          icon: Icon(\n                                            (_isListening && _activeSttField == 'dest') \n                                                ? Icons.mic \n                                                : Icons.mic_none,\n                                            color: (_isListening && _activeSttField == 'dest') \n                                                ? Colors.redAccent \n                                                : const Color(0xFF666666),\n                                          ),\n                                          onPressed: () => _toggleListening('dest'),\n                                        ),",
    "suffixIcon: PulseAnimationWrapper(\n                                          isActive: _isListening && _activeSttField == 'dest',\n                                          child: IconButton(\n                                            icon: Icon(\n                                              (_isListening && _activeSttField == 'dest') \n                                                  ? Icons.mic \n                                                  : Icons.mic_none,\n                                              color: (_isListening && _activeSttField == 'dest') \n                                                  ? Colors.redAccent \n                                                  : const Color(0xFF666666),\n                                            ),\n                                            onPressed: () => _toggleListening('dest'),\n                                          ),\n                                        ),"
  );

  // 5. Add floating toast
  content = content.replaceFirst(
    "            AnimatedOpacity(\n              opacity: _isPanelVisible ? 1.0 : 0.0,",
    "            if (_isListening)\n              Positioned(\n                bottom: MediaQuery.of(context).viewInsets.bottom + 120,\n                left: 16,\n                right: 16,\n                child: Center(\n                  child: Container(\n                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),\n                    decoration: BoxDecoration(\n                      color: Colors.black.withOpacity(0.8),\n                      borderRadius: BorderRadius.circular(30),\n                      border: Border.all(color: const Color(0xFFFFC700).withOpacity(0.5)),\n                      boxShadow: [\n                        BoxShadow(\n                          color: Colors.black.withOpacity(0.5),\n                          blurRadius: 10,\n                          offset: const Offset(0, 4),\n                        ),\n                      ],\n                    ),\n                    child: Text(\n                      _activeSttField == 'origin' \n                          ? '🎤 출발지를 말씀해 주세요...' \n                          : '🎤 도착지를 말씀해 주세요...',\n                      style: const TextStyle(\n                        color: Colors.white,\n                        fontSize: 15,\n                        fontWeight: FontWeight.w600,\n                      ),\n                    ),\n                  ),\n                ),\n              ),\n            AnimatedOpacity(\n              opacity: _isPanelVisible ? 1.0 : 0.0,"
  );

  file.writeAsStringSync(content);
}
