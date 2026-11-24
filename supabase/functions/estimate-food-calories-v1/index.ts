const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = req.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "ابتدا وارد حساب کاربری شو." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!supabaseUrl || !anonKey) return json({ error: "تنظیمات احراز هویت سرور کامل نیست." }, 500);
  if (!openAiKey) return json({ error: "کلید OPENAI_API_KEY هنوز در Secrets پروژه ثبت نشده است." }, 503);

  const authCheck = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: authorization },
  });
  if (!authCheck.ok) return json({ error: "نشست کاربری معتبر نیست؛ دوباره وارد حساب شو." }, 401);

  let body: { image_data_url?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "درخواست تصویر معتبر نیست." }, 400);
  }

  const imageDataUrl = body.image_data_url || "";
  const match = imageDataUrl.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/);
  if (!match) return json({ error: "فقط تصویر JPG، PNG یا WEBP قابل بررسی است." }, 400);
  if (match[2].length > 8_500_000) return json({ error: "حجم تصویر بیش از حد مجاز است؛ تصویر کوچک‌تری انتخاب کن." }, 413);

  const prompt = `این تصویر یک وعده یا خوراکی است. غذاهای قابل مشاهده را تشخیص بده و برای هر مورد مقدار خوراکی قابل مشاهده را به گرم و کالری و درشت‌مغذی‌ها را تخمین بزن. روغن، سس و مواد پنهان را بدون شواهد فرض نکن. اگر اندازه ظرف یا عمق تصویر نامشخص است، بازه عدم‌قطعیت را در notes توضیح بده. نتیجه صرفاً تخمین تصویری است و نباید ادعای دقت آزمایشگاهی داشته باشد.
فقط یک شیء JSON معتبر برگردان، بدون Markdown، با ساختار:
{"foods":[{"name":"نام فارسی غذا","estimated_grams":150,"calories":250,"protein_g":12,"carbs_g":30,"fat_g":8,"fiber_g":4}],"total_grams":150,"total_calories":250,"total_protein_g":12,"total_carbs_g":30,"total_fat_g":8,"total_fiber_g":4,"confidence":"low|medium|high","notes":"توضیح کوتاه درباره فرض‌ها و عدم‌قطعیت"}.
همه اعداد باید غیرمنفی و تقریبی باشند. اگر غذا قابل تشخیص نیست، foods را خالی و confidence را low قرار بده.`;

  const aiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4.1-mini",
      max_output_tokens: 700,
      input: [{
        role: "user",
        content: [
          { type: "input_text", text: prompt },
          { type: "input_image", image_url: imageDataUrl, detail: "high" },
        ],
      }],
    }),
  });

  const aiBody = await aiResponse.json().catch(() => ({}));
  if (!aiResponse.ok) {
    return json({ error: aiBody?.error?.message || "سرویس تخمین تصویر پاسخ نداد." }, 502);
  }

  const outputText = aiBody.output_text || (aiBody.output || [])
    .flatMap((item: { content?: Array<{ type?: string; text?: string }> }) => item.content || [])
    .filter((part: { type?: string }) => part.type === "output_text")
    .map((part: { text?: string }) => part.text || "")
    .join("\n");

  try {
    const cleaned = String(outputText).replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
    const estimate = JSON.parse(cleaned);
    if (!Array.isArray(estimate.foods)) throw new Error("invalid foods");
    return json({ estimate });
  } catch {
    return json({ error: "پاسخ تخمین‌گر قابل خواندن نبود؛ دوباره امتحان کن." }, 502);
  }
});
