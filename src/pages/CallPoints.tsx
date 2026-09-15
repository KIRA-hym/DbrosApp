import { useState, useEffect } from 'react';
import { RefreshCw, Activity, MapPin } from 'lucide-react';
import { MapContainer, TileLayer, CircleMarker, Popup, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

// MapController to handle programmatic panning
function MapController({ center }: { center: [number, number] | null }) {
  const map = useMap();
  useEffect(() => {
    if (center) {
      // 렌더링 이슈가 아니라 duration 1.5초 설정 때문이었음. 0.4초로 확 줄여서 빠르게 포커싱되도록 수정
      map.flyTo(center, 15, { duration: 0.4 });
    }
  }, [center, map]);
  return null;
}

export default function CallPoints() {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedPoint, setSelectedPoint] = useState<[number, number] | null>(null);

  const fetchMapData = async () => {
    setLoading(true);
    setError(null);
    try {
      const url = 'https://us-central1-dbros-apps-7bbmw4.cloudfunctions.net/getCallPointsMap';
      // Append cache buster to bypass Cloud Functions public cache
      const response = await fetch(url + '?t=' + new Date().getTime());
      if (!response.ok) throw new Error('API fetching failed');
      const json = await response.json();
      setData(json);
    } catch (e: any) {
      console.error(e);
      setError('데이터를 불러오지 못했습니다. 새벽 6시 스케줄러가 아직 실행되지 않았을 수 있습니다.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchMapData();
  }, []);

  const total = data?.stats?.total || 0;
  const kakaoRatio = total > 0 ? Math.round((data.stats.kakao / total) * 100) : 0;
  const logiRatio = total > 0 ? Math.round((data.stats.logi / total) * 100) : 0;
  const colmanerRatio = total > 0 ? Math.round((data.stats.colmaner / total) * 100) : 0;
  const tmapRatio = total > 0 ? Math.round((data.stats.tmap / total) * 100) : 0;
  const otherCount = total - ((data?.stats?.kakao || 0) + (data?.stats?.logi || 0) + (data?.stats?.colmaner || 0) + (data?.stats?.tmap || 0));
  const otherRatio = total > 0 && otherCount > 0 ? Math.round((otherCount / total) * 100) : 0;

  // 색상 매핑
  const getColor = (t: string) => {
    if (t.includes('카카오')) return '#eab308'; // yellow-500
    if (t.includes('로지')) return '#ef4444'; // red-500
    if (t.includes('콜마너')) return '#3b82f6'; // blue-500
    if (t.includes('티맵')) return '#22c55e'; // green-500
    return '#9ca3af'; // gray
  };

  const mapCenter = [37.5665, 126.9780] as [number, number]; // 서울시청 중심

  return (
    <div className="p-8 h-full flex flex-col">
      <style>{`
        .leaflet-interactive { cursor: pointer !important; }
        .map-tiles {
          filter: invert(100%) hue-rotate(180deg) grayscale(80%) contrast(1.2) brightness(0.8);
        }
      `}</style>
      
      <div className="flex justify-between items-end mb-6 shrink-0">
        <div>
          <h2 className="text-2xl font-bold text-white mb-1">콜 포인트 맵 (빅데이터)</h2>
          <p className="text-gray-400 text-sm">과금 없는 100% 무료 OpenStreetMap 기반 핫스팟 시각화입니다.</p>
        </div>
        <div className="flex items-center gap-3">
          <button 
            onClick={fetchMapData} 
            disabled={loading}
            className="flex items-center gap-2 bg-gray-800 hover:bg-gray-700 text-gray-200 px-4 py-2 rounded-xl transition-colors text-sm border border-gray-700 disabled:opacity-50"
          >
            <RefreshCw size={16} className={loading ? 'animate-spin text-blue-400' : 'text-blue-400'} />
            최신 데이터 갱신
          </button>
        </div>
      </div>

      <div className="bg-[#1a1d24] border border-white/5 rounded-2xl p-6 shadow-lg mb-6 flex-1 flex flex-col">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 flex-1">
          <div className="lg:col-span-2 relative min-h-[500px] bg-gray-900 rounded-xl overflow-hidden border border-gray-700 flex flex-col">
            {error ? (
              <div className="absolute inset-0 flex items-center justify-center text-red-400 p-4 text-center z-10 bg-gray-900/80">
                {error}
              </div>
            ) : null}
            {!loading && data && (
              <MapContainer 
                center={mapCenter} 
                zoom={12} 
                style={{ height: '100%', width: '100%', backgroundColor: '#111827' }}
                preferCanvas={true}
              >
                <TileLayer
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  className="map-tiles"
                />
                <MapController center={selectedPoint} />
                {data.points && data.points.map((pt: any, i: number) => (
                  <CircleMarker 
                    key={i}
                    center={[pt.lat, pt.lng]} 
                    radius={12}
                    pathOptions={{ color: '#ffffff', fillColor: getColor(pt.t), fillOpacity: 0.8, weight: 2 }}
                    eventHandlers={{
                      click: () => setSelectedPoint([pt.lat, pt.lng]),
                    }}
                  >
                    <Popup>
                      <div className="text-sm min-w-[200px]">
                        <strong className="text-base block mb-2 text-blue-600">{pt.t} 콜</strong>
                        <p className="mb-1 text-gray-700"><strong>출발:</strong> {pt.sl || '정보 없음'}</p>
                        <p className="mb-1 text-gray-700"><strong>도착:</strong> {pt.el || '정보 없음'}</p>
                        <p className="mb-1 text-gray-700"><strong>요금:</strong> {pt.f ? pt.f.toLocaleString() + '원' : '정보 없음'}</p>
                        <p className="text-xs text-gray-400 mt-3 border-t pt-2">{new Date(pt.time).toLocaleString()}</p>
                      </div>
                    </Popup>
                  </CircleMarker>
                ))}
              </MapContainer>
            )}
            
            <div className="absolute bottom-4 left-4 z-[400] pointer-events-none">
              <div className="bg-gray-900/90 border border-gray-700 px-4 py-3 rounded-lg shadow-lg backdrop-blur-sm">
                <div className="text-xs text-gray-400 flex items-center gap-1 mb-1">
                  <Activity size={12} className="text-blue-400" /> 화면 내 마커 수
                </div>
                <div className="text-sm font-bold text-white">{data?.points?.length?.toLocaleString() || 0}건</div>
              </div>
            </div>
          </div>
          
          <div className="flex flex-col gap-4" style={{ height: '100%', minHeight: '500px' }}>
            <div className="bg-gray-800/40 p-5 rounded-xl border border-gray-700 shrink-0">
              <div className="text-sm text-gray-400 font-medium mb-1">JSON 수집 누적 데이터</div>
              <div className="text-3xl font-bold text-white">{total.toLocaleString()}<span className="text-lg text-gray-500 font-normal ml-1">건</span></div>
              <p className="text-xs text-indigo-400 mt-2">
                마지막 갱신: {data?.updatedAtISO ? new Date(data.updatedAtISO).toLocaleString() : '정보 없음'}
              </p>
            </div>
            
            <div className="bg-gray-800/40 p-5 rounded-xl border border-gray-700 shrink-0">
              <div className="text-sm text-gray-400 font-medium mb-4">플랫폼별 콜 비중</div>
              <div className="space-y-4">
                {[
                  { name: '카카오', ratio: kakaoRatio, color: 'bg-yellow-500' },
                  { name: '로지', ratio: logiRatio, color: 'bg-red-500' },
                  { name: '콜마너', ratio: colmanerRatio, color: 'bg-blue-500' },
                  { name: '티맵', ratio: tmapRatio, color: 'bg-green-500' },
                  { name: '기타', ratio: otherRatio, color: 'bg-gray-400' }
                ].filter(s => s.ratio > 0).map(s => (
                  <div key={s.name}>
                    <div className="flex justify-between text-xs text-white mb-1">
                      <span>{s.name}</span><span>{s.ratio}%</span>
                    </div>
                    <div className="w-full bg-gray-700 rounded-full h-2">
                      <div className={`${s.color} h-2 rounded-full`} style={{ width: `${s.ratio}%` }}></div>
                    </div>
                  </div>
                ))}
                {[
                  { name: '카카오', ratio: kakaoRatio, color: 'bg-yellow-500' },
                  { name: '로지', ratio: logiRatio, color: 'bg-red-500' },
                  { name: '콜마너', ratio: colmanerRatio, color: 'bg-blue-500' },
                  { name: '티맵', ratio: tmapRatio, color: 'bg-green-500' },
                  { name: '기타', ratio: otherRatio, color: 'bg-gray-400' }
                ].filter(s => s.ratio > 0).length === 0 && (
                  <div className="text-center text-sm text-gray-500 py-2">집계된 데이터가 없습니다.</div>
                )}
              </div>
            </div>

            <div className="bg-gray-800/40 p-5 rounded-xl border border-gray-700 flex-1 overflow-hidden flex flex-col">
              <div className="text-sm text-gray-400 font-medium mb-3 shrink-0">콜 상세 목록 (클릭 시 지도 이동)</div>
              <div className="overflow-y-auto flex-1 pr-2 space-y-2 custom-scrollbar">
                {data?.points && data.points.map((pt: any, i: number) => (
                  <div 
                    key={i} 
                    onClick={() => setSelectedPoint([pt.lat, pt.lng])}
                    className="bg-gray-800 hover:bg-gray-700 cursor-pointer p-3 rounded-lg border border-gray-700 transition"
                  >
                    <div className="flex justify-between items-start mb-2">
                      <span className="text-xs font-bold px-2 py-0.5 rounded bg-blue-500/20 text-blue-400">{pt.t}</span>
                      <span className="text-xs text-gray-400">{new Date(pt.time).toLocaleTimeString()}</span>
                    </div>
                    <div className="text-sm text-gray-300 truncate mb-1"><span className="text-gray-500">출발:</span> {pt.sl || '정보없음'}</div>
                    <div className="text-sm text-gray-300 truncate"><span className="text-gray-500">도착:</span> {pt.el || '정보없음'}</div>
                    <div className="text-sm text-white font-bold mt-2 text-right">{pt.f ? pt.f.toLocaleString() + '원' : '-'}</div>
                  </div>
                ))}
                {!data?.points?.length && (
                  <div className="text-center text-sm text-gray-500 py-4">수집된 데이터가 없습니다.</div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="bg-blue-500/10 border-l-4 border-l-blue-500 p-4 rounded-r-lg shadow-sm">
        <h4 className="font-bold text-blue-400 mb-1 flex items-center gap-2"><MapPin size={16} /> 자동화 스케줄러 정보</h4>
        <p className="text-gray-300 text-sm leading-relaxed">
          서버 과금을 방어하기 위해 매일 새벽 6시(`0 6 * * *`)에 전체 데이터를 수집하여 JSON을 생성 및 Storage에 저장합니다.<br />
          지도를 열 때마다 DB 조회가 발생하지 않으므로, 백만 명이 동시에 조회해도 추가 과금이 발생하지 않는 구조입니다.
        </p>
      </div>
    </div>
  );
}
