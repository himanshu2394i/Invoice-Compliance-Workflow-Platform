"use client";

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import styles from './page.module.css';
import { authFetch, useRequireAuth, logout } from '../lib/auth';

const PAGE_SIZE = 25;

export default function Home() {
  const router = useRouter();
  const user = useRequireAuth();
  const [invoices, setInvoices] = useState<any[]>([]);
  const [page, setPage] = useState(0);
  const [total, setTotal] = useState(0);

  // Poll backend
  useEffect(() => {
    if (!user) return;
    const fetchInvoices = async () => {
      try {
        const res = await authFetch(`/invoices?limit=${PAGE_SIZE}&offset=${page * PAGE_SIZE}`);
        const data = await res.json();
        setInvoices(Array.isArray(data.invoices) ? data.invoices : []);
        setTotal(typeof data.total === 'number' ? data.total : 0);
      } catch (err) {
        console.error("Failed to fetch invoices", err);
      }
    };

    fetchInvoices();
    const interval = setInterval(fetchInvoices, 2000);
    return () => clearInterval(interval);
  }, [user, page]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR' }).format(amount);
  };

  if (!user) {
    return (
      <div style={{ width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>
        Checking session...
      </div>
    );
  }

  return (
    <main className={styles.container}>
      <header className={styles.header}>
        <div className={styles.logo}>InvoiceSaaS</div>
        <div style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
          <span style={{ fontSize: '0.85rem', color: 'var(--muted-foreground)' }}>{user.email} ({user.role})</span>
          <button
            className={styles.uploadBtn}
            onClick={() => router.push('/dashboard/worker')}
          >
            + Upload Invoice
          </button>
          <button
            className={styles.uploadBtn}
            style={{ background: 'transparent', color: 'var(--foreground)', border: '1px solid var(--border)' }}
            onClick={logout}
          >
            Log out
          </button>
        </div>
      </header>

      <div className={styles.dashboard}>
        <aside className={styles.sidebar}>
          <div className={`${styles.navItem} ${styles.active}`}>Dashboard</div>
          <div className={styles.navItem}>Invoices</div>
          <div className={styles.navItem}>Vendors</div>
          <div className={styles.navItem}>Approvals</div>
          <div className={styles.navItem}>Settings</div>
        </aside>

        <section className={styles.mainContent}>
          <div className={styles.glassCard}>
            <h2 className={styles.cardTitle}>Recent Workflows</h2>
            <div className={styles.invoiceList}>
              {invoices.length === 0 ? (
                <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--muted-foreground)' }}>
                  No invoices found. Click &quot;+ Upload Invoice&quot; to get started.
                </div>
              ) : (
                invoices.map((inv) => (
                  <div
                    key={inv.id}
                    className={styles.invoiceRow}
                    style={{ cursor: 'pointer' }}
                    onClick={() => router.push(`/invoice/${inv.id}`)}
                  >
                    <div>
                      <strong>{inv.invoice_number || inv.id}</strong>
                      <div style={{ fontSize: '0.875rem', color: 'var(--muted-foreground)' }}>
                        Vendor ID: {inv.vendor_id ? inv.vendor_id.substring(0, 8) + '...' : 'Unknown'}
                      </div>
                    </div>
                    <div>{formatCurrency(inv.gross_amount || 0)}</div>
                    <div className={`${styles.badge} ${inv.current_state === 'APPROVED' ? styles.approved : styles.pending}`}>
                      {inv.current_state || 'PENDING'}
                    </div>
                  </div>
                ))
              )}
            </div>
            {total > 0 && (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '1rem', borderTop: '1px solid var(--border)' }}>
                <span style={{ fontSize: '0.8rem', color: 'var(--muted-foreground)' }}>
                  Showing {page * PAGE_SIZE + 1}-{Math.min(total, (page + 1) * PAGE_SIZE)} of {total}
                </span>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <button
                    className={styles.uploadBtn}
                    style={{ background: 'transparent', color: 'var(--foreground)', border: '1px solid var(--border)', opacity: page === 0 ? 0.5 : 1 }}
                    disabled={page === 0}
                    onClick={() => setPage((p) => Math.max(0, p - 1))}
                  >
                    ← Prev
                  </button>
                  <button
                    className={styles.uploadBtn}
                    style={{ background: 'transparent', color: 'var(--foreground)', border: '1px solid var(--border)', opacity: page + 1 >= totalPages ? 0.5 : 1 }}
                    disabled={page + 1 >= totalPages}
                    onClick={() => setPage((p) => p + 1)}
                  >
                    Next →
                  </button>
                </div>
              </div>
            )}
          </div>
        </section>
      </div>
    </main>
  );
}
