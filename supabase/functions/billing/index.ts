import { confirmCheckout } from "../_shared/billing_checkout.ts";
import { billingUrls, callbackUrl, paymentPageUrl } from "../_shared/billing_urls.ts";
import { ApiError, endpoint, jsonResponse, readJson, uuid } from "../_shared/http.ts";
import {
  cancelSubscription,
  type CheckoutCustomer,
  initializeCheckout,
  iyzicoConfig,
  IyzicoError,
  upgradeSubscription,
} from "../_shared/iyzico.ts";
import { authenticate, serviceClient } from "../_shared/supabase.ts";

type Started = { checkout_id: string; pricing_plan_code: string; customer: CheckoutCustomer };
type Subscription = { subscription_ref: string; plan_key: string; billing_period: string | null };

// Online payment for administrators: start a checkout, change plan, cancel, or re-check
// a payment. State changes are applied by service-only database functions after iyzico
// confirms them.
Deno.serve(endpoint(async (req) => {
  const { userId } = await authenticate(req);
  const body = await readJson(req, 4096);
  const tenantId = uuid(body.tenant_id, "tenant_id");
  const config = iyzicoConfig();
  const urls = billingUrls();
  if (!config || !urls) {
    throw new ApiError(503, "billing_not_configured", "Online payment is not configured");
  }
  const service = serviceClient();
  const rpc = async <T>(name: string, params: Record<string, unknown>): Promise<T> => {
    const { data, error } = await service.rpc(name, params);
    if (error) throw rpcError(error);
    return data as T;
  };

  switch (body.action) {
    case "checkout": {
      const planKey = planKeyOf(body.plan_key);
      const period = body.period === "yearly" ? "yearly" : body.period === "monthly" ? "monthly" : null;
      if (!period) throw new ApiError(422, "invalid_period", "period must be monthly or yearly");
      const started = await rpc<Started>("begin_billing_checkout", {
        p_tenant_id: tenantId,
        p_actor_id: userId,
        p_plan_key: planKey,
        p_period: period,
      });
      let form: Awaited<ReturnType<typeof initializeCheckout>>;
      try {
        form = await initializeCheckout(config, {
          checkoutId: started.checkout_id,
          pricingPlanCode: started.pricing_plan_code,
          callbackUrl: callbackUrl(urls, started.checkout_id),
          customer: started.customer,
        });
      } catch (error) {
        await service.rpc("fail_billing_checkout", {
          p_checkout_id: started.checkout_id,
          p_code: error instanceof IyzicoError ? error.code : "provider_error",
        });
        throw providerError(error);
      }
      await rpc("ready_billing_checkout", {
        p_checkout_id: started.checkout_id,
        p_token: form.token,
        p_content: form.content,
        p_expires_in: form.expiresIn,
      });
      return jsonResponse({
        status: "ready",
        checkout_id: started.checkout_id,
        payment_url: paymentPageUrl(urls, started.checkout_id),
      });
    }
    case "refresh": {
      const pending = await rpc<{ checkout_id: string; token: string } | null>("pending_billing_checkout", {
        p_tenant_id: tenantId,
        p_actor_id: userId,
      });
      if (!pending) return jsonResponse({ status: "none" });
      try {
        const status = await confirmCheckout(
          async (name, params) => await service.rpc(name, params),
          config,
          pending.checkout_id,
          pending.token,
        );
        return jsonResponse({ status });
      } catch (error) {
        if (error instanceof IyzicoError) throw providerError(error);
        throw new ApiError(503, "billing_unconfirmed", "Payment result could not be saved");
      }
    }
    case "cancel": {
      const sub = await rpc<Subscription>("billing_subscription_for_actor", {
        p_tenant_id: tenantId,
        p_actor_id: userId,
      });
      try {
        await cancelSubscription(config, sub.subscription_ref);
      } catch (error) {
        throw providerError(error);
      }
      await rpc("apply_subscription_change", { p_tenant_id: tenantId, p_kind: "canceled" });
      return jsonResponse({ status: "canceled" });
    }
    case "change_plan": {
      const planKey = planKeyOf(body.plan_key);
      const sub = await rpc<Subscription>("billing_subscription_for_actor", {
        p_tenant_id: tenantId,
        p_actor_id: userId,
      });
      if (sub.plan_key === planKey) throw new ApiError(409, "same_plan", "Already on this plan");
      const code = await rpc<string | null>("billing_plan_code", {
        p_plan_key: planKey,
        p_period: sub.billing_period ?? "monthly",
      });
      if (!code) throw new ApiError(409, "plan_unavailable", "Plan not available for online payment");
      try {
        await upgradeSubscription(config, sub.subscription_ref, code);
      } catch (error) {
        throw providerError(error);
      }
      await rpc("apply_subscription_change", {
        p_tenant_id: tenantId,
        p_kind: "plan_changed",
        p_plan_key: planKey,
      });
      return jsonResponse({ status: "changed", plan_key: planKey });
    }
    default:
      throw new ApiError(422, "invalid_action", "Unknown billing action");
  }
}));

function planKeyOf(value: unknown): string {
  if (typeof value !== "string" || !/^[a-z_]{2,30}$/.test(value)) {
    throw new ApiError(422, "invalid_plan", "Unknown plan");
  }
  return value;
}

function rpcError(error: { code?: string; hint?: string | null }): ApiError {
  if (error.code === "42501") return new ApiError(403, "admin_required", "Administrator required");
  if (error.code === "P0021" && error.hint && /^[a-z_]{1,40}$/.test(error.hint)) {
    return new ApiError(409, error.hint, "Billing action not possible");
  }
  if (error.code === "22023") return new ApiError(422, "invalid_request", "Check the request");
  return new ApiError(503, "billing_unavailable", "Billing is temporarily unavailable");
}

function providerError(error: unknown): ApiError {
  if (error instanceof IyzicoError && error.code === "provider_rejected") {
    return new ApiError(502, "provider_rejected", "The payment provider rejected the request");
  }
  return new ApiError(503, "provider_unavailable", "The payment provider is unreachable");
}
