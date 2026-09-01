/**
 * P2-10: executable security-boundary tests for firestore.rules, run against the
 * Firestore emulator. Covers the tenant boundary (unauth / owner / other-user),
 * the schema-bounded collections, and the PR-8 hardening (concernReports field
 * allowlist + bounds, consents DOB immutability).
 *
 * Run via `npm run test:rules` (wraps this in `firebase emulators:exec`).
 */

import { readFileSync } from "fs";
import { resolve } from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, Timestamp } from "firebase/firestore";

const PROJECT_ID = "demo-coil";
const ALICE = "alice";
const BOB = "bob";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => { await testEnv.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

function aliceDb() { return testEnv.authenticatedContext(ALICE).firestore(); }
function bobDb() { return testEnv.authenticatedContext(BOB).firestore(); }
function anonDb() { return testEnv.unauthenticatedContext().firestore(); }

describe("tenant boundary — users/{uid} tree", () => {
  it("owner can read + write their own profile", async () => {
    const db = aliceDb();
    await assertSucceeds(setDoc(doc(db, `users/${ALICE}/profile/health`), { activityLevel: "active" }));
    await assertSucceeds(getDoc(doc(db, `users/${ALICE}/profile/health`)));
  });

  it("another user cannot read or write someone else's tree", async () => {
    await assertFails(setDoc(doc(bobDb(), `users/${ALICE}/profile/health`), { activityLevel: "x" }));
    await assertFails(getDoc(doc(bobDb(), `users/${ALICE}/profile/health`)));
  });

  it("unauthenticated cannot read or write", async () => {
    await assertFails(getDoc(doc(anonDb(), `users/${ALICE}/profile/health`)));
    await assertFails(setDoc(doc(anonDb(), `users/${ALICE}/profile/health`), { activityLevel: "x" }));
  });
});

describe("consents — dateOfBirth immutability (P1-04/P2-02)", () => {
  const dob = Timestamp.fromDate(new Date("2000-01-01"));
  const otherDob = Timestamp.fromDate(new Date("2010-01-01"));

  it("can set DOB on first write", async () => {
    await assertSucceeds(setDoc(doc(aliceDb(), `users/${ALICE}/consents/legal`), { tosVersion: "1", dateOfBirth: dob }));
  });

  it("can re-write the SAME DOB (merge writes preserve it)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${ALICE}/consents/legal`), { dateOfBirth: dob });
    });
    await assertSucceeds(setDoc(doc(aliceDb(), `users/${ALICE}/consents/legal`), { dateOfBirth: dob, tosVersion: "2" }, { merge: true }));
  });

  it("cannot CHANGE DOB once set", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${ALICE}/consents/legal`), { dateOfBirth: dob });
    });
    await assertFails(setDoc(doc(aliceDb(), `users/${ALICE}/consents/legal`), { dateOfBirth: otherDob }, { merge: true }));
  });

  it("healthData consent (no DOB) writes freely", async () => {
    await assertSucceeds(setDoc(doc(aliceDb(), `users/${ALICE}/consents/healthData`), { policyVersion: "2026.07" }));
  });
});

describe("concernReports — field allowlist + bounds (P2-02)", () => {
  const valid = () => ({ userId: ALICE, category: "Safety concern", message: "something happened", createdAt: Timestamp.now(), appVersion: "1.0" });

  it("owner can create a well-formed report", async () => {
    await assertSucceeds(setDoc(doc(aliceDb(), "concernReports/r1"), valid()));
  });

  it("rejects a report claiming another user's id", async () => {
    await assertFails(setDoc(doc(aliceDb(), "concernReports/r2"), { ...valid(), userId: BOB }));
  });

  it("rejects an extra/unexpected field", async () => {
    await assertFails(setDoc(doc(aliceDb(), "concernReports/r3"), { ...valid(), evil: "payload" }));
  });

  it("rejects an oversized message", async () => {
    await assertFails(setDoc(doc(aliceDb(), "concernReports/r4"), { ...valid(), message: "x".repeat(5001) }));
  });

  it("rejects an empty message", async () => {
    await assertFails(setDoc(doc(aliceDb(), "concernReports/r5"), { ...valid(), message: "" }));
  });

  it("rejects an unauthenticated create", async () => {
    await assertFails(setDoc(doc(anonDb(), "concernReports/r6"), valid()));
  });
});

describe("schema-bounded subcollections", () => {
  it("formAnalyses accepts a valid score and rejects an out-of-range one", async () => {
    const db = aliceDb();
    await assertSucceeds(setDoc(doc(db, `users/${ALICE}/formAnalyses/a`), { score: 80, exerciseName: "Bird Dog", createdAt: Timestamp.now() }));
    await assertFails(setDoc(doc(db, `users/${ALICE}/formAnalyses/b`), { score: 999, exerciseName: "Bird Dog", createdAt: Timestamp.now() }));
  });

  it("streakData rejects a negative streak", async () => {
    await assertFails(setDoc(doc(aliceDb(), `users/${ALICE}/streakData/current`), { currentStreak: -1, longestStreak: 0 }));
  });
});

describe("locked-down collections", () => {
  it("sessionLogs create is owner-scoped", async () => {
    await assertSucceeds(setDoc(doc(aliceDb(), "sessionLogs/s1"), { userId: ALICE }));
    await assertFails(setDoc(doc(aliceDb(), "sessionLogs/s2"), { userId: BOB }));
  });

  it("rateLimits are never client-writable", async () => {
    await assertFails(setDoc(doc(aliceDb(), `rateLimits/${ALICE}/windows/2026-07-22T00:00`), { count: 0 }));
  });

  it("config is read-only to clients", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "config/exerciseImageAliases"), { aliases: {} });
    });
    await assertSucceeds(getDoc(doc(aliceDb(), "config/exerciseImageAliases")));
    await assertFails(setDoc(doc(aliceDb(), "config/exerciseImageAliases"), { aliases: { x: "y" } }));
  });
});

describe("missingExerciseImages — bounded writes", () => {
  const valid = () => ({
    exerciseName: "Wall Sits",
    normalizedKey: "wall-sits",
    matchType: "none",
    exerciseCategory: "strength",
    targetArea: "Knee",
    source: "display",
    count: 1,
    lastSeen: Timestamp.now(),
  });

  it("accepts the payload the client actually sends", async () => {
    await assertSucceeds(setDoc(doc(aliceDb(), "missingExerciseImages/wall-sits"), valid()));
  });

  /// The security-relevant case: the same document is the generation lock for
  /// `generateExerciseImage`, and those fields are Admin-SDK only. A client that
  /// could forge them would block generation for that exercise for the lock's TTL.
  it("rejects a client forging the generation-lock fields", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "missingExerciseImages/locked-1"), {
        ...valid(),
        status: "generating",
        generatingStartedAt: Timestamp.now(),
      })
    );
  });

  it("rejects unknown fields and oversized strings", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "missingExerciseImages/junk-1"), { ...valid(), attackerField: "x" })
    );
    await assertFails(
      setDoc(doc(aliceDb(), "missingExerciseImages/junk-2"), { ...valid(), exerciseName: "x".repeat(5000) })
    );
  });

  it("allows the counter to step by exactly one, never to jump", async () => {
    const ref = doc(aliceDb(), "missingExerciseImages/step-1");
    await assertSucceeds(setDoc(ref, valid()));
    await assertSucceeds(setDoc(ref, { ...valid(), count: 2 }));
    await assertFails(setDoc(ref, { ...valid(), count: 99 }));
  });

  it("stays readable to signed-in clients and closed to anonymous ones", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "missingExerciseImages/readable"), valid());
    });
    await assertSucceeds(getDoc(doc(aliceDb(), "missingExerciseImages/readable")));
    await assertFails(getDoc(doc(anonDb(), "missingExerciseImages/readable")));
  });
});
