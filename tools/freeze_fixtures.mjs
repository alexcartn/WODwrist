// Regenerate docs/fixtures/*.json from *.txt. Review the diff before committing.
import { parseWod } from "../web-editor/js/wod-parser.js";
import fs from "node:fs";
import path from "node:path";
const dir = new URL("../docs/fixtures/", import.meta.url).pathname;
for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".txt"))) {
  const r = parseWod(fs.readFileSync(path.join(dir, f), "utf8"));
  fs.writeFileSync(path.join(dir, f.replace(/\.txt$/, ".json")), JSON.stringify(r.wod ?? r, null, 2) + "\n");
}
