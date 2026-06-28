// Shared invoice-workflow constants mirroring backend/internal/workflow/workflows.go.
// Kept in one place since both the reviewer dashboard and invoice detail page need
// to know which states a given role can actually act on.

export const ACTIONABLE_STATES_BY_ROLE: Record<string, string[]> = {
  MANAGER: ['PENDING_MANAGER_APPROVAL', 'VALIDATION_FAILED'],
  FINANCE: ['PENDING_FINANCE_APPROVAL'],
  ADMIN: ['PENDING_MANAGER_APPROVAL', 'PENDING_FINANCE_APPROVAL', 'VALIDATION_FAILED'],
};

export function canActOnState(role: string, state: string): boolean {
  return (ACTIONABLE_STATES_BY_ROLE[role] || []).includes(state);
}
