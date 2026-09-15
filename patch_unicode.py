import codecs

with codecs.open('lib/utils/tmap_trip_detail_ocr.dart', 'r', 'utf-8') as f:
    text = f.read()

# Restore the original file state to avoid double patches
import subprocess
subprocess.run(['git', 'checkout', 'lib/utils/tmap_trip_detail_ocr.dart'])

with codecs.open('lib/utils/tmap_trip_detail_ocr.dart', 'r', 'utf-8') as f:
    text = f.read()

# 1. Clear false positives before vertical fallback
new_fallback = '''    if (startAddress.contains('\uC6B4\uD589\uC77C\uC790') || startAddress.contains('\uC6B4\uD589\uBC88\uD638') || startAddress.contains('\uC694\uAE30\uC694')) startAddress = '';
    if (endAddress.contains('\uC6B4\uD589\uC77C\uC790') || endAddress.contains('\uC6B4\uD589\uBC88\uD638') || endAddress.contains('\uC694\uAE30\uC694')) endAddress = '';

    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---'''

text = text.replace('    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---', new_fallback)

# 2. Fix Date regex
old_regex = r\"RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~')\"
new_regex = r\"RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~')\"
text = text.replace(old_regex, new_regex)

# 3. Strip spaces from time
text = text.replace(\"driveStartTimeHm = dtMatch.group(4)!;\", \"driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');\")

with codecs.open('lib/utils/tmap_trip_detail_ocr.dart', 'w', 'utf-8') as f:
    f.write(text)

print('Done unicode patch')
