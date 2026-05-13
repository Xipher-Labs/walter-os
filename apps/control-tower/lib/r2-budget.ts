/**
 * R2 wall-clock budget helper.
 *
 * The R2 loop runs agents sequentially. Without a budget cap, 6 × 30s timeout
 * = 180s theoretical worst case — far above the AC-7 SLA of 75s for Round 2.
 * This module provides the budget check used by the R2 route to abort remaining
 * agents and mark them as timed out when the budget is nearly exhausted.
 *
 * Refs: docs/specs/walter-council-v2.md (AC-7)
 * Reviewer round 1 finding: R2 wall-clock budget for AC-7 SLA.
 */

export interface BudgetCheckResult {
  /** true if there is enough time remaining to invoke another agent */
  canContinue: boolean;
  /** milliseconds remaining in the budget (may be negative if exceeded) */
  remainingMs: number;
}

/**
 * Check whether the R2 loop has enough wall-clock budget remaining to invoke
 * another agent.
 *
 * @param _agents - the full list of agents (unused in the check, present for
 *   signature clarity at the call site)
 * @param startTime - Date.now() at the start of the R2 loop
 * @param budgetMs - total wall-clock budget for the entire R2 loop
 * @param minCallMs - minimum milliseconds required to worth making another
 *   LLM call (default 5000ms)
 */
export function applyR2Budget(
  _agents: string[],
  startTime: number,
  budgetMs: number,
  minCallMs = 5000
): BudgetCheckResult {
  const elapsed = Date.now() - startTime;
  const remainingMs = budgetMs - elapsed;
  const canContinue = remainingMs >= minCallMs;
  return { canContinue, remainingMs };
}
