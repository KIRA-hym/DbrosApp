import { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { NavLink, Outlet } from 'react-router-dom';
import { Bell, FileText, Settings, LogOut, FileSearch, Menu, X, Users, Ticket } from 'lucide-react';

export default function Layout() {
  const { logout, currentUser } = useAuth();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const menuItems = [
    { name: '유저 관리', path: '/', icon: <Users size={20} /> },
    { name: '프로모션 코드 관리', path: '/promotion', icon: <Ticket size={20} /> },
    { name: '공지사항 관리', path: '/notices', icon: <FileText size={20} /> },
    { name: '푸시 알림 센터', path: '/push', icon: <Bell size={20} /> },
    { name: 'OCR 룰/로그', path: '/ocr', icon: <FileSearch size={20} /> },
    { name: '설정', path: '/settings', icon: <Settings size={20} /> },
  ];

  const toggleMobileMenu = () => {
    setIsMobileMenuOpen(!isMobileMenuOpen);
  };

  const closeMobileMenu = () => {
    setIsMobileMenuOpen(false);
  };

  return (
    <div className="flex h-screen bg-[#121418] text-gray-200 overflow-hidden flex-col md:flex-row">
      {/* Mobile Header (Visible only on mobile) */}
      <div className="md:hidden flex items-center justify-between p-4 bg-[#1a1d24] border-b border-white/5 shrink-0 z-20">
        <h1 className="text-xl font-bold bg-gradient-to-r from-yellow-500 to-orange-500 bg-clip-text text-transparent">
          Dbros Admin
        </h1>
        <button onClick={toggleMobileMenu} className="text-gray-300 hover:text-white p-1">
          {isMobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>

      {/* Mobile Menu Overlay */}
      {isMobileMenuOpen && (
        <div 
          className="fixed inset-0 bg-black/60 backdrop-blur-sm z-30 md:hidden" 
          onClick={closeMobileMenu}
        />
      )}

      {/* Sidebar (Desktop and Mobile drawer) */}
      <div className={`fixed inset-y-0 left-0 z-40 w-64 bg-[#1a1d24] border-r border-white/5 flex flex-col transform transition-transform duration-300 ease-in-out md:relative md:translate-x-0 ${isMobileMenuOpen ? 'translate-x-0' : '-translate-x-full'}`}>
        <div className="p-6 hidden md:block">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-yellow-500 to-orange-500 bg-clip-text text-transparent">
            Dbros Admin
          </h1>
          <p className="text-xs text-gray-500 mt-1">{currentUser?.email}</p>
        </div>
        
        {/* Mobile Sidebar Header */}
        <div className="p-6 md:hidden border-b border-white/5 flex justify-between items-center">
           <div>
             <h2 className="font-bold text-white">Dbros Admin</h2>
             <p className="text-xs text-gray-500 mt-1">{currentUser?.email}</p>
           </div>
           <button onClick={closeMobileMenu} className="text-gray-400 hover:text-white p-1">
             <X size={20} />
           </button>
        </div>

        <nav className="flex-1 px-4 space-y-2 mt-4 overflow-y-auto">
          {menuItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              onClick={closeMobileMenu}
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

      {/* Main Content */}
      <div className="flex-1 overflow-auto bg-[#121418]">
        <Outlet />
      </div>
    </div>
  );
}
