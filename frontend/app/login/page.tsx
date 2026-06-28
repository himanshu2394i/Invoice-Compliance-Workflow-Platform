"use client";

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import styles from './login.module.css';
import { login, dashboardPathForRole } from '../../lib/auth';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const user = await login(email, password);
      router.push(dashboardPathForRole(user.role));
    } catch (err: any) {
      setError(err.message || 'Login failed');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.ambientOrb1}></div>
      <div className={styles.ambientOrb2}></div>

      <div className={styles.glassCard}>
        <div className={styles.header}>
          <h1 className={styles.logo}>InvoiceSaaS</h1>
          <p className={styles.subtitle}>Sign in to continue</p>
        </div>

        <form className={styles.form} onSubmit={handleSubmit}>
          <div className={styles.field}>
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="manager@demo.local"
              required
              autoFocus
            />
          </div>
          <div className={styles.field}>
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
            />
          </div>

          {error && <div className={styles.errorBox}>{error}</div>}

          <button className={styles.submitBtn} type="submit" disabled={submitting}>
            {submitting ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <div className={styles.footerNote}>
          No account yet? <Link href="/dashboard/admin">Seed a demo organization</Link> to get one.
        </div>
      </div>
    </div>
  );
}
