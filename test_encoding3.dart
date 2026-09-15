import 'dart:io'; void main() { final text = File('lib/utils/tmap_trip_detail_ocr.dart').readAsStringSync(); final idx = text.indexOf('NEW FALLBACK'); print(text.substring(idx, idx + 400)); }
