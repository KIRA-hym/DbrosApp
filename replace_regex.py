import sys, re

f = 'C:/DbrosApp/lib/utils/logi_colmanner_ocr.dart'
try:
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    if 'remote_config_service.dart' not in content:
        content = "import '../services/remote_config_service.dart';\n" + content
        
    s1 = r'(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)'
    s2 = r'(서울|경기|인천|대전|대구|부산|광주|울산|세종|제주|강원|충북|충남|전북|전남|경북|경남)'
    
    content = content.replace(s1, r'${RemoteConfigService().regionPattern}')
    content = content.replace(s2, r'${RemoteConfigService().regionPattern}')
    
    with open(f, 'w', encoding='utf-8') as file:
        file.write(content)
    print('Replaced successfully.')
except Exception as e:
    print(e)
