import { handleWhatsAppWebhook } from "../_shared/whatsapp_webhook.ts";
// Preserve the old callback URL while removing unsigned/default-tenant dispatch.
Deno.serve(handleWhatsAppWebhook);
