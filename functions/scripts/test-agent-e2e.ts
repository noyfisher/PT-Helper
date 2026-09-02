/**
 * End-to-end test for the agentInsights endpoint.
 *
 * 1. Seeds Firestore with test workout sessions, rehab plan, and user profile
 * 2. Mints a Firebase Auth custom token → exchanges for an ID token
 * 3. Calls the agentInsights endpoint
 * 4. Prints the result
 * 5. Cleans up test data
 *
 * Run: cd functions && ANTHROPIC_API_KEY=$(firebase functions:secrets:access ANTHROPIC_API_KEY) npx ts-node scripts/test-agent-e2e.ts
 */

import * as admin from "firebase-admin";

// Initialize with service account impersonation for custom token signing
admin.initializeApp({
  projectId: "pt-helper-dev",
  serviceAccountId: "firebase-adminsdk-fbsvc@pt-helper-dev.iam.gserviceaccount.com",
});

const TEST_UID = "vuser-e2e-agent-test";
const AGENT_INSIGHTS_URL = "https://us-central1-pt-helper-dev.cloudfunctions.net/agentInsights";

async function seedTestData() {
  const db = admin.firestore();
  const userRef = db.doc(`users/${TEST_UID}`);

  // Seed user profile
  await userRef.collection("profile").doc("health").set({
    dateOfBirth: admin.firestore.Timestamp.fromDate(new Date("1990-05-15")),
    biologicalSex: "male",
    activityLevel: "moderate",
    medicalConditions: [],
    medications: [],
    surgeries: [],
    injuries: [],
  });

  // Seed a rehab plan
  const planId = "test-plan-001";
  await userRef.collection("rehabPlans").doc(planId).set({
    planName: "Knee Recovery Plan",
    conditions: ["Patellofemoral Pain Syndrome"],
    exercises: [
      { name: "Quad Sets", targetArea: "knee", sets: 3, reps: 10 },
      { name: "Straight Leg Raises", targetArea: "knee", sets: 3, reps: 12 },
      { name: "Wall Squats", targetArea: "knee", sets: 3, reps: 10 },
      { name: "Calf Raises", targetArea: "ankle", sets: 3, reps: 15 },
    ],
    weeklySchedule: {
      "0": ["Quad Sets", "Straight Leg Raises"],
      "1": [],
      "2": ["Wall Squats", "Calf Raises"],
      "3": [],
      "4": ["Quad Sets", "Straight Leg Raises", "Wall Squats"],
      "5": [],
      "6": [],
    },
    totalWeeks: 6,
    createdDate: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 21 * 86400000)),
    lastModifiedDate: admin.firestore.Timestamp.now(),
    planType: "rehab",
  });

  // Seed 5 workout sessions over the past 14 days
  const sessions = [
    { daysAgo: 12, pain: 6.5, exercises: ["Quad Sets", "Straight Leg Raises"], duration: 1200, regionPain: { knee: 6.5 } },
    { daysAgo: 10, pain: 6.0, exercises: ["Wall Squats", "Calf Raises"], duration: 900, regionPain: { knee: 6.0 } },
    { daysAgo: 7, pain: 5.0, exercises: ["Quad Sets", "Straight Leg Raises", "Wall Squats"], duration: 1500, regionPain: { knee: 5.0 } },
    { daysAgo: 4, pain: 4.5, exercises: ["Quad Sets", "Straight Leg Raises"], duration: 1100, regionPain: { knee: 4.0, ankle: 2.0 } },
    { daysAgo: 1, pain: 3.5, exercises: ["Wall Squats", "Calf Raises", "Quad Sets"], duration: 1400, regionPain: { knee: 3.5 } },
  ];

  for (let i = 0; i < sessions.length; i++) {
    const s = sessions[i];
    const date = new Date(Date.now() - s.daysAgo * 86400000);
    await userRef.collection("workoutSessions").doc(`test-session-${i}`).set({
      date: admin.firestore.Timestamp.fromDate(date),
      painLevel: s.pain,
      exercisesPerformed: s.exercises,
      duration: s.duration,
      isCompleted: true,
      regionPainLevels: s.regionPain,
      planId: planId,
    });
  }

  console.log("✅ Test data seeded: 1 profile, 1 plan, 5 sessions");
}

async function getIdToken(): Promise<string> {
  // Create a custom token
  const customToken = await admin.auth().createCustomToken(TEST_UID);

  // Exchange custom token for an ID token via Firebase Auth REST API
  // Firebase Web/iOS API keys are public-by-design identifiers (this one also
  // ships in every IPA), so this is not a credential leak and needs no
  // rotation — but committing it to a PUBLIC repo hands it over without even
  // unpacking the app, which is free recon for Identity Toolkit abuse while
  // GCP API-key restrictions remain unconfirmed. Read it from the environment
  // instead; this is a manual E2E helper, not deployed code.
  const apiKey = process.env.FIREBASE_API_KEY;
  if (!apiKey) {
    throw new Error("FIREBASE_API_KEY must be set to run the agent E2E helper.");
  }
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    }
  );

  const data = (await response.json()) as { idToken?: string; error?: { message: string } };
  if (!data.idToken) {
    throw new Error(`Failed to get ID token: ${data.error?.message || "unknown error"}`);
  }

  return data.idToken;
}

async function callAgentInsights(idToken: string): Promise<unknown> {
  console.log("🚀 Calling agentInsights endpoint...");
  const startTime = Date.now();

  const response = await fetch(AGENT_INSIGHTS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${idToken}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  const data = await response.json();

  if (!response.ok) {
    console.error(`❌ Endpoint returned ${response.status} (${elapsed}s):`, data);
    return null;
  }

  console.log(`✅ Response received in ${elapsed}s (status ${response.status})`);
  return data;
}

async function cleanup() {
  const db = admin.firestore();
  const userRef = db.doc(`users/${TEST_UID}`);

  // Delete sessions
  const sessions = await userRef.collection("workoutSessions").listDocuments();
  for (const doc of sessions) await doc.delete();

  // Delete plans
  const plans = await userRef.collection("rehabPlans").listDocuments();
  for (const doc of plans) await doc.delete();

  // Delete profile
  await userRef.collection("profile").doc("health").delete();

  console.log("🧹 Test data cleaned up");
}

async function main() {
  try {
    // 1. Seed test data
    await seedTestData();

    // 2. Get auth token
    console.log("🔑 Getting Firebase ID token...");
    const idToken = await getIdToken();
    console.log("✅ ID token obtained");

    // 3. Call the endpoint
    const result = await callAgentInsights(idToken);

    if (result) {
      // Parse the response (same format as Anthropic API response)
      const content = (result as { content?: Array<{ text?: string }> }).content;
      const text = content?.[0]?.text;

      if (text) {
        try {
          const insights = JSON.parse(text);
          console.log("\n📊 Recovery Insights Result:");
          console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
          console.log(`Headline: ${insights.headline}`);
          console.log(`Summary: ${insights.summary}`);
          console.log(`Pain Trend: ${insights.painAnalysis?.trendDirection} (avg: ${insights.painAnalysis?.averagePain})`);
          console.log(`Adherence: ${insights.adherenceAnalysis?.score}% (${insights.adherenceAnalysis?.sessionsCompleted}/${insights.adherenceAnalysis?.sessionsExpected})`);
          console.log(`Key Wins: ${insights.keyWins?.join("; ")}`);
          console.log(`Focus Areas: ${insights.focusAreas?.join("; ")}`);
          console.log(`Recommendations: ${insights.recommendations?.length} items`);
          if (insights.recommendations) {
            for (const rec of insights.recommendations) {
              console.log(`  • [${rec.icon}] ${rec.title}: ${rec.description}`);
            }
          }
          console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        } catch {
          console.log("\nRaw response text:", text);
        }
      } else {
        console.log("\nFull response:", JSON.stringify(result, null, 2));
      }
    }

    // 4. Cleanup
    await cleanup();
  } catch (err) {
    console.error("E2E test failed:", err);
    // Still try to clean up
    try { await cleanup(); } catch { /* ignore */ }
    process.exit(1);
  }

  process.exit(0);
}

main();
