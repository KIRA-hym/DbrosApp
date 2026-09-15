import sys

def patch():
    path = 'lib/screens/write_log_page.dart'
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    find_row = '''        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                  ),
                ),
              ),
              if (labelAction != null) ...[
                SizedBox(width: 8),
                labelAction,
              ],
            ],
          ),'''
          
    replace_row = '''        children: [
          Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                ),
              ),
              if (labelAction != null) ...[
                const SizedBox(width: 8),
                labelAction!,
              ],
              const Spacer(),
            ],
          ),'''

    content = content.replace(find_row, replace_row)
    
    find_build = '''  @override
  Widget build(BuildContext context) {'''
    
    replace_build = '''  Widget _buildListeningOverlay() {
    if (!_isListening) return const SizedBox.shrink();
    return Positioned(
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
              const Icon(Icons.mic, color: Colors.redAccent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _activeSttField == 'origin' ? '출발지를 말씀해 주세요...' : '도착지를 말씀해 주세요...',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {'''
    content = content.replace(find_build, replace_build)

    find_scaffold1 = '''      return Scaffold(
        backgroundColor: const Color(0xCC000000), // 80% 불투명 검은색으로 기존 반투명 UI 유지'''
    replace_scaffold1 = '''      return Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xCC000000), // 80% 불투명 검은색으로 기존 반투명 UI 유지'''
    content = content.replace(find_scaffold1, replace_scaffold1)

    find_close1 = '''                  ),
                ),
              ),
            ),
          ),
        );
      }

      return PopScope('''
    replace_close1 = '''                  ),
                ),
              ),
            ),
          ),
          if (_isListening) _buildListeningOverlay(),
        ],
      );
    }

    return PopScope('''
    content = content.replace(find_close1, replace_close1)
    
    find_scaffold2 = '''        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,'''
    replace_scaffold2 = '''        child: Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,'''
    content = content.replace(find_scaffold2, replace_scaffold2)
    
    find_close2 = '''                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationInputField('''
    replace_close2 = '''                  );
                },
              ),
            ),
          ),
          if (_isListening) _buildListeningOverlay(),
        ],
      );
    },
  );
}

  Widget _buildLocationInputField('''
  
    content = content.replace(find_close2, replace_close2)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
        
patch()
print('Python patch done.')
