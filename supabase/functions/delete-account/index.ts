import { ApiError, endpoint, jsonResponse, readJson } from "../_shared/http.ts";
import {
  authenticate,
  type DatabaseClient,
  serviceClient,
} from "../_shared/supabase.ts";

type Plan = {
  blocked: { tenant_id: string; name: string }[];
  delete_tenants: string[];
  leave_tenants: string[];
};

// Permanently deletes the caller's account. Every step is safe to repeat: if a
// later step fails, calling again finds a smaller plan and finishes the job.
Deno.serve(endpoint(async (req) => {
  const { client, userId } = await authenticate(req);
  const body = await readJson(req, 4096);
  const { data: user, error: userError } = await client.auth.getUser();
  const email = user?.user?.email?.toLowerCase();
  if (
    userError || !email || typeof body.confirm_email !== "string" ||
    body.confirm_email.trim().toLowerCase() !== email
  ) {
    throw new ApiError(
      422,
      "confirmation_mismatch",
      "Type your account email to confirm",
    );
  }
  const service = serviceClient();
  const { data: planData, error: planError } = await service.rpc(
    "account_deletion_plan",
    { p_user_id: userId },
  );
  if (planError || !planData) {
    throw new ApiError(503, "deletion_unavailable", "Deletion unavailable");
  }
  const plan = planData as Plan;
  if (plan.blocked.length > 0) {
    return jsonResponse({
      code: "admin_transfer_required",
      error: "Transfer the administrator role first",
      blocked: plan.blocked.map((tenant) => tenant.name),
    }, 409);
  }
  // Files first: once the tenant row is gone, its folder is no longer reachable
  // through any plan.
  for (const tenantId of plan.delete_tenants) {
    await removeTenantMedia(service, tenantId);
  }
  const { error: dataError } = await service.rpc("delete_account_data", {
    p_user_id: userId,
  });
  if (dataError) {
    if (dataError.code === "P0014") {
      throw new ApiError(409, "admin_transfer_required", "Transfer the administrator role first");
    }
    throw new ApiError(503, "deletion_unavailable", "Deletion unavailable; retry");
  }
  const { error: authError } = await service.auth.admin.deleteUser(userId);
  if (authError) {
    throw new ApiError(503, "deletion_incomplete", "Account deletion incomplete; retry");
  }
  return jsonResponse({
    status: "deleted",
    deleted_businesses: plan.delete_tenants.length,
    left_businesses: plan.leave_tenants.length,
  });
}));

/** Removes every object under {tenant}/ in inbox-media (conversation and outbound folders). */
async function removeTenantMedia(service: DatabaseClient, tenantId: string) {
  const bucket = service.storage.from("inbox-media");
  const files: string[] = [];
  const pending = [tenantId];
  while (pending.length > 0 && files.length < 50000) {
    const folder = pending.pop()!;
    for (let offset = 0;; offset += 1000) {
      const { data, error } = await bucket.list(folder, { limit: 1000, offset });
      if (error) {
        throw new ApiError(503, "deletion_unavailable", "Stored files unavailable; retry");
      }
      for (const entry of data ?? []) {
        // Folders have no id in Storage listings.
        if (entry.id === null) pending.push(`${folder}/${entry.name}`);
        else files.push(`${folder}/${entry.name}`);
      }
      if ((data ?? []).length < 1000) break;
    }
  }
  for (let start = 0; start < files.length; start += 100) {
    const { error } = await bucket.remove(files.slice(start, start + 100));
    if (error) {
      throw new ApiError(503, "deletion_unavailable", "Stored files unavailable; retry");
    }
  }
}
