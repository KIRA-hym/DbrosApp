import { useState, useEffect } from 'react';
import { collection, query, orderBy, onSnapshot, doc, Timestamp, writeBatch } from 'firebase/firestore';
import { db } from '../firebase';
import { Ticket, CheckCircle, Clock, Plus, Loader2, Trash2, Copy } from 'lucide-react';

interface PromotionCodeData {
  id: string;
  code: string;
  durationMonths: number;
  isUsed: boolean;
  usedBy: string | null;
  usedAt: Timestamp | null;
  createdAt: Timestamp | null;
}

export default function PromotionCodes() {
  const [codes, setCodes] = useState<PromotionCodeData[]>([]);
  const [loading, setLoading] = useState(true);
  const [isGenerating, setIsGenerating] = useState(false);
  const [generateCount, setGenerateCount] = useState<number>(10);
  const [selectedCodes, setSelectedCodes] = useState<string[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    const q = query(collection(db, 'promotion_codes'), orderBy('createdAt', 'desc'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const codeList: PromotionCodeData[] = snapshot.docs.map(doc => ({
        id: doc.id,
        code: doc.data().code || '',
        durationMonths: doc.data().durationMonths || 1,
        isUsed: doc.data().isUsed === true,
        usedBy: doc.data().usedBy || null,
        usedAt: doc.data().usedAt || null,
        createdAt: doc.data().createdAt || null,
      }));
      setCodes(codeList);
      setLoading(false);
    }, (error) => {
      console.error("Error fetching promotion codes: ", error);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const generateRandomCode = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let result = '';
    for (let i = 0; i < 8; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return `DBROS2026${result}`;
  };

  const handleGenerateCodes = async () => {
    if (generateCount < 1 || generateCount > 100) {
      alert('1개에서 100개 사이로 생성해주세요.');
      return;
    }

    if (!window.confirm(`프로모션 코드 ${generateCount}개를 생성하시겠습니까?`)) return;

    setIsGenerating(true);
    try {
      const batch = writeBatch(db);
      const codesRef = collection(db, 'promotion_codes');

      for (let i = 0; i < generateCount; i++) {
        const newCode = generateRandomCode();
        const docRef = doc(codesRef, newCode);
        batch.set(docRef, {
          code: newCode,
          durationMonths: 1,
          isUsed: false,
          usedBy: null,
          usedAt: null,
          createdAt: Timestamp.now(),
        });
      }

      await batch.commit();
      alert('성공적으로 발급되었습니다.');
      setGenerateCount(10);
    } catch (error) {
      console.error("Error generating codes: ", error);
      alert('발급 중 오류가 발생했습니다.');
    } finally {
      setIsGenerating(false);
    }
  };

  const handleSelectAll = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.checked) {
      setSelectedCodes(codes.map(c => c.id));
    } else {
      setSelectedCodes([]);
    }
  };

  const handleSelectOne = (e: React.ChangeEvent<HTMLInputElement>, id: string) => {
    if (e.target.checked) {
      setSelectedCodes(prev => [...prev, id]);
    } else {
      setSelectedCodes(prev => prev.filter(codeId => codeId !== id));
    }
  };

  const handleDeleteSelected = async () => {
    if (selectedCodes.length === 0) return;
    if (!window.confirm(`선택한 ${selectedCodes.length}개의 프로모션 코드를 정말 삭제하시겠습니까? (복구 불가)`)) return;

    setIsProcessing(true);
    try {
      const batch = writeBatch(db);
      selectedCodes.forEach(id => {
        batch.delete(doc(db, 'promotion_codes', id));
      });
      await batch.commit();
      setSelectedCodes([]);
      alert('삭제되었습니다.');
    } catch (error) {
      console.error("Error deleting codes: ", error);
      alert('삭제 중 오류가 발생했습니다.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleCopySelected = async () => {
    if (selectedCodes.length === 0) return;
    const codesToCopy = codes
      .filter(c => selectedCodes.includes(c.id))
      .map(c => c.code)
      .join('\n'); // 자동 줄바꿈으로 합치기

    try {
      await navigator.clipboard.writeText(codesToCopy);
      alert(`${selectedCodes.length}개의 코드가 클립보드에 복사되었습니다.`);
    } catch (error) {
      console.error("Error copying to clipboard: ", error);
      alert('클립보드 복사에 실패했습니다.');
    }
  };

  if (loading) {
    return <div className="p-8 text-center text-gray-400">코드를 불러오는 중...</div>;
  }

  const unusedCount = codes.filter(c => !c.isUsed).length;
  const usedCount = codes.filter(c => c.isUsed).length;
  const isAllSelected = codes.length > 0 && selectedCodes.length === codes.length;
  const isSomeSelected = selectedCodes.length > 0 && selectedCodes.length < codes.length;

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Ticket className="text-yellow-500" />
            프로모션 코드 관리
          </h1>
          <p className="text-gray-400 mt-1">프리미엄 권한을 제공하는 코드를 대량으로 발급하고 내역을 확인합니다.</p>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded-lg border border-gray-700 flex gap-4 text-sm whitespace-nowrap">
          <div>
            <span className="text-gray-400">총 발급: </span>
            <span className="text-white font-bold">{codes.length}</span>
          </div>
          <div className="w-px bg-gray-700"></div>
          <div>
            <span className="text-gray-400">미사용: </span>
            <span className="text-emerald-400 font-bold">{unusedCount}</span>
          </div>
          <div className="w-px bg-gray-700"></div>
          <div>
            <span className="text-gray-400">사용 완료: </span>
            <span className="text-gray-400 font-bold">{usedCount}</span>
          </div>
        </div>
      </div>

      <div className="bg-gray-800 p-6 rounded-2xl border border-gray-700 flex flex-col md:flex-row items-center gap-4">
        <div className="flex-1">
          <h2 className="text-white font-semibold flex items-center gap-2">
            코드 일괄 발급기
          </h2>
          <p className="text-sm text-gray-400 mt-1">한 번에 최대 100개까지 무작위 난수 코드를 발급할 수 있습니다. (기본 1개월용)</p>
        </div>
        <div className="flex items-center gap-3">
          <div className="relative">
            <input
              type="number"
              min="1"
              max="100"
              value={generateCount}
              onChange={(e) => setGenerateCount(parseInt(e.target.value) || 1)}
              className="bg-gray-900 border border-gray-700 text-white rounded-lg px-4 py-2 w-32 focus:outline-none focus:border-yellow-500"
            />
            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 text-sm">개</span>
          </div>
          <button
            onClick={handleGenerateCodes}
            disabled={isGenerating}
            className="flex items-center gap-2 bg-yellow-500 hover:bg-yellow-400 text-black font-bold py-2 px-6 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isGenerating ? <Loader2 className="animate-spin" size={20} /> : <Plus size={20} />}
            발급하기
          </button>
        </div>
      </div>

      {selectedCodes.length > 0 && (
        <div className="bg-blue-500/10 border border-blue-500/20 p-4 rounded-xl flex items-center justify-between">
          <span className="text-blue-400 font-medium">
            {selectedCodes.length}개 선택됨
          </span>
          <div className="flex items-center gap-3">
            <button
              onClick={handleCopySelected}
              className="flex items-center gap-2 px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg border border-gray-700 transition-colors"
            >
              <Copy size={16} /> 클립보드 복사
            </button>
            <button
              onClick={handleDeleteSelected}
              disabled={isProcessing}
              className="flex items-center gap-2 px-4 py-2 bg-red-500/10 hover:bg-red-500/20 text-red-500 border border-red-500/20 rounded-lg transition-colors disabled:opacity-50"
            >
              {isProcessing ? <Loader2 className="animate-spin" size={16} /> : <Trash2 size={16} />}
              선택 삭제
            </button>
          </div>
        </div>
      )}

      <div className="bg-gray-800 rounded-2xl border border-gray-700 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-gray-900/50 text-gray-400 text-sm border-b border-gray-700">
                <th className="p-4 w-12">
                  <input
                    type="checkbox"
                    checked={isAllSelected}
                    ref={input => {
                      if (input) input.indeterminate = isSomeSelected;
                    }}
                    onChange={handleSelectAll}
                    className="w-4 h-4 rounded border-gray-600 bg-gray-700 text-yellow-500 focus:ring-yellow-500 focus:ring-offset-gray-900"
                  />
                </th>
                <th className="p-4 font-medium">프로모션 코드</th>
                <th className="p-4 font-medium">혜택 기간</th>
                <th className="p-4 font-medium">상태</th>
                <th className="p-4 font-medium">사용자 UID</th>
                <th className="p-4 font-medium">사용 일시</th>
                <th className="p-4 font-medium text-right">발급 일시</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-700">
              {codes.length === 0 ? (
                <tr>
                  <td colSpan={7} className="p-8 text-center text-gray-400">
                    발급된 프로모션 코드가 없습니다.
                  </td>
                </tr>
              ) : (
                codes.map((code) => (
                  <tr key={code.id} className={`hover:bg-gray-700/30 transition-colors ${code.isUsed ? 'opacity-60' : ''}`}>
                    <td className="p-4">
                      <input
                        type="checkbox"
                        checked={selectedCodes.includes(code.id)}
                        onChange={(e) => handleSelectOne(e, code.id)}
                        className="w-4 h-4 rounded border-gray-600 bg-gray-700 text-yellow-500 focus:ring-yellow-500 focus:ring-offset-gray-900"
                      />
                    </td>
                    <td className="p-4 font-mono font-medium text-white">
                      {code.code}
                    </td>
                    <td className="p-4 text-gray-300">
                      {code.durationMonths}개월
                    </td>
                    <td className="p-4">
                      {code.isUsed ? (
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-gray-700 text-gray-300 border border-gray-600">
                          <CheckCircle size={14} /> 사용 완료
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-emerald-500/10 text-emerald-500 border border-emerald-500/20">
                          <Clock size={14} /> 미사용
                        </span>
                      )}
                    </td>
                    <td className="p-4 text-sm text-gray-400 font-mono">
                      {code.usedBy || '-'}
                    </td>
                    <td className="p-4 text-sm text-gray-400">
                      {code.usedAt ? code.usedAt.toDate().toLocaleString('ko-KR') : '-'}
                    </td>
                    <td className="p-4 text-sm text-gray-400 text-right">
                      {code.createdAt ? code.createdAt.toDate().toLocaleString('ko-KR') : '-'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
