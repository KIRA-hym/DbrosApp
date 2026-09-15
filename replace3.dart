import 'dart:io';

void main() {
  final file = File('lib/screens/write_log_page.dart');
  String content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');

  final target1 = '''            _buildLocationInputField(
              _endLocCon,
              label: "도착지",
              focusNode: _endLocFocusNode,
              suffixIcon: kMapFeaturesEnabled
                  ? _pinPickButton(forStart: false)
                  : null,
            ),''';
  final replacement1 = '''            _buildLocationInputField(
              _endLocCon,
              label: "도착지",
              focusNode: _endLocFocusNode,
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
              ),
              suffixIcon: kMapFeaturesEnabled
                  ? _pinPickButton(forStart: false)
                  : null,
            ),''';

  final target2 = '''          _buildLocationInputField(
            _endLocCon,
            label: "도착지",
            focusNode: _endLocFocusNode,
            isError: _isEndLocMissing,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,''';
  final replacement2 = '''          _buildLocationInputField(
            _endLocCon,
            label: "도착지",
            focusNode: _endLocFocusNode,
            isError: _isEndLocMissing,
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
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,''';

  if (content.contains(target1)) {
    content = content.replaceFirst(target1, replacement1);
    print('Replaced target1');
  } else {
    print('Target1 not found');
  }

  if (content.contains(target2)) {
    content = content.replaceFirst(target2, replacement2);
    print('Replaced target2');
  } else {
    print('Target2 not found');
  }

  file.writeAsStringSync(content);
}
