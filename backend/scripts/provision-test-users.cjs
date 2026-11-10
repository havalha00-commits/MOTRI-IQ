require("dotenv/config");
const BASE = "http://localhost:3000";

async function register(email, username) {
  const res = await fetch(`${BASE}/api/auth/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: "TestPassword123!", username, full_name: "Test User" }),
  });
  if (!res.ok) throw new Error(await res.text());
  return await res.json();
}

(async () => {
  const a = await register("testa@example.com", "testa");
  const b = await register("testb@example.com", "testb");
  console.log(JSON.stringify({ a: { id: a.user.id, token: a.access_token }, b: { id: b.user.id, token: b.access_token } }));
})();
