export const ALLOWANCES = {
  "com.notelab.standard.monthly": 180,
  "com.notelab.standard.yearly": 180,
  "com.notelab.pro.monthly": 900,
  "com.notelab.pro.yearly": 900
};

export const CREDIT_COSTS = {
  "ai.highlight": 2,
  "ai.extractTasks": 3,
  "ai.organize": 6,
  "ai.plan": 6,
  "ai.rewrite": 8,
  "ai.semanticConnections": 10,
  "ai.recentFocus": 12
};

export function allowanceForProductId(productId) {
  return ALLOWANCES[productId] ?? 0;
}

export function costForAction(action) {
  return CREDIT_COSTS[action] ?? 0;
}

export function periodKey(date = new Date()) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}
