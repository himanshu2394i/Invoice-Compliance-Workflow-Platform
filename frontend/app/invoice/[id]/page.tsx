// page.tsx (details)
"use client";

import React, { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import styles from './page.module.css';
import { authFetch, useRequireAuth } from '../../../lib/auth';
import { canActOnState } from '../../../lib/workflow';

interface Invoice {
  id: string;
  organization_id: string;
  entity_id: string;
  vendor_id: string;
  buyer_id?: string;
  invoice_number: string;
  invoice_date: string;
  gross_amount: number;
  tax_amount: number;
  currency: string;
  current_state: string;
  created_at: string;
  updated_at: string;
}

interface Document {
  id: string;
  document_type: string;
  is_primary: boolean;
  created_at: string;
}

interface AuditEvent {
  id: string;
  event_type: string;
  actor_id: string;
  description: string;
  payload: any;
  previous_hash: string;
  current_hash: string;
  created_at: string;
}

export default function InvoiceDetails({ params }: { params: { id: string } }) {
  const router = useRouter();
  const user = useRequireAuth();
  const invoiceID = params.id;

  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [documents, setDocuments] = useState<Document[]>([]);
  const [auditTrail, setAuditTrail] = useState<AuditEvent[]>([]);
  const [comments, setComments] = useState('');
  const [buyer, setBuyer] = useState<{ id: string; name: string; gstin: string } | null>(null);
  const [invoiceExceptions, setInvoiceExceptions] = useState<any[]>([]);

  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<{ text: string; isError: boolean } | null>(null);

  const loadData = useCallback(async () => {
    try {
      const invRes = await authFetch(`/invoices/${invoiceID}`);
      if (invRes.ok) {
        const data = await invRes.json();
        setInvoice(data.invoice);
        setDocuments(data.documents || []);

        // Ledger invoices (buyer_id set) never enter the AP approval workflow,
        // so the buyer + open exceptions are the relevant context here instead.
        if (data.invoice?.buyer_id) {
          const buyersRes = await authFetch('/buyers');
          if (buyersRes.ok) {
            const buyersData = await buyersRes.json();
            const match = (buyersData.buyers || []).find((b: any) => b.id === data.invoice.buyer_id);
            setBuyer(match || null);
          }
          const excRes = await authFetch('/exceptions');
          if (excRes.ok) {
            const excData = await excRes.json();
            setInvoiceExceptions((excData.invoice_exceptions || []).filter((e: any) => e.invoice_id === invoiceID));
          }
        }
      }

      const auditRes = await authFetch(`/invoices/${invoiceID}/audit-trail`);
      if (auditRes.ok) {
        const auditData = await auditRes.json();
        setAuditTrail(auditData || []);
      }
    } catch (e) {
      console.error("Error loading invoice details:", e);
    } finally {
      setLoading(false);
    }
  }, [invoiceID]);

  useEffect(() => {
    if (!user) return;
    loadData();
    // Poll data every 2.5 seconds to watch Temporal state transitions
    const interval = setInterval(loadData, 2500);
    return () => clearInterval(interval);
  }, [user, loadData]);

  const handleAction = async (approved: boolean) => {
    setSubmitting(true);
    setMessage(null);

    try {
      const res = await authFetch(`/invoices/${invoiceID}/approve`, {
        method: 'POST',
        body: JSON.stringify({ approved, comments }),
      });

      if (res.ok) {
        setMessage({
          text: approved ? 'Approval signal registered successfully!' : 'Invoice marked as rejected.',
          isError: false
        });
        setComments('');
        loadData();
      } else {
        const err = await res.json();
        setMessage({ text: `Failed to submit approval: ${err.error || 'Unknown error'}`, isError: true });
      }
    } catch (e) {
      setMessage({ text: 'Error connecting to approval endpoint.', isError: true });
    } finally {
      setSubmitting(false);
    }
  };

  if (!user || loading) {
    return <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-secondary)' }}>Loading invoice profile...</div>;
  }

  if (!invoice) {
    return (
      <div className={styles.container}>
        <button className={styles.backBtn} onClick={() => router.push('/')}>← Return to Registry</button>
        <div className="glass" style={{ padding: '3rem', textAlign: 'center' }}>
          <h3>Invoice profile not found</h3>
          <p style={{ color: 'var(--text-muted)' }}>Could not retrieve record details for UUID: {invoiceID}</p>
        </div>
      </div>
    );
  }

  const state = invoice.current_state;
  const userCanAct = canActOnState(user.role, state);
  const isLedgerInvoice = !!invoice.buyer_id;
  const hasSupportingDoc = documents.some((d) => !d.is_primary);

  const viewDocument = async (docId: string) => {
    const res = await authFetch(`/documents/${docId}/content`);
    if (!res.ok) return;
    const blob = await res.blob();
    window.open(URL.createObjectURL(blob), '_blank');
  };

  // Determine stage progression status
  const getStepClass = (stage: string) => {
    switch (stage) {
      case 'INGESTION':
        return styles.completed;
      case 'VERIFICATION':
        if (['PENDING_MANAGER_APPROVAL', 'PENDING_FINANCE_APPROVAL', 'APPROVED', 'ARCHIVED'].includes(state)) return styles.completed;
        if (state === 'VALIDATING') return styles.active;
        if (state === 'VALIDATION_FAILED') return styles.failed;
        return '';
      case 'APPROVALS':
        if (['APPROVED', 'ARCHIVED'].includes(state)) return styles.completed;
        if (['PENDING_MANAGER_APPROVAL', 'PENDING_FINANCE_APPROVAL'].includes(state)) return styles.active;
        return '';
      case 'ERP_SYNC':
        if (state === 'ARCHIVED') return styles.completed;
        if (state === 'APPROVED') return styles.active;
        return '';
      default:
        return '';
    }
  };

  // Find validation failures from audit logs
  const validationFailures = auditTrail
    .filter(event => event.event_type === 'VALIDATION_FAILED')
    .map(event => event.payload?.errors || [])
    .flat();

  return (
    <div className={styles.container}>
      <button className={styles.backBtn} onClick={() => router.push('/')}>← Return to Registry</button>

      {/* Invoice Header summary */}
      <div className={`${styles.headerCard} glass`}>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' }}>
            <h1 className={styles.invTitle}>Invoice {invoice.invoice_number}</h1>
            <span className={`${styles.badge} ${styles['badge' + state]}`}>{state.replace('_', ' ')}</span>
          </div>
          <div className={styles.invMeta}>
            <div className={styles.metaItem}>
              <span className={styles.metaLabel}>{isLedgerInvoice ? 'Buyer' : 'Issuer Vendor'}</span>
              <span className={styles.metaValue}>
                {isLedgerInvoice ? (buyer ? `${buyer.name} (${buyer.gstin})` : 'Loading...') : 'Acme supplies'}
              </span>
            </div>
            <div className={styles.metaItem}>
              <span className={styles.metaLabel}>Document Date</span>
              <span className={styles.metaValue}>{new Date(invoice.invoice_date).toLocaleDateString()}</span>
            </div>
            <div className={styles.metaItem}>
              <span className={styles.metaLabel}>Gross Amount</span>
              <span className={styles.metaValue} style={{ color: 'var(--primary)' }}>
                {invoice.gross_amount.toLocaleString('en-IN', { style: 'currency', currency: invoice.currency })}
              </span>
            </div>
            <div className={styles.metaItem}>
              <span className={styles.metaLabel}>Verification Hash</span>
              <span className={styles.metaValue} style={{ fontFamily: 'monospace', fontSize: '0.8rem', wordBreak: 'break-all' }}>
                {auditTrail[0]?.current_hash ? `${auditTrail[0].current_hash.slice(0, 16)}...` : 'N/A'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Progress Timeline -- ledger invoices never enter the AP approval
          workflow (no manager/finance signal, no ERP sync), so their
          current_state sits at INGESTED forever; showing the AP stage
          timeline for them just spins on stage 2 indefinitely. */}
      {isLedgerInvoice ? (
        <div className={`${styles.timelineCard} glass`}>
          <h3 className={styles.metaLabel}>Ledger Filing Status</h3>
          <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap', marginTop: '0.75rem' }}>
            <span style={{ fontSize: '0.8rem', padding: '0.3rem 0.7rem', borderRadius: '999px', background: 'rgba(34,197,94,0.15)', color: '#22c55e', fontWeight: 600 }}>
              Filed
            </span>
            <span style={{
              fontSize: '0.8rem', padding: '0.3rem 0.7rem', borderRadius: '999px', fontWeight: 600,
              background: hasSupportingDoc ? 'rgba(34,197,94,0.15)' : 'rgba(234,179,8,0.15)',
              color: hasSupportingDoc ? '#22c55e' : '#eab308',
            }}>
              {hasSupportingDoc ? 'Supporting document attached' : 'No supporting document yet'}
            </span>
            {invoiceExceptions.length > 0 && (
              <span style={{ fontSize: '0.8rem', padding: '0.3rem 0.7rem', borderRadius: '999px', background: 'rgba(239,68,68,0.15)', color: '#ef4444', fontWeight: 600 }}>
                {invoiceExceptions.length} open exception{invoiceExceptions.length > 1 ? 's' : ''}
              </span>
            )}
          </div>
        </div>
      ) : (
        <div className={`${styles.timelineCard} glass`}>
          <h3 className={styles.metaLabel}>Temporal Workflow Stage</h3>
          <div className={styles.timeline}>
            <div className={`${styles.timelineStep} ${getStepClass('INGESTION')}`}>
              <div className={styles.timelineNode}>1</div>
              <span className={styles.stepLabel}>Ingestion Completed</span>
            </div>
            <div className={`${styles.timelineStep} ${getStepClass('VERIFICATION')}`}>
              <div className={styles.timelineNode}>2</div>
              <span className={styles.stepLabel}>
                {state === 'VALIDATION_FAILED' ? 'Compliance Failed' : 'Compliance Verified'}
              </span>
            </div>
            <div className={`${styles.timelineStep} ${getStepClass('APPROVALS')}`}>
              <div className={styles.timelineNode}>3</div>
              <span className={styles.stepLabel}>Dual Approvals</span>
            </div>
            <div className={`${styles.timelineStep} ${getStepClass('ERP_SYNC')}`}>
              <div className={styles.timelineNode}>4</div>
              <span className={styles.stepLabel}>ERP Synced & Archived</span>
            </div>
          </div>
        </div>
      )}

      {message && (
        <div style={{
          padding: '1rem',
          borderRadius: '8px',
          background: message.isError ? 'var(--danger-bg)' : 'var(--success-bg)',
          border: `1px solid ${message.isError ? 'var(--danger)' : 'var(--success)'}`,
          color: message.isError ? 'var(--danger)' : 'var(--success)',
          fontSize: '0.9rem'
        }}>
          {message.text}
        </div>
      )}

      {/* Split details panel */}
      <div className={styles.grid}>

        {/* Left: Actions & Rules Panel */}
        <div className={`${styles.panel} glass`}>

          {isLedgerInvoice && (
            <div>
              <h3 className={styles.panelTitle}>
                <span>📄</span> Buyer & Documents
              </h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
                <div>
                  <div className={styles.metaLabel}>Documents on file</div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginTop: '0.5rem' }}>
                    {documents.length === 0 ? (
                      <span style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>No documents found.</span>
                    ) : documents.map((d) => (
                      <button
                        key={d.id}
                        onClick={() => viewDocument(d.id)}
                        style={{
                          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                          padding: '0.6rem 0.8rem', borderRadius: '6px', background: 'rgba(255,255,255,0.03)',
                          border: '1px solid var(--border-color)', color: 'var(--text-primary)', cursor: 'pointer',
                          fontSize: '0.85rem', textAlign: 'left',
                        }}
                      >
                        <span>{d.is_primary ? 'Invoice image' : d.document_type.replace('_', ' ')}</span>
                        <span style={{ color: 'var(--text-secondary)' }}>{new Date(d.created_at).toLocaleDateString()} →</span>
                      </button>
                    ))}
                  </div>
                </div>

                {invoiceExceptions.length > 0 && (
                  <div>
                    <div className={styles.metaLabel} style={{ color: '#ef4444' }}>Open exceptions</div>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginTop: '0.5rem' }}>
                      {invoiceExceptions.map((e) => (
                        <div key={e.id} style={{ padding: '0.6rem 0.8rem', borderRadius: '6px', background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.25)', fontSize: '0.85rem' }}>
                          {e.exception_type === 'missing_document' ? 'Missing supporting document' : 'Document mismatch'}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Validation Failure warning banner */}
          {!isLedgerInvoice && state === 'VALIDATION_FAILED' && (
            <div>
              <h3 className={styles.panelTitle} style={{ color: 'var(--danger)' }}>
                <span>⚠️</span> Compliance Errors Detected
              </h3>
              <div className={styles.validationErrors}>
                {validationFailures.map((err, i) => (
                  <div className={styles.errorItem} key={i}>
                    <span>🛑</span> {err}
                  </div>
                ))}
              </div>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', lineHeight: '1.4' }}>
                A manager can override and approve despite the validation failure, or reject below.
              </p>
            </div>
          )}

          {/* Approval Controls Console */}
          {!isLedgerInvoice && ['PENDING_MANAGER_APPROVAL', 'PENDING_FINANCE_APPROVAL', 'VALIDATION_FAILED'].includes(state) && (
            <div>
              <h3 className={styles.panelTitle}>
                <span>🔐</span> Authorization Console
              </h3>
              <div className={styles.actionConsole}>
                {userCanAct ? (
                  <>
                    <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', lineHeight: '1.4' }}>
                      This invoice is waiting on {state === 'PENDING_FINANCE_APPROVAL' ? 'Finance' : 'Manager'} authorization. Acting as <strong>{user.role}</strong>.
                    </p>
                    <textarea
                      className={styles.commentArea}
                      placeholder="Enter evaluation comments, audit logs, or rejection notes..."
                      value={comments}
                      onChange={e => setComments(e.target.value)}
                    />
                    <div className={styles.actionRow}>
                      <button
                        className={styles.btn}
                        onClick={() => handleAction(true)}
                        disabled={submitting}
                      >
                        Approve
                      </button>
                      <button
                        className={styles.btn}
                        style={{ background: 'none', border: '1px solid var(--danger)', color: 'var(--danger)' }}
                        onClick={() => handleAction(false)}
                        disabled={submitting}
                      >
                        Reject Invoice
                      </button>
                    </div>
                  </>
                ) : (
                  <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', lineHeight: '1.4' }}>
                    This invoice is waiting on {state === 'PENDING_FINANCE_APPROVAL' ? 'Finance' : 'Manager'} authorization. Your role ({user.role}) can&apos;t act on it at this stage.
                  </p>
                )}
              </div>
            </div>
          )}

          {/* Archived/Approved State */}
          {!isLedgerInvoice && ['APPROVED', 'ARCHIVED'].includes(state) && (
            <div>
              <h3 className={styles.panelTitle} style={{ color: 'var(--success)' }}>
                <span>✅</span> Compliance Cycle Complete
              </h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', lineHeight: '1.6' }}>
                This invoice has cleared all operational syntax check rules, received the dual approvals from the Manager and Finance departments, and has been securely synced to the centralized ERP ledger.
              </p>
              <div style={{ marginTop: '1.5rem', background: 'rgba(255,255,255,0.02)', padding: '1rem', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <span className={styles.metaLabel}>Audit ledger block location:</span>
                <div style={{ fontFamily: 'monospace', fontSize: '0.75rem', marginTop: '0.3rem', wordBreak: 'break-all', color: 'var(--success)' }}>
                  S3_Glacier_Reference://archive/{invoice.organization_id}/{invoice.invoice_number}.enc
                </div>
              </div>
            </div>
          )}

          {/* Rejected State */}
          {state === 'REJECTED' && (
            <div>
              <h3 className={styles.panelTitle} style={{ color: 'var(--danger)' }}>
                <span>❌</span> Invoice Rejected
              </h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', lineHeight: '1.6' }}>
                This invoice has been rejected. It is flagged as non-compliant, and workflow execution has terminated. Please ingest a fresh document with corrected metrics to start a new lifecycle.
              </p>
            </div>
          )}

          {/* Ingested/Validating state */}
          {!isLedgerInvoice && ['INGESTED', 'VALIDATING'].includes(state) && (
            <div style={{ textAlign: 'center', paddingTop: '3rem' }}>
              <div style={{
                width: '40px',
                height: '40px',
                border: '3px solid rgba(6,182,212,0.1)',
                borderTopColor: 'var(--primary)',
                borderRadius: '99px',
                margin: '0 auto 1.5rem',
                animation: 'spin 1s linear infinite'
              }} />
              <h3 className={styles.panelTitle} style={{ justifyContent: 'center' }}>
                Executing Temporal Verification
              </h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>
                The automated pipeline is checking duplicate numbers and tax compliance.
              </p>
            </div>
          )}

        </div>

        {/* Right: Cryptographic Audit Trail Inspector */}
        <div className={`${styles.panel} glass`}>
          <h3 className={styles.panelTitle}>
            <span>🔗</span> Tamper-Proof Audit Chain
          </h3>
          {auditTrail.length === 0 ? (
            <div style={{ textAlign: 'center', color: 'var(--text-muted)', paddingTop: '4rem' }}>
              No audit trail events recorded yet.
            </div>
          ) : (
            <div className={styles.auditList}>
              {auditTrail.map((event, i) => {
                // Cryptographic validation logic
                // Ensure current.prevHash === previous.currentHash
                let matches = true;
                if (i > 0) {
                  matches = event.previous_hash === auditTrail[i - 1].current_hash;
                }

                return (
                  <div className={styles.auditNode} key={event.id}>
                    <div className={styles.auditMeta}>
                      <span>👤 {event.actor_id}</span>
                      <span>{new Date(event.created_at).toLocaleTimeString()}</span>
                    </div>
                    <div className={styles.auditDesc}>
                      {event.description}
                    </div>
                    <div className={styles.auditHashes}>
                      <div>
                        Prev: <span className={styles.hashVal}>{event.previous_hash.slice(0, 16)}...</span>
                      </div>
                      <div>
                        Block: <span className={styles.hashVal}>{event.current_hash.slice(0, 16)}...</span>
                        {i > 0 && (
                          <span className={styles.hashMatch}>
                            {matches ? ' ✓ Verified Linked' : ' ✗ Hash Broken!'}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

      </div>
    </div>
  );
}
