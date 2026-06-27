import assert from "node:assert/strict";
import { allowanceForProductId, costForAction, periodKey } from "../src/ai-rules.mjs";

assert.equal(allowanceForProductId("com.notelab.standard.monthly"), 180);
assert.equal(allowanceForProductId("com.notelab.pro.yearly"), 900);
assert.equal(allowanceForProductId("unknown"), 0);

assert.equal(costForAction("ai.extractTasks"), 3);
assert.equal(costForAction("ai.semanticConnections"), 10);
assert.equal(costForAction("bad"), 0);

assert.equal(periodKey(new Date("2026-06-22T00:00:00.000Z")), "2026-06");
