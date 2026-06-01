import { doc, getDoc, setDoc } from 'firebase/firestore';
import { db } from '../firebase';
import { getDefaultOcrRules } from '../config/defaultOcrRules';

const RULES_DOC_ID = 'latest';
const COLLECTION_NAME = 'ocr_rules';

/** Firestore 문서 위에 기본 룰을 깊게 병합 — 누락된 키는 dbros_app 기준으로 채움 */
const deepMerge = (base: Record<string, unknown>, override: Record<string, unknown>): Record<string, unknown> => {
  const out: Record<string, unknown> = { ...base };
  for (const key of Object.keys(override)) {
    const b = base[key];
    const o = override[key];
    if (
      o !== null &&
      typeof o === 'object' &&
      !Array.isArray(o) &&
      b !== null &&
      typeof b === 'object' &&
      !Array.isArray(b)
    ) {
      out[key] = deepMerge(b as Record<string, unknown>, o as Record<string, unknown>);
    } else if (o !== undefined) {
      out[key] = o;
    }
  }
  return out;
};

export const getDefaultOcrRulesJson = (): string =>
  JSON.stringify(getDefaultOcrRules(), null, 2);

export const getOcrRules = async (): Promise<string> => {
  try {
    const docRef = doc(db, COLLECTION_NAME, RULES_DOC_ID);
    const docSnap = await getDoc(docRef);
    const defaults = getDefaultOcrRules();

    if (docSnap.exists()) {
      const stored = docSnap.data() as Record<string, unknown>;
      const storedVersion = typeof stored.version === 'number' ? stored.version : 0;
      // v1 이하(초기 플레이스홀더)는 dbros_app 기본 룰로 교체
      if (storedVersion < 2) {
        return JSON.stringify(defaults, null, 2);
      }
      const merged = deepMerge(defaults, stored);
      return JSON.stringify(merged, null, 2);
    }

    return JSON.stringify(defaults, null, 2);
  } catch (error) {
    console.error('Error fetching OCR rules:', error);
    throw error;
  }
};

export const saveOcrRules = async (rulesJson: string): Promise<void> => {
  try {
    const data = JSON.parse(rulesJson) as Record<string, unknown>;
    if (typeof data.version !== 'number' || data.version < 2) {
      data.version = 2;
    }
    const docRef = doc(db, COLLECTION_NAME, RULES_DOC_ID);
    await setDoc(docRef, data);
  } catch (error) {
    console.error('Error saving OCR rules:', error);
    throw error;
  }
};
