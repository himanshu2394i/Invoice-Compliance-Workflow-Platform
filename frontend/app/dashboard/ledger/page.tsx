"use client";

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import DualPaneWorkspace from '../../../components/DualPaneWorkspace';
import { authFetch, useRequireAuth } from '../../../lib/auth';

interface InvoiceException {
  id: string;
  invoice_id: string;
  invoice_number?: string;
  exception_type: 'missing_document' | 'document_mismatch';
  details: Record<string, any>;
  status: string;
  raised_at: string;
}

interface MissingInvoiceNumber {
  id: string;
  entity_id: string;
  invoice_series: string;
  missing_number: string;
  detected_at: string;
  status: string;
}

interface Invoice {
  id: string;
  invoice_number: string;
  gross_amount: number;
  invoice_date: string;
  current_state: string;
}

const EXCEPTION_LABELS: Record<string, string> = {
  missing_document: 'Missing supporting document',
  document_mismatch: 'Document mismatch',
};

export default function LedgerDashboard() {
  const router = useRouter();
  const user = useRequireAuth();

  const [invoiceExceptions, setInvoiceExceptions] = useState<InvoiceException[]>([]);
  const [missingNumbers, setMissingNumbers] = useState<MissingInvoiceNumber[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<Invoice[]>([]);
  const [searching, setSearching] = useState(false);

  const loadExceptions = async () => {
    try {
      const res = await authFetch('/exceptions');
      if (res.ok) {
        const data = await res.json();
        setInvoiceExceptions(Array.isArray(data.invoice_exceptions) ? data.invoice_exceptions : []);
        setMissingNumbers(Array.isArray(data.missing_invoice_numbers) ? data.missing_invoice_numbers : []);
      }
    } catch (err) {
      console.error('Failed to load exceptions', err);
    }
  };

  useEffect(() => {
    if (!user) return;
    loadExceptions();
    const interval = setInterval(loadExceptions, 5000);
    return () => clearInterval(interval);
  }, [user]);

  const runSearch = async () => {
    setSearching(true);
    try {
      const res = await authFetch(`/invoices?limit=25&q=${encodeURIComponent(searchQuery)}`);
      const data = await res.json();
      setSearchResults(Array.isArray(data.invoices) ? data.invoices : []);
    } catch (err) {
      console.error('Search failed', err);
    } finally {
      setSearching(false);
    }
  };

  const resolveException = async (id: string, status: 'resolved' | 'not_applicable') => {
    await authFetch(`/exceptions/${id}/resolve`, { method: 'POST', body: JSON.stringify({ status }) });
    loadExceptions();
  };

  const resolveMissingNumber = async (id: string, status: 'resolved' | 'not_applicable') => {
    await authFetch(`/missing-invoice-numbers/${id}/resolve`, { method: 'POST', body: JSON.stringify({ status }) });
    loadExceptions();
  };

  if (!user) {
    return (
      <div style={{ width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>
        Checking session...
      </div>
    );
  }

  const totalOpen = invoiceExceptions.length + missingNumbers.length;

  const ExceptionsPane = (
    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1.5rem', height: '100%', overflowY: 'auto' }}>
      <div>
        <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '0.25rem' }}>
          Open exceptions {totalOpen > 0 && <span style={{ color: '#ef4444' }}>({totalOpen})</span>}
        </h2>
        <p style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>
          Invoices missing a supporting document, documents filed under the wrong invoice, and gaps in an entity&apos;s invoice-number sequence.
        </p>
      </div>

      {totalOpen === 0 ? (
        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--muted-foreground)', border: '1px dashed var(--border)', borderRadius: '8px' }}>
          Nothing open. Everything filed so far is accounted for.
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
          {invoiceExceptions.map((exc) => (
            <div key={exc.id} style={{ padding: '1rem', borderRadius: '8px', background: 'var(--muted)', border: '1px solid var(--border)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '1rem' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <span style={{
                      fontSize: '0.7rem', fontWeight: 700, padding: '0.2rem 0.5rem', borderRadius: '4px',
                      background: exc.exception_type === 'missing_document' ? 'rgba(234,179,8,0.15)' : 'rgba(239,68,68,0.15)',
                      color: exc.exception_type === 'missing_document' ? '#eab308' : '#ef4444',
                    }}>
                      {EXCEPTION_LABELS[exc.exception_type] || exc.exception_type}
                    </span>
                    <strong
                      style={{ cursor: 'pointer', textDecoration: 'underline' }}
                      onClick={() => router.push(`/invoice/${exc.invoice_id}`)}
                    >
                      {exc.invoice_number || exc.invoice_id.slice(0, 8)}
                    </strong>
                  </div>
                  {exc.details?.reasons && (
                    <ul style={{ margin: '0.5rem 0 0', paddingLeft: '1.25rem', fontSize: '0.8rem', color: 'var(--muted-foreground)' }}>
                      {exc.details.reasons.map((reason: string, i: number) => <li key={i}>{reason}</li>)}
                    </ul>
                  )}
                  <div style={{ fontSize: '0.75rem', color: 'var(--muted-foreground)', marginTop: '0.4rem' }}>
                    Raised {new Date(exc.raised_at).toLocaleString()}
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '0.4rem', flexShrink: 0 }}>
                  <button style={btnStyle} onClick={() => resolveException(exc.id, 'resolved')}>Resolve</button>
                  <button style={{ ...btnStyle, background: 'transparent', border: '1px solid var(--border)', color: 'var(--foreground)' }} onClick={() => resolveException(exc.id, 'not_applicable')}>Not applicable</button>
                </div>
              </div>
            </div>
          ))}

          {missingNumbers.map((m) => (
            <div key={m.id} style={{ padding: '1rem', borderRadius: '8px', background: 'var(--muted)', border: '1px solid var(--border)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '1rem' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <span style={{ fontSize: '0.7rem', fontWeight: 700, padding: '0.2rem 0.5rem', borderRadius: '4px', background: 'rgba(234,179,8,0.15)', color: '#eab308' }}>
                      Missing invoice
                    </span>
                    <strong>{m.missing_number}</strong>
                    <span style={{ fontSize: '0.75rem', color: 'var(--muted-foreground)' }}>series {m.invoice_series}</span>
                  </div>
                  <div style={{ fontSize: '0.8rem', color: 'var(--muted-foreground)', marginTop: '0.4rem' }}>
                    This number falls inside the series&apos; known sequence but was never filed. Detected {new Date(m.detected_at).toLocaleString()}.
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '0.4rem', flexShrink: 0 }}>
                  <button style={btnStyle} onClick={() => resolveMissingNumber(m.id, 'resolved')}>Filed now</button>
                  <button style={{ ...btnStyle, background: 'transparent', border: '1px solid var(--border)', color: 'var(--foreground)' }} onClick={() => resolveMissingNumber(m.id, 'not_applicable')}>Never issued</button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const SearchPane = (
    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1rem', height: '100%' }}>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 600 }}>Look up an invoice</h2>
      <div style={{ display: 'flex', gap: '0.5rem' }}>
        <input
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && runSearch()}
          placeholder="Invoice number..."
          style={{ flex: 1, padding: '0.6rem 0.8rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'var(--background)', color: 'var(--foreground)' }}
        />
        <button style={btnStyle} onClick={runSearch} disabled={searching}>{searching ? '...' : 'Search'}</button>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', overflowY: 'auto', flex: 1 }}>
        {searchResults.length === 0 ? (
          <div style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem', textAlign: 'center', paddingTop: '2rem' }}>
            No results yet. Try a full or partial invoice number.
          </div>
        ) : (
          searchResults.map((inv) => (
            <div
              key={inv.id}
              onClick={() => router.push(`/invoice/${inv.id}`)}
              style={{ padding: '0.75rem 1rem', borderRadius: '8px', background: 'var(--muted)', border: '1px solid var(--border)', cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
            >
              <div>
                <strong>{inv.invoice_number}</strong>
                <div style={{ fontSize: '0.75rem', color: 'var(--muted-foreground)' }}>{new Date(inv.invoice_date).toLocaleDateString()}</div>
              </div>
              <span style={{ fontSize: '0.8rem', color: 'var(--muted-foreground)' }}>{inv.current_state}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );

  return <DualPaneWorkspace leftPane={ExceptionsPane} rightPane={SearchPane} headerTitle="Ledger" />;
}

const btnStyle: React.CSSProperties = {
  fontSize: '0.8rem', padding: '0.4rem 0.8rem', borderRadius: '6px', border: 'none',
  background: 'linear-gradient(135deg, #a78bfa 0%, #8b5cf6 100%)', color: 'white', cursor: 'pointer', fontWeight: 600,
};
