// Apply migrations/app.sql. Idempotent. Needs DATABASE_URL.
import { readFileSync } from "node:fs";
import pg from "pg";

const sql = readFileSync(new URL("../migrations/app.sql", import.meta.url), "utf8");
const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
await client.query(sql);
await client.end();
console.log("app tables ready");
