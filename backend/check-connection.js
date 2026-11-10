import dotenv from "dotenv";
dotenv.config();

const u = new URL(process.env.DATABASE_URL);

console.log({
  host: u.hostname,
  user: decodeURIComponent(u.username),
  database: u.pathname.slice(1),
  passwordPresent: Boolean(u.password),
  passwordLength: decodeURIComponent(u.password).length
});
