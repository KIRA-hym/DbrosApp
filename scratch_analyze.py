import json

with open('D:\\DbrosApp\\logs\\ocr_parse_export_20260517.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

entries = data.get('entries', [])
bad_parses = {'로지': [], '콜마너': [], '카카오(일반)': []}

for e in entries:
    prog = e.get('program', '')
    parsed = e.get('parsed_data', {})
    dep = parsed.get('departure', '')
    dest = parsed.get('destination', '')
    
    is_bad = False
    if '지도' in dep or '취소' in dep or '갱신' in dep or len(dep) > 40:
        is_bad = True
    if '지도' in dest or '취소' in dest or '갱신' in dest or len(dest) > 40:
        is_bad = True
        
    if is_bad and prog in bad_parses and len(bad_parses[prog]) < 5:
        bad_parses[prog].append(e)

print('Analysis Complete.')
for p, arr in bad_parses.items():
    print(f'\n--- {p} Bad Parses ---')
    for x in arr:
        print('ID:', x['id'])
        print('Parsed Dep:', x['parsed_data']['departure'])
        print('Parsed Dest:', x['parsed_data']['destination'])
