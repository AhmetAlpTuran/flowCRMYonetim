import { handleWhatsAppWebhook } from "../_shared/whatsapp_webhook.ts";
Deno.serve(handleWhatsAppWebhook);
