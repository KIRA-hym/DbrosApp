import 'package:flutter/material.dart';

import '../repositories/push_repository.dart';

/// 오너(마스터) 전용 — 전체 사용자 FCM 푸시 발송 다이얼로그.
class AdminPushDialog extends StatefulWidget {
  const AdminPushDialog({super.key});

  /// 다이얼로그를 띄우는 편의 메서드.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AdminPushDialog(),
    );
  }

  @override
  State<AdminPushDialog> createState() => _AdminPushDialogState();
}

class _AdminPushDialogState extends State<AdminPushDialog> {
  final _titleCon = TextEditingController();
  final _bodyCon = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;

  @override
  void dispose() {
    _titleCon.dispose();
    _bodyCon.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await PushRepository.instance.requestAdminPush(
        _titleCon.text.trim(),
        _bodyCon.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('푸시 발송 요청이 등록되었습니다.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('발송 요청 실패: $e'),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _inputDeco(String label, String hint) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9FA3AE)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF5C6070)),
        filled: true,
        fillColor: const Color(0xFF121418),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2E38)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFFC700)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF5252)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF5252)),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF5252)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F222A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.campaign_rounded, color: Color(0xFFFFC700), size: 22),
          SizedBox(width: 10),
          Text(
            '공지사항 푸시 발송',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '전체 사용자에게 FCM 푸시 알림을 발송합니다.',
              style: TextStyle(color: Color(0xFF9FA3AE), fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleCon,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('제목', '알림 제목을 입력하세요'),
              maxLength: 60,
              counterStyle: const TextStyle(color: Color(0xFF5C6070)),
              textInputAction: TextInputAction.next,
              enabled: !_sending,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '제목을 입력해 주세요.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyCon,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('내용', '공지 내용을 입력하세요'),
              maxLines: 4,
              maxLength: 300,
              counterStyle: const TextStyle(color: Color(0xFF5C6070)),
              enabled: !_sending,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '내용을 입력해 주세요.';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('취소', style: TextStyle(color: Color(0xFF9FA3AE))),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFC700),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black54,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? '발송 중…' : '발송'),
        ),
      ],
    );
  }
}
