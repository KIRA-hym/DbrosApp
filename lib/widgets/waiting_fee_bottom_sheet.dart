import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../utils/waiting_fee_calculator.dart';
import '../utils/app_bottom_sheet.dart';

/// 홈 빠른 작업에서 여는 대기비용 계산 바텀시트.
class WaitingFeeBottomSheet extends StatefulWidget {
  const WaitingFeeBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F222A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const WaitingFeeBottomSheet(),
    );
  }

  @override
  State<WaitingFeeBottomSheet> createState() => _WaitingFeeBottomSheetState();
}

class _WaitingFeeBottomSheetState extends State<WaitingFeeBottomSheet> {
  static final _currency = NumberFormat('#,###');

  late String _selectedCompanyId;
  final _minutesController = TextEditingController();
  int? _fee;

  @override
  void initState() {
    super.initState();
    _selectedCompanyId = WaitingFeeCompany.all.first.id;
    _minutesController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final minutes = int.tryParse(_minutesController.text.trim());
    setState(() {
      if (minutes == null) {
        _fee = null;
        return;
      }
      _fee = WaitingFeeCompany.calculateFor(_selectedCompanyId, minutes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final company = WaitingFeeCompany.byId(_selectedCompanyId) ?? WaitingFeeCompany.all.first;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF6E717C),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '대기비용 계산',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '업체와 대기시간(분)을 입력하면 참고용 대기비용을 계산합니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF9FA3AE),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 18),
          Text(
            '업체',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: const Color(0xFF9FA3AE)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCompanyId,
            dropdownColor: const Color(0xFF16181D),
            decoration: _fieldDecoration(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            items: [
              for (final item in WaitingFeeCompany.all)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCompanyId = value);
              _recalculate();
            },
          ),
          const SizedBox(height: 14),
          Text(
            '대기시간(분)',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: const Color(0xFF9FA3AE)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _minutesController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            decoration: _fieldDecoration(hintText: '예: 35'),
          ),
          const SizedBox(height: 14),
          Text(
            company.ruleSummary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6E717C),
                  height: 1.35,
                ),
          ),
          if (_selectedCompanyId == 'daerigo') ...[
            const SizedBox(height: 8),
            Text(
              '도착 후 고객 취소 시 취소비 10,000원은 별도입니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6E717C),
                    height: 1.35,
                  ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF16181D),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text(
                  '대기비용',
                  style: TextStyle(
                    color: Color(0xFF9FA3AE),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _fee == null ? '-' : '${_currency.format(_fee)}원',
                  style: const TextStyle(
                    color: Color(0xFFFFC700),
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: const Color(0xFF121418),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF16181D),
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF6E717C)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFC700)),
      ),
    );
  }
}
