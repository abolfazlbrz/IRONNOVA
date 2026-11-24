import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

async function getFirebaseAccessToken(serviceAccount: Record<string, string>) {
  const privateKey = await importPKCS8(serviceAccount.private_key.replace(/\\n/g, "\n"), "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token) {
    console.error("Firebase OAuth token request failed:", response.status);
    throw new Error("Firebase authorization failed");
  }
  return result.access_token as string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return reply(401, { error: "Unauthorized" });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!supabaseUrl || !anonKey || !serviceRoleKey || !firebaseJson) {
      console.error("Required push environment configuration is missing.");
      return reply(500, { error: "Push service is not configured" });
    }

    const jwt = authHeader.slice("Bearer ".length);
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
    const user = authData?.user;
    if (authError || !user) return reply(401, { error: "Invalid session" });

    const body = await req.json().catch(() => ({}));
    const logId = typeof body.log_id === "string" ? body.log_id : "";
    if (!/^[0-9a-f-]{36}$/i.test(logId)) return reply(400, { error: "Invalid log_id" });

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: log, error: logError } = await admin
      .from("iron_student_logs")
      .select("id, student_id, log_type, payload")
      .eq("id", logId)
      .maybeSingle();
    if (logError) throw logError;
    if (!log || log.student_id !== user.id || log.log_type !== "workout" || log.payload?.event !== "started") {
      return reply(403, { error: "Workout event not authorized" });
    }

    const { data: studentRole, error: studentRoleError } = await admin
      .from("iron_account_roles_v2")
      .select("role, status")
      .eq("user_id", user.id)
      .maybeSingle();
    if (studentRoleError) throw studentRoleError;
    if (studentRole?.role !== "student" || studentRole?.status !== "approved") {
      return reply(403, { error: "Only approved students can send workout alerts" });
    }

    const { data: links, error: linksError } = await admin
      .from("iron_coach_students_v2")
      .select("coach_id")
      .eq("student_id", user.id)
      .eq("status", "approved");
    if (linksError) throw linksError;
    const linkedCoachIds = [...new Set((links || []).map((row) => row.coach_id).filter(Boolean))];
    if (!linkedCoachIds.length) return reply(200, { ok: true, sent: 0, reason: "No approved coach link" });

    const { data: coachRoles, error: coachRolesError } = await admin
      .from("iron_account_roles_v2")
      .select("user_id")
      .in("user_id", linkedCoachIds)
      .eq("role", "coach")
      .eq("status", "approved");
    if (coachRolesError) throw coachRolesError;
    const coachIds = (coachRoles || []).map((row) => row.user_id);
    if (!coachIds.length) return reply(200, { ok: true, sent: 0, reason: "No approved coach account" });

    const { data: devices, error: devicesError } = await admin
      .from("iron_push_tokens")
      .select("user_id, token")
      .in("user_id", coachIds);
    if (devicesError) throw devicesError;
    const uniqueDevices = [...new Map((devices || []).map((device) => [device.token, device])).values()];
    if (!uniqueDevices.length) return reply(200, { ok: true, sent: 0, reason: "Coach has not registered a device yet" });

    const { data: profile } = await admin
      .from("profiles")
      .select("full_name")
      .eq("id", user.id)
      .maybeSingle();
    const studentName = (profile?.full_name || user.user_metadata?.full_name || "شاگرد شما").toString().slice(0, 80);
    const planName = (typeof log.payload?.plan === "string" ? log.payload.plan : "تمرین").slice(0, 100);

    const serviceAccount = JSON.parse(firebaseJson);
    if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
      throw new Error("Firebase service account is incomplete");
    }
    const accessToken = await getFirebaseAccessToken(serviceAccount);
    const endpoint = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    let sent = 0;
    let failed = 0;
    await Promise.all(uniqueDevices.map(async (device) => {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: {
              title: "شروع تمرین در IRONNOVA",
              body: `${studentName} تمرین «${planName}» را شروع کرد.`,
            },
            data: {
              type: "workout_started",
              student_id: user.id,
              log_id: logId,
              plan: planName,
            },
            android: { priority: "HIGH", notification: { sound: "default" } },
          },
        }),
      });
      const result = await response.json().catch(() => ({}));
      if (response.ok) {
        sent++;
        return;
      }
      failed++;
      const errorCode = result?.error?.details?.find((item: any) => item?.errorCode)?.errorCode;
      if (errorCode === "UNREGISTERED" || result?.error?.status === "NOT_FOUND") {
        await admin.from("iron_push_tokens").delete().eq("user_id", device.user_id).eq("token", device.token);
      } else {
        console.error("FCM delivery failed:", response.status, result?.error?.status || "unknown");
      }
    }));

    return reply(200, { ok: true, sent, failed });
  } catch (error) {
    console.error("notify-coach-workout-start failed:", error);
    return reply(500, { error: "Unable to send workout notification" });
  }
});
