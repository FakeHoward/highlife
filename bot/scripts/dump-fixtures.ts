import { writeFileSync } from "node:fs";
import { createProtocolFixtures } from "../src/showcase.js";

const fixtures = createProtocolFixtures();
for (const [name, value] of Object.entries({
  keyboard: fixtures.keyboard,
  callback: fixtures.callback,
  commands: fixtures.commands,
  mini_app: fixtures.miniApp,
  mini_app_data: fixtures.miniAppData,
})) {
  writeFileSync(
    new URL(`../../contracts/fixtures/dev.aiomatrix.${name}.json`, import.meta.url),
    `${JSON.stringify(value, null, 2)}\n`,
    "utf8",
  );
}
console.log("fixtures updated");
