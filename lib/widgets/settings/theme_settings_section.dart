import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../bordered_section.dart';
import '../../utils/responsive_layout.dart';

enum UIThemeMode { light, dark, amoled }

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
              return ValueListenableBuilder<bool>(
                valueListenable: SettingsService.isAmoledBlackNotifier,
                builder: (context, isAmoledBlack, _) {
                  
                  UIThemeMode currentUiMode;
                  if (themeMode == ThemeMode.light) {
                    currentUiMode = UIThemeMode.light;
                  } else if (isAmoledBlack) {
                    currentUiMode = UIThemeMode.amoled;
                  } else {
                    currentUiMode = UIThemeMode.dark;
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: _buildThemeOption(
                          context: context,
                          title: '밝은 테마',
                          value: UIThemeMode.light,
                          groupValue: currentUiMode,
                          icon: Icons.light_mode,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildThemeOption(
                          context: context,
                          title: '어두운 테마',
                          value: UIThemeMode.dark,
                          groupValue: currentUiMode,
                          icon: Icons.dark_mode,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildThemeOption(
                          context: context,
                          title: '절전 블랙 테마',
                          value: UIThemeMode.amoled,
                          groupValue: currentUiMode,
                          icon: Icons.battery_charging_full, // Or Icons.nightlight_round
                        ),
                      ),
                    ],
                  );
                },
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
    required UIThemeMode value,
    required UIThemeMode groupValue,
    required IconData icon,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () {
        if (value == UIThemeMode.light) {
          SettingsService.setThemeMode(ThemeMode.light);
          SettingsService.setIsAmoledBlack(false);
        } else if (value == UIThemeMode.dark) {
          SettingsService.setThemeMode(ThemeMode.dark);
          SettingsService.setIsAmoledBlack(false);
        } else if (value == UIThemeMode.amoled) {
          SettingsService.setThemeMode(ThemeMode.dark);
          SettingsService.setIsAmoledBlack(true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13, // Slightly smaller to fit 3 options
              ),
            ),
          ],
        ),
      ),
    );
  }
}
