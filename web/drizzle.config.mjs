/** @type {import("drizzle-kit").Config} */
const config = {
  schema: "./src/data/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL },
  verbose: true,
  strict: true,
};

export default config;
