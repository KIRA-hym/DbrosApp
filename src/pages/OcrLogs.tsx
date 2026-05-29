import { useState, useEffect } from 'react';
import { collection, query, orderBy, onSnapshot } from 'firebase/firestore';
import { db } from '../firebase';
import { AlertTriangle, ChevronDown, ChevronUp, Clock, Smartphone, Bug, Copy } from 'lucide-react';

interface OcrFailureLog {
  id: string;
  app_version: string;
  error_reason: string;
  platform: string;
  raw_text: string;
  timestamp: any;
  parsed_data?: {
    fee_amount?: number;
    gross_fare?: number;
    departure?: string;
    destination?: string;
    waypoints?: string[];
  };
}

export default function OcrLogs() {
  const [logs, setLogs] = useState<OcrFailureLog[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(collection(db, 'ocr_failures'), orderBy('timestamp', 'desc'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const logData: OcrFailureLog[] = [];
      snapshot.forEach((doc) => {
        logData.push({ id: doc.id, ...doc.data() } as OcrFailureLog);
      });
      setLogs(logData);
      setLoading(false);
    }, (error) => {
      console.error("Error fetching ocr_failures: ", error);
      setLoading(false);
    });

    return unsubscribe;
  }, []);

  const formatTimestamp = (timestamp: any) => {
    if (!timestamp) return '알 수 없음';
    let date: Date;
    if (timestamp.toDate) {
      date = timestamp.toDate();
    } else if (typeof timestamp === 'number') {
      date = new Date(timestamp);
    } else {
      date = new Date(timestamp);
    }
    
    if (isNaN(date.getTime())) return String(timestamp);

    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  };

  return (
    <div className="p-8 h-full flex flex-col">
      <div className="flex justify-between items-center mb-6">
        <div>
          <h2 className="text-2xl font-bold text-white mb-1">OCR 디버그 로그</h2>
          <p className="text-gray-400 text-sm">콜카드 OCR 파싱 실패 및 예외 케이스 원본 로그를 확인합니다.</p>
        </div>
      </div>

      {/* 상단 경고 배너 */}
      <div className="w-full mb-6 p-4 bg-[#2A1A00] rounded-xl border border-yellow-500/40 flex items-center gap-3">
        <Bug className="text-yellow-500" size={20} />
        <p className="text-yellow-500 text-sm">
          개발자 전용 도구 - 기기에서 자동으로 보고된 파싱 실패(또는 예외) 건들의 RAW 텍스트와 에러 사유를 추출합니다.
        </p>
      </div>

      {/* 결과 목록 */}
      <div className="flex-1 overflow-auto pr-2 custom-scrollbar">
        {loading ? (
          <div className="flex flex-col items-center justify-center h-64">
            <div className="w-8 h-8 border-4 border-yellow-500 border-t-transparent rounded-full animate-spin mb-4"></div>
            <p className="text-gray-400">로그를 불러오는 중입니다...</p>
          </div>
        ) : logs.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-64 bg-[#1a1d24] rounded-2xl border border-white/5">
            <AlertTriangle size={48} className="text-gray-600 mb-4" />
            <p className="text-gray-400">수집된 OCR 실패 로그가 없습니다.</p>
          </div>
        ) : (
          <div className="space-y-4">
            {logs.map((log, index) => (
              <LogCard key={log.id} log={log} index={index} formatTimestamp={formatTimestamp} total={logs.length} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function LogCard({ log, index, formatTimestamp, total }: { log: OcrFailureLog, index: number, formatTimestamp: (t: any) => string, total: number }) {
  const [showRaw, setShowRaw] = useState(false);
  const isAndroid = log.platform?.toLowerCase().includes('android');

  const handleCopy = () => {
    if (!log.raw_text) return;
    navigator.clipboard.writeText(log.raw_text).then(() => {
      alert('클립보드에 복사되었습니다.');
    }).catch((err) => {
      console.error('Failed to copy: ', err);
      alert('복사에 실패했습니다.');
    });
  };

  let fee = log.parsed_data?.fee_amount ?? log.parsed_data?.gross_fare;
  let start = log.parsed_data?.departure;
  let end = log.parsed_data?.destination;
  let waypoints = log.parsed_data?.waypoints;

  // error_reason에서 폴백(Fallback)으로 파싱 데이터 추출 (과거 로그 또는 parsed_data 누락 대비)
  if (log.error_reason && log.error_reason.includes('start:')) {
    const match = log.error_reason.match(/start:\s*(.*?),\s*end:\s*(.*?),\s*fare:\s*(.*)/);
    if (match) {
      if (start === undefined) start = match[1] === 'null' ? '' : match[1];
      if (end === undefined) end = match[2] === 'null' ? '' : match[2];
      if (fee === undefined) {
        const parsedFare = parseInt(match[3].replace(/[^0-9]/g, ''), 10);
        fee = isNaN(parsedFare) ? 0 : parsedFare;
      }
    }
  }

  const feeDisplay = fee ? `${fee.toLocaleString()}원` : '⚠️ 0원 (파싱실패 의심)';
  const startDisplay = start ? start : (start === '' ? '⚠️ (빈 텍스트)' : '⚠️ 없음');
  const endDisplay = end ? end : (end === '' ? '⚠️ (빈 텍스트)' : '⚠️ 없음');

  return (
    <div className="bg-[#1F222A] rounded-2xl border border-red-500/30 overflow-hidden shadow-lg transition-all hover:border-red-500/50">
      {/* 카드 헤더 */}
      <div className="px-5 py-4 flex items-center justify-between border-b border-[#2E323C]">
        <div className="flex items-center gap-3">
          <div className={`px-2.5 py-1 rounded text-xs font-bold flex items-center gap-1.5 ${isAndroid ? 'bg-green-500/10 text-green-400' : 'bg-gray-500/10 text-gray-300'}`}>
            <Smartphone size={14} />
            {log.platform || 'UNKNOWN'}
          </div>
          <span className="text-gray-400 text-sm">
            [{total - index}]
          </span>
          <div className="flex items-center gap-1.5 text-gray-300 text-sm">
            <Clock size={14} className="text-gray-500" />
            {formatTimestamp(log.timestamp)}
          </div>
        </div>
        <AlertTriangle size={18} className="text-red-400" />
      </div>

      {/* 본문 정보 */}
      <div className="px-5 py-4 space-y-3">
        <div className="flex items-start gap-4">
          <span className="w-20 text-gray-500 text-sm shrink-0">앱 버전</span>
          <span className="text-gray-200 text-sm">{log.app_version || '알 수 없음'}</span>
        </div>
        <div className="flex items-start gap-4">
          <span className="w-20 text-gray-500 text-sm shrink-0">💰 총요금</span>
          <span className={`text-sm ${!fee ? 'text-red-400 font-bold' : 'text-gray-200'}`}>
            {feeDisplay}
          </span>
        </div>
        <div className="flex items-start gap-4">
          <span className="w-20 text-gray-500 text-sm shrink-0">🚩 출발지</span>
          <span className={`text-sm ${!start ? 'text-red-400 font-bold' : 'text-gray-200'}`}>
            {startDisplay}
          </span>
        </div>
        {waypoints && waypoints.length > 0 && (
          <div className="flex items-start gap-4">
            <span className="w-20 text-gray-500 text-sm shrink-0">🔄 경유지</span>
            <span className="text-gray-200 text-sm">{waypoints.join(', ')}</span>
          </div>
        )}
        <div className="flex items-start gap-4">
          <span className="w-20 text-gray-500 text-sm shrink-0">🏁 도착지</span>
          <span className={`text-sm ${!end ? 'text-red-400 font-bold' : 'text-gray-200'}`}>
            {endDisplay}
          </span>
        </div>
        <div className="flex items-start gap-4">
          <span className="w-20 text-gray-500 text-sm shrink-0">❌ 에러사유</span>
          <span className="text-red-400 text-sm font-medium">{log.error_reason || '파싱 실패 (알 수 없음)'}</span>
        </div>
      </div>

      {/* 토글 버튼 */}
      <button 
        onClick={() => setShowRaw(!showRaw)}
        className="w-full px-5 py-3 flex items-center gap-2 border-t border-[#2E323C] bg-white/[0.02] hover:bg-white/[0.05] transition-colors group text-left"
      >
        {showRaw ? <ChevronUp size={16} className="text-gray-500 group-hover:text-gray-300" /> : <ChevronDown size={16} className="text-gray-500 group-hover:text-gray-300" />}
        <span className="text-xs text-gray-500 group-hover:text-gray-300 font-medium transition-colors">
          {showRaw ? 'RAW 텍스트 숨기기' : 'RAW OCR 텍스트 보기'}
        </span>
      </button>

      {/* 원본 텍스트 표시 영역 */}
      {showRaw && (
        <div className="p-4 mx-4 mb-4 mt-2 bg-[#121418] rounded-xl border border-white/5 relative group/raw overflow-x-auto">
          <button
            onClick={handleCopy}
            className="absolute top-3 right-3 p-2 bg-[#2A2D35] hover:bg-[#3A3D45] rounded-lg border border-white/10 text-gray-400 hover:text-white transition-all opacity-0 group-hover/raw:opacity-100 shadow-lg"
            title="텍스트 복사"
          >
            <Copy size={16} />
          </button>
          <pre className="text-[#B0B5C0] text-xs font-mono leading-relaxed whitespace-pre-wrap break-words pr-10">
            {log.raw_text || '(텍스트 없음)'}
          </pre>
        </div>
      )}
    </div>
  );
}
