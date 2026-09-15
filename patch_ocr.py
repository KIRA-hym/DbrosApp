import codecs
with codecs.open('lib/utils/tmap_trip_detail_ocr.dart', 'r', 'utf-8') as f:
    text = f.read()

text = text.replace('// --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---', '''    // Clear false positives from horizontal parsing
    if (startAddress.contains('款青老磊') || startAddress.contains('款青锅龋') || startAddress.contains('夸扁夸')) startAddress = '';
    if (endAddress.contains('款青老磊') || endAddress.contains('款青锅龋') || endAddress.contains('夸扁夸')) endAddress = '';

    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---''')

text = text.replace(
    r\"final dtMatch = RegExp(r'款青老磊\s*(\d{4})[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~').firstMatch(flat);\",
    r\"final dtMatch = RegExp(r'款青老磊\s*(\d{4})\s*[.\-斥]\s*(\d{1,2})\s*[.\-岿]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~').firstMatch(flat);\"
)

text = text.replace('driveStartTimeHm = dtMatch.group(4)!;', 'driveStartTimeHm = dtMatch.group(4)!.replace(\" \", \"\");')

with codecs.open('lib/utils/tmap_trip_detail_ocr.dart', 'w', 'utf-8') as f:
    f.write(text)
print('Done')
