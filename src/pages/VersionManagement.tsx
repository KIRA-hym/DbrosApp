import { useState, useEffect } from 'react';
import { Save, AlertTriangle } from 'lucide-react';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { db } from '../firebase';

export default function VersionManagement() {
  const [version, setVersion] = useState('');
  const [downloadUrl, setDownloadUrl] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    async function loadConfig() {
      try {
        const docRef = doc(db, 'config', 'app_version');
        const docSnap = await getDoc(docRef);
        if (docSnap.exists()) {
          setVersion(docSnap.data().latest_version || '');
          setDownloadUrl(docSnap.data().download_url || '');
        }
      } catch (e) {
        console.error(e);
      } finally {
        setIsLoading(false);
      }
    }
    loadConfig();
  }, []);

  const handleSave = async () => {
    setIsSaving(true);
    setMessage('');
    try {
      await setDoc(doc(db, 'config', 'app_version'), {
        latest_version: version.trim(),
        download_url: downloadUrl.trim()
      }, { merge: true });
      setMessage('성공적으로 저장되었습니다.');
    } catch (e) {
      console.error(e);
      setMessage('저장 실패!');
    } finally {
      setIsSaving(false);
      setTimeout(() => setMessage(''), 3000);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold text-white tracking-tight">앱 버전 관리</h2>
      </div>

      <div className="bg-[#1a1d24] rounded-2xl border border-gray-800 p-6">
        <div className="mb-6 p-4 bg-blue-500/10 border border-blue-500/20 rounded-xl flex items-start gap-3">
          <AlertTriangle className="text-blue-400 shrink-0 mt-0.5" size={20} />
          <div className="text-sm text-blue-200">
            여기에 설정된 최신 버전보다 낮은 버전을 사용하는 유저에게는 앱 실행 시 <strong>강제 업데이트 안내 팝업</strong>이 표시됩니다.
          </div>
        </div>

        {isLoading ? (
          <div className="text-gray-400">데이터를 불러오는 중...</div>
        ) : (
          <div className="space-y-6 max-w-xl">
            <div>
              <label className="block text-sm font-medium text-gray-400 mb-2">최신 버전 (예: 1.1.6+110603)</label>
              <input
                type="text"
                value={version}
                onChange={(e) => setVersion(e.target.value)}
                className="w-full bg-[#111318] border border-gray-700 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-blue-500 transition-colors"
                placeholder="버전 입력"
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-400 mb-2">업데이트 다운로드 URL</label>
              <input
                type="text"
                value={downloadUrl}
                onChange={(e) => setDownloadUrl(e.target.value)}
                className="w-full bg-[#111318] border border-gray-700 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-blue-500 transition-colors"
                placeholder="https://play.google.com/store/apps/details?id=com.dbros.drive"
              />
            </div>

            <button
              onClick={handleSave}
              disabled={isSaving}
              className="flex items-center justify-center w-full gap-2 bg-blue-600 hover:bg-blue-500 text-white px-6 py-3 rounded-xl font-medium transition-colors disabled:opacity-50"
            >
              {isSaving ? '저장 중...' : (
                <>
                  <Save size={20} />
                  설정 저장하기
                </>
              )}
            </button>

            {message && (
              <div className="text-center text-sm font-medium text-green-400 mt-2">
                {message}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
