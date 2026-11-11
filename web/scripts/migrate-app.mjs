// Apply migrations/app.sql, or another file in migrations/ named as the argument. Needs DATABASE_URL.
import { readFileSync } from "node:fs";
import pg from "pg";

const file = process.argv[2] ?? "app.sql";
const sql = readFileSync(new URL(`../migrations/${file}`, import.meta.url), "utf8");
const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
await client.query(sql);
await client.end();
console.log(`${file} applied`);
