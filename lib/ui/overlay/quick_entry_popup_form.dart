import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:dbros_app/services/premium_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../services/auto_register_notification_service.dart';
import '../../data/repositories/address_repository.dart';
import '../../services/overlay_manager.dart';
import '../../services/settings_service.dart';
import '../../services/font_size_service.dart';
import '../../services/db_helper.dart';
import '../../utils/work_date_utils.dart';
import '../../utils/drive_time_format.dart';
import '../../widgets/pulse_animation_wrapper.dart';

class QuickEntryPopupForm extends StatefulWidget {
  final VoidCallback? onClose;
  const QuickEntryPopupForm({Key? key, this.onClose}) : super(key: key);

  @override
  State<QuickEntryPopupForm> createState() => _QuickEntryPopupFormState();
}

class _QuickEntryPopupFormState extends State<QuickEntryPopupForm> {
  bool _isPanelVisible = false; // ?µÎì±Î°??ùÏóÖ ?†ÎãàÎ©îÏù¥???∏Î¶¨Í±?

  double _opacity = 0.9;
  stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  String _activeSttField = '';
  String _selectedProgram = '';
  late List<String> _programs;

  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  List<String> _originSuggestions = [];
  List<String> _destSuggestions = [];
  bool _isOriginFocused = false;
  bool _isDestFocused = false;

  List<String> _distinctLocations = [];

  @override
  void initState() {
    super.initState();
    DriveLogDatabase.instance.getDistinctLocations().then((list) {
      if (mounted) setState(() => _distinctLocations = list);
    });

    _programs = SettingsService.programList;
    if (_programs.isNotEmpty && _selectedProgram.isEmpty) {
      _selectedProgram = _programs.first;
    }
    
    _originController.addListener(() => _searchOrigin(_originController.text));
    _destController.addListener(() => _searchDest(_destController.text));

    // ?§Ïù¥?ºÎ°úÍ∑??ùÏóÖ???????§Ïù¥?∞Î∏å Ï∞??ïÏû•(matchParent) ?úÍ∞Ñ??Î≤åÏñ¥Ï£ºÏñ¥ ?îÏÉÅ/Ï∞åÍ∑∏?¨Ïßê Î∞©Ï?
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _isPanelVisible = true);
    });
  }

  void _toggleListening(String field) async {
    await SettingsService.reload();
    if (!PremiumService.isPremium) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2D34),
          title: const Text('?ÑÎ¶¨ÎØ∏ÏóÑ Í∏∞Îä•', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('?åÏÑ± ?∏Ïãù ???±Î°ù?Ä ?ÑÎ¶¨ÎØ∏ÏóÑ Í∏∞Îä•?ÖÎãà??\n???§Ï†ï?êÏÑú ?ÑÎ¶¨ÎØ∏ÏóÑ??Íµ¨ÎèÖ?¥Ï£º?∏Ïöî.', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('?ïÏù∏', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        ),
      );
      return;
    }

    if (_isListening && _activeSttField == field) {
      _speechToText.stop();
      setState(() {
        _isListening = false;
        _activeSttField = '';
      });
      return;
    }

    // 1. ?§Î≤Ñ?àÏù¥(Î∞±Í∑∏?ºÏö¥???êÏÑú??Í∂åÌïú ?îÏ≤≠(request) ?§Ïù¥?ºÎ°úÍ∑∏Í? ???????àÏúºÎØÄÎ°?statusÎß?Ï≤¥ÌÅ¨
    var status = await Permission.microphone.status;
    if (status != PermissionStatus.granted) {
      // ÎßåÏïΩ Í∂åÌïú???ÜÎã§Î©??¨Í∏∞???§Ïù¥?ºÎ°úÍ∑??ÑÏõå ?àÎÇ¥
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2D34),
          title: const Text('ÎßàÏù¥??Í∂åÌïú ?ÑÏöî', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('?åÏÑ± ?∏Ïãù???ÑÌï¥ ÎßàÏù¥??Í∂åÌïú???ÑÏöî?©Îãà??\n?§Î≤Ñ?àÏù¥ Ï∞ΩÏùÑ ?´Í≥† ??Î≥∏Ï≤¥Î•??¥Í±∞???§Ï†ï?êÏÑú Í∂åÌïú???àÏö©?¥Ï£º?∏Ïöî.', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ï∑®ÏÜå', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('?§Ï†ï?ºÎ°ú ?¥Îèô', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        ),
      );
      return;
    }

    // 2. STT Ï¥àÍ∏∞?????êÎü¨ ÏΩúÎ∞± Ï∂îÍ??òÏó¨ Î®πÌÜµ ?êÏù∏ ?åÏïÖ
    bool available = false;
    try {
      available = await _speechToText.initialize(
        onError: (error) {
          print('STT Error: ${error.errorMsg}');
          setState(() {
            _isListening = false;
            _activeSttField = '';
          });
        },
      );
    } catch (e) {
      print('STT Init Exception: $e');
    }
    
    if (available) {
      setState(() {
        _isListening = true;
        _activeSttField = field;
      });
      _speechToText.listen(
        onResult: (result) {
          setState(() {
            if (field == 'origin') {
              _originController.text = result.recognizedWords;
            } else if (field == 'dest') {
              _destController.text = result.recognizedWords;
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
      // Ï¥àÍ∏∞???§Ìå® ??(Í∏∞Í∏∞Í∞Ä STT ÎØ∏Ï?????
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2D34),
          title: const Text('?åÏÑ± ?∏Ïãù ?§Î•ò', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('Í∏∞Í∏∞?êÏÑú ?åÏÑ± ?∏Ïãù(STT)??Ï¥àÍ∏∞?îÌï† ???ÜÏäµ?àÎã§.\nÍµ¨Í? ?åÏÑ± ?∏Ïãù ?îÏßÑ??ÏºúÏ†∏ ?àÎäîÏßÄ ?ïÏù∏?¥Ï£º?∏Ïöî.', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('?ïÏù∏', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _resetForm() {
    setState(() {
      _selectedProgram = 'Î°úÏ?';
      _originController.clear();
      _destController.clear();
      _priceController.clear();
      _originSuggestions.clear();
      _destSuggestions.clear();
    });
  }

  Future<void> _searchOrigin(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() => _originSuggestions = []);
      return;
    }
    final queryLower = query.toLowerCase();
    final mode = SettingsService.addressSearchMode;
    
    List<String> historyMatches = [];
    Set<String> historySet = {};
    if (mode == 'both' || mode == 'history') {
      final historyRaw = _distinctLocations
          .where((s) => s.toLowerCase().contains(queryLower))
          .toList();
      historyMatches = historyRaw.map((s) => '[ÏµúÍ∑º] $s').toList();
      historySet = historyRaw.toSet();
    }
    
    List<String> filteredDbMatches = [];
    if (mode == 'both' || mode == 'address') {
      final dbMatches = await AddressRepository().search(query);
      filteredDbMatches = dbMatches.where((s) => !historySet.contains(s)).toList();
    }
    
    if (mounted) setState(() => _originSuggestions = [...historyMatches, ...filteredDbMatches]);
  }

  Future<void> _searchDest(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() => _destSuggestions = []);
      return;
    }
    final queryLower = query.toLowerCase();
    final mode = SettingsService.addressSearchMode;
    
    List<String> historyMatches = [];
    Set<String> historySet = {};
    if (mode == 'both' || mode == 'history') {
      final historyRaw = _distinctLocations
          .where((s) => s.toLowerCase().contains(queryLower))
          .toList();
      historyMatches = historyRaw.map((s) => '[ÏµúÍ∑º] $s').toList();
      historySet = historyRaw.toSet();
    }
    
    List<String> filteredDbMatches = [];
    if (mode == 'both' || mode == 'address') {
      final dbMatches = await AddressRepository().search(query);
      filteredDbMatches = dbMatches.where((s) => !historySet.contains(s)).toList();
    }
    
    if (mounted) setState(() => _destSuggestions = [...historyMatches, ...filteredDbMatches]);
  }

  Future<void> _submit() async {
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    final priceStr = _priceController.text.trim().replaceAll(',', '');

    if (origin.isEmpty || dest.isEmpty || priceStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Î™®Îì† ??™©???ÖÎ†•?¥Ï£º?∏Ïöî.')));
      return;
    }

    final price = int.tryParse(priceStr) ?? 0;

    final now = DateTime.now();
    final work = WorkDateUtils.effectiveWorkDateYmd(now);
    final timeStr = formatDriveTimeHm(now);
    final drive = WorkDateUtils.resolveDriveDateForNightShift(work, timeStr);
    final nowIso = now.toIso8601String();

    int fee = SettingsService.deductionFeeFromGross(price, _selectedProgram);
    int insurance = SettingsService.calculatePerTripInsurance(_selectedProgram);
    int netIncome = price - fee - insurance;

    final row = <String, dynamic>{
      'work_date': work,
      'drive_date': drive,
      'drive_time': timeStr,
      'program': _selectedProgram,
      'gross_fare': price,
      'fee': fee,
      'insurance_fee': insurance,
      'transport_cost': 0,
      'net_income': netIncome,
      'start_location': origin,
      'waypoint': '',
      'end_location': dest,
      'memo': '',
      'created_at': nowIso,
      'updated_at': nowIso,
      'registration_source': 'quick',
    };

    try {
      final newId = await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
      print(
        '???µÎì±Î°??ºÏ? ?Ä???ÑÎ£å: [$_selectedProgram] $origin -> $dest (?îÍ∏à: $price)',
      );
      
      try {
        FlutterOverlayWindow.shareData({"type": "refresh_logs"});
        AutoRegisterNotificationService.instance.showQuickRegisterComplete(logId: newId);
      } catch (e) {
        debugPrint('shareData error: $e');
      }

      _resetForm();
      Future.delayed(const Duration(milliseconds: 500), () {
        _closePanel();
      });
    } catch (e) {
      print('?µÎì±Î°??êÎü¨: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('?Ä???§Ìå®: $e')));
      }
    }
  }

  void _closePanel() async {
    FocusScope.of(context).unfocus();

    // 1. Î®ºÏ? ?ùÏóÖ??fade-out
    if (mounted) {
      setState(() => _isPanelVisible = false);
    }

    // 2. fade-out ?†ÎãàÎ©îÏù¥???ÄÍ∏????´Í∏∞ ÏΩúÎ∞± ?∏Ï∂ú
    await Future.delayed(const Duration(milliseconds: 220));
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // ?úÏàò ?ùÏóÖ ?§Ïù¥?ºÎ°úÍ∑?Î∑?Î¶¨ÌÑ¥

    // Panel background color based on theme
    final isAmoled = SettingsService.isAmoledBlackNotifier.value;
    final panelBgColor = isAmoled ? Colors.black : const Color(0xFF121418);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Opacity(
        opacity: _opacity,
        child: Stack(
          children: [
            // ?§Ïù¥?ºÎ°úÍ∑?Î∞∞Í≤Ω???∞Ïπò?òÎ©¥ ?´Ìûò
            Positioned.fill(
              child: GestureDetector(
                onTap: _closePanel,
                child: Container(color: Colors.transparent),
              ),
            ),

          // Panel - _isPanelVisible???∞Îùº Î∂Ä?úÎüΩÍ≤?fade-in/out (?îÏÉÅ Î∞©Ï?)
          AnimatedOpacity(
            opacity: _isPanelVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_isPanelVisible,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: _isPanelVisible ? 1.0 : 0.0,
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: 0.9 + (0.1 * value),
                      child: child,
                    );
                  },
                  child: Opacity(
                    opacity: _opacity,
                    child: Container(
                    margin: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16,
                      left: 16,
                      right: 16,
                    ),
                    decoration: BoxDecoration(
                      color: panelBgColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: const Color(0xFFFFC700).withOpacity(0.2),
                          blurRadius: 10,
                          spreadRadius: -2,
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFF333333),
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.bolt,
                                    color: const Color(0xFFFFC700),
                                    size: FontSizeService.getScaledFontSize(24),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '?ºÏ? ?µÎì±Î°?,
                                    style: TextStyle(
                                      fontSize:
                                          FontSizeService.getScaledFontSize(18),
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  InkWell(
                                    onTap: _resetForm,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2A2D34),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF444444),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.refresh,
                                        color: Color(0xFFCCCCCC),
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Icon(
                                    Icons.opacity,
                                    color: const Color(0xFF888888),
                                    size: FontSizeService.getScaledFontSize(16),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    height: 24,
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 12,
                                            ),
                                        activeTrackColor: const Color(
                                          0xFFFFC700,
                                        ),
                                        inactiveTrackColor: const Color(
                                          0xFF444444,
                                        ),
                                        thumbColor: const Color(0xFFFFC700),
                                      ),
                                      child: Slider(
                                        value: _opacity,
                                        min: 0.2,
                                        max: 1.0,
                                        onChanged: (val) =>
                                            setState(() => _opacity = val),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _closePanel,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF555555),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Color(0xFFCCCCCC),
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Form Row: ÏΩúÏ†ïÎ≥?
                          _buildFormRow(
                            icon: Icons.apps,
                            label: 'ÏΩúÏ†ïÎ≥?,
                            child: DropdownButtonHideUnderline(
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2024),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF444444),
                                  ),
                                ),
                                child: DropdownButton<String>(
                                  value: _selectedProgram,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Color(0xFF888888),
                                  ),
                                  dropdownColor: const Color(0xFF1E2024),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: FontSizeService.getScaledFontSize(
                                      15,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onChanged: (String? newValue) {
                                    if (newValue != null)
                                      setState(
                                        () => _selectedProgram = newValue,
                                      );
                                  },
                                  items: _programs
                                      .map<DropdownMenuItem<String>>((
                                        String value,
                                      ) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      })
                                      .toList(),
                                ),
                              ),
                            ),
                          ),

                          // Form Row: ?îÍ∏à
                          _buildFormRow(
                            icon: Icons.account_balance_wallet,
                            iconColor: const Color(0xFFFFC700),
                            label: '??Í∏?,
                            child: SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _priceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [CurrencyInputFormatter()],
                                style: TextStyle(
                                  color: const Color(0xFFFFC700),
                                  fontSize: FontSizeService.getScaledFontSize(
                                    16,
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: _inputDecoration(
                                  '',
                                  suffixText: '??,
                                  suffixColor: const Color(0xFFFFC700),
                                ),
                              ),
                            ),
                          ),

                          // Form Row: Ï∂úÎ∞úÏßÄ
                          _buildFormRow(
                            icon: Icons.my_location,
                            iconColor: const Color(0xFF4A90E2),
                            label: 'Ï∂úÎ∞úÏßÄ',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 44,
                                  child: Focus(
                                    onFocusChange: (f) =>
                                        setState(() => _isOriginFocused = f),
                                    child: TextField(
                                      controller: _originController,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize:
                                            FontSizeService.getScaledFontSize(
                                              15,
                                            ),
                                      ),
                                      decoration: _inputDecoration(
                                        '',
                                        suffixIcon: PulseAnimationWrapper(isActive: _isListening && _activeSttField == 'origin', child: IconButton(
                                          icon: Icon(
                                            (_isListening && _activeSttField == 'origin') 
                                                ? Icons.mic 
                                                : Icons.mic_none,
                                            color: (_isListening && _activeSttField == 'origin') 
                                                ? Colors.redAccent 
                                                : const Color(0xFF666666),
                                          ),
                                          onPressed: () => _toggleListening('origin'),
                                        )),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_isOriginFocused &&
                                    _originSuggestions.isNotEmpty)
                                  _buildSuggestionBox(_originSuggestions, (
                                    val,
                                  ) {
                                    _originController.text = val.startsWith('[ÏµúÍ∑º] ') ? val.substring(5) : val;
                                    setState(() {
                                      _originSuggestions = [];
                                      _isOriginFocused = false;
                                    });
                                    FocusScope.of(context).unfocus();
                                  }),
                              ],
                            ),
                          ),

                          // Form Row: ?ÑÏ∞©ÏßÄ
                          _buildFormRow(
                            icon: Icons.flag,
                            iconColor: const Color(0xFFFF6B6B),
                            label: '?ÑÏ∞©ÏßÄ',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 44,
                                  child: Focus(
                                    onFocusChange: (f) =>
                                        setState(() => _isDestFocused = f),
                                    child: TextField(
                                      controller: _destController,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize:
                                            FontSizeService.getScaledFontSize(
                                              15,
                                            ),
                                      ),
                                      decoration: _inputDecoration(
                                        '',
                                        suffixIcon: PulseAnimationWrapper(isActive: _isListening && _activeSttField == 'dest', child: IconButton(
                                          icon: Icon(
                                            (_isListening && _activeSttField == 'dest') 
                                                ? Icons.mic 
                                                : Icons.mic_none,
                                            color: (_isListening && _activeSttField == 'dest') 
                                                ? Colors.redAccent 
                                                : const Color(0xFF666666),
                                          ),
                                          onPressed: () => _toggleListening('dest'),
                                        )),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_isDestFocused &&
                                    _destSuggestions.isNotEmpty)
                                  _buildSuggestionBox(_destSuggestions, (val) {
                                    _destController.text = val.startsWith('[ÏµúÍ∑º] ') ? val.substring(5) : val;
                                    setState(() {
                                      _destSuggestions = [];
                                      _isDestFocused = false;
                                    });
                                    FocusScope.of(context).unfocus();
                                  }),
                              ],
                            ),
                            isLast: true,
                          ),

                          const SizedBox(height: 24),

                          // Submit Button
                          ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC700),
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                              shadowColor: const Color(
                                0xFFFFC700,
                              ).withOpacity(0.4),
                            ),
                            child: Text(
                              '??Î°?,
                              style: TextStyle(
                                fontSize: FontSizeService.getScaledFontSize(16),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ),
                        ], // Column children ??
                      ), // Column ??
                    ), // Padding ??
                  ), // Container ??
                  ), // Opacity Í¥ÑÌò∏ Ï∂îÍ?
                ), // TweenAnimationBuilder ??
              ), // Align ??
            ), // IgnorePointer ??
          ), // AnimatedOpacity ??
        ], // Stack children ??
      ), // Stack ??
      ), // Opacity ??
    ); // Scaffold ??
  }

  Widget _buildFormRow({
    required IconData icon,
    required String label,
    required Widget child,
    Color iconColor = const Color(0xFF888888),
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment
            .start, // For suggestions to expand downwards properly
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: iconColor,
                  size: FontSizeService.getScaledFontSize(16),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50, // Fixed width for label alignment
                  child: Text(
                    label,
                    style: TextStyle(
                      color: const Color(0xFFCCCCCC),
                      fontSize: FontSizeService.getScaledFontSize(14),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint, {
    String? suffixText,
    Color? suffixColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF666666)),
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      suffixStyle: suffixText != null
          ? TextStyle(
              color: suffixColor ?? Colors.white,
              fontSize: FontSizeService.getScaledFontSize(16),
              fontWeight: FontWeight.bold,
            )
          : null,
      filled: true,
      fillColor: const Color(0xFF1E2024),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFC700), width: 1.5),
      ),
    );
  }

  Widget _buildSuggestionBox(List<String> suggestions, Function(String) onTap) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2D34),
        border: Border.all(color: const Color(0xFF444444)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFF333333)),
        itemBuilder: (context, index) {
          return ListTile(
            dense: true,
            title: Text(
              suggestions[index],
              style: TextStyle(
                color: Colors.white,
                fontSize: FontSizeService.getScaledFontSize(13),
              ),
            ),
            onTap: () => onTap(suggestions[index]),
          );
        },
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }
    String newText = digitsOnly.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
