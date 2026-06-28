"use client";

import { useEffect, useRef, useState } from 'react';
import DualPaneWorkspace from '../../../components/DualPaneWorkspace';
import { authFetch, useRequireAuth } from '../../../lib/auth';

interface Invoice {
  id: string;
  invoice_number: string;
  current_state: string;
  gross_amount: number;
  invoice_series?: string;
}

interface Entity {
  id: string;
  legal_name: string;
  tax_identifier: string;
}

interface Buyer {
  id: string;
  name: string;
  gstin: string;
}

const inputStyle: React.CSSProperties = {
  padding: '0.6rem 0.8rem', borderRadius: '6px', border: '1px solid var(--border)',
  background: 'var(--background)', color: 'var(--foreground)', fontSize: '0.875rem', width: '100%',
};
const labelStyle: React.CSSProperties = { fontSize: '0.75rem', color: 'var(--muted-foreground)', marginBottom: '0.25rem', display: 'block' };

export default function WorkerDashboard() {
  const user = useRequireAuth();
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [entities, setEntities] = useState<Entity[]>([]);
  const [buyers, setBuyers] = useState<Buyer[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const supportingDocInputRef = useRef<HTMLInputElement>(null);
  const [attachingTo, setAttachingTo] = useState<string | null>(null);

  // Invoice metadata typed in before picking a file -- this is the real
  // ledger flow (see backend handleUploadLedgerInvoice), not the old
  // fixed-demo-amount simulator.
  const [entityID, setEntityID] = useState('');
  const [buyerID, setBuyerID] = useState('');
  const [invoiceNumber, setInvoiceNumber] = useState('');
  const [invoiceSeries, setInvoiceSeries] = useState('');
  const [invoiceDate, setInvoiceDate] = useState('');
  const [grossAmount, setGrossAmount] = useState('');
  const [taxAmount, setTaxAmount] = useState('');

  // New-buyer inline form
  const [showNewBuyer, setShowNewBuyer] = useState(false);
  const [newBuyerName, setNewBuyerName] = useState('');
  const [newBuyerGSTIN, setNewBuyerGSTIN] = useState('');

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
    const fetchMasters = async () => {
      try {
        const [entRes, buyRes] = await Promise.all([authFetch('/entities'), authFetch('/buyers')]);
        const entData = await entRes.json();
        const buyData = await buyRes.json();
        const ents = Array.isArray(entData.entities) ? entData.entities : [];
        const bys = Array.isArray(buyData.buyers) ? buyData.buyers : [];
        setEntities(ents);
        setBuyers(bys);
        if (ents.length > 0) setEntityID((prev) => prev || ents[0].id);
      } catch (err) {
        console.error("Failed to fetch entities/buyers", err);
      }
    };

    fetchInvoices();
    fetchMasters();
    const interval = setInterval(fetchInvoices, 3000);
    return () => clearInterval(interval);
  }, [user]);

  const createBuyer = async () => {
    if (!newBuyerName.trim() || !newBuyerGSTIN.trim()) return;
    const res = await authFetch('/buyers', {
      method: 'POST',
      body: JSON.stringify({ name: newBuyerName.trim(), gstin: newBuyerGSTIN.trim() }),
    });
    if (res.ok) {
      const buyer = await res.json();
      setBuyers((prev) => [...prev, buyer]);
      setBuyerID(buyer.id);
      setShowNewBuyer(false);
      setNewBuyerName('');
      setNewBuyerGSTIN('');
    } else {
      const err = await res.json().catch(() => ({}));
      alert(`Failed to create buyer: ${err.error || res.statusText}`);
    }
  };

  const handleUpload = async (file: File) => {
    if (!entityID || !buyerID || !invoiceNumber.trim()) {
      alert('Pick an entity and buyer, and type the invoice number, before uploading the file.');
      return;
    }
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('entity_id', entityID);
      formData.append('buyer_id', buyerID);
      formData.append('invoice_number', invoiceNumber.trim());
      if (invoiceSeries.trim()) formData.append('invoice_series', invoiceSeries.trim());
      if (invoiceDate) formData.append('invoice_date', invoiceDate);
      formData.append('gross_amount', grossAmount || '0');
      formData.append('tax_amount', taxAmount || '0');

      const res = await authFetch('/invoices/ledger-upload', { method: 'POST', body: formData });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        alert(`Upload failed: ${err.error || res.statusText}`);
      } else {
        setInvoiceNumber('');
        setInvoiceSeries('');
        setGrossAmount('');
        setTaxAmount('');
      }
    } catch (err) {
      console.error("Upload failed", err);
    } finally {
      setUploading(false);
    }
  };

  const handleFileInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleUpload(file);
    e.target.value = '';
  };

  const handleDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files?.[0];
    if (file) handleUpload(file);
  };

  const handleSupportingDocChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    const invoiceID = attachingTo;
    e.target.value = '';
    setAttachingTo(null);
    if (!file || !invoiceID) return;

    const formData = new FormData();
    formData.append('file', file);
    formData.append('document_type', 'SUPPORTING_DOCUMENT');
    const res = await authFetch(`/invoices/${invoiceID}/documents`, { method: 'POST', body: formData });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      alert(`Failed to attach document: ${err.error || res.statusText}`);
    }
  };

  if (!user) {
    return (
      <div style={{ width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>
        Checking session...
      </div>
    );
  }

  const UploadPane = (
    <div style={{ width: '100%', height: '100%', padding: '2.5rem', display: 'flex', flexDirection: 'column', gap: '1rem', overflowY: 'auto' }}>
      <h2 style={{ fontSize: '1.1rem', fontWeight: 600 }}>File a new invoice</h2>

      <div>
        <label style={labelStyle}>Entity (who issued it)</label>
        <select style={inputStyle} value={entityID} onChange={(e) => setEntityID(e.target.value)}>
          {entities.length === 0 && <option value="">No entities -- seed the database first</option>}
          {entities.map((e) => <option key={e.id} value={e.id}>{e.legal_name} ({e.tax_identifier})</option>)}
        </select>
      </div>

      <div>
        <label style={labelStyle}>Buyer (who it was issued to)</label>
        {!showNewBuyer ? (
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <select style={inputStyle} value={buyerID} onChange={(e) => setBuyerID(e.target.value)}>
              <option value="">Select a buyer...</option>
              {buyers.map((b) => <option key={b.id} value={b.id}>{b.name} ({b.gstin})</option>)}
            </select>
            <button style={smallBtnStyle} onClick={() => setShowNewBuyer(true)}>+ New</button>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', padding: '0.75rem', border: '1px solid var(--border)', borderRadius: '6px' }}>
            <input style={inputStyle} placeholder="Buyer legal name" value={newBuyerName} onChange={(e) => setNewBuyerName(e.target.value)} />
            <input style={inputStyle} placeholder="GSTIN" value={newBuyerGSTIN} onChange={(e) => setNewBuyerGSTIN(e.target.value)} />
            <div style={{ display: 'flex', gap: '0.5rem' }}>
              <button style={smallBtnStyle} onClick={createBuyer}>Save buyer</button>
              <button style={{ ...smallBtnStyle, background: 'transparent', border: '1px solid var(--border)', color: 'var(--foreground)' }} onClick={() => setShowNewBuyer(false)}>Cancel</button>
            </div>
          </div>
        )}
      </div>

      <div style={{ display: 'flex', gap: '0.5rem' }}>
        <div style={{ flex: 1 }}>
          <label style={labelStyle}>Invoice number</label>
          <input style={inputStyle} value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} placeholder="e.g. NIV3594182600261" />
        </div>
        <div style={{ flex: 1 }}>
          <label style={labelStyle}>Series (optional)</label>
          <input style={inputStyle} value={invoiceSeries} onChange={(e) => setInvoiceSeries(e.target.value)} placeholder="e.g. NIV" />
        </div>
      </div>

      <div style={{ display: 'flex', gap: '0.5rem' }}>
        <div style={{ flex: 1 }}>
          <label style={labelStyle}>Invoice date</label>
          <input type="date" style={inputStyle} value={invoiceDate} onChange={(e) => setInvoiceDate(e.target.value)} />
        </div>
        <div style={{ flex: 1 }}>
          <label style={labelStyle}>Gross amount</label>
          <input type="number" style={inputStyle} value={grossAmount} onChange={(e) => setGrossAmount(e.target.value)} placeholder="0.00" />
        </div>
        <div style={{ flex: 1 }}>
          <label style={labelStyle}>Tax amount</label>
          <input type="number" style={inputStyle} value={taxAmount} onChange={(e) => setTaxAmount(e.target.value)} placeholder="0.00" />
        </div>
      </div>

      <input ref={fileInputRef} type="file" accept=".pdf,.jpg,.jpeg,.png" style={{ display: 'none' }} onChange={handleFileInputChange} />
      <div
        onClick={() => !uploading && fileInputRef.current?.click()}
        onDragOver={(e) => { e.preventDefault(); setIsDragging(true); }}
        onDragLeave={() => setIsDragging(false)}
        onDrop={handleDrop}
        style={{
          border: `2px dashed ${isDragging ? 'var(--primary)' : 'var(--border)'}`,
          borderRadius: '12px', padding: '2.5rem', textAlign: 'center',
          background: isDragging ? 'rgba(59,130,246,0.05)' : 'rgba(255,255,255,0.02)',
          cursor: uploading ? 'wait' : 'pointer', transition: 'border 0.2s, background 0.2s'
        }}
      >
        <h3 style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--foreground)', marginBottom: '0.25rem' }}>
          {uploading ? 'Uploading...' : 'Drop the invoice photo here'}
        </h3>
        <p style={{ color: 'var(--muted-foreground)', fontSize: '0.8rem' }}>Fill in the fields above first, then drop or click to choose a file (PDF, JPG, PNG)</p>
      </div>

      <input ref={supportingDocInputRef} type="file" accept=".pdf,.jpg,.jpeg,.png" style={{ display: 'none' }} onChange={handleSupportingDocChange} />
    </div>
  );

  const StatusQueue = (
    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1.5rem', height: '100%' }}>
      <div>
        <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '0.5rem' }}>Filed invoices</h2>
        <p style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>Attach the stamped/signed receipt or Gate Entry Note as it comes back from the buyer.</p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', flex: 1, overflowY: 'auto' }}>
        {invoices.length === 0 ? (
          <div style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>No invoices yet.</div>
        ) : invoices.map((inv) => (
          <div key={inv.id} style={{ padding: '1rem', borderRadius: '8px', background: 'var(--muted)', border: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <div style={{ fontWeight: 500, fontSize: '0.875rem' }}>{inv.invoice_number}</div>
              <div style={{ fontSize: '0.75rem', color: 'var(--muted-foreground)' }}>{inv.invoice_series || ''}</div>
            </div>
            <button
              style={smallBtnStyle}
              onClick={() => { setAttachingTo(inv.id); supportingDocInputRef.current?.click(); }}
            >
              + Attach receipt
            </button>
          </div>
        ))}
      </div>
    </div>
  );

  return <DualPaneWorkspace leftPane={UploadPane} rightPane={StatusQueue} headerTitle="Ledger Filing" />;
}

const smallBtnStyle: React.CSSProperties = {
  fontSize: '0.78rem', padding: '0.45rem 0.8rem', borderRadius: '6px', border: 'none',
  background: 'linear-gradient(135deg, #a78bfa 0%, #8b5cf6 100%)', color: 'white', cursor: 'pointer', fontWeight: 600, whiteSpace: 'nowrap',
};
