import re

with open('lib/ui/overlay/quick_entry_popup_form.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace origin mic
pattern1 = r"(suffixIcon:\s*)(IconButton\(\s*icon:\s*Icon\(\s*\(\_isListening\s*&&\s*\_activeSttField\s*==\s*'origin'\)\s*\?\s*Icons\.mic\s*:\s*Icons\.mic_none,\s*color:\s*\(\_isListening\s*&&\s*\_activeSttField\s*==\s*'origin'\)\s*\?\s*Colors\.redAccent\s*:\s*const\s*Color\(0xFF666666\),\s*\),\s*onPressed:\s*\(\)\s*=>\s*\_toggleListening\('origin'\),\s*\))"
content = re.sub(pattern1, r"\1PulseAnimationWrapper(isActive: _isListening && _activeSttField == 'origin', child: \2)", content)

# Replace dest mic
pattern2 = r"(suffixIcon:\s*)(IconButton\(\s*icon:\s*Icon\(\s*\(\_isListening\s*&&\s*\_activeSttField\s*==\s*'dest'\)\s*\?\s*Icons\.mic\s*:\s*Icons\.mic_none,\s*color:\s*\(\_isListening\s*&&\s*\_activeSttField\s*==\s*'dest'\)\s*\?\s*Colors\.redAccent\s*:\s*const\s*Color\(0xFF666666\),\s*\),\s*onPressed:\s*\(\)\s*=>\s*\_toggleListening\('dest'\),\s*\))"
content = re.sub(pattern2, r"\1PulseAnimationWrapper(isActive: _isListening && _activeSttField == 'dest', child: \2)", content)

# Add floating message at the end of stack
if '출발지를 말씀해 주세요' not in content:
    stack_pattern = r"(\s+)(\]\s*,\s*\)\s*;\s*\})"
    floating_msg = r"""
          if (_isListening)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isListening ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _activeSttField == 'origin' ? '출발지를 말씀해 주세요...' : '도착지를 말씀해 주세요...',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),\1\2"""
    content = re.sub(stack_pattern, floating_msg, content, count=1)

with open('lib/ui/overlay/quick_entry_popup_form.dart', 'w', encoding='utf-8') as f:
    f.write(content)
