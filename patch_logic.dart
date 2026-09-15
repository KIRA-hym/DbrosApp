import 'dart:io';

void main() {
  final file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();
  
  // 1. Add imports
  int insertIdx = lines.indexWhere((l) => l.startsWith('import \'package:intl/intl.dart\';'));
  if (insertIdx != -1) {
    lines.insert(insertIdx + 1, 'import \\'package:speech_to_text/speech_to_text.dart\\' as stt;');
    lines.insert(insertIdx + 2, 'import \\'package:permission_handler/permission_handler.dart\\';');
  }
  
  int stubIdx = lines.indexWhere((l) => l.contains('../utils/maps_web_stub.dart'));
  if (stubIdx != -1) {
    lines.insert(stubIdx + 1, 'import \\'../widgets/pulse_animation_wrapper.dart\\';');
  }

  // 2. Add state variables
  int stateIdx = lines.indexWhere((l) => l.contains('final _memoCon = TextEditingController();'));
  if (stateIdx != -1) {
    lines.insert(stateIdx + 1, '  stt.SpeechToText _speechToText = stt.SpeechToText();');
    lines.insert(stateIdx + 2, '  bool _isListening = false;');
    lines.insert(stateIdx + 3, '  String _activeSttField = \\'\\';');
  }

  // 3. Add methods before dispose
  int disposeIdx = lines.indexWhere((l) => l.contains('void dispose() {'));
  if (disposeIdx != -1) {
    // Look backwards for @override
    if (lines[disposeIdx - 1].contains('@override')) {
       disposeIdx--;
    }
    
    final methods = '''
  void _startListeningWithGuard(String field) {
    ProFeatureGuard.checkAndRun(
      context: context,
      featureKey: 'voice_entry',
      canUseFree: () async => false,
      canUseWithAd: () async => true,
      onGranted: (isFreeTicket) {
        _toggleListening(field);
      },
    );
  }

  void _toggleListening(String field) async {
    if (_isListening && _activeSttField == field) {
      _speechToText.stop();
      setState(() {
        _isListening = false;
        _activeSttField = '';
      });
      return;
    }

    var status = await Permission.microphone.status;
    if (status != PermissionStatus.granted) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2D34),
          title: const Text('마이크 권한 필요', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('음성 인식을 위해 마이크 권한이 필요합니다.\\n설정에서 권한을 허용해주세요.', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('설정으로 이동', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        ),
      );
      return;
    }

    bool available = false;
    try {
      available = await _speechToText.initialize(
        onError: (error) {
          debugPrint('STT Error: \');
          if (mounted) {
            setState(() {
              _isListening = false;
              _activeSttField = '';
            });
          }
        },
      );
    } catch (e) {
      debugPrint('STT Init Exception: \');
    }

    if (available) {
      setState(() {
        _isListening = true;
        _activeSttField = field;
      });
      _speechToText.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            if (field == 'origin') {
              _startLocCon.text = result.recognizedWords;
            } else if (field == 'dest') {
              _endLocCon.text = result.recognizedWords;
            }
          });
          if (result.finalResult) {
            setState(() {
              _isListening = false;
              _activeSttField = '';
            });
          }
        },
        localeId: 'ko_KR',
      );
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2D34),
          title: const Text('음성 인식 오류', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('기기에서 음성 인식(STT)을 초기화할 수 없습니다.\\n구글 음성 인식 엔진이 켜져 있는지 확인해주세요.', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        ),
      );
    }
  }
''';
    lines.insertAll(disposeIdx, methods.split('\\n'));
  }

  // 4. Update UI for 'origin' 
  // We look for 'Text(' and the next line '"출발지",'
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('child: Text(') && i + 1 < lines.length && lines[i+1].contains('"출발지",')) {
      // Found an origin label block. 
      // Skip ahead to find the closing parentheses of Expanded.
      int indent = lines[i].indexOf('child: Text(');
      String spaces = ' ' * indent;
      int endIndex = i;
      while (!lines[endIndex].contains('\),') && !lines[endIndex].contains('\)')) {
        endIndex++;
      }
      
      final micButton = '''
\PulseAnimationWrapper(
\  isActive: _isListening && _activeSttField == 'origin',
\  child: IconButton(
\    padding: EdgeInsets.zero,
\    constraints: const BoxConstraints(),
\    icon: Icon(
\      (_isListening && _activeSttField == 'origin') ? Icons.mic : Icons.mic_none,
\      size: 20,
\      color: (_isListening && _activeSttField == 'origin') ? Colors.redAccent : const Color(0xFF666666),
\    ),
\    onPressed: () => _startListeningWithGuard('origin'),
\  ),
\),''';
      
      lines.insertAll(endIndex + 1, micButton.split('\\n'));
      i = endIndex + micButton.split('\\n').length;
    }
  }

  // 5. Update _buildLocationInputField
  int locInputIdx = lines.indexWhere((l) => l.contains('Widget _buildLocationInputField('));
  if (locInputIdx != -1) {
    int endArgs = lines.indexWhere((l) => l.contains('}) {'), locInputIdx);
    lines.insert(endArgs, '    Widget? labelAction,');
    
    int rowInsert = lines.indexWhere((l) => l.contains('crossAxisAlignment: CrossAxisAlignment.start,'), locInputIdx);
    int textStart = lines.indexWhere((l) => l.contains('Text('), rowInsert);
    int textEnd = lines.indexWhere((l) => l.contains('),'), textStart + 5);
    
    lines[textStart] = '        Row(children: [ Expanded(child: Text(';
    lines.insert(textEnd + 1, '            ), if (labelAction != null) ...[SizedBox(width: 8), labelAction] ]),');
  }

  // 6. Update _buildLocationInputField calls to pass labelAction
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('_buildLocationInputField(')) {
      int endCall = i;
      while(!lines[endCall].contains('),') && !lines[endCall].contains(');')) {
         endCall++;
      }
      
      final labelAction = '''
              labelAction: PulseAnimationWrapper(
                isActive: _isListening && _activeSttField == 'dest',
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    (_isListening && _activeSttField == 'dest') ? Icons.mic : Icons.mic_none,
                    size: 20,
                    color: (_isListening && _activeSttField == 'dest') ? Colors.redAccent : const Color(0xFF666666),
                  ),
                  onPressed: () => _startListeningWithGuard('dest'),
                ),
              ),''';
      lines.insertAll(endCall, labelAction.split('\\n'));
      i = endCall + labelAction.split('\\n').length;
    }
  }

  file.writeAsStringSync(lines.join('\\n'));
  print('Patch applied successfully via dart script.');
}
