"use client";

import { useEffect, useState } from 'react';
import DualPaneWorkspace from '../../../components/DualPaneWorkspace';
import { authFetch, useRequireAuth } from '../../../lib/auth';
import { canActOnState } from '../../../lib/workflow';

interface Invoice {
  id: string;
  invoice_number: string;
  current_state: string;
  gross_amount: number;
}

export default function ReviewerDashboard() {
  const user = useRequireAuth();
  const [invoices, setInvoices] = useState<Invoice[]>([]);

  useEffect(() => {
    if (!user) return;
    const fetchInvoices = async () => {
      try {
        const res = await authFetch('/invoices');
        const data = await res.json();
        setInvoices(Array.isArray(data.invoices) ? data.invoices : []);
      } catch (err) {
        console.error("Failed to fetch invoices", err);
      }
    };

    fetchInvoices();
    const interval = setInterval(fetchInvoices, 2000);
    return () => clearInterval(interval);
  }, [user]);

  if (!user) {
    return (
      <div style={{ width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>
        Checking session...
      </div>
    );
  }

  const pending = invoices.find((inv) => canActOnState(user.role, inv.current_state));

  const handleAction = async (approve: boolean) => {
    if (!pending) return;
    await authFetch(`/invoices/${pending.id}/approve`, {
      method: 'POST',
      body: JSON.stringify({ approved: approve, comments: '' }),
    });
  };

  const DocumentViewer = (
    <div style={{ width: '100%', height: '100%', padding: '2rem', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      {pending ? (
      <div style={{ width: '100%', maxWidth: '800px', flex: 1, backgroundColor: '#fff', borderRadius: '8px', padding: '2rem', boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)' }}>
        <div style={{ borderBottom: '2px solid #e2e8f0', paddingBottom: '1rem', marginBottom: '2rem' }}>
          <h2 style={{ color: '#0f172a', margin: 0 }}>TAX INVOICE</h2>
          <p style={{ color: '#64748b', fontSize: '0.875rem' }}>Invoice: {pending.invoice_number}</p>
        </div>
        <div style={{ color: '#0f172a' }}>
          <p><strong>Seller:</strong> DBR GURGAON</p>
          <p><strong>Buyer:</strong> V Mart Retail Limited</p>
          <p><strong>Date:</strong> 11-Jun-2026</p>
          <br/>
          <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: '2rem' }}>
            <tr style={{ borderBottom: '1px solid #e2e8f0', textAlign: 'left' }}>
              <th>Item</th>
              <th>Qty</th>
              <th>Rate</th>
              <th>Amount</th>
            </tr>
            <tr style={{ borderBottom: '1px solid #e2e8f0' }}>
              <td style={{ padding: '0.5rem 0' }}>HARPIC 1L</td>
              <td>200 Box</td>
              <td>-</td>
              <td>{pending.gross_amount?.toLocaleString('en-IN', { style: 'currency', currency: 'INR' })}</td>
            </tr>
          </table>
          <div style={{ marginTop: '4rem', padding: '1rem', border: '2px dashed #cbd5e1', color: '#64748b', textAlign: 'center' }}>
            <span style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#ef4444', transform: 'rotate(-10deg)', display: 'inline-block' }}>200 BOX RECEIVED By Ganpati 12/06/26</span>
          </div>
        </div>
      </div>
      ) : (
        <div style={{ color: 'white' }}>No pending invoices for your role. Queue is clear!</div>
      )}
    </div>
  );

  const ValidationForm = (
    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
      {pending ? (
      <>
      <div>
        <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '0.5rem' }}>Validation Queue</h2>
        <p style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>Review exception for: {pending.invoice_number} ({pending.current_state}) -- acting as {user.role}</p>
      </div>

      {pending.current_state === 'VALIDATION_FAILED' && (
        <div style={{ backgroundColor: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.2)', padding: '1rem', borderRadius: '8px', color: '#ef4444' }}>
          <div style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>
            Validation Error
          </div>
          <p style={{ fontSize: '0.875rem', marginTop: '0.5rem' }}>Deterministic validation failed -- see the invoice&apos;s audit trail for details. Approve here to override after manual review, or reject.</p>
        </div>
      )}

      <div style={{ marginTop: 'auto', display: 'flex', gap: '1rem', paddingTop: '2rem', borderTop: '1px solid var(--border)' }}>
        <button onClick={() => handleAction(false)} style={{ flex: 1, padding: '0.75rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--foreground)', cursor: 'pointer', fontWeight: 500 }}>Reject</button>
        <button onClick={() => handleAction(true)} style={{ flex: 2, padding: '0.75rem', borderRadius: '6px', border: 'none', background: 'linear-gradient(135deg, #a78bfa 0%, #8b5cf6 100%)', color: 'white', cursor: 'pointer', fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem' }}>
          Approve Workflow
        </button>
      </div>
      </>
      ) : (
        <div style={{ color: 'var(--muted-foreground)' }}>All caught up!</div>
      )}
    </div>
  );

  return <DualPaneWorkspace leftPane={DocumentViewer} rightPane={ValidationForm} headerTitle={`Reviewer Workspace (${user.role})`} />;
}
