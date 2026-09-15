import { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { NavLink, Outlet } from 'react-router-dom';
import { LayoutDashboard, Map, Bug, LogOut, Menu, X, Users, Ticket, BellRing, Smartphone } from 'lucide-react';

type MenuItem = {
  type?: 'divider';
  name: string;
  path?: string;
  icon?: React.ReactNode;
};

export default function Layout() {
  const { logout, currentUser } = useAuth();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const menuItems: MenuItem[] = [
    { name: '종합 대시보드', path: '/', icon: <LayoutDashboard size={20} /> },
    { type: 'divider', name: 'Data Analytics' },
    { name: '콜 포인트 맵', path: '/call-points', icon: <Map size={20} className="text-indigo-400" /> },
    { name: 'OCR 품질 관리', path: '/ocr', icon: <Bug size={20} className="text-red-400" /> },
    { name: 'OCR 룰 엔진 (JSON)', path: '/ocr-rules', icon: <Bug size={20} className="text-yellow-400" /> },
    { name: 'OCR 기출문제 검수', path: '/golden-samples', icon: <Bug size={20} className="text-green-400" /> },
    { type: 'divider', name: 'Management' },
    { name: '사용자 및 구독 관리', path: '/users', icon: <Users size={20} /> },
    { name: '프로모션 관리', path: '/promotion', icon: <Ticket size={20} /> },
    { name: '공지사항 및 푸시', path: '/notices', icon: <BellRing size={20} /> },
    { name: '앱 버전 관리', path: '/version', icon: <Smartphone size={20} /> },
  ];

  const toggleMobileMenu = () => setIsMobileMenuOpen(!isMobileMenuOpen);
  const closeMobileMenu = () => setIsMobileMenuOpen(false);

  return (
    <div className="flex h-screen bg-[#121418] text-gray-200 overflow-hidden flex-col md:flex-row font-['Pretendard']">
      <div className="md:hidden flex items-center justify-between p-4 bg-[#1a1d24] border-b border-white/5 shrink-0 z-20">
        <h1 className="text-xl font-bold text-blue-500 flex items-center gap-2">
          DbrosAdmin
        </h1>
        <button onClick={toggleMobileMenu} className="text-gray-300 hover:text-white p-1">
          {isMobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>

      {isMobileMenuOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-30 md:hidden" onClick={closeMobileMenu} />
      )}

      <div className={"fixed inset-y-0 left-0 z-40 w-64 bg-[#1a1d24] border-r border-white/5 flex flex-col transform transition-transform duration-300 ease-in-out md:relative md:translate-x-0 " + (isMobileMenuOpen ? 'translate-x-0' : '-translate-x-full')}>
        <div className="p-6 hidden md:block">
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            Dbros<span className="text-blue-500">Admin</span>
          </h1>
          <p className="text-xs text-gray-500 mt-2">{currentUser?.email}</p>
        </div>
        
        <div className="p-6 md:hidden border-b border-white/5 flex justify-between items-center">
           <div>
             <h2 className="font-bold text-white">DbrosAdmin</h2>
             <p className="text-xs text-gray-500 mt-1">{currentUser?.email}</p>
           </div>
           <button onClick={closeMobileMenu} className="text-gray-400 hover:text-white p-1">
             <X size={20} />
           </button>
        </div>

        <nav className="flex-1 px-4 mt-2 overflow-y-auto">
          {menuItems.map((item, idx) => {
            if (item.type === 'divider') {
              return (
                <div key={idx} className="mt-8 mb-2 px-2 text-xs font-bold text-gray-500 uppercase tracking-wider">
                  {item.name}
                </div>
              );
            }
            return (
              <NavLink
                key={item.path}
                to={item.path!}
                onClick={closeMobileMenu}
                className={({ isActive }) =>
                  "flex items-center gap-3 px-4 py-3 rounded-xl transition-all mb-1 " +
                  (isActive
                    ? 'bg-blue-500/10 text-blue-400 font-semibold border border-blue-500/20'
                    : 'text-gray-400 hover:bg-white/5 hover:text-gray-200 border border-transparent')
                }
              >
                {item.icon}
                {item.name}
              </NavLink>
            );
          })}
        </nav>

        <div className="p-4 border-t border-white/5">
          <button
            onClick={() => {
              closeMobileMenu();
              logout();
            }}
            className="flex items-center gap-3 px-4 py-3 w-full rounded-xl text-gray-400 hover:bg-red-500/10 hover:text-red-400 transition-all"
          >
            <LogOut size={20} />
            로그아웃
          </button>
        </div>
      </div>

      <div className="flex-1 bg-[#0f1115] overflow-y-auto relative z-0 min-h-0">
        <Outlet />
      </div>
    </div>
  );
}
