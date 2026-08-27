import 'dart:io';
void main() {
  final file = File('lib/ui/overlay/quick_entry_popup_form.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('pulse_animation_wrapper.dart')) {
    content = content.replaceFirst(
      \"import '../../utils/drive_time_format.dart';\", 
      \"import '../../utils/drive_time_format.dart';\\nimport '../../widgets/pulse_animation_wrapper.dart';\"
    );
  }

  content = content.replaceAllMapped(
    RegExp(r\"(suffixIcon:\\s*)(IconButton\\(\\s*icon:\\s*Icon\\(\\s*\\(\\_isListening\\s*&&\\s*\\_activeSttField\\s*==\\s*'origin'\\)\\s*\\?\\s*Icons\\.mic\\s*:\\s*Icons\\.mic_none,\\s*color:\\s*\\(\\_isListening\\s*&&\\s*\\_activeSttField\\s*==\\s*'origin'\\)\\s*\\?\\s*Colors\\.redAccent\\s*:\\s*const\\s*Color\\(0xFF666666\\),\\s*\\),\\s*onPressed:\\s*\\(\\)\\s*=>\\s*\\_toggleListening\\('origin'\\),\\s*\\))\"),
    (m) => \"\PulseAnimationWrapper(isAnimating: _isListening && _activeSttField == 'origin', child: \)\"
  );
  
  content = content.replaceAllMapped(
    RegExp(r\"(suffixIcon:\\s*)(IconButton\\(\\s*icon:\\s*Icon\\(\\s*\\(\\_isListening\\s*&&\\s*\\_activeSttField\\s*==\\s*'dest'\\)\\s*\\?\\s*Icons\\.mic\\s*:\\s*Icons\\.mic_none,\\s*color:\\s*\\(\\_isListening\\s*&&\\s*\\_activeSttField\\s*==\\s*'dest'\\)\\s*\\?\\s*Colors\\.redAccent\\s*:\\s*const\\s*Color\\(0xFF666666\\),\\s*\\),\\s*onPressed:\\s*\\(\\)\\s*=>\\s*\\_toggleListening\\('dest'\\),\\s*\\))\"),
    (m) => \"\PulseAnimationWrapper(isAnimating: _isListening && _activeSttField == 'dest', child: \)\"
  );

  file.writeAsStringSync(content);
  print('done');
}
