import 'dart:ui';
import 'package:flutter/material.dart';

/// 항목 목록 관리 다이얼로그 (프로그램 / 지출항목 / 수익항목 공용).
///
/// 글래스모피즘 스타일(AppGlassDialog 동일)로 표시되며:
/// - 상단 타이틀 행 우측에 [+ 추가] 버튼
/// - 추가 버튼 누르면 하단 입력란 노출
/// - 입력 중에는 버튼이 [저장]으로 변경
/// - 각 항목 우측에 🗑️ 삭제 버튼
class ListManageDialog extends StatefulWidget {
  const ListManageDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.hintText,
    required this.onAdd,
    required this.onDelete,
    this.accentColor = const Color(0xFFFFC700),
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final String hintText;
  final Future<bool> Function(String item) onAdd;
  final Future<void> Function(int index, String item) onDelete;
  final Color accentColor;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<String> items,
    required String hintText,
    required Future<bool> Function(String item) onAdd,
    required Future<void> Function(int index, String item) onDelete,
    Color accentColor = const Color(0xFFFFC700),
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => ListManageDialog(
        title: title,
        icon: icon,
        items: items,
        hintText: hintText,
        onAdd: onAdd,
        onDelete: onDelete,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<ListManageDialog> createState() => _ListManageDialogState();
}

class _ListManageDialogState extends State<ListManageDialog> {
  late List<String> _items;
  final _inputCon = TextEditingController();
  final _inputFocus = FocusNode();
  bool _showInput = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _inputCon.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _inputCon.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  bool get _hasInput => _inputCon.text.trim().isNotEmpty;

  Future<void> _save() async {
    final text = _inputCon.text.trim();
    if (text.isEmpty) return;
    if (_items.contains(text)) {
      _showSnack('이미 존재하는 항목입니다.');
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onAdd(text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _items.add(text);
        _inputCon.clear();
        _showInput = false;
      }
    });
  }

  Future<void> _delete(int index) async {
    final item = _items[index];
    await widget.onDelete(index, item);
    if (!mounted) return;
    setState(() => _items.removeAt(index));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: const Color(0xCC1F222A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 타이틀 행 ───────────────────────────────────
                Row(
                  children: [
                    Icon(widget.icon, color: widget.accentColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontFamily: 'GmarketSans',
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    // 추가 / 저장 버튼
                    _AddSaveButton(
                      showInput: _showInput,
                      hasInput: _hasInput,
                      saving: _saving,
                      accentColor: widget.accentColor,
                      onAdd: () => setState(() {
                        _showInput = true;
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _inputFocus.requestFocus());
                      }),
                      onSave: _save,
                      onCancel: () => setState(() {
                        _showInput = false;
                        _inputCon.clear();
                      }),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),

                // ─── 입력란 (추가 눌렀을 때, 목록 위) ───────────
                if (_showInput) ...[
                  _InputRow(
                    controller: _inputCon,
                    focusNode: _inputFocus,
                    hintText: widget.hintText,
                    accentColor: widget.accentColor,
                    onSubmit: _save,
                  ),
                  const SizedBox(height: 10),
                ],

                // ─── 항목 목록 ───────────────────────────────────
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: _items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              '항목이 없습니다.',
                              style: TextStyle(color: Colors.white38, fontSize: 14),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _ItemRow(
                            item: _items[i],
                            onDelete: () => _delete(i),
                          ),
                        ),
                ),

                // ─── 닫기 버튼 ───────────────────────────────────
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기', style: TextStyle(color: Color(0xFF9FA3AE))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 추가/저장/취소 버튼 ─────────────────────────────────────────────

class _AddSaveButton extends StatelessWidget {
  const _AddSaveButton({
    required this.showInput,
    required this.hasInput,
    required this.saving,
    required this.accentColor,
    required this.onAdd,
    required this.onSave,
    required this.onCancel,
  });

  final bool showInput;
  final bool hasInput;
  final bool saving;
  final Color accentColor;
  final VoidCallback onAdd;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (!showInput) {
      return TextButton.icon(
        onPressed: onAdd,
        icon: Icon(Icons.add, size: 16, color: accentColor),
        label: Text('추가', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          backgroundColor: accentColor.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    // 입력 중 — 저장 or 취소
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: onCancel,
          child: const Text('취소', style: TextStyle(color: Color(0xFF9FA3AE), fontSize: 13)),
        ),
        const SizedBox(width: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: hasInput
              ? TextButton(
                  key: const ValueKey('save'),
                  onPressed: saving ? null : onSave,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC700).withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFC700)),
                        )
                      : const Text(
                          '저장',
                          style: TextStyle(
                            color: Color(0xFFFFC700),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                )
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
      ],
    );
  }
}

// ─── 항목 행 ─────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onDelete});
  final String item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              item,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 19),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ─── 입력란 ──────────────────────────────────────────────────────────

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.accentColor,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final Color accentColor;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmit(),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF6E717C), fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
