import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

class GuideContentWidget extends StatelessWidget {
  final String title;
  final String description;
  final TutorialCoachMarkController controller;
  final bool isLast;

  const GuideContentWidget({
    super.key,
    required this.title,
    required this.description,
    required this.controller,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.45),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2024),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFC700), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18.0)),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Text(description, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 15.0, height: 1.4)),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC700),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(80, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (isLast) {
                    controller.skip();
                  } else {
                    controller.next();
                  }
                },
                child: Text(isLast ? '완료' : '다음 >', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
