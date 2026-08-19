import { useState, useEffect } from 'react';
import { collection, query, orderBy, onSnapshot, addDoc, updateDoc, deleteDoc, doc, serverTimestamp } from 'firebase/firestore';
import { db } from '../firebase';
import { Plus, Edit2, Trash2, Calendar, AlertCircle } from 'lucide-react';

interface Notice {
  id: string;
  title: string;
  content: string;
  startDate: string;
  endDate: string;
  isImportant: boolean;
  createdAt: any;
}

export default function Notices() {
  const [notices, setNotices] = useState<Notice[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  // Form State
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [isImportant, setIsImportant] = useState(false);

  useEffect(() => {
    const q = query(collection(db, 'notices'), orderBy('createdAt', 'desc'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const noticeData: Notice[] = [];
      snapshot.forEach((doc) => {
        noticeData.push({ id: doc.id, ...doc.data() } as Notice);
      });
      setNotices(noticeData);
    });
    return unsubscribe;
  }, []);

  
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
    if (window.confirm(`선택한 ${selectedIds.length}개의 공지사항을 삭제하시겠습니까?`)) {
      try {
        await Promise.all(selectedIds.map(id => deleteDoc(doc(db, 'notices', id))));
        setSelectedIds([]);
      } catch (error) {
        console.error('Delete error:', error);
        alert('일부 항목 삭제에 실패했습니다.');
      }
    }
  };

  const resetForm = () => {
    setTitle('');
    setContent('');
    setStartDate('');
    setEndDate('');
    setIsImportant(false);
    setEditingId(null);
    setIsModalOpen(false);
  };

  const getTodayDate = () => {
    const today = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}`;
  };

  const handleOpenNew = () => {
    resetForm();
    setStartDate(getTodayDate());
    setIsModalOpen(true);
  };

  const handleOpenEdit = (notice: Notice) => {
    setTitle(notice.title);
    setContent(notice.content);
    setStartDate(notice.startDate);
    setEndDate(notice.endDate);
    setIsImportant(notice.isImportant || false);
    setEditingId(notice.id);
    setIsModalOpen(true);
  };

  const handleDelete = async (id: string) => {
    if (window.confirm('정말 이 공지사항을 삭제하시겠습니까?')) {
      await deleteDoc(doc(db, 'notices', id));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!startDate || !endDate) {
      alert('게시 시작일과 종료일을 모두 지정해주세요.');
      return;
    }
    if (startDate > endDate) {
      alert('종료일은 시작일보다 빠를 수 없습니다.');
      return;
    }

    const noticeData = {
      title,
      content,
      startDate,
      endDate,
      isImportant,
    };

    try {
      if (editingId) {
        await updateDoc(doc(db, 'notices', editingId), noticeData);
      } else {
        await addDoc(collection(db, 'notices'), {
          ...noticeData,
          createdAt: serverTimestamp(),
        });
      }
      resetForm();
    } catch (error) {
      console.error("Error saving notice: ", error);
      alert('저장 중 오류가 발생했습니다.');
    }
  };

  return (
    <div className="p-4 md:p-8 h-full flex flex-col">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-6 md:mb-8">
        <div>
          <h2 className="text-2xl font-bold text-white mb-1">공지사항 관리</h2>
          <p className="text-gray-400 text-sm">앱 실행 시 사용자에게 보여줄 공지사항과 게시 기간을 설정합니다.</p>
        </div>
        {selectedIds.length > 0 && (
          <button
            onClick={handleDeleteSelected}
            className="flex items-center gap-2 bg-red-500/20 text-red-400 hover:bg-red-500/30 px-5 py-2.5 rounded-xl font-medium shadow-lg transition-colors"
          >
            <Trash2 size={18} />
            선택 삭제 ({selectedIds.length})
          </button>
        )}
        <button
          onClick={handleOpenNew}
          className="flex items-center gap-2 bg-gradient-to-r from-yellow-500 to-orange-500 hover:from-yellow-400 hover:to-orange-400 text-white px-5 py-2.5 rounded-xl font-medium shadow-lg transition-transform active:scale-95"
        >
          <Plus size={18} />
          새 공지사항 등록
        </button>
      </div>

      <div className="flex-1 bg-[#1a1d24] rounded-2xl border border-white/5 overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-[#222630] text-gray-400 text-sm border-b border-white/5">
                <th className="p-4 w-12 text-center"><input type="checkbox" onChange={handleSelectAll} checked={notices.length > 0 && selectedIds.length === notices.length} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></th>
                <th className="p-4 font-medium w-16 text-center">중요</th>
                <th className="p-4 font-medium">제목</th>
                <th className="p-4 font-medium w-64">게시 기간 (YYYY-MM-DD)</th>
                <th className="p-4 font-medium w-32 text-center">관리</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5 text-gray-200">
              {notices.length === 0 ? (
                <tr>
                  <td colSpan={5} className="p-8 text-center text-gray-500">
                    등록된 공지사항이 없습니다.
                  </td>
                </tr>
              ) : (
                notices.map((notice) => (
                  <tr key={notice.id} className="hover:bg-white/[0.02] transition-colors">
                    <td className="p-4 text-center"><input type="checkbox" checked={selectedIds.includes(notice.id)} onChange={() => handleSelectOne(notice.id)} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></td>
                    <td className="p-4 text-center">
                      {notice.isImportant && <AlertCircle size={18} className="text-red-400 mx-auto" />}
                    </td>
                    <td className="p-4 font-medium">{notice.title}</td>
                    <td className="p-4 text-sm text-gray-400 flex items-center gap-2">
                      <Calendar size={14} className="text-gray-500" />
                      {notice.startDate} ~ {notice.endDate}
                    </td>
                    <td className="p-4">
                      <div className="flex items-center justify-center gap-3">
                        <button onClick={() => handleOpenEdit(notice)} className="text-gray-400 hover:text-yellow-400 transition-colors">
                          <Edit2 size={18} />
                        </button>
                        <button onClick={() => handleDelete(notice.id)} className="text-gray-400 hover:text-red-400 transition-colors">
                          <Trash2 size={18} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Form Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-[#1a1d24] border border-white/10 rounded-2xl w-full max-w-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
            <div className="p-6 border-b border-white/5 flex justify-between items-center">
              <h3 className="text-xl font-bold text-white">{editingId ? '공지사항 수정' : '새 공지사항 작성'}</h3>
              <button onClick={resetForm} className="text-gray-400 hover:text-white transition-colors">✕</button>
            </div>
            
            <form onSubmit={handleSubmit} className="p-6 overflow-y-auto flex-1 space-y-5">
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">제목</label>
                <input
                  type="text"
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-[#121418] border border-white/10 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-yellow-500/50"
                  placeholder="공지사항 제목을 입력하세요"
                />
              </div>

              <div className="flex flex-col md:flex-row gap-4">
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-400 mb-2">게시 시작일</label>
                  <input
                    type="date"
                    required
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                    className="w-full px-4 py-3 bg-[#121418] border border-white/10 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-yellow-500/50 cursor-pointer [color-scheme:dark]"
                  />
                </div>
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-400 mb-2">게시 종료일</label>
                  <input
                    type="date"
                    required
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                    className="w-full px-4 py-3 bg-[#121418] border border-white/10 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-yellow-500/50 cursor-pointer [color-scheme:dark]"
                  />
                </div>
              </div>

              <label className="flex items-center gap-3 cursor-pointer p-4 bg-red-500/5 border border-red-500/10 rounded-xl">
                <input
                  type="checkbox"
                  checked={isImportant}
                  onChange={(e) => setIsImportant(e.target.checked)}
                  className="w-5 h-5 accent-red-500 rounded bg-[#121418] border-white/10"
                />
                <div>
                  <span className="text-red-400 font-medium block">중요 공지 (필독)</span>
                  <span className="text-gray-500 text-xs">체크 시 앱 내에서 강조되어 표시됩니다.</span>
                </div>
              </label>

              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">상세 내용</label>
                <textarea
                  required
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  rows={6}
                  className="w-full px-4 py-3 bg-[#121418] border border-white/10 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-yellow-500/50 resize-none"
                  placeholder="공지 내용을 입력하세요 (줄바꿈 지원)"
                ></textarea>
              </div>

              <div className="pt-4 flex flex-col-reverse md:flex-row gap-3 justify-end">
                <button type="button" onClick={resetForm} className="px-5 py-2.5 text-gray-400 hover:text-white font-medium transition-colors w-full md:w-auto">취소</button>
                <button type="submit" className="px-5 py-2.5 bg-yellow-500 hover:bg-yellow-400 text-[#121418] font-bold rounded-xl shadow-lg shadow-yellow-500/20 transition-all w-full md:w-auto">
                  {editingId ? '수정 완료' : '등록하기'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
