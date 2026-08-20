const fs = require('fs');

const filePath = 'C:\\DbrosAdmin\\src\\pages\\Push.tsx';
let content = fs.readFileSync(filePath, 'utf-8');

// 1. imports update
content = content.replace(
    "import { collection, query, orderBy, onSnapshot, addDoc, serverTimestamp } from 'firebase/firestore';",
    "import { collection, query, orderBy, onSnapshot, addDoc, serverTimestamp, doc, deleteDoc } from 'firebase/firestore';"
);
content = content.replace(
    "import { Send, History, CheckCircle2, AlertCircle } from 'lucide-react';",
    "import { Send, History, CheckCircle2, AlertCircle, Trash2 } from 'lucide-react';"
);

// 2. handleDelete method
const handleDeleteCode = `
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
`;
content = content.replace("  const handleSend = async (e: React.FormEvent) => {", handleDeleteCode);

// 3. Table Headers
content = content.replace(
    /<th className="p-4 font-medium text-right">([^<]*)<\/th>/,
    '<th className="p-4 font-medium text-right">$1</th>\n                    <th className="p-4 font-medium text-center w-20">관리</th>'
);

// 4. Table Body column
content = content.replace(
    /<td className="p-4 text-right text-sm text-gray-400">\s*\{formatDate\(req.createdAt\)\}\s*<\/td>/g,
    `<td className="p-4 text-right text-sm text-gray-400">
                          {formatDate(req.createdAt)}
                        </td>
                        <td className="p-4 text-center">
                          <button onClick={() => handleDelete(req.id)} className="text-gray-400 hover:text-red-400 transition-colors">
                            <Trash2 size={18} />
                          </button>
                        </td>`
);

// Colspan in empty row
content = content.replace('colSpan={4}', 'colSpan={5}');

fs.writeFileSync(filePath, content, 'utf-8');
console.log("Updated Push.tsx");
