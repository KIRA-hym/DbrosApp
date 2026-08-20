import os

file_path = r'C:\DbrosAdmin\src\pages\Push.tsx'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. imports update
content = content.replace(
    "import { collection, query, orderBy, onSnapshot, addDoc, serverTimestamp } from 'firebase/firestore';",
    "import { collection, query, orderBy, onSnapshot, addDoc, serverTimestamp, doc, deleteDoc } from 'firebase/firestore';"
)
content = content.replace(
    "import { Send, History, CheckCircle2, AlertCircle } from 'lucide-react';",
    "import { Send, History, CheckCircle2, AlertCircle, Trash2 } from 'lucide-react';"
)

# 2. handleDelete method
handle_delete_code = """
  const handleDelete = async (id: string) => {
    if (window.confirm('정말 이 푸시 발송 내역을 삭제하시겠습니까?')) {
      try {
        await deleteDoc(doc(db, 'admin_push_requests', id));
      } catch (error) {
        console.error('Delete error:', error);
        alert('삭제에 실패했습니다.');
      }
    }
  };

  const handleSend = async (e: React.FormEvent) => {
"""
content = content.replace("  const handleSend = async (e: React.FormEvent) => {", handle_delete_code)

# 3. Table Headers
old_th = """<th className="p-4 font-medium text-right">요청 일시</th>"""
new_th = """<th className="p-4 font-medium text-right">요청 일시</th>
                    <th className="p-4 font-medium text-center w-20">관리</th>"""
content = content.replace(old_th, new_th)

# Wait, the terminal showed "요청 일시" might be garbled in PowerShell output, so let's match exact string if possible, or use regex.
import re
content = re.sub(
    r'(<th className="p-4 font-medium text-right">[^<]*</th>)',
    r'\1\n                    <th className="p-4 font-medium text-center w-20">관리</th>',
    content
)

# 4. Table Body column
old_td = """<td className="p-4 text-right text-sm text-gray-400">
                          {formatDate(req.createdAt)}
                        </td>"""
new_td = """<td className="p-4 text-right text-sm text-gray-400">
                          {formatDate(req.createdAt)}
                        </td>
                        <td className="p-4 text-center">
                          <button onClick={() => handleDelete(req.id)} className="text-gray-400 hover:text-red-400 transition-colors">
                            <Trash2 size={18} />
                          </button>
                        </td>"""
content = content.replace(old_td, new_td)
# also try regex if formatting varies
if not "handleDelete(req.id)" in content:
    content = re.sub(
        r'(<td className="p-4 text-right text-sm text-gray-400">\s*\{formatDate\(req.createdAt\)\}\s*</td>)',
        r'\1\n                        <td className="p-4 text-center">\n                          <button onClick={() => handleDelete(req.id)} className="text-gray-400 hover:text-red-400 transition-colors">\n                            <Trash2 size={18} />\n                          </button>\n                        </td>',
        content
    )

# Colspan in empty row
content = content.replace('colSpan={4}', 'colSpan={5}')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated Push.tsx")
