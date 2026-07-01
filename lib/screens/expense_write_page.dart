import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../utils/formatters.dart';
import '../utils/responsive_layout.dart';
import '../utils/work_date_utils.dart';
import '../widgets/responsive_body.dart';

import '../expense_nav_bus.dart';
import '../services/expense_repository.dart';

class ExpenseWritePage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? initialExpenseDate;
  /// 목록·상세에서 [Navigator.push]로 연 경우 저장 후 pop.
  final bool closeAfterSave;

  const ExpenseWritePage({
    super.key,
    this.existing,
    this.initialExpenseDate,
    this.closeAfterSave = false,
  });

  /// 탭 작성 화면이 이미 떠 있는 경우, 목록 상세 하단 '작성'에서 날짜를 넘길 때 사용합니다.
  static final ValueNotifier<String?> pendingExpenseDateNotifier = ValueNotifier<String?>(null);

  @override
  State<ExpenseWritePage> createState() => _ExpenseWritePageState();
}

class _ExpenseWritePageState extends State<ExpenseWritePage> {
  final _amountCon = TextEditingController();
  final _memoCon = TextEditingController();
  final FocusNode _amountFocus = FocusNode();

  late String _dateYmd;
  late String _timeHm;
  String? _categoryName;
  List<String> _categories = [];
  int? _entryId;

  void _onPendingDate() {
    final v = ExpenseWritePage.pendingExpenseDateNotifier.value?.trim();
    if (v == null || v.isEmpty || !mounted || widget.existing != null) return;
    setState(() {
      _dateYmd = v;
      _timeHm = DateFormat('HH:mm').format(DateTime.now());
    });
    ExpenseWritePage.pendingExpenseDateNotifier.value = null;
  }

  @override
  void initState() {
    super.initState();
    ExpenseWritePage.pendingExpenseDateNotifier.addListener(_onPendingDate);
    final now = DateTime.now();
    if (widget.existing != null) {
      final e = widget.existing!;
      _entryId = (e['id'] as num?)?.toInt();
      _dateYmd = e['expense_date']?.toString() ?? WorkDateUtils.effectiveWorkDateYmd(now);
      try {
        final w = DateTime.parse(e['written_at']?.toString() ?? '');
        _timeHm = DateFormat('HH:mm').format(w);
      } catch (_) {
        _timeHm = DateFormat('HH:mm').format(now);
      }
      _categoryName = e['category_name']?.toString();
      _amountCon.text = NumberFormat('#,###').format((e['amount'] as num?)?.toInt() ?? 0);
      _memoCon.text = e['memo']?.toString() ?? '';
    } else {
      if (widget.initialExpenseDate != null && widget.initialExpenseDate!.trim().isNotEmpty) {
        _dateYmd = widget.initialExpenseDate!.trim();
      } else {
        final pending = ExpenseWritePage.pendingExpenseDateNotifier.value?.trim();
        if (pending != null && pending.isNotEmpty) {
          _dateYmd = pending;
          ExpenseWritePage.pendingExpenseDateNotifier.value = null;
        } else {
          _dateYmd = WorkDateUtils.effectiveWorkDateYmd(now);
        }
      }
      _timeHm = DateFormat('HH:mm').format(now);
      _categoryName = null;
    }
    _reloadCategories();
  }

  Future<void> _reloadCategories() async {
    final list = await ExpenseRepository.getCategoryNames();
    if (!mounted) return;
    setState(() {
      _categories = list;
      if (_categoryName != null && !_categories.contains(_categoryName)) {
        // 삭제된 항목명은 그대로 표시
      }
      _categoryName ??= _categories.isNotEmpty ? _categories.first : null;
    });
  }

  @override
  void dispose() {
    ExpenseWritePage.pendingExpenseDateNotifier.removeListener(_onPendingDate);
    _amountFocus.dispose();
    _amountCon.dispose();
    _memoCon.dispose();
    super.dispose();
  }

  void _onCategorySelected(String? v) {
    setState(() => _categoryName = v);
    if (v == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  Widget _buildSection({required IconData icon, required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color!,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Theme.of(context).primaryColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  int _parseAmount(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  Future<void> _save() async {
    final cat = _categoryName?.trim() ?? '';
    if (cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지출 유형을 선택해 주세요.')));
      return;
    }
    final amount = _parseAmount(_amountCon.text);
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지출 금액을 입력해 주세요.')));
      return;
    }

    DateTime writtenDt;
    try {
      writtenDt = DateFormat('yyyy-MM-dd HH:mm').parse('$_dateYmd $_timeHm');
    } catch (_) {
      writtenDt = DateTime.now();
    }
    final writtenIso = writtenDt.toIso8601String();
    final memo = _memoCon.text.trim();

    final catId = await ExpenseRepository.findCategoryIdByName(cat);

    try {
      if (_entryId != null) {
        await ExpenseRepository.updateEntry(_entryId!, {
          'expense_date': _dateYmd,
          'written_at': writtenIso,
          'category_id': catId,
          'category_name': cat,
          'amount': amount,
          'memo': memo,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지출이 수정되었습니다.')));
        if (widget.closeAfterSave) {
          Navigator.pop(context);
        } else {
          ExpenseNavBus.goToTab(1);
        }
      } else {
        await ExpenseRepository.insertEntry(
          expenseDateYmd: _dateYmd,
          writtenAtIso: writtenIso,
          categoryId: catId,
          categoryName: cat,
          amount: amount,
          memo: memo,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지출이 등록되었습니다.')));
        if (widget.closeAfterSave) {
          Navigator.pop(context);
        } else {
          ExpenseNavBus.goToTab(1);
          _resetForNewEntry();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 오류: $e')));
    }
  }

  void _resetForNewEntry() {
    final now = DateTime.now();
    setState(() {
      _entryId = null;
      _dateYmd = WorkDateUtils.effectiveWorkDateYmd(now);
      _timeHm = DateFormat('HH:mm').format(now);
      _amountCon.clear();
      _memoCon.clear();
      _categoryName = _categories.isNotEmpty ? _categories.first : null;
    });
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dateYmd) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(primary: const Color(0xFFFFC700), surface: Theme.of(context).cardTheme.color!),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (d != null && mounted) {
      setState(() => _dateYmd = DateFormat('yyyy-MM-dd').format(d));
    }
  }

  Future<void> _pickTime() async {
    final parts = _timeHm.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(primary: const Color(0xFFFFC700), surface: Theme.of(context).cardTheme.color!),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (t != null && mounted) {
      setState(() => _timeHm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _entryId != null;
    final padding = ResponsiveLayout.horizontalPadding(context);
    final formMaxW = ResponsiveLayout.formMaxWidth(MediaQuery.sizeOf(context));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardTheme.color!,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEdit ? '지출 수정' : '지출 작성',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('등록', style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ResponsiveBody(
        maxWidth: formMaxW,
        child: ListView(
        padding: EdgeInsets.all(padding),
        children: [
          _buildSection(
            icon: Icons.event_available_outlined,
            title: '지출일시',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickDate,
                    style: OutlinedButton.styleFrom(foregroundColor: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                    child: Text(_dateYmd),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickTime,
                    style: OutlinedButton.styleFrom(foregroundColor: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                    child: Text(_timeHm),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildSection(
            icon: Icons.category_outlined,
            title: '지출유형',
            child: _categories.isEmpty
                ? Text(
                    '설정에서 지출 항목을 먼저 추가해 주세요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFFF5252)),
                  )
                : DropdownButtonFormField<String>(
                    value: _categories.isEmpty
                        ? null
                        : (_categoryName != null && _categories.contains(_categoryName)
                            ? _categoryName
                            : _categories.first),
                    dropdownColor: Theme.of(context).cardTheme.color!,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)))),
                        )
                        .toList(),
                    onChanged: _onCategorySelected,
                  ),
          ),
          const SizedBox(height: 14),
          _buildSection(
            icon: Icons.payments_outlined,
            title: '지출금액',
            child: TextField(
              controller: _amountCon,
              focusNode: _amountFocus,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              inputFormatters: [thousandSeparatorFormatter],
              style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                hintText: '금액 (원)',
                hintStyle: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.3)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildSection(
            icon: Icons.sticky_note_2_outlined,
            title: '지출메모',
            child: TextField(
              controller: _memoCon,
              minLines: 3,
              maxLines: 6,
              style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                hintText: '메모 (선택)',
                hintStyle: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.35)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
