import { useState, useEffect } from 'react';
import { collection, query, orderBy, onSnapshot, addDoc, serverTimestamp, doc, deleteDoc } from 'firebase/firestore';
import { db } from '../firebase';
import { Send, History, CheckCircle2, AlertCircle, Trash2 } from 'lucide-react';

interface PushRequest {
  id: string;
  title: string;
  body: string;
  status: string; // 'pending', 'completed', 'failed'
  createdAt: any;
  sentAt?: any;
  successCount?: number;
  failureCount?: number;
}

export default function Push() {
  const [requests, setRequests] = useState<PushRequest[]>([]);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  useEffect(() => {
    const q = query(collection(db, 'admin_push_requests'), orderBy('createdAt', 'desc'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const data: PushRequest[] = [];
      snapshot.forEach((doc) => {
        data.push({ id: doc.id, ...doc.data() } as PushRequest);
      });
      setRequests(data);
    });
    return unsubscribe;
  }, []);


  
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
    if (window.confirm(`선택한 ${selectedIds.length}개의 발송 내역을 삭제하시겠습니까?`)) {
      try {
        await Promise.all(selectedIds.map(id => deleteDoc(doc(db, 'admin_push_requests', id))));
        setSelectedIds([]);
      } catch (error) {
        console.error('Delete error:', error);
        alert('일부 항목 삭제에 실패했습니다.');
      }
    }
  };

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

    e.preventDefault();
    if (!title.trim() || !body.trim()) return;

    if (!window.confirm('전체 사용자에게 푸시 알림을 발송하시겠습니까?')) {
      return;
    }

    setIsSending(true);
    try {
      await addDoc(collection(db, 'admin_push_requests'), {
        title,
        body,
        status: 'pending',
        createdAt: serverTimestamp(),
      });
      setTitle('');
      setBody('');
      alert('푸시 알림 발송이 예약되었습니다.');
    } catch (error) {
      console.error('Push request error:', error);
      alert('푸시 알림 발송 요청에 실패했습니다.');
    } finally {
      setIsSending(false);
    }
  };

  const formatDate = (timestamp: any) => {
    if (!timestamp?.toDate) return '-';
    const d = timestamp.toDate();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  };

  return (
    <div className="p-4 md:p-8 h-full flex flex-col gap-6 md:gap-8 max-w-6xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-white mb-1">푸시 알림 센터</h2>
        <p className="text-gray-400 text-sm">전체 사용자에게 중요한 공지사항이나 업데이트 내역을 푸시 메시지로 발송합니다.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* 작상 폼 */}
        <div className="lg:col-span-1">
          <div className="bg-[#1a1d24] rounded-2xl border border-white/5 p-6 shadow-xl sticky top-8">
            <div className="flex items-center gap-2 mb-6">
              <Send size={20} className="text-yellow-500" />
              <h3 className="text-lg font-bold text-white">메시지 작성</h3>
            </div>
            
            <form onSubmit={handleSend} className="space-y-5">
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">푸시 제목</label>
                <input
                  type="text"
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-[#121418] border border-white/10 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-yellow-500/50"
                  placeholder="예: 긴급 서버 점검 안내"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">푸시 내용</label>
                <textarea
                  required
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  rows={6}
                  className="w-full px-4 py-3 bg-[#121418] border border-white/10 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-yellow-500/50 resize-none"
                  placeholder="사용자에게 발송될 메시지 내용을 입력하세요"
                ></textarea>
              </div>

              <button
                type="submit"
                disabled={isSending || !title.trim() || !body.trim()}
                className="w-full py-3.5 bg-gradient-to-r from-yellow-500 to-orange-500 hover:from-yellow-400 hover:to-orange-400 text-[#121418] font-bold rounded-xl shadow-lg shadow-yellow-500/20 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex justify-center items-center gap-2"
              >
                {isSending ? (
                  <div className="w-5 h-5 border-2 border-[#121418]/30 border-t-[#121418] rounded-full animate-spin" />
                ) : (
                  <>
                    <Send size={18} />
                    전체 발송하기
                  </>
                )}
              </button>
            </form>
          </div>
        </div>

        {/* 발송 내역 */}
        <div className="lg:col-span-2">
          <div className="bg-[#1a1d24] rounded-2xl border border-white/5 overflow-hidden shadow-xl flex flex-col h-full">
            <div className="p-6 border-b border-white/5 flex items-center gap-2">
              <History size={20} className="text-gray-400" />
              <h3 className="text-lg font-bold text-white">최근 발송 내역</h3>
              {selectedIds.length > 0 && (
                <button
                  onClick={handleDeleteSelected}
                  className="ml-auto flex items-center gap-2 bg-red-500/20 text-red-400 hover:bg-red-500/30 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
                >
                  <Trash2 size={16} />
                  선택 삭제 ({selectedIds.length})
                </button>
              )}
            </div>
            
            <div className="flex-1 overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-[#222630] text-gray-400 text-sm border-b border-white/5">
                    <th className="p-4 w-12 text-center"><input type="checkbox" onChange={handleSelectAll} checked={requests.length > 0 && selectedIds.length === requests.length} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></th>
                    <th className="p-4 font-medium">상태</th>
                    <th className="p-4 font-medium w-64">메시지</th>
                    <th className="p-4 font-medium text-center">성공/실패</th>
                    <th className="p-4 font-medium text-right">요청 일시</th>
                    <th className="p-4 font-medium text-center w-20">관리</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5 text-gray-200">
                  {requests.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="p-8 text-center text-gray-500">
                        발송 내역이 없습니다.
                      </td>
                    </tr>
                  ) : (
                    requests.map((req) => (
                      <tr key={req.id} className="hover:bg-white/[0.02] transition-colors">
                        <td className="p-4 text-center"><input type="checkbox" checked={selectedIds.includes(req.id)} onChange={() => handleSelectOne(req.id)} className="w-4 h-4 rounded accent-yellow-500 cursor-pointer" /></td>
                        <td className="p-4">
                          {req.status === 'completed' ? (
                            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-green-500/10 text-green-400 text-xs font-medium border border-green-500/20">
                              <CheckCircle2 size={14} /> 발송완료
                            </span>
                          ) : req.status === 'failed' ? (
                            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-red-500/10 text-red-400 text-xs font-medium border border-red-500/20">
                              <AlertCircle size={14} /> 실패
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-yellow-500/10 text-yellow-400 text-xs font-medium border border-yellow-500/20">
                              <div className="w-3 h-3 border border-yellow-500 border-t-transparent rounded-full animate-spin" />
                              처리중
                            </span>
                          )}
                        </td>
                        <td className="p-4">
                          <div className="font-medium text-white mb-1 truncate max-w-[200px]">{req.title}</div>
                          <div className="text-sm text-gray-500 truncate max-w-[200px]">{req.body}</div>
                        </td>
                        <td className="p-4 text-center">
                          <span className="text-green-400 font-medium">{req.successCount ?? 0}</span>
                          <span className="text-gray-600 mx-1">/</span>
                          <span className="text-red-400 font-medium">{req.failureCount ?? 0}</span>
                        </td>
                        <td className="p-4 text-right text-sm text-gray-400">
                          {formatDate(req.createdAt)}
                        </td>
                        <td className="p-4 text-center">
                          <button onClick={() => handleDelete(req.id)} className="text-gray-400 hover:text-red-400 transition-colors">
                            <Trash2 size={18} />
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
