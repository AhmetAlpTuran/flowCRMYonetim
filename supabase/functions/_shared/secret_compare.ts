export async function secretEquals(
  left: string,
  right: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all(
    [left, right].map(async (value) =>
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", encoder.encode(value)),
      )
    ),
  );
  let difference = 0;
  for (let index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}
