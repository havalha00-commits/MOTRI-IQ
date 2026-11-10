const S3rver = require("s3rver");
const path = require("path");
const fs = require("fs");
const dir = path.join(process.env.TEMP || "C:\\temp", "motri-s3-test");
fs.mkdirSync(dir, { recursive: true });
const server = new S3rver({
  port: 4566,
  hostname: "127.0.0.1",
  directory: dir,
  configureBuckets: [{ name: "cars" }, { name: "market_images" }],
  silent: false,
});
server.run((err, host, port) => {
  if (err) { console.error(err); process.exit(1); }
  console.log(`S3rver running at http://${host}:${port}`);
});
process.on("SIGINT", () => { server.close(); process.exit(0); });
