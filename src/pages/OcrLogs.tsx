import { useState, useEffect } from 'react';
import { Terminal, Copy, CheckCircle2, AlertTriangle, RefreshCw } from 'lucide-react';
import { collection, query, orderBy, limit, getDocs } from 'firebase/firestore';
import { db } from '../firebase';

export default function OcrLogs() {
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [logs, setLogs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchLogs = async () => {
    setLoading(true);
    try {
      const q = query(collection(db, "ocr_failures"), orderBy("timestamp", "desc"), limit(10));
      const querySnapshot = await getDocs(q);
      const fetchedLogs = querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      setLogs(fetchedLogs);
    } catch (error) {
      console.error("Error fetching logs:", error);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchLogs();
  }, []);

  const handleCopyPrompt = (log: any) => {
    const rawText = log.raw_text || "내용 없음";
    const promptText = rawText;

    navigator.clipboard.writeText(promptText).then(() => {
      setCopiedId(log.id);
      setTimeout(() => setCopiedId(null), 2000);
    });
  };

  return (
    <div className="p-8">
      <div className="mb-8 flex justify-between items-end">
        <div>
          <h2 className="text-2xl font-bold text-white mb-1">OCR 품질 관리 센터</h2>
          <p className="text-gray-400 text-sm">에러 로그와 기사님의 수동 수정 내역을 비교하여 파싱 정규식을 개선합니다.</p>
        </div>
        <button 
          onClick={fetchLogs} 
          disabled={loading}
          className="bg-gray-800 hover:bg-gray-700 text-white px-4 py-2 rounded-lg flex items-center gap-2 text-sm transition"
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} /> 새로고침
        </button>
      </div>

      <div className="bg-red-500/10 border-l-4 border-l-red-500 p-4 rounded-r-lg shadow-sm mb-6">
        <h4 className="font-bold text-red-400 mb-1 flex items-center gap-2"><AlertTriangle size={16} /> 에러 추적 메커니즘</h4>
        <p className="text-gray-300 text-sm leading-relaxed">
          특정 대리 앱이 업데이트되어 형식이 바뀌면 에러가 발생합니다. 관리자는 <strong>[클립보드에 원본 복사]</strong> 버튼을 눌러 채팅창에 붙여넣기만 하면,<br />
          개발자에게 전달하여 정규식을 고치고 업데이트를 준비합니다.
        </p>
      </div>

      <div className="space-y-6">
        {loading ? (
          <div className="text-center text-gray-500 py-10">데이터를 불러오는 중입니다...</div>
        ) : logs.length === 0 ? (
          <div className="text-center text-gray-500 py-10 bg-[#1a1d24] rounded-xl border border-white/5">최근 수집된 에러 로그가 없습니다. (파싱 완벽함!)</div>
        ) : (
          logs.map((log) => (
            <div key={log.id} className="bg-[#1a1d24] border border-red-500/20 rounded-2xl p-6 shadow-lg">
              <h4 className="text-white font-bold mb-4 flex items-center gap-2">
                <Terminal size={18} className="text-gray-400" /> 
                파싱 실패 내역 ({log.timestamp?.toDate ? log.timestamp.toDate().toLocaleString() : '알 수 없음'})
              </h4>
              
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <div className="bg-red-500/5 border border-red-500/20 rounded-xl p-5 relative">
                  <div className="text-red-400 text-xs font-bold uppercase bg-red-500/10 px-2 py-1 rounded inline-block mb-3">파싱 실패 원본 (raw_text)</div>
                  <p className="text-gray-400 text-sm font-mono break-all leading-loose bg-black/40 p-4 rounded-lg border border-black/50 shadow-inner min-h-[100px]">
                    {log.raw_text || "텍스트 없음"}
                  </p>
                </div>

                <div className="bg-gray-800/20 border border-gray-700/50 rounded-xl p-5 relative flex items-center justify-center flex-col gap-3 min-h-[150px]">
                  <p className="text-gray-400 text-sm text-center">
                    이 원본 데이터를 분석하여 정규식을 수정하려면<br/>아래 버튼을 눌러 개발자에게 전달하세요.
                  </p>
                  
                  <button 
                    onClick={() => handleCopyPrompt(log)}
                    className={`text-white text-sm px-4 py-2.5 rounded-lg transition shadow-lg flex items-center gap-2 font-bold
                      ${copiedId === log.id ? 'bg-green-600 hover:bg-green-500' : 'bg-blue-600 hover:bg-blue-500'}`}
                  >
                    {copiedId === log.id ? <CheckCircle2 size={16} /> : <Copy size={16} />}
                    {copiedId === log.id ? '복사 완료!' : '원본 텍스트 복사'}
                  </button>
                </div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

