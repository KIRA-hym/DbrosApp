const fs = require('fs');

const filePath = 'C:\\DbrosAdmin\\src\\pages\\Notices.tsx';
let content = fs.readFileSync(filePath, 'utf-8');

// 1. Add selectedIds state
if (!content.includes('selectedIds')) {
    content = content.replace(
        "const [editingId, setEditingId] = useState<string | null>(null);",
        "const [editingId, setEditingId] = useState<string | null>(null);\n  const [selectedIds, setSelectedIds] = useState<string[]>([]);"
    );
}

// 2. Add multi-select handlers
const multiSelectCode = `
  const handleSelectAll = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.checked) {
      setSelectedIds(notices.map(n => n.id));
    } else {
      setSelectedIds([]);
    }
  };

  const handleSelectOne = (id: string) => {
    setSelectedIds(prev => prev.includes(id) ? prev.filter(i => i !== id) : [...prev, id]);
  };

  const handleDeleteSelected = async () => {
    if (selectedIds.length === 0) return;
    if (window.confirm(\`선택한 \${selectedIds.length}개의 공지사항을 삭제하시겠습니까?\`)) {
      try {
        await Promise.all(selectedIds.map(id => deleteDoc(doc(db, 'notices', id))));
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
        "const resetForm = () => {",
        multiSelectCode + "\n  const resetForm = () => {"
    );
}

// 3. Add Delete Selected button to header
const headerTarget = `<button
          onClick={handleOpenNew}`;
const headerReplace = `{selectedIds.length > 0 && (
          <button
            onClick={handleDeleteSelected}
            className="flex items-center gap-2 bg-red-500/20 text-red-400 hover:bg-red-500/30 px-5 py-2.5 rounded-xl font-medium shadow-lg transition-colors"
          >
            <Trash2 size={18} />
            선택 삭제 ({selectedIds.length})
          </button>
        )}
        <button
          onClick={handleOpenNew}`;
if (!content.includes('선택 삭제')) {
    content = content.replace(headerTarget, headerReplace);
}

// 4. Table Header
if (!content.includes('onChange={handleSelectAll}')) {
    content = content.replace(
        '<tr className="bg-[#222630] text-gray-400 text-sm border-b border-white/5">\n                <th className="p-4 font-medium w-16 text-center">중요</th>',
        '<tr className="bg-[#222630] text-gray-400 text-sm border-b border-white/5">\n                <th className="p-4 w-12 text-center"><input type="checkbox" onChange={handleSelectAll} checked={notices.length > 0 && selectedIds.length === notices.length} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></th>\n                <th className="p-4 font-medium w-16 text-center">중요</th>'
    );
}

// 5. Table Body
if (!content.includes('handleSelectOne(notice.id)')) {
    content = content.replace(
        '<tr key={notice.id} className="hover:bg-white/[0.02] transition-colors">\n                    <td className="p-4 text-center">',
        '<tr key={notice.id} className="hover:bg-white/[0.02] transition-colors">\n                    <td className="p-4 text-center"><input type="checkbox" checked={selectedIds.includes(notice.id)} onChange={() => handleSelectOne(notice.id)} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></td>\n                    <td className="p-4 text-center">'
    );
}

// 6. Colspan update
content = content.replace('colSpan={4}', 'colSpan={5}');

fs.writeFileSync(filePath, content, 'utf-8');
console.log('Notices.tsx updated for multi-select');
