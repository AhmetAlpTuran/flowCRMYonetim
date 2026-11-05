import { type IyzicoConfig, retrieveCheckout } from "./iyzico.ts";

type Rpc = (name: string, params: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;

/**
 * Confirms a checkout with iyzico by its token (never trusting the browser) and applies
 * the result: `completed`, `failed`, `unknown` (token does not belong to the checkout).
 * Throws IyzicoError when iyzico cannot be asked; the checkout then stays open for a
 * later re-check.
 */
export async function confirmCheckout(
  rpc: Rpc,
  config: IyzicoConfig,
  checkoutId: string,
  token: string,
  transport: typeof fetch = fetch,
): Promise<string> {
  const result = await retrieveCheckout(config, token, transport);
  const { data, error } = await rpc("complete_billing_checkout", {
    p_checkout_id: checkoutId,
    p_token: token,
    p_success: result.active,
    p_subscription_ref: result.subscriptionRef,
    p_customer_ref: result.customerRef,
    p_failure_code: result.active ? null : "payment_not_completed",
  });
  if (error || typeof data !== "string") throw new Error("billing_unconfirmed");
  return data;
}
