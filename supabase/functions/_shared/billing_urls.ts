/** Public URLs of the payment flow. */
export type BillingUrls = { functions: string; paymentPage: string; resultPage: string };

export function billingUrls(read: (name: string) => string | undefined = (n) => Deno.env.get(n)): BillingUrls | null {
  const supabase = read("SUPABASE_URL")?.trim() ?? "";
  const functions = (read("PUBLIC_FUNCTIONS_URL")?.trim() || (supabase ? `${supabase}/functions/v1` : ""))
    .replace(/\/+$/, "");
  const page = read("BILLING_PAGE_URL")?.trim() ?? "";
  if (!/^https?:\/\//.test(functions) || !/^https?:\/\//.test(page)) return null;
  const paymentPage = page.endsWith("/") ? page : `${page}/`;
  return { functions, paymentPage, resultPage: new URL("sonuc/", paymentPage).toString() };
}

export function paymentPageUrl(urls: BillingUrls, checkoutId: string): string {
  return `${urls.paymentPage}?oturum=${encodeURIComponent(checkoutId)}`;
}

export function resultPageUrl(urls: BillingUrls, outcome: "basarili" | "basarisiz" | "beklemede"): string {
  return `${urls.resultPage}?durum=${outcome}`;
}

export function callbackUrl(urls: BillingUrls, checkoutId: string): string {
  return `${urls.functions}/iyzico-gateway/callback/${checkoutId}`;
}
