/// Plain-language invoice status labels for non-technical staff. Raw workflow
/// states like PENDING_MANAGER_APPROVAL stay in the backend/audit trail; the
/// UI shows what the state means to the person reading it.
String invoiceStatusLabel(
  String state, {
  String? paymentType,
  bool overdue = false,
  double? balance,
}) {
  // A finished CREDIT invoice's interesting status is whether we've been
  // paid, not that the workflow archived it.
  if (state == 'ARCHIVED' && paymentType == 'CREDIT' && balance != null) {
    if (balance <= 0.005) return 'Paid';
    return overdue ? 'Overdue' : 'Open';
  }

  switch (state) {
    case 'INGESTED':
      return 'Submitted';
    case 'VALIDATING':
      return 'Checking';
    case 'VALIDATION_FAILED':
      return 'Needs Review';
    case 'PENDING_MANAGER_APPROVAL':
      return 'Waiting for Manager';
    case 'PENDING_FINANCE_APPROVAL':
      return 'Waiting for Finance';
    case 'APPROVED':
      return 'Approved';
    case 'REJECTED':
      return 'Rejected';
    case 'ARCHIVED':
      return 'Archived';
  }

  // Unknown state: make it readable rather than shouting SNAKE_CASE.
  return state
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}
