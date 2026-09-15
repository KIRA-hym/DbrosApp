import { useState, useEffect } from 'react';
import { collection, query, where, getDocs, updateDoc, doc, deleteDoc } from 'firebase/firestore';
import { db, remoteConfig } from '../firebase';
import { getString } from 'firebase/remote-config';

export default function GoldenSamples() {
  const [samples, setSamples] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [processing, setProcessing] = useState(false);
  const [logs, setLogs] = useState<string[]>([]);

  useEffect(() => {
    fetchSamples();
  }, []);

  const fetchSamples = async () => {
    setLoading(true);
    try {
      const q = query(collection(db, 'ocr_golden_samples'), where('is_verified', '==', false));
      const snap = await getDocs(q);
      const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setSamples(data);
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  };

  const addLog = (msg: string) => setLogs(prev => [...prev, msg]);

  const handleAutoReview = async () => {
    if (samples.length === 0) return;
    setProcessing(true);
    setLogs([]);
    
    try {
      const geminiApiKey = getString(remoteConfig, 'gemini_api_key');
      if (!geminiApiKey) {
        addLog('오류: Gemini API 키를 Remote Config(gemini_api_key)에서 찾을 수 없습니다.');
        setProcessing(false);
        return;
      }

      for (const sample of samples) {
        addLog(`분석 중... [${sample.source_file}]`);
        try {
          const prompt = `You are an expert at parsing Korean designated driver (대리운전) call cards. 
The user provides raw OCR text. Determine if it contains a valid call. 
If it is completely garbage/not a call, return {"is_valid": false}.
If it is a call, extract the total fare (integer), start location, and end location. 
Return strictly valid JSON: {"is_valid": true, "fare": 30000, "start": "출발지주소", "end": "도착지주소"}.
Do not include markdown or backticks.
Text: ${sample.raw_text}`;

          const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${geminiApiKey}`;
          const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              contents: [{ parts: [{ text: prompt }] }]
            })
          });

          if (!response.ok) {
            addLog(`-> API 오류: HTTP ${response.status} (무료 요금제 초당 요청 한도 초과)`);
            await new Promise(resolve => setTimeout(resolve, 4500));
            continue;
          }

          const result = await response.json();
          const textResponse = result.candidates[0].content.parts[0].text;
          const responseText = textResponse.trim().replace(/```json/g, '').replace(/```/g, '');
          const json = JSON.parse(responseText);

          if (!json.is_valid) {
            addLog(`-> 가비지 감지됨. 데이터 삭제: ${sample.source_file}`);
            await deleteDoc(doc(db, 'ocr_golden_samples', sample.id));
          } else {
            addLog(`-> 파싱 성공! (요금: ${json.fare}, 출발: ${json.start}, 도착: ${json.end}) -> 승인 처리`);
            await updateDoc(doc(db, 'ocr_golden_samples', sample.id), {
              gross_fare: json.fare,
              start_location: json.start,
              end_location: json.end,
              is_verified: true,
              verified_by: 'ai_auto_label'
            });
          }
        } catch (err: any) {
          addLog(`-> 오류 발생 [${sample.source_file}]: ${err.message}`);
        }
        
        // 구글 Gemini 무료 티어(Free Tier)의 분당 15회 제한(RPM)을 회피하기 위해 4.1초 대기
        await new Promise(resolve => setTimeout(resolve, 4100));
      }
      addLog('✅ 모든 자동 검수 및 라벨링 완료!');
      await fetchSamples();
    } catch (e: any) {
      addLog('치명적 오류: ' + e.message);
    }
    setProcessing(false);
  };

  return (
    <div className="p-6">
      <h1 className="text-2xl font-bold mb-4">OCR 기출문제 정답지 검수 (Golden Samples)</h1>
      <p className="text-gray-600 mb-6">앱에서 다중으로 올려진 '미검수 정답지'를 AI가 분석하여 자동으로 요금을 입력하고 확정 짓거나 삭제합니다.</p>
      
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-lg font-semibold">미검수 항목: {samples.length}개</h2>
        <button 
          onClick={handleAutoReview}
          disabled={processing || samples.length === 0}
          className="bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded disabled:opacity-50"
        >
          {processing ? 'AI가 검수 중...' : '🤖 AI 일괄 자동 검수 시작'}
        </button>
      </div>

      {logs.length > 0 && (
        <div className="bg-gray-900 text-green-400 p-4 rounded mb-6 font-mono text-sm max-h-40 overflow-y-auto">
          {logs.map((log, i) => <div key={i}>{log}</div>)}
        </div>
      )}

      {loading ? (
        <p>데이터 불러오는 중...</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {samples.map(s => (
            <div key={s.id} className="border p-4 rounded shadow bg-white">
              <div className="font-bold text-gray-700 truncate">{s.source_file}</div>
              <div className="text-xs text-gray-400 mb-2">업로드: {s.uploaded_from}</div>
              <pre className="text-xs bg-gray-100 p-2 rounded h-32 overflow-y-auto whitespace-pre-wrap">
                {s.raw_text}
              </pre>
            </div>
          ))}
          {samples.length === 0 && <p className="text-gray-500">대기 중인 미검수 항목이 없습니다.</p>}
        </div>
      )}
    </div>
  );
}
