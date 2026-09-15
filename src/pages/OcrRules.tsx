import { useState, useEffect } from 'react';
import { db } from '../firebase';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { Save, AlertTriangle, CheckCircle, RefreshCw } from 'lucide-react';

const defaultRules = {
  platforms: {
    kakao_general: {
      detect_keywords: ["출발지", "도착지", "예상요금"],
      field_patterns: {
        gross_fare: "(\\d[\\d,]+)\\s*원",
        start_location: "출발지[:\\s]*([^\\n]+)",
        end_location: "도착지[:\\s]*([^\\n]+)"
      },
      noise_remove: ["상황실연락처", "기사메모", "고객메모"]
    },
    logi: {
      detect_keywords: ["갱신", "입금액"],
      field_patterns: {
        gross_fare: "입금액[:\\s]*(\\d[\\d,]+)",
        start_location: "출발지[:\\s]*([^\\n]+)",
        end_location: "도착지[:\\s]*([^\\n]+)"
      },
      noise_remove: ["고객과의거리", "운행시작"]
    },
    colmanner: {
      detect_keywords: ["출도", "지사명"],
      field_patterns: {
        gross_fare: "(\\d[\\d,]+)\\s*원",
        start_location: "출발[:\\s]*([^\\n]+)",
        end_location: "도착[:\\s]*([^\\n]+)"
      },
      noise_remove: ["출도", "지사명"]
    }
  }
};

export default function OcrRules() {
  const [loading, setLoading] = useState(true);
  const [version, setVersion] = useState<number>(0);
  const [rulesJson, setRulesJson] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchRules();
  }, []);

  const fetchRules = async () => {
    try {
      setLoading(true);
      setError(null);
      const vDoc = await getDoc(doc(db, 'parsing_rules', 'version'));
      const rDoc = await getDoc(doc(db, 'parsing_rules', 'rules'));

      if (!vDoc.exists() || !rDoc.exists()) {
        // Initialize if empty
        setVersion(1);
        setRulesJson(JSON.stringify(defaultRules, null, 2));
      } else {
        setVersion(vDoc.data().version || 1);
        setRulesJson(JSON.stringify(rDoc.data(), null, 2));
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      setError(null);
      setSuccess(null);
      
      const parsed = JSON.parse(rulesJson); // validate json
      
      const newVersion = version + 1;
      await setDoc(doc(db, 'parsing_rules', 'rules'), parsed);
      await setDoc(doc(db, 'parsing_rules', 'version'), {
        version: newVersion,
        updated_at: new Date().toISOString()
      });
      
      setVersion(newVersion);
      setSuccess(`성공적으로 저장되었습니다. (버전 ${newVersion} 적용됨)`);
      setTimeout(() => setSuccess(null), 3000);
    } catch (err: any) {
      setError("JSON 형식이 올바르지 않거나 저장에 실패했습니다: " + err.message);
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="p-8 text-gray-400">Loading...</div>;

  return (
    <div className="p-8 max-w-5xl mx-auto">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-3xl font-bold text-white mb-2">OCR 정규식 룰 엔진 (JSON)</h1>
          <p className="text-gray-400">앱 업데이트 없이 실시간으로 적용되는 파싱 룰을 관리합니다.</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="text-sm bg-blue-500/10 text-blue-400 px-3 py-1.5 rounded-full border border-blue-500/20">
            현재 앱 적용 버전: <span className="font-bold">v{version}</span>
          </div>
          <button 
            onClick={fetchRules}
            className="p-2 hover:bg-white/5 rounded-lg text-gray-400 transition-colors"
          >
            <RefreshCw size={20} />
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-6 p-4 bg-red-500/10 border border-red-500/20 rounded-xl flex gap-3 text-red-400 items-start">
          <AlertTriangle size={20} className="shrink-0 mt-0.5" />
          <p className="text-sm">{error}</p>
        </div>
      )}

      {success && (
        <div className="mb-6 p-4 bg-green-500/10 border border-green-500/20 rounded-xl flex gap-3 text-green-400 items-center">
          <CheckCircle size={20} className="shrink-0" />
          <p className="text-sm">{success}</p>
        </div>
      )}

      <div className="bg-[#1a1d24] rounded-2xl border border-white/5 overflow-hidden flex flex-col h-[600px]">
        <div className="p-4 border-b border-white/5 flex justify-between items-center bg-black/20">
          <h2 className="font-semibold text-gray-200">parsing_rules / rules 문서</h2>
          <button
            onClick={handleSave}
            disabled={saving}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-medium transition-colors disabled:opacity-50"
          >
            <Save size={18} />
            {saving ? '저장 중...' : '버전 올리고 배포하기'}
          </button>
        </div>
        <textarea
          value={rulesJson}
          onChange={(e) => setRulesJson(e.target.value)}
          className="flex-1 w-full bg-transparent text-gray-300 p-6 font-mono text-sm focus:outline-none resize-none leading-relaxed"
          spellCheck={false}
        />
      </div>
    </div>
  );
}
