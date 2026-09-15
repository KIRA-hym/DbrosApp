import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import Layout from './components/Layout';
import Login from './pages/Login';
import OcrSimulatorPage from './pages/OcrSimulatorPage';
import Notices from './pages/Notices';
import Push from './pages/Push';
import OcrLogs from './pages/OcrLogs';
import UserManagement from './pages/UserManagement';
import PromotionCodes from './pages/PromotionCodes';
import CallPoints from './pages/CallPoints';
import Dashboard from './pages/Dashboard';
import VersionManagement from './pages/VersionManagement';
import OcrRules from './pages/OcrRules';
import GoldenSamples from './pages/GoldenSamples';
import './index.css';

const ProtectedRoute = ({ children }: { children: React.ReactNode }) => {
  const { currentUser, loading } = useAuth();
  if (loading) return <div className="h-screen w-screen flex items-center justify-center bg-gray-900 text-white">Loading...</div>;
  if (!currentUser) return <Navigate to="/login" />;
  return <>{children}</>;
};

function App() {
  return (
    <Router>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/" element={<ProtectedRoute><Layout /></ProtectedRoute>}>
            <Route index element={<Dashboard />} />
            <Route path="users" element={<UserManagement />} />
            <Route path="notices" element={<Notices />} />
            <Route path="push" element={<Push />} />
            <Route path="promotion" element={<PromotionCodes />} />
            <Route path="call-points" element={<CallPoints />} />
            <Route path="ocr" element={<OcrLogs />} />
            <Route path="ocr-simulator" element={<OcrSimulatorPage />} />
            <Route path="ocr-rules" element={<OcrRules />} />
            <Route path="golden-samples" element={<GoldenSamples />} />
            <Route path="version" element={<VersionManagement />} />
          </Route>
        </Routes>
      </AuthProvider>
    </Router>
  );
}
export default App;