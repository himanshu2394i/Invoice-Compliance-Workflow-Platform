# Mobile Navigation, Search, and Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reliable mobile back navigation, admin/manager invoice search, and a prioritized product/security roadmap for follow-up implementation.

**Architecture:** Introduce a small shared navigation helper for logical back behavior and reuse it across screens that currently have no `PopScope`/hardware-back policy. Keep invoice search client-side on the existing `ownerInvoicesProvider` result because the list model already includes invoice number, buyer, GSTIN, amount, status, and exception/dispute counts. Capture follow-up roadmap items in `task.md` so later work can proceed one by one without reopening the product discovery.

**Tech Stack:** Flutter, Riverpod, GoRouter, Material 3, `flutter_test`, existing Go backend only if a later roadmap item requires API changes.

## Global Constraints

- Do not add worker batch mode.
- Admin/manager invoice search must find a specific invoice by invoice number, buyer name, GSTIN, amount, or status.
- Keep all data for now. Do not implement purge, delete, archive, or retention expiry workflows.
- Preserve existing capture-step back behavior and unsaved-work protections.
- Use `puro flutter analyze` after mobile changes and compare against `mobile/analysis_baseline.txt`.
- Do not touch abandoned `frontend/` work.

---

### Task 1: Shared Back Navigation Helper

**Files:**
- Create: `mobile/lib/core/navigation/app_back.dart`
- Test: `mobile/test/core/navigation/app_back_test.dart`

**Interfaces:**
- Produces: `class AppBackScope extends StatelessWidget`
- Produces: `const AppBackScope({required Widget child, required String fallbackLocation, bool preferPop = true, String? exitSnackBarMessage, Duration exitWindow = const Duration(seconds: 2)})`
- Produces: `static void goBack(BuildContext context, {required String fallbackLocation, bool preferPop = true})`

- [ ] **Step 1: Write the failing helper tests**

Create `mobile/test/core/navigation/app_back_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/core/navigation/app_back.dart';

GoRouter _router({String initialLocation = '/child'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const Text('Home')),
        GoRoute(
          path: '/child',
          builder: (_, __) => const AppBackScope(
            fallbackLocation: '/home',
            child: Scaffold(
              appBar: AppBar(title: Text('Child')),
              body: Text('Child body'),
            ),
          ),
        ),
      ],
    );

void main() {
  testWidgets('AppBackScope sends hardware back to fallback route',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('goBack sends a direct route to its fallback', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    AppBackScope.goBack(
      tester.element(find.text('Child body')),
      fallbackLocation: '/home',
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile; puro flutter test test/core/navigation/app_back_test.dart`

Expected: FAIL because `package:invoice_capture/core/navigation/app_back.dart` does not exist.

- [ ] **Step 3: Implement the helper**

Create `mobile/lib/core/navigation/app_back.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBackScope extends StatefulWidget {
  final Widget child;
  final String fallbackLocation;
  final bool preferPop;
  final String? exitSnackBarMessage;
  final Duration exitWindow;

  const AppBackScope({
    super.key,
    required this.child,
    required this.fallbackLocation,
    this.preferPop = true,
    this.exitSnackBarMessage,
    this.exitWindow = const Duration(seconds: 2),
  });

  static void goBack(
    BuildContext context, {
    required String fallbackLocation,
    bool preferPop = true,
  }) {
    if (preferPop && context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackLocation);
    }
  }

  @override
  State<AppBackScope> createState() => _AppBackScopeState();
}

class _AppBackScopeState extends State<AppBackScope> {
  DateTime? _lastExitRequest;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (widget.exitSnackBarMessage != null) {
          final now = DateTime.now();
          final shouldExit = _lastExitRequest != null &&
              now.difference(_lastExitRequest!) <= widget.exitWindow;
          if (shouldExit) {
            Navigator.of(context).maybePop();
            return;
          }
          _lastExitRequest = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.exitSnackBarMessage!)),
          );
          return;
        }
        AppBackScope.goBack(
          context,
          fallbackLocation: widget.fallbackLocation,
          preferPop: widget.preferPop,
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile; puro flutter test test/core/navigation/app_back_test.dart`

Expected: PASS.

---

### Task 2: Apply Back Policy Across Existing Screens

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart`
- Modify: `mobile/lib/features/queue/queue_screen.dart`
- Modify: `mobile/lib/features/capture/my_invoices_screen.dart`
- Modify: `mobile/lib/features/owner/alerts_screen.dart`
- Modify: `mobile/lib/features/owner/owner_dashboard_screen.dart`
- Modify: `mobile/lib/features/owner/owner_invoices_screen.dart`
- Modify: `mobile/lib/features/owner/invoice_detail_screen.dart`
- Modify: `mobile/lib/features/admin/buyer_requirements_screen.dart`
- Modify: `mobile/lib/features/admin/rules_screen.dart`
- Modify: `mobile/lib/features/settings/settings_screen.dart`
- Test: `mobile/test/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `AppBackScope`
- Consumes: `AppBackScope.goBack(BuildContext context, {required String fallbackLocation, bool preferPop = true})`

- [ ] **Step 1: Write failing home back test**

Add to `mobile/test/home/home_screen_test.dart`:

```dart
testWidgets('home requires two Android back presses before exit',
    (tester) async {
  await pumpHomeAsRole(tester, 'WORKER');

  await tester.binding.handlePopRoute();
  await tester.pump();

  expect(find.text('Press back again to exit'), findsOneWidget);
  expect(find.text('Invoice Capture'), findsWidgets);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile; puro flutter test test/home/home_screen_test.dart`

Expected: FAIL because home does not yet show the exit snackbar.

- [ ] **Step 3: Wrap home in `AppBackScope`**

Modify `mobile/lib/features/home/home_screen.dart`:

```dart
import '../../core/navigation/app_back.dart';
```

Return:

```dart
return AppBackScope(
  fallbackLocation: '/home',
  exitSnackBarMessage: 'Press back again to exit',
  child: Scaffold(
    appBar: AppBar(
      title: const Text('Invoice Capture'),
      actions: [
        ...
      ],
    ),
    body: SafeArea(
      ...
    ),
  ),
);
```

- [ ] **Step 4: Add visible back buttons and hardware fallbacks**

For each listed screen, import `../../core/navigation/app_back.dart` or the correct relative path, wrap the returned `Scaffold` in `AppBackScope`, and add `leading` where missing:

```dart
return AppBackScope(
  fallbackLocation: '/home',
  child: Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => AppBackScope.goBack(
          context,
          fallbackLocation: '/home',
        ),
      ),
      title: const Text('Screen Title'),
    ),
    body: ...,
  ),
);
```

Use these fallbacks:

- `QueueScreen`: `/home`
- `MyInvoicesScreen`: `/home`
- `AlertsScreen`: `/home`
- `OwnerDashboardScreen`: `/home`
- `OwnerInvoicesScreen`: `/owner`
- `InvoiceDetailScreen`: `/owner/invoices`
- `BuyerRequirementsScreen`: `/owner`
- `RulesScreen`: `/owner`
- `SettingsScreen`: `/home`

- [ ] **Step 5: Run focused tests**

Run: `cd mobile; puro flutter test test/home/home_screen_test.dart test/capture/review_screen_test.dart`

Expected: PASS, including the existing capture review back test.

---

### Task 3: Admin/Manager Invoice Search

**Files:**
- Modify: `mobile/lib/features/owner/owner_invoices_screen.dart`
- Test: `mobile/test/owner/owner_invoice_search_test.dart`

**Interfaces:**
- Consumes: `OwnerInvoice`
- Produces: `List<OwnerInvoice> filterOwnerInvoices(List<OwnerInvoice> invoices, String query)`

- [ ] **Step 1: Write failing filter tests**

Create `mobile/test/owner/owner_invoice_search_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/owner/owner_invoices_screen.dart';
import 'package:invoice_capture/features/owner/owner_provider.dart';

OwnerInvoice _invoice({
  required String invoiceNumber,
  required String buyerName,
  required String gstin,
  required double amount,
  required String state,
}) =>
    OwnerInvoice(
      id: invoiceNumber,
      invoiceNumber: invoiceNumber,
      invoiceDate: '2026-06-30',
      grossAmount: amount,
      taxAmount: 0,
      currentState: state,
      createdAt: '2026-06-30T00:00:00Z',
      buyerName: buyerName,
      buyerGstin: gstin,
      entityName: 'Meridian Brothers',
      openExceptions: 0,
      openDisputes: 0,
      documentCount: 1,
    );

void main() {
  final invoices = [
    _invoice(
      invoiceNumber: 'HAL08222',
      buyerName: 'Flipkart India Pvt Ltd',
      gstin: '06AAAAA0012A1ZC',
      amount: 10913,
      state: 'PENDING_REVIEW',
    ),
    _invoice(
      invoiceNumber: 'MAX-100',
      buyerName: 'Max Hypermarket',
      gstin: '06AAAAA0005A1Z5',
      amount: 25100,
      state: 'APPROVED',
    ),
  ];

  test('empty query returns all invoices', () {
    expect(filterOwnerInvoices(invoices, ''), hasLength(2));
  });

  test('matches invoice number, buyer, GSTIN, amount, and state', () {
    expect(filterOwnerInvoices(invoices, 'hal'), [invoices.first]);
    expect(filterOwnerInvoices(invoices, 'hypermarket'), [invoices.last]);
    expect(filterOwnerInvoices(invoices, '4872'), [invoices.first]);
    expect(filterOwnerInvoices(invoices, '25100'), [invoices.last]);
    expect(filterOwnerInvoices(invoices, 'approved'), [invoices.last]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile; puro flutter test test/owner/owner_invoice_search_test.dart`

Expected: FAIL because `filterOwnerInvoices` does not exist.

- [ ] **Step 3: Implement search filtering and UI**

Modify `mobile/lib/features/owner/owner_invoices_screen.dart`:

```dart
List<OwnerInvoice> filterOwnerInvoices(
  List<OwnerInvoice> invoices,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return invoices;
  return invoices.where((inv) {
    final haystack = [
      inv.invoiceNumber,
      inv.buyerName ?? '',
      inv.buyerGstin ?? '',
      inv.entityName ?? '',
      inv.currentState,
      inv.invoiceDate,
      inv.grossAmount.toStringAsFixed(0),
      inv.grossAmount.toStringAsFixed(2),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }).toList();
}
```

Convert `OwnerInvoicesScreen` from `ConsumerWidget` to `ConsumerStatefulWidget`, add a `_searchController`, dispose it, and filter the loaded data:

```dart
class OwnerInvoicesScreen extends ConsumerStatefulWidget {
  const OwnerInvoicesScreen({super.key});

  @override
  ConsumerState<OwnerInvoicesScreen> createState() =>
      _OwnerInvoicesScreenState();
}

class _OwnerInvoicesScreenState extends ConsumerState<OwnerInvoicesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
```

In the `data:` branch, compute `final visibleInvoices = filterOwnerInvoices(invoices, _searchController.text);` and render a `TextField` above the list:

```dart
TextField(
  controller: _searchController,
  onChanged: (_) => setState(() {}),
  textInputAction: TextInputAction.search,
  decoration: InputDecoration(
    prefixIcon: const Icon(Icons.search),
    suffixIcon: _searchController.text.isEmpty
        ? null
        : IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Clear search',
            onPressed: () {
              _searchController.clear();
              setState(() {});
            },
          ),
    hintText: 'Search invoice, buyer, GSTIN, amount, status',
    border: const OutlineInputBorder(),
  ),
)
```

If `visibleInvoices.isEmpty`, show `No matching invoices` instead of an empty list.

- [ ] **Step 4: Run search tests**

Run: `cd mobile; puro flutter test test/owner/owner_invoice_search_test.dart`

Expected: PASS.

---

### Task 4: Product Roadmap Tracking

**Files:**
- Modify: `task.md`

**Interfaces:**
- Consumes: approved roadmap in `docs/superpowers/specs/2026-07-01-mobile-navigation-product-security-design.md`
- Produces: a prioritized roadmap checklist for follow-up implementation.

- [ ] **Step 1: Add roadmap section**

Append this section to `task.md`:

```markdown
## Phase 8 — Navigation, search, and product hardening roadmap (2026-07-01)

- `[ ]` Add app-wide Android back handling and visible back buttons across mobile screens.
- `[ ]` Add admin/manager invoice search by invoice number, buyer, GSTIN, amount, and status.
- `[ ]` Add OCR confidence/review cues on autofilled worker fields.
- `[ ]` Add photo quality checks for blur, darkness, and missing document edges.
- `[ ]` Add duplicate-invoice warning before submit.
- `[ ]` Add capture draft recovery.
- `[ ]` Add alert filters and aging for exceptions/disputes/approval work.
- `[ ]` Add password-change/reset support before real staff rollout.
- `[ ]` Add MFA for admin/manager users before broader pilot use.
- `[ ]` Define DPDP/CERT-In operating checklist while keeping data indefinitely for now.
```

- [ ] **Step 2: Mark completed roadmap items**

After Tasks 2 and 3 pass, update the first two roadmap items to `[x]`.

---

### Task 5: Final Verification

**Files:**
- Verify only; no new source files.

**Interfaces:**
- Consumes: all prior task outputs.

- [ ] **Step 1: Run focused Flutter tests**

Run: `cd mobile; puro flutter test test/core/navigation/app_back_test.dart test/home/home_screen_test.dart test/capture/review_screen_test.dart test/owner/owner_invoice_search_test.dart`

Expected: PASS.

- [ ] **Step 2: Run full Flutter test suite**

Run: `cd mobile; puro flutter test`

Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run: `cd mobile; puro flutter analyze`

Expected: output matches the known baseline in `mobile/analysis_baseline.txt`; do not require zero issues unless the baseline is zero.

- [ ] **Step 4: Review diff**

Run: `git diff -- mobile/lib mobile/test task.md docs/superpowers/plans/2026-07-01-mobile-navigation-search-roadmap.md`

Expected: changes are limited to navigation helper, screen wiring, invoice search, tests, and roadmap tracking.
