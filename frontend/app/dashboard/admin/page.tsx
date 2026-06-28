"use client";

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import DualPaneWorkspace from '../../../components/DualPaneWorkspace';
import { API_BASE } from '../../../lib/auth';

interface SeededUser {
  email: string;
  role: string;
}

interface SeedResult {
  organization_id: string;
  entity_id: string;
  vendor_id: string;
  users: SeededUser[];
  demo_password: string;
  message: string;
}

export default function AdminDashboard() {
  const router = useRouter();
  const [seedResult, setSeedResult] = useState<SeedResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSeeding, setIsSeeding] = useState(false);

  // Seeding is intentionally unauthenticated -- it's how the very first
  // organization and users get created. There's no token to attach yet.
  const handleSeed = async () => {
    setIsSeeding(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/admin/seed`, { method: 'POST' });
      const data = await res.json();
      if (res.ok) {
        setSeedResult(data);
      } else {
        setError(data.error || 'Seed failed');
      }
    } catch (err) {
      setError('Could not reach the API server.');
    } finally {
      setIsSeeding(false);
    }
  };

  const InfoPane = (
    <div style={{ width: '100%', height: '100%', padding: '3rem', display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 600 }}>System Configuration</h2>
      <p style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem', lineHeight: 1.6 }}>
        Seeding creates a demo Organization, a legal Entity (GSTIN 27AAAAA1111A1Z1), a
        Vendor (GSTIN 27BBBBB2222B2Z2), and one login per role (Admin/Worker/Manager/Finance).
        Run this first on a fresh database.
      </p>
      <button
        onClick={handleSeed}
        disabled={isSeeding}
        style={{ alignSelf: 'flex-start', padding: '0.75rem 1.5rem', borderRadius: '6px', border: 'none', background: 'linear-gradient(135deg, #a78bfa 0%, #8b5cf6 100%)', color: 'white', cursor: 'pointer', fontWeight: 600 }}
      >
        {isSeeding ? 'Seeding...' : 'Seed Database'}
      </button>
      {error && <div style={{ color: '#ef4444', fontSize: '0.875rem' }}>{error}</div>}
    </div>
  );

  const ResultPane = (
    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 600 }}>Seeded Tenant</h2>
      {seedResult ? (
        <>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', fontFamily: 'monospace', fontSize: '0.75rem' }}>
            <div><strong>organization_id:</strong> {seedResult.organization_id}</div>
            <div><strong>entity_id:</strong> {seedResult.entity_id}</div>
            <div><strong>vendor_id:</strong> {seedResult.vendor_id}</div>
          </div>

          <div style={{ marginTop: '1rem' }}>
            <div style={{ fontWeight: 600, marginBottom: '0.5rem' }}>Demo logins (password: <code>{seedResult.demo_password}</code>)</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
              {seedResult.users.map((u) => (
                <div key={u.email} style={{ fontFamily: 'monospace', fontSize: '0.8rem', display: 'flex', justifyContent: 'space-between', background: 'var(--muted)', padding: '0.5rem 0.75rem', borderRadius: '6px' }}>
                  <span>{u.email}</span>
                  <span style={{ color: 'var(--muted-foreground)' }}>{u.role}</span>
                </div>
              ))}
            </div>
          </div>

          <button
            onClick={() => router.push('/login')}
            style={{ marginTop: '1rem', alignSelf: 'flex-start', padding: '0.6rem 1.25rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--foreground)', cursor: 'pointer', fontWeight: 500 }}
          >
            Go to Login →
          </button>
        </>
      ) : (
        <div style={{ color: 'var(--muted-foreground)', fontSize: '0.875rem' }}>No seed run yet this session.</div>
      )}
    </div>
  );

  return <DualPaneWorkspace leftPane={InfoPane} rightPane={ResultPane} headerTitle="Admin Workspace" />;
}
