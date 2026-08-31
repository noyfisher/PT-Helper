/**
 * `getUserAge` DOB source precedence (C: age gate).
 *
 * firestore.rules makes `dateOfBirth` immutable on `users/{uid}/consents/legal`
 * (written once at terms acceptance) while `users/{uid}/profile/health` stays
 * freely owner-writable. Reading the profile first therefore let any user patch
 * their profile DOB to an adult date and walk straight through the under-13 hard
 * block and the minor safeguards — the rules-level control existed and was
 * defeated purely by which document the resolver consulted first.
 *
 * These tests pin the precedence, using the injectable `db` seam (same pattern
 * as `isRateLimited` in rate-limit.test.ts). No real Firestore.
 */

import { getUserAge } from "../src/index";

/** A Firestore-ish Timestamp: only `toDate()` is used by getUserAge. */
function ts(date: Date) {
  return { toDate: () => date };
}

function yearsAgo(years: number): Date {
  const d = new Date();
  d.setUTCFullYear(d.getUTCFullYear() - years);
  return d;
}

interface DocFields { dateOfBirth?: unknown }

/** Minimal fake Firestore exposing just `doc(path).get().get(field)`. */
function fakeDb(docs: Record<string, DocFields | undefined>) {
  const reads: string[] = [];
  const db = {
    doc(path: string) {
      return {
        async get() {
          reads.push(path);
          const data = docs[path];
          return { get: (field: string) => (data ? (data as Record<string, unknown>)[field] : undefined) };
        },
      };
    },
  };
  return { db: db as unknown as FirebaseFirestore.Firestore, reads };
}

// A distinct uid per test — getUserAge memoizes per uid for AGE_CACHE_TTL_MS.
let uidCounter = 0;
const nextUid = () => `age-test-uid-${uidCounter++}`;

describe("getUserAge DOB source precedence", () => {
  it("prefers the immutable consents DOB over a conflicting profile DOB", async () => {
    const uid = nextUid();
    const { db } = fakeDb({
      [`users/${uid}/consents/legal`]: { dateOfBirth: ts(yearsAgo(10)) },   // truth: under 13
      [`users/${uid}/profile/health`]: { dateOfBirth: ts(yearsAgo(30)) },   // forged: adult
    });

    expect(await getUserAge(uid, db)).toBe(10);
  });

  it("does not read the mutable profile at all when the consents DOB exists", async () => {
    const uid = nextUid();
    const { db, reads } = fakeDb({
      [`users/${uid}/consents/legal`]: { dateOfBirth: ts(yearsAgo(25)) },
      [`users/${uid}/profile/health`]: { dateOfBirth: ts(yearsAgo(30)) },
    });

    await getUserAge(uid, db);

    expect(reads).toEqual([`users/${uid}/consents/legal`]);
  });

  it("falls back to the profile DOB for legacy accounts with no consents doc", async () => {
    const uid = nextUid();
    const { db } = fakeDb({
      [`users/${uid}/consents/legal`]: undefined,
      [`users/${uid}/profile/health`]: { dateOfBirth: ts(yearsAgo(40)) },
    });

    expect(await getUserAge(uid, db)).toBe(40);
  });

  it("returns null when neither document carries a DOB (callers treat unknown as a minor)", async () => {
    const uid = nextUid();
    const { db } = fakeDb({});

    expect(await getUserAge(uid, db)).toBeNull();
  });
});
