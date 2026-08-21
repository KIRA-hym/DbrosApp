import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';
import { getStorage } from 'firebase/storage';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || "AIzaSyBNPzMTqlmubRaY88f3xLpiXYlhMu9qhCA",
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || "dbros-apps-7bbmw4.firebaseapp.com",
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || "dbros-apps-7bbmw4",
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || "dbros-apps-7bbmw4.firebasestorage.app",
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || "643066110177",
  appId: import.meta.env.VITE_FIREBASE_APP_ID || "1:643066110177:web:xxxxxxxxxxxxxxxxx"
};

const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const auth = getAuth(app);
export const storage = getStorage(app);
