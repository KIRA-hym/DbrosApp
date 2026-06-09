import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../bordered_section.dart';
import '../../utils/responsive_layout.dart';

class ThemeSettingsSection extends StatelessWidget {
  const ThemeSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '화면 테마 설정', 
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).primaryColor, 
                  fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
          SizedBox(height: spacing),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: SettingsService.themeModeNotifier,
            builder: (context, themeMode, _) {
              return Row(
                children: [
                  Expanded(
                    child: _buildThemeOption(
                      context: context,
                      title: '다크 모드',
                      value: ThemeMode.dark,
                      groupValue: themeMode,
                      icon: Icons.dark_mode,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOption(
                      context: context,
                      title: '라이트 모드',
                      value: ThemeMode.light,
                      groupValue: themeMode,
                      icon: Icons.light_mode,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String title,
    required ThemeMode value,
    required ThemeMode groupValue,
    required IconData icon,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => SettingsService.setThemeMode(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).dividerColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).textTheme.bodySmall?.color, size: 28),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
