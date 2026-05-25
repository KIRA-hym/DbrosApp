import os
import shutil

src_dir = 'C:/DbrosApp/android/app/src/main/kotlin/com/example/dbros_app'
dst_dir = 'C:/DbrosApp/android/app/src/main/kotlin/com/dbros/drive'

os.makedirs(dst_dir, exist_ok=True)

for filename in os.listdir(src_dir):
    if filename.endswith('.kt'):
        src_path = os.path.join(src_dir, filename)
        dst_path = os.path.join(dst_dir, filename)
        
        with open(src_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        content = content.replace('package com.example.dbros_app', 'package com.dbros.drive')
        content = content.replace('com.example.dbros_app', 'com.dbros.drive')
        
        with open(dst_path, 'w', encoding='utf-8') as f:
            f.write(content)

print("Kotlin migration complete.")
