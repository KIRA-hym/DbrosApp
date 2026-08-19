import { useState, useEffect } from 'react';
import { collection, query, orderBy, onSnapshot, doc, updateDoc, Timestamp } from 'firebase/firestore';
import { db } from '../firebase';
import { Users, Ban, CheckCircle, ShieldAlert } from 'lucide-react';

interface UserData {
  id: string;
  email: string;
  displayName: string;
  isBanned: boolean;
  isAdmin: boolean;
  createdAt: Timestamp | null;
  premiumUntil: Timestamp | null;
}

export default function UserManagement() {
  const [users, setUsers] = useState<UserData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(collection(db, 'users'), orderBy('createdAt', 'desc'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const userList: UserData[] = snapshot.docs.map(doc => ({
        id: doc.id,
        email: doc.data().email || '',
        displayName: doc.data().displayName || '이름 없음',
        isBanned: doc.data().isBanned === true,
        isAdmin: doc.data().isAdmin === true,
        createdAt: doc.data().createdAt,
        premiumUntil: doc.data().premiumUntil || null,
      }));
      setUsers(userList);
      setLoading(false);
    }, (error) => {
      console.error("Error fetching users: ", error);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const toggleBanStatus = async (userId: string, currentStatus: boolean) => {
    if (!window.confirm(currentStatus ? '차단을 해제하시겠습니까?' : '정말 이 유저를 차단하시겠습니까?\n차단 즉시 앱 사용이 제한됩니다.')) return;
    
    try {
      await updateDoc(doc(db, 'users', userId), {
        isBanned: !currentStatus
      });
    } catch (error) {
      console.error("Error updating user status: ", error);
      alert('상태 변경에 실패했습니다.');
    }
  };

  const expirePremium = async (userId: string) => {
    if (!window.confirm('이 유저의 프리미엄 구독을 즉시 강제 종료하시겠습니까?')) return;
    try {
      await updateDoc(doc(db, 'users', userId), {
        premiumUntil: Timestamp.fromDate(new Date()) // 현재 시간으로 덮어씌워 즉시 만료 처리
      });
      alert('프리미엄 구독이 종료되었습니다.');
    } catch (error) {
      console.error("Error expiring premium: ", error);
      alert('구독 종료에 실패했습니다.');
    }
  };

  const toggleAdminStatus = async (userId: string, currentStatus: boolean) => {
    if (!window.confirm(currentStatus ? '관리자 권한을 해제하시겠습니까?' : '이 유저에게 관리자 권한을 부여하시겠습니까?')) return;
    try {
      await updateDoc(doc(db, 'users', userId), {
        isAdmin: !currentStatus
      });
      alert('관리자 권한이 변경되었습니다.');
    } catch (error) {
      console.error("Error updating admin status: ", error);
      alert('권한 변경에 실패했습니다.');
    }
  };

  if (loading) {
    return <div className="p-8 text-center text-gray-400">유저 목록을 불러오는 중...</div>;
  }

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Users className="text-yellow-500" />
            유저 관리
          </h1>
          <p className="text-gray-400 mt-1">앱에 가입한 유저들의 상태를 확인하고 관리(차단)할 수 있습니다.</p>
        </div>
        <div className="bg-gray-800 px-4 py-2 rounded-lg border border-gray-700 flex gap-4">
          <div>
            <span className="text-gray-400 text-sm">총 가입 유저: </span>
            <span className="text-white font-bold">{users.length}명</span>
          </div>
          <div className="w-px bg-gray-700"></div>
          <div>
            <span className="text-gray-400 text-sm">차단 유저: </span>
            <span className="text-red-400 font-bold">{users.filter(u => u.isBanned).length}명</span>
          </div>
        </div>
      </div>

      <div className="bg-gray-800 rounded-2xl border border-gray-700 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-gray-900/50 text-gray-400 text-sm border-b border-gray-700">
                <th className="p-4 font-medium">유저 정보</th>
                <th className="p-4 font-medium">가입일시</th>
                <th className="p-4 font-medium">상태</th>
                <th className="p-4 font-medium text-right">관리</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-700">
              {users.length === 0 ? (
                <tr>
                  <td colSpan={4} className="p-8 text-center text-gray-400">
                    가입한 유저가 없습니다.
                  </td>
                </tr>
              ) : (
                users.map((user) => (
                  <tr key={user.id} className={`hover:bg-gray-700/30 transition-colors ${user.isBanned ? 'opacity-70' : ''}`}>
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <div className={`w-10 h-10 rounded-full flex items-center justify-center ${user.isBanned ? 'bg-red-500/20 text-red-500' : 'bg-gray-700 text-gray-300'}`}>
                          {user.isAdmin ? <ShieldAlert size={20} className="text-yellow-500" /> : <Users size={20} />}
                        </div>
                        <div>
                          <div className={`font-medium ${user.isBanned ? 'text-gray-400 line-through' : 'text-gray-200'}`}>
                            {user.displayName}
                            {user.isAdmin && <span className="ml-2 text-xs bg-yellow-500/20 text-yellow-500 px-2 py-0.5 rounded-full">관리자</span>}
                          </div>
                          <div className="text-xs text-gray-500">{user.email}</div>
                          <div className="text-[10px] text-gray-600 font-mono mt-0.5">UID: {user.id}</div>
                        </div>
                      </div>
                    </td>
                    <td className="p-4 text-sm text-gray-400">
                      {user.createdAt ? user.createdAt.toDate().toLocaleString('ko-KR') : '-'}
                    </td>
                    <td className="p-4">
                      {user.isBanned ? (
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-red-500/10 text-red-500 border border-red-500/20">
                          <Ban size={14} /> 차단됨
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-emerald-500/10 text-emerald-500 border border-emerald-500/20">
                          <CheckCircle size={14} /> 정상
                        </span>
                      )}
                    </td>
                    <td className="p-4 text-right">
                      <div className="flex justify-end gap-2">
                        {user.premiumUntil && user.premiumUntil.toDate() > new Date() && (
                          <button
                            onClick={() => expirePremium(user.id)}
                            className="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium bg-orange-500/10 hover:bg-orange-500/20 text-orange-500 border border-orange-500/20 hover:border-orange-500/30 transition-all"
                          >
                            구독 종료
                          </button>
                        )}
                        <button
                          onClick={() => toggleAdminStatus(user.id, user.isAdmin)}
                          className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium transition-all ${
                            user.isAdmin
                              ? 'bg-gray-700 hover:bg-gray-600 text-yellow-500'
                              : 'bg-yellow-500/10 hover:bg-yellow-500/20 text-yellow-500 border border-yellow-500/20 hover:border-yellow-500/30'
                          }`}
                        >
                          {user.isAdmin ? '관리자 해제' : '관리자 지정'}
                        </button>
                        {!user.isAdmin && (
                          <button
                            onClick={() => toggleBanStatus(user.id, user.isBanned)}
                            className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium transition-all ${
                              user.isBanned
                                ? 'bg-gray-700 hover:bg-gray-600 text-white'
                                : 'bg-red-500/10 hover:bg-red-500/20 text-red-500 border border-red-500/20 hover:border-red-500/30'
                            }`}
                          >
                            {user.isBanned ? '차단 해제' : '차단하기'}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
