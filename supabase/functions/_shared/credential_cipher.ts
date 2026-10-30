// Web Crypto only: no server env dependency, so cryptographic regression cases
// can use deterministic fixture keys without reading production configuration.
export type EncryptedCredential = {
  key_id: string;
  ciphertext: string;
  iv: string;
};
export type CredentialContext = {
  tenantId: string;
  connectionId: string;
  phoneNumberId: string;
};
export type Keyring = { active: string; keys: Record<string, string> };

function decode(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}
function encode(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function contextBytes(context: CredentialContext): Uint8Array<ArrayBuffer> {
  return new TextEncoder().encode(JSON.stringify([
    "whatsapp-token-v1",
    context.tenantId,
    context.connectionId,
    context.phoneNumberId,
  ]));
}
async function importKey(keyring: Keyring, keyId: string) {
  const encoded = keyring.keys[keyId];
  if (typeof encoded !== "string" || !encoded) {
    throw new Error("Credential key unavailable");
  }
  const bytes = decode(encoded);
  if (bytes.length !== 32) throw new Error("Credential key must be 256 bits");
  return await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

export async function encryptCredential(
  token: string,
  context: CredentialContext,
  keyring: Keyring,
): Promise<EncryptedCredential> {
  if (!token || token.length > 16384) {
    throw new Error("Invalid credential size");
  }
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await importKey(keyring, keyring.active);
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: contextBytes(context),
      tagLength: 128,
    },
    key,
    new TextEncoder().encode(token),
  );
  return {
    key_id: keyring.active,
    iv: encode(iv),
    ciphertext: encode(new Uint8Array(ciphertext)),
  };
}

export async function decryptCredential(
  value: EncryptedCredential,
  context: CredentialContext,
  keyring: Keyring,
): Promise<string> {
  const iv = decode(value.iv);
  if (iv.length !== 12) throw new Error("Invalid credential IV");
  const key = await importKey(keyring, value.key_id);
  const result = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: contextBytes(context),
      tagLength: 128,
    },
    key,
    decode(value.ciphertext),
  );
  return new TextDecoder().decode(result);
}
