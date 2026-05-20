/// 백업 JSON의 운행일지 한 건을 현재 `drive_logs` 스키마 INSERT에 맞게 정규화.
class BackupLogRow {
  BackupLogRow._();

  static const List<String> driveLogColumnOrder = <String>[
    'id',
    'work_date',
    'drive_date',
    'drive_time',
    'program',
    'gross_fare',
    'fee',
    'transport_cost',
    'waypoint_tip',
    'net_income',
    'start_location',
    'waypoint',
    'end_location',
    'memo',
    'image_path',
    'start_lat',
    'start_lng',
    'end_lat',
    'end_lng',
    'created_at',
    'updated_at',
  ];

  static const Set<String> _driveLogColumns = {
    'id',
    'work_date',
    'drive_date',
    'drive_time',
    'program',
    'gross_fare',
    'fee',
    'transport_cost',
    'waypoint_tip',
    'net_income',
    'start_location',
    'waypoint',
    'end_location',
    'memo',
    'image_path',
    'start_lat',
    'start_lng',
    'end_lat',
    'end_lng',
    'created_at',
    'updated_at',
  };

  static Map<String, dynamic> sanitizeForRestore(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};

    for (final key in _driveLogColumns) {
      if (!raw.containsKey(key)) continue;
      final v = raw[key];
      if (v == null) {
        if (key == 'image_path' ||
            key == 'waypoint' ||
            key == 'memo' ||
            key == 'start_location' ||
            key == 'end_location') {
          out[key] = '';
        } else if (key == 'start_lat' ||
            key == 'start_lng' ||
            key == 'end_lat' ||
            key == 'end_lng') {
          out[key] = null;
        }
        continue;
      }

      switch (key) {
        case 'id':
        case 'gross_fare':
        case 'fee':
        case 'transport_cost':
        case 'waypoint_tip':
        case 'net_income':
          out[key] = (v as num).toInt();
        case 'start_lat':
        case 'start_lng':
        case 'end_lat':
        case 'end_lng':
          out[key] = v is num ? v.toDouble() : double.tryParse(v.toString());
        default:
          out[key] = v.toString();
      }
    }

    out['waypoint_tip'] ??= 0;
    out['transport_cost'] ??= 0;
    out['fee'] ??= 0;
    out['gross_fare'] ??= 0;
    out['net_income'] ??= 0;
    out['image_path'] ??= '';
    out['waypoint'] ??= '';
    out['memo'] ??= '';
    out['start_location'] ??= '';
    out['end_location'] ??= '';

    final work = (out['work_date']?.toString() ?? '').trim();
    final drive = (out['drive_date']?.toString() ?? '').trim();
    if (work.isEmpty && drive.isNotEmpty) {
      out['work_date'] = drive;
    } else if (drive.isEmpty && work.isNotEmpty) {
      out['drive_date'] = work;
    }

    return out;
  }

  /// 레거시 DB에 `date` 컬럼이 남아 있을 때 NOT NULL 위반 방지.
  static Map<String, dynamic> withLegacyDateIfNeeded(
    Map<String, dynamic> row,
    bool tableHasDateColumn,
  ) {
    if (!tableHasDateColumn) return row;
    final copy = Map<String, dynamic>.from(row);
    final dateVal = (copy['drive_date']?.toString() ?? '').trim().isNotEmpty
        ? copy['drive_date']
        : copy['work_date'];
    copy['date'] = dateVal?.toString() ?? '';
    return copy;
  }
}
