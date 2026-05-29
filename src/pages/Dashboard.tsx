export default function Dashboard() {
  return (
    <div className="p-8">
      <h2 className="text-2xl font-bold mb-6 text-white">대시보드</h2>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-[#1a1d24] rounded-2xl p-6 border border-white/5 shadow-lg">
          <h3 className="text-gray-400 text-sm font-medium">당일 활성 사용자 (DAU)</h3>
          <p className="text-3xl font-bold text-white mt-2">1,204</p>
          <p className="text-green-400 text-xs mt-2 flex items-center gap-1">
            <span className="text-lg">↗</span> 어제 대비 12% 증가
          </p>
        </div>
        <div className="bg-[#1a1d24] rounded-2xl p-6 border border-white/5 shadow-lg">
          <h3 className="text-gray-400 text-sm font-medium">오늘 OCR 파싱 실패</h3>
          <p className="text-3xl font-bold text-white mt-2">32</p>
          <p className="text-red-400 text-xs mt-2 flex items-center gap-1">
            <span className="text-lg">↘</span> 새로운 로그 확인 요망
          </p>
        </div>
        <div className="bg-[#1a1d24] rounded-2xl p-6 border border-white/5 shadow-lg">
          <h3 className="text-gray-400 text-sm font-medium">발송된 푸시 알림</h3>
          <p className="text-3xl font-bold text-white mt-2">5</p>
          <p className="text-yellow-500 text-xs mt-2 flex items-center gap-1">
            이번 주 발송 건수
          </p>
        </div>
      </div>
    </div>
  );
}
