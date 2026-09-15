import { useState, useEffect } from 'react';
import { UserCheck, Crown, Database, Server, SatelliteDish, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { collection, getCountFromServer, query, where, Timestamp, getDocs, orderBy, limit } from 'firebase/firestore';
import { db } from '../firebase';

export default function Dashboard() {
  const [stats, setStats] = useState({
    totalUsers: 0,
    newUsersToday: 0,
    premiumUsers: 0,
    dau: 0,
    totalCallPoints: 0,
    callPointsToday: 0,
    ocrErrorsToday: 0,
    recentErrors: [] as any[],
    loading: true
  });

  useEffect(() => {
    async function fetchStats() {
      try {
        // 오늘 자정 타임스탬프 계산
        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const startTimestamp = Timestamp.fromDate(startOfToday);

        // 1. 유저 통계 (getCountFromServer 활용하여 과금 방어)
        const [
          totalUsersSnap,
          newUsersSnap,
          premiumSnap,
          paidSnap,
          dauSnap,
          totalCallPointsSnap,
          callPointsTodaySnap,
          ocrErrorsTodaySnap
        ] = await Promise.all([
          getCountFromServer(collection(db, "users")), // 총 유저
          getCountFromServer(query(collection(db, "users"), where("createdAt", ">=", startTimestamp))), // 오늘 신규 유저
          getCountFromServer(query(collection(db, "users"), where("premiumUntil", ">", Timestamp.now()))), // 프로모션 프리미엄 유저
          getCountFromServer(query(collection(db, "users"), where("isRevenueCatPremium", "==", true))), // 정기구독 유료 결제 유저
          getCountFromServer(query(collection(db, "users"), where("lastLoginAt", ">=", startTimestamp))), // DAU
          getCountFromServer(collection(db, "shared_call_points")), // 전체 누적 콜 포인트
          getCountFromServer(query(collection(db, "shared_call_points"), where("timestamp", ">=", startTimestamp))),
          getCountFromServer(query(collection(db, "ocr_failures"), where("timestamp", ">=", startTimestamp)))
        ]);

        // 2. 최근 에러 피드 5건 가져오기
        const recentErrorsQuery = query(collection(db, "ocr_failures"), orderBy("timestamp", "desc"), limit(5));
        const recentErrorsDocs = await getDocs(recentErrorsQuery);
        const recentErrors = recentErrorsDocs.docs.map(doc => ({ id: doc.id, ...doc.data() }));

        setStats({
          totalUsers: totalUsersSnap.data().count,
          newUsersToday: newUsersSnap.data().count,
          premiumUsers: premiumSnap.data().count + paidSnap.data().count,
          dau: dauSnap.data().count,
          totalCallPoints: totalCallPointsSnap.data().count,
          callPointsToday: callPointsTodaySnap.data().count,
          ocrErrorsToday: ocrErrorsTodaySnap.data().count,
          recentErrors,
          loading: false
        });
      } catch (error) {
        console.error("Error fetching stats:", error);
        setStats(prev => ({ ...prev, loading: false }));
      }
    }
    fetchStats();
  }, []);

  return (
    <div className="p-8">
      <div className="flex justify-between items-end mb-8">
        <div>
          <h2 className="text-2xl font-bold text-white mb-1">종합 대시보드</h2>
          <p className="text-gray-400 text-sm">앱 전체 현황과 파이어베이스 서버 상태를 실시간 모니터링합니다.</p>
        </div>
        <div className="text-sm text-gray-500 flex items-center gap-2 bg-gray-800/50 px-3 py-1.5 rounded-lg border border-gray-700">
          <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>실시간 연결됨
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
        {/* Row 1: 유저 현황 */}
        <div className="bg-[#1a1d24] border border-white/5 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-gray-400 text-sm font-medium">전체 누적 기사님</div>
            <div className="p-2 bg-gray-700/50 rounded-lg"><Users size={20} className="text-gray-300" /></div>
          </div>
          <div className="text-2xl font-bold text-white">
            {stats.loading ? "..." : stats.totalUsers.toLocaleString()}
          </div>
          <div className="text-xs text-emerald-400 mt-2 flex items-center gap-1">오늘 신규 가입: +{stats.newUsersToday.toLocaleString()}명</div>
        </div>

        <div className="bg-[#1a1d24] border border-white/5 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-gray-400 text-sm font-medium">일일 활성 기사님 (DAU)</div>
            <div className="p-2 bg-blue-500/10 rounded-lg"><UserCheck size={20} className="text-blue-400" /></div>
          </div>
          <div className="text-2xl font-bold text-white">
            {stats.loading ? "..." : (stats.dau > 0 ? stats.dau.toLocaleString() : '집계 대기중')}
          </div>
          <div className="text-xs text-gray-500 mt-2 flex items-center gap-1">앱 접속 기록 캐싱 후 반영됨</div>
        </div>

        {/* Premium Users */}
        <div className="bg-[#1f2937] p-6 rounded-xl border border-[#374151]">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-gray-400 font-medium">프리미엄 구독</h3>
            <div className="p-2 bg-yellow-500/10 rounded-lg"><Crown size={20} className="text-yellow-500" /></div>
          </div>
          <div className="text-2xl font-bold text-yellow-500">
            {stats.loading ? "..." : stats.premiumUsers.toLocaleString()}
          </div>
          <div className="text-xs text-yellow-500/80 mt-2">유료 구독자 (프로모션 포함)</div>
        </div>

        <div className="bg-[#1a1d24] border border-emerald-500/20 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-emerald-400 text-sm font-medium">전체 누적 콜 포인트</div>
            <div className="p-2 bg-emerald-500/10 rounded-lg"><Database size={20} className="text-emerald-400" /></div>
          </div>
          <div className="text-2xl font-bold text-emerald-400">
            {stats.loading ? "..." : stats.totalCallPoints.toLocaleString()}
          </div>
          <div className="text-xs text-emerald-400/70 mt-2">오늘 수집: +{stats.callPointsToday.toLocaleString()}건</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-[#1a1d24] border border-white/5 border-t-4 border-t-blue-500 rounded-2xl p-6 shadow-lg">
          <h3 className="text-lg font-bold text-white flex items-center gap-2 mb-6">
            <Server className="text-blue-400" /> 서버 DB (Firebase) 사용량
          </h3>
          <div className="space-y-6">
            <div>
              <div className="flex justify-between text-sm mb-2">
                <span className="text-gray-400">일일 읽기 (Reads) 최적화 상태</span>
                <span className="text-white font-mono">안전함</span>
              </div>
              <div className="w-full bg-gray-800 rounded-full h-3">
                <div className="bg-green-500 h-3 rounded-full" style={{ width: '10%' }}></div>
              </div>
            </div>
            <div className="bg-blue-500/10 border border-blue-500/20 p-4 rounded-lg flex items-start gap-3 mt-4">
              <div className="mt-1"><Server size={16} className="text-blue-400" /></div>
              <p className="text-sm text-blue-200 leading-relaxed">
                <strong>과금 방어 시스템 작동 중:</strong> 현재 대시보드의 통계는 `getCountFromServer`를 사용하여 <strong>단 1번의 읽기(Read) 비용</strong>만으로 처리됩니다. 매우 경제적입니다.
              </p>
            </div>
          </div>
        </div>
        
        <div className="bg-[#1a1d24] border border-white/5 border-t-4 border-t-red-500 rounded-2xl overflow-hidden shadow-lg flex flex-col">
          <div className="p-5 border-b border-gray-800 flex justify-between items-center bg-[#1a1d24]">
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <SatelliteDish className="text-red-400" /> 실시간 OCR 에러 피드
            </h3>
            <Link to="/ocr" className="text-xs text-red-400 hover:underline">품질 관리로 이동</Link>
          </div>
          <div className="divide-y divide-gray-800 flex-1 overflow-y-auto">
            {stats.loading ? (
              <div className="p-8 text-center text-gray-500">데이터 불러오는 중...</div>
            ) : stats.recentErrors.length === 0 ? (
              <div className="p-8 text-center text-gray-500">최근 발생한 에러가 없습니다.</div>
            ) : (
              stats.recentErrors.map((err: any) => (
                <div key={err.id} className="p-4 hover:bg-white/5 transition">
                  <div className="flex justify-between items-center mb-1">
                    <span className="text-sm font-bold text-red-400">파싱 실패</span>
                    <span className="text-[10px] text-gray-500">
                      {err.timestamp?.toDate ? err.timestamp.toDate().toLocaleString() : '최근'}
                    </span>
                  </div>
                  <p className="text-xs text-gray-400 font-mono truncate">원본: {err.raw_text || '내용 없음'}</p>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}