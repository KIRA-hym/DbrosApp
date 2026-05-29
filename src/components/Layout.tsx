import { useAuth } from '../contexts/AuthContext';
import { NavLink, Outlet } from 'react-router-dom';
import { LayoutDashboard, Bell, FileText, Settings, LogOut, FileSearch } from 'lucide-react';

export default function Layout() {
  const { logout, currentUser } = useAuth();

  const menuItems = [
    { name: '대시보드', path: '/', icon: <LayoutDashboard size={20} /> },
    { name: '공지사항 관리', path: '/notices', icon: <FileText size={20} /> },
    { name: '푸시 알림 센터', path: '/push', icon: <Bell size={20} /> },
    { name: 'OCR 룰/로그', path: '/ocr', icon: <FileSearch size={20} /> },
    { name: '설정', path: '/settings', icon: <Settings size={20} /> },
  ];

  return (
    <div className="flex h-screen bg-[#121418] text-gray-200">
      {/* Sidebar */}
      <div className="w-64 bg-[#1a1d24] border-r border-white/5 flex flex-col">
        <div className="p-6">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-yellow-500 to-orange-500 bg-clip-text text-transparent">
            Dbros Admin
          </h1>
          <p className="text-xs text-gray-500 mt-1">{currentUser?.email}</p>
        </div>

        <nav className="flex-1 px-4 space-y-2 mt-4">
          {menuItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) =>
                `flex items-center gap-3 px-4 py-3 rounded-xl transition-all ${
                  isActive
                    ? 'bg-yellow-500/10 text-yellow-500 font-medium'
                    : 'text-gray-400 hover:bg-white/5 hover:text-gray-200'
                }`
              }
            >
              {item.icon}
              {item.name}
            </NavLink>
          ))}
        </nav>

        <div className="p-4 border-t border-white/5">
          <button
            onClick={logout}
            className="flex items-center gap-3 px-4 py-3 w-full rounded-xl text-gray-400 hover:bg-red-500/10 hover:text-red-400 transition-all"
          >
            <LogOut size={20} />
            로그아웃
          </button>
        </div>
      </div>

      {/* Main Content */}
      <div className="flex-1 overflow-auto">
        <Outlet />
      </div>
    </div>
  );
}
