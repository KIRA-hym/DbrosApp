import React, { useState, useEffect } from 'react';
import { ref, getDownloadURL, uploadString } from 'firebase/storage';
import { storage } from '../firebase';
import { MapPin, Upload, Save, Trash2, Plus, Download } from 'lucide-react';
import * as XLSX from 'xlsx';

interface CallPoint {
  id: string; // for React list keys
  type: string; // 'reference', 'restroom', 'shuttle'
  start_location: string;
  start_lat: number;
  start_lng: number;
  memo?: string;
}

export default function CallPoints() {
  const [points, setPoints] = useState<CallPoint[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchPoints();
  }, []);

  const fetchPoints = async () => {
    setLoading(true);
    try {
      const fileRef = ref(storage, 'map_data/common_points.json');
      const url = await getDownloadURL(fileRef);
      const response = await fetch(url);
      const data = await response.json();
      
      const mapped = data.map((item: any) => ({
        id: crypto.randomUUID(),
        type: item.type || 'reference',
        start_location: item.start_location || '',
        start_lat: Number(item.start_lat) || 0,
        start_lng: Number(item.start_lng) || 0,
        memo: item.memo || ''
      }));
      setPoints(mapped);
    } catch (e: any) {
      console.log('Error fetching points, might not exist yet:', e.message);
      setPoints([]);
    } finally {
      setLoading(false);
    }
  };

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const bstr = evt.target?.result;
        const wb = XLSX.read(bstr, { type: 'binary' });
        const wsname = wb.SheetNames[0];
        const ws = wb.Sheets[wsname];
        const data = XLSX.utils.sheet_to_json(ws);

        const newPoints: CallPoint[] = data.map((row: any) => ({
          id: crypto.randomUUID(),
          type: row['type'] || row['종류'] || 'reference',
          start_location: row['start_location'] || row['위치명'] || '',
          start_lat: Number(row['start_lat'] || row['위도']) || 0,
          start_lng: Number(row['start_lng'] || row['경도']) || 0,
          memo: row['memo'] || row['메모'] || ''
        })).filter(p => p.start_lat !== 0 && p.start_lng !== 0);

        // 덮어쓰기 여부 확인
        if (window.confirm(`기존 데이터를 무시하고 엑셀 데이터(${newPoints.length}개)로 덮어쓰시겠습니까?\n(취소 시 기존 데이터에 추가됩니다)`)) {
          setPoints(newPoints);
        } else {
          setPoints([...points, ...newPoints]);
        }
      } catch (error) {
        alert('엑셀 파일 파싱 중 오류가 발생했습니다.');
        console.error(error);
      }
    };
    reader.readAsBinaryString(file);
    // Reset file input
    e.target.value = '';
  };

  const handleSave = async () => {
    if (!window.confirm(`총 ${points.length}개의 마커 데이터를 기사님 앱으로 배포하시겠습니까?`)) return;

    setSaving(true);
    try {
      const dataToSave = points.map(({ id, ...rest }) => ({
        ...rest,
        is_mine: 0,
        user_id: 'admin',
        created_at: new Date().toISOString()
      }));

      const jsonString = JSON.stringify(dataToSave, null, 2);
      const fileRef = ref(storage, 'map_data/common_points.json');
      
      await uploadString(fileRef, jsonString, 'raw', {
        contentType: 'application/json'
      });

      alert('성공적으로 배포되었습니다. 기사님 앱을 다시 실행하면 새 데이터가 다운로드됩니다.');
    } catch (e) {
      alert('저장 중 오류가 발생했습니다.');
      console.error(e);
    } finally {
      setSaving(false);
    }
  };

  const deletePoint = (id: string) => {
    setPoints(points.filter(p => p.id !== id));
  };

  const addEmptyPoint = () => {
    setPoints([{
      id: crypto.randomUUID(),
      type: 'reference',
      start_location: '',
      start_lat: 0,
      start_lng: 0
    }, ...points]);
  };

  const updatePoint = (id: string, field: keyof CallPoint, value: string | number) => {
    setPoints(points.map(p => p.id === id ? { ...p, [field]: value } : p));
  };

  const downloadTemplate = () => {
    const ws = XLSX.utils.json_to_sheet([
      { 종류: 'reference', 위치명: '강남역 10번출구', 위도: 37.4979, 경도: 127.0276, 메모: '테스트' },
      { 종류: 'shuttle', 위치명: '판교역 셔틀', 위도: 37.3949, 경도: 127.1111, 메모: '' }
    ]);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Points");
    XLSX.writeFile(wb, "콜포인트_업로드_양식.xlsx");
  };

  return (
    <div className="p-8 max-w-7xl mx-auto">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <MapPin className="text-yellow-500" />
            주변콜맵 마커 관리
          </h1>
          <p className="text-gray-400 mt-1">기사님 앱 지도에 표시될 공통 마커(콜포인트, 화장실, 셔틀)를 관리하고 배포합니다.</p>
        </div>
        
        <div className="flex gap-3">
          <button 
            onClick={downloadTemplate}
            className="flex items-center gap-2 px-4 py-2 bg-gray-800 text-gray-300 rounded-lg hover:bg-gray-700 transition"
          >
            <Download size={18} />
            엑셀 양식
          </button>

          <label className="flex items-center gap-2 px-4 py-2 bg-blue-600/20 text-blue-400 border border-blue-500/30 rounded-lg hover:bg-blue-600/30 transition cursor-pointer">
            <Upload size={18} />
            엑셀 업로드
            <input 
              type="file" 
              accept=".xlsx, .xls" 
              className="hidden" 
              onChange={handleFileUpload} 
            />
          </label>
          
          <button 
            onClick={handleSave}
            disabled={saving}
            className="flex items-center gap-2 px-4 py-2 bg-yellow-500 text-black font-semibold rounded-lg hover:bg-yellow-400 transition disabled:opacity-50"
          >
            <Save size={18} />
            {saving ? '배포 중...' : '기사앱 배포'}
          </button>
        </div>
      </div>

      <div className="bg-[#1a1d24] rounded-xl border border-white/5 overflow-hidden flex flex-col h-[calc(100vh-200px)]">
        <div className="p-4 border-b border-white/5 flex justify-between items-center bg-[#1e2129]">
          <span className="text-gray-300 font-medium">총 {points.length}개의 마커</span>
          <button 
            onClick={addEmptyPoint}
            className="flex items-center gap-1 text-sm text-yellow-500 hover:text-yellow-400"
          >
            <Plus size={16} /> 행 추가
          </button>
        </div>

        <div className="overflow-auto flex-1">
          {loading ? (
            <div className="flex items-center justify-center h-full text-gray-400">데이터를 불러오는 중...</div>
          ) : points.length === 0 ? (
             <div className="flex flex-col items-center justify-center h-full text-gray-500 gap-2">
               <MapPin size={48} className="opacity-20" />
               <p>등록된 마커가 없습니다. 엑셀을 업로드하거나 직접 추가해주세요.</p>
             </div>
          ) : (
            <table className="w-full text-left border-collapse">
              <thead className="bg-[#121418] sticky top-0 z-10">
                <tr>
                  <th className="p-4 font-medium text-gray-400 text-sm">종류</th>
                  <th className="p-4 font-medium text-gray-400 text-sm">위치명</th>
                  <th className="p-4 font-medium text-gray-400 text-sm">위도 (Lat)</th>
                  <th className="p-4 font-medium text-gray-400 text-sm">경도 (Lng)</th>
                  <th className="p-4 font-medium text-gray-400 text-sm w-16">삭제</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {points.map((point) => (
                  <tr key={point.id} className="hover:bg-white/[0.02] transition-colors">
                    <td className="p-3">
                      <select 
                        value={point.type}
                        onChange={(e) => updatePoint(point.id, 'type', e.target.value)}
                        className="bg-[#121418] border border-white/10 rounded px-2 py-1.5 text-sm text-gray-200 w-full focus:border-yellow-500/50 outline-none"
                      >
                        <option value="reference">콜포인트</option>
                        <option value="restroom">화장실</option>
                        <option value="shuttle">셔틀</option>
                      </select>
                    </td>
                    <td className="p-3">
                      <input 
                        type="text" 
                        value={point.start_location}
                        onChange={(e) => updatePoint(point.id, 'start_location', e.target.value)}
                        className="bg-[#121418] border border-white/10 rounded px-3 py-1.5 text-sm text-gray-200 w-full focus:border-yellow-500/50 outline-none"
                        placeholder="예: 강남역 10번 출구"
                      />
                    </td>
                    <td className="p-3">
                      <input 
                        type="number" 
                        value={point.start_lat}
                        onChange={(e) => updatePoint(point.id, 'start_lat', Number(e.target.value))}
                        className="bg-[#121418] border border-white/10 rounded px-3 py-1.5 text-sm text-gray-200 w-full focus:border-yellow-500/50 outline-none font-mono"
                      />
                    </td>
                    <td className="p-3">
                      <input 
                        type="number" 
                        value={point.start_lng}
                        onChange={(e) => updatePoint(point.id, 'start_lng', Number(e.target.value))}
                        className="bg-[#121418] border border-white/10 rounded px-3 py-1.5 text-sm text-gray-200 w-full focus:border-yellow-500/50 outline-none font-mono"
                      />
                    </td>
                    <td className="p-3 text-center">
                      <button 
                        onClick={() => deletePoint(point.id)}
                        className="p-1.5 text-gray-500 hover:text-red-400 hover:bg-red-400/10 rounded transition"
                      >
                        <Trash2 size={16} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
