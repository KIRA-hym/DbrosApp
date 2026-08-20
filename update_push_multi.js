const fs = require('fs');

const filePath = 'C:\\DbrosAdmin\\src\\pages\\Push.tsx';
let content = fs.readFileSync(filePath, 'utf-8');

// 1. Add selectedIds state
if (!content.includes('selectedIds')) {
    content = content.replace(
        "const [isSending, setIsSending] = useState(false);",
        "const [isSending, setIsSending] = useState(false);\n  const [selectedIds, setSelectedIds] = useState<string[]>([]);"
    );
}

// 2. Add multi-select handlers
const multiSelectCode = `
  const handleSelectAll = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.checked) {
      setSelectedIds(requests.map(req => req.id));
    } else {
      setSelectedIds([]);
    }
  };

  const handleSelectOne = (id: string) => {
    setSelectedIds(prev => prev.includes(id) ? prev.filter(i => i !== id) : [...prev, id]);
  };

  const handleDeleteSelected = async () => {
    if (selectedIds.length === 0) return;
    if (window.confirm(\`선택한 \${selectedIds.length}개의 발송 내역을 삭제하시겠습니까?\`)) {
      try {
        await Promise.all(selectedIds.map(id => deleteDoc(doc(db, 'admin_push_requests', id))));
        setSelectedIds([]);
      } catch (error) {
        console.error('Delete error:', error);
        alert('일부 항목 삭제에 실패했습니다.');
      }
    }
  };
`;

if (!content.includes('handleDeleteSelected')) {
    content = content.replace(
        "const handleDelete = async",
        multiSelectCode + "\n  const handleDelete = async"
    );
}

// 3. Add Delete Selected button to header
const headerTarget = '<h3 className="text-lg font-bold text-white">최근 발송 내역</h3>';
const headerReplace = `<h3 className="text-lg font-bold text-white">최근 발송 내역</h3>
              {selectedIds.length > 0 && (
                <button
                  onClick={handleDeleteSelected}
                  className="ml-auto flex items-center gap-2 bg-red-500/20 text-red-400 hover:bg-red-500/30 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
                >
                  <Trash2 size={16} />
                  선택 삭제 ({selectedIds.length})
                </button>
              )}`;
if (!content.includes('선택 삭제')) {
    content = content.replace(headerTarget, headerReplace);
}

// 4. Table Header
if (!content.includes('onChange={handleSelectAll}')) {
    content = content.replace(
        '<tr className="bg-[#222630] text-gray-400 text-sm border-b border-white/5">\n                    <th className="p-4 font-medium">상태</th>',
        '<tr className="bg-[#222630] text-gray-400 text-sm border-b border-white/5">\n                    <th className="p-4 w-12 text-center"><input type="checkbox" onChange={handleSelectAll} checked={requests.length > 0 && selectedIds.length === requests.length} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></th>\n                    <th className="p-4 font-medium">상태</th>'
    );
}

// 5. Table Body
if (!content.includes('handleSelectOne(req.id)')) {
    content = content.replace(
        '<tr key={req.id} className="hover:bg-white/[0.02] transition-colors">\n                        <td className="p-4">',
        '<tr key={req.id} className="hover:bg-white/[0.02] transition-colors">\n                        <td className="p-4 text-center"><input type="checkbox" checked={selectedIds.includes(req.id)} onChange={() => handleSelectOne(req.id)} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></td>\n                        <td className="p-4">'
    );
}

// 6. Colspan update
content = content.replace('colSpan={5}', 'colSpan={6}');

fs.writeFileSync(filePath, content, 'utf-8');
console.log('Push.tsx updated for multi-select');
