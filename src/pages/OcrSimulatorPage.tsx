import { useState, useEffect } from 'react';
import { getOcrRules, saveOcrRules } from '../services/ocrRulesService';
import { parseOcrText, ParseResult } from '../utils/ocrParser';
import { Save, Play, RefreshCw } from 'lucide-react';

const OcrSimulatorPage = () => {
  const [platform, setPlatform] = useState<'kakao' | 'logi' | 'colmanner'>('kakao');
  const [rawText, setRawText] = useState('');
  const [rulesJson, setRulesJson] = useState('');
  const [result, setResult] = useState<ParseResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchRules();
  }, []);

  const fetchRules = async () => {
    setLoading(true);
    try {
      const json = await getOcrRules();
      setRulesJson(json);
    } catch (error) {
      console.error(error);
      alert('규칙을 불러오는데 실패했습니다.');
    } finally {
      setLoading(false);
    }
  };

  const handleTest = () => {
    try {
      JSON.parse(rulesJson); // Validate JSON first
      const parsed = parseOcrText(rawText, rulesJson, platform);
      setResult(parsed);
    } catch (e: any) {
      alert('JSON 문법 오류: ' + e.message);
    }
  };

  const handleSave = async () => {
    if (!window.confirm('이 규칙을 실서버에 배포하시겠습니까?\n(현재 앱은 새 엔진을 사용하지 않아 즉시 운영에 영향은 없습니다)')) return;
    
    setSaving(true);
    try {
      JSON.parse(rulesJson); // Validate
      await saveOcrRules(rulesJson);
      alert('실서버 DB에 배포 완료되었습니다!');
    } catch (e: any) {
      alert('저장 실패: JSON 문법을 확인해주세요.\n' + e.message);
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="p-8 text-white">Loading rules...</div>;

  return (
    <div className="p-6 h-screen flex flex-col bg-gray-900 text-white font-sans">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <RefreshCw className="text-blue-400" />
          OCR 파싱 룰 시뮬레이터 (Shadow Mode)
        </h1>
        <div className="flex gap-4">
          <select 
            className="bg-gray-800 border border-gray-700 rounded px-4 py-2"
            value={platform}
            onChange={e => setPlatform(e.target.value as any)}
          >
            <option value="kakao">카카오 (Kakao)</option>
            <option value="logi">로지 (Logi)</option>
            <option value="colmanner">콜마너 (Colmanner)</option>
          </select>
          <button 
            onClick={handleTest}
            className="flex items-center gap-2 bg-green-600 hover:bg-green-500 px-4 py-2 rounded font-semibold transition"
          >
            <Play size={18} /> 테스트 파싱
          </button>
          <button 
            onClick={handleSave}
            disabled={saving}
            className="flex items-center gap-2 bg-blue-600 hover:bg-blue-500 px-4 py-2 rounded font-semibold transition disabled:opacity-50"
          >
            <Save size={18} /> {saving ? '저장 중...' : 'DB에 배포'}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-6 flex-1 min-h-0">
        {/* Left Column */}
        <div className="flex flex-col gap-6">
          <div className="flex flex-col flex-1 bg-gray-800 rounded-lg p-4 border border-gray-700 shadow-xl">
            <h2 className="text-lg font-semibold mb-2 text-gray-300">원본 로그 텍스트 (Raw OCR)</h2>
            <textarea 
              className="flex-1 bg-gray-900 border border-gray-700 rounded p-3 text-sm font-mono resize-none focus:border-blue-500 focus:outline-none"
              placeholder="여기에 실패한 콜카드 텍스트를 붙여넣으세요..."
              value={rawText}
              onChange={e => setRawText(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col h-64 bg-gray-800 rounded-lg p-4 border border-gray-700 shadow-xl">
            <h2 className="text-lg font-semibold mb-2 text-gray-300">파싱 결과 (Parsed Result)</h2>
            {result ? (
              <div className="flex-1 bg-gray-900 rounded p-3 overflow-y-auto space-y-3">
                <div className="flex justify-between border-b border-gray-800 pb-2">
                  <span className="text-gray-400">요금</span>
                  <span className="font-bold text-green-400">{result.fare} 원</span>
                </div>
                <div className="flex justify-between border-b border-gray-800 pb-2">
                  <span className="text-gray-400">출발지</span>
                  <span className="font-bold text-white text-right break-words max-w-[70%]">{result.start || '-'}</span>
                </div>
                <div className="flex justify-between pb-2">
                  <span className="text-gray-400">도착지</span>
                  <span className="font-bold text-blue-400 text-right break-words max-w-[70%]">{result.end || '-'}</span>
                </div>
              </div>
            ) : (
              <div className="flex-1 flex items-center justify-center text-gray-600">
                테스트 버튼을 눌러주세요.
              </div>
            )}
          </div>
        </div>

        {/* Right Column */}
        <div className="flex flex-col gap-6">
          <div className="flex flex-col flex-1 bg-gray-800 rounded-lg p-4 border border-gray-700 shadow-xl">
            <h2 className="text-lg font-semibold mb-2 text-gray-300">
              정규식 JSON 룰 에디터 (Firestore + dbros_app 기본값 병합)
            </h2>
            <p className="text-xs text-gray-500 mb-2">
              Firestore에 저장된 값이 없는 필드는 C:\dbros_app 파싱 로직에서 추출한 기본 룰로 자동 채워집니다.
            </p>
            <textarea 
              className="flex-1 bg-gray-900 border border-gray-700 rounded p-3 text-sm font-mono resize-none focus:border-blue-500 focus:outline-none text-blue-300"
              value={rulesJson}
              onChange={e => setRulesJson(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col h-64 bg-gray-800 rounded-lg p-4 border border-gray-700 shadow-xl">
            <h2 className="text-lg font-semibold mb-2 text-gray-300">디버그 로그 (Engine Logs)</h2>
            <div className="flex-1 bg-black rounded p-3 overflow-y-auto font-mono text-xs text-gray-400">
              {result?.debugLog.map((log, i) => (
                <div key={i} className="mb-1">{log}</div>
              )) || "대기 중..."}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OcrSimulatorPage;
