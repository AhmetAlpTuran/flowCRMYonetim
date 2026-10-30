import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decryptCredential,
  encryptCredential,
  type Keyring,
} from "./credential_cipher.ts";

const context = {
  tenantId: "tenant-a",
  connectionId: "connection-a",
  phoneNumberId: "12345",
};
// Synthetic fixture keys, never deployment secrets.
const keyring: Keyring = {
  active: "test-v1",
  keys: { "test-v1": btoa("a".repeat(32)), "test-v2": btoa("b".repeat(32)) },
};

Deno.test("credentials round-trip and independent encryption uses new IVs", async () => {
  const first = await encryptCredential(
    "fixture-access-token",
    context,
    keyring,
  );
  const second = await encryptCredential(
    "fixture-access-token",
    context,
    keyring,
  );
  assertEquals(
    await decryptCredential(first, context, keyring),
    "fixture-access-token",
  );
  assertNotEquals(first.iv, second.iv);
  assertNotEquals(first.ciphertext, second.ciphertext);
});

Deno.test("tenant, connection and phone swaps fail authentication", async () => {
  const value = await encryptCredential(
    "fixture-access-token",
    context,
    keyring,
  );
  for (
    const changed of [
      { ...context, tenantId: "tenant-b" },
      { ...context, connectionId: "connection-b" },
      { ...context, phoneNumberId: "67890" },
    ]
  ) await assertRejects(() => decryptCredential(value, changed, keyring));
  const corrupted = {
    ...value,
    ciphertext: (value.ciphertext[0] === "A" ? "B" : "A") +
      value.ciphertext.slice(1),
  };
  await assertRejects(() => decryptCredential(corrupted, context, keyring));
});

Deno.test("key rotation retains old decryption and refuses unavailable keys", async () => {
  const old = await encryptCredential("fixture-old-token", context, keyring);
  const rotated = { ...keyring, active: "test-v2" };
  assertEquals(
    await decryptCredential(old, context, rotated),
    "fixture-old-token",
  );
  const current = await encryptCredential(
    "fixture-new-token",
    context,
    rotated,
  );
  assertEquals(current.key_id, "test-v2");
  await assertRejects(() =>
    decryptCredential(old, context, {
      active: "test-v2",
      keys: { "test-v2": keyring.keys["test-v2"] },
    })
  );
  await assertRejects(() =>
    encryptCredential("fixture-token", context, {
      active: "bad",
      keys: { bad: btoa("short") },
    })
  );
});
