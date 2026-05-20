import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/responsive_layout.dart';

void main() {
  group('ResponsiveLayout.qualifiesAsExpanded', () {
    test('fold unfolded portrait', () {
      expect(ResponsiveLayout.qualifiesAsExpanded(const Size(690, 829)), isTrue);
    });

    test('wide portrait tablet width', () {
      expect(ResponsiveLayout.qualifiesAsExpanded(const Size(840, 600)), isTrue);
    });

    test('phone portrait stays phone tier', () {
      expect(ResponsiveLayout.qualifiesAsExpanded(const Size(390, 844)), isFalse);
    });

    test('phone landscape uses expanded layout', () {
      expect(ResponsiveLayout.qualifiesAsExpanded(const Size(844, 390)), isTrue);
      expect(ResponsiveLayout.qualifiesAsExpanded(const Size(915, 412)), isTrue);
    });

    test('tiny landscape does not expand', () {
      expect(ResponsiveLayout.qualifiesAsExpanded(const Size(520, 280)), isFalse);
    });
  });

  group('ResponsiveLayout.tierOf', () {
    test('landscape phone is expanded not tablet', () {
      expect(ResponsiveLayout.tierOf(const Size(800, 360)), LayoutTier.expanded);
    });

    test('portrait phone', () {
      expect(ResponsiveLayout.tierOf(const Size(390, 844)), LayoutTier.phone);
    });
  });

  group('ResponsiveLayout.isLandscape', () {
    test('width greater than height', () {
      expect(ResponsiveLayout.isLandscape(const Size(800, 400)), isTrue);
      expect(ResponsiveLayout.isLandscape(const Size(400, 800)), isFalse);
    });
  });
}
