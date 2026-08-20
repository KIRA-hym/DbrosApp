import sqlite3
import os
import requests
import json

CHOSUNG_LIST = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ']

def get_chosung(text):
    result = []
    for char in text:
        if '가' <= char <= '힣':
            char_code = ord(char) - ord('가')
            chosung_index = char_code // 588
            result.append(CHOSUNG_LIST[chosung_index])
        elif char == ' ':
            result.append(' ')
        else:
            result.append(char)
    return ''.join(result)

def build_db():
    assets_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets')
    if not os.path.exists(assets_dir):
        os.makedirs(assets_dir)
        
    db_path = os.path.join(assets_dir, 'address.db')
    
    if os.path.exists(db_path):
        os.remove(db_path)
        
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE addresses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            cho_seong TEXT NOT NULL
        )
    ''')
    
    print("전국 법정동 데이터를 가져오는 중...")
    
    # 시도 코드 가져오기
    res = requests.get('https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=*00000000')
    sido_data = res.json()
    
    total_count = 0
    
    for sido in sido_data.get('regcodes', []):
        prefix = sido['code'][:2]
        sido_name = sido['name']
        
        # 각 시도별로 전체 하위 코드 가져오기 (is_ignore_zero=true로 0으로 끝나는 것 제외하여 읍면동만)
        url = f"https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern={prefix}*&is_ignore_zero=true"
        try:
            detail_res = requests.get(url)
            detail_data = detail_res.json()
            
            insert_data = []
            for item in detail_data.get('regcodes', []):
                name = item['name']
                cho_seong = get_chosung(name)
                insert_data.append((name, cho_seong))
                
            cursor.executemany('INSERT INTO addresses (full_name, cho_seong) VALUES (?, ?)', insert_data)
            total_count += len(insert_data)
            print(f"{sido_name} 완료... (현재 총 {total_count}건)")
        except Exception as e:
            print(f"{sido_name} 데이터를 가져오는 중 에러 발생: {e}")
            
    cursor.execute('CREATE INDEX idx_cho_seong ON addresses (cho_seong)')
    cursor.execute('CREATE INDEX idx_full_name ON addresses (full_name)')
    
    conn.commit()
    conn.close()
    
    print(f"✅ 리얼 DB 생성 완료! 총 {total_count}개의 주소가 삽입되었습니다.")
    print(f"경로: {db_path}")

if __name__ == "__main__":
    build_db()
