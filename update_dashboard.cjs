const fs = require('fs');
const path = 'C:\\DbrosAdmin\\src\\pages\\Dashboard.tsx';
let content = fs.readFileSync(path, 'utf8');

// Add new icons to import
content = content.replace(
    "import { UserCheck, Crown, Database, Bug, Server, SatelliteDish } from 'lucide-react';",
    "import { UserCheck, Crown, Database, Bug, Server, SatelliteDish, Users } from 'lucide-react';"
);

// Replace the state
const old_state = `  const [stats, setStats] = useState({
    callPointsToday: 0,
    ocrErrorsToday: 0,
    recentErrors: [] as any[],
    loading: true
  });`;

const new_state = `  const [stats, setStats] = useState({
    totalUsers: 0,
    newUsersToday: 0,
    premiumUsers: 0,
    dau: 0,
    totalCallPoints: 0,
    callPointsToday: 0,
    ocrErrorsToday: 0,
    recentErrors: [] as any[],
    loading: true
  });`;
content = content.replace(old_state, new_state);

// Replace the fetchStats logic
const old_fetch = `        // 1. 오늘 수집된 콜 포인트 건수
        const callPointsQuery = query(collection(db, "shared_call_points"), where("timestamp", ">=", startTimestamp));
        const callPointsSnapshot = await getCountFromServer(callPointsQuery);
        
        // 2. 오늘 발생한 OCR 에러 건수
        const errorsQuery = query(collection(db, "ocr_failures"), where("timestamp", ">=", startTimestamp));
        const errorsSnapshot = await getCountFromServer(errorsQuery);

        // 3. 최근 에러 피드 5건 가져오기
        const recentErrorsQuery = query(collection(db, "ocr_failures"), orderBy("timestamp", "desc"), limit(5));
        const recentErrorsDocs = await getDocs(recentErrorsQuery);
        const recentErrors = recentErrorsDocs.docs.map(doc => ({ id: doc.id, ...doc.data() }));

        setStats({
          callPointsToday: callPointsSnapshot.data().count,
          ocrErrorsToday: errorsSnapshot.data().count,
          recentErrors,
          loading: false
        });`;

const new_fetch = `        // 1. 유저 통계 (getCountFromServer 활용하여 과금 방어)
        const [
          totalUsersSnap,
          newUsersSnap,
          premiumSnap,
          dauSnap,
          totalCallPointsSnap,
          callPointsTodaySnap,
          ocrErrorsTodaySnap
        ] = await Promise.all([
          getCountFromServer(collection(db, "users")), // 총 유저
          getCountFromServer(query(collection(db, "users"), where("createdAt", ">=", startTimestamp))), // 오늘 신규 유저
          getCountFromServer(query(collection(db, "users"), where("premiumUntil", ">", Timestamp.now()))), // 활성 프리미엄 유저
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
          premiumUsers: premiumSnap.data().count,
          dau: dauSnap.data().count,
          totalCallPoints: totalCallPointsSnap.data().count,
          callPointsToday: callPointsTodaySnap.data().count,
          ocrErrorsToday: ocrErrorsTodaySnap.data().count,
          recentErrors,
          loading: false
        });`;
content = content.replace(old_fetch, new_fetch);

// Replace the grid UI
const old_grid = `      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <div className="bg-[#1a1d24] border border-white/5 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-gray-400 text-sm font-medium">일일 활성 기사님 (DAU)</div>
            <div className="p-2 bg-blue-500/10 rounded-lg"><UserCheck size={20} className="text-blue-400" /></div>
          </div>
          <div className="text-2xl font-bold text-white">--</div>
          <div className="text-xs text-gray-500 mt-2 flex items-center gap-1">유저 집계(Auth) 연결 예정</div>
        </div>

        <div className="bg-yellow-500/5 border border-yellow-500/20 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-yellow-500/80 text-sm font-medium">프리미엄 구독 유저</div>
            <div className="p-2 bg-yellow-500/10 rounded-lg"><Crown size={20} className="text-yellow-500" /></div>
          </div>
          <div className="text-2xl font-bold text-yellow-500">--</div>
          <div className="text-xs text-yellow-500/80 mt-2">수익화(구독) 연동 시 표기</div>
        </div>

        <div className="bg-[#1a1d24] border border-indigo-500/20 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-indigo-400 text-sm font-medium">수집된 콜 포인트 (오늘)</div>
            <div className="p-2 bg-indigo-500/10 rounded-lg"><Database size={20} className="text-indigo-400" /></div>
          </div>
          <div className="text-2xl font-bold text-indigo-400">
            {stats.loading ? "..." : stats.callPointsToday.toLocaleString()}
          </div>
          <div className="text-xs text-indigo-400/70 mt-2">1인당 5건 안전 제한 적용 중</div>
        </div>

        <div className="bg-[#1a1d24] border border-red-500/20 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-red-400 text-sm font-medium">발생한 OCR 에러 (오늘)</div>
            <div className="p-2 bg-red-500/10 rounded-lg"><Bug size={20} className="text-red-400" /></div>
          </div>
          <div className="text-2xl font-bold text-red-400">
            {stats.loading ? "..." : stats.ocrErrorsToday.toLocaleString()}
          </div>
          <div className="text-xs text-red-400/70 mt-2">1인당 5건 안전 제한 적용 중</div>
        </div>
      </div>`;

const new_grid = `      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
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

        <div className="bg-yellow-500/5 border border-yellow-500/20 rounded-2xl p-5 shadow-lg">
          <div className="flex justify-between items-start mb-2">
            <div className="text-yellow-500/80 text-sm font-medium">현재 구독 중인 유저</div>
            <div className="p-2 bg-yellow-500/10 rounded-lg"><Crown size={20} className="text-yellow-500" /></div>
          </div>
          <div className="text-2xl font-bold text-yellow-500">
            {stats.loading ? "..." : stats.premiumUsers.toLocaleString()}
          </div>
          <div className="text-xs text-yellow-500/80 mt-2">활성 프리미엄 멤버</div>
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
      </div>`;

content = content.replace(old_grid, new_grid);

fs.writeFileSync(path, content, 'utf8');
console.log('Dashboard.tsx updated successfully');
