"use client";

import React from 'react';
import styles from './DualPaneWorkspace.module.css';
import { logout, getUser } from '../lib/auth';

interface DualPaneWorkspaceProps {
  leftPane: React.ReactNode;
  rightPane: React.ReactNode;
  headerTitle: string;
}

export default function DualPaneWorkspace({ leftPane, rightPane, headerTitle }: DualPaneWorkspaceProps) {
  const user = typeof window !== 'undefined' ? getUser() : null;

  return (
    <div className={styles.workspaceContainer}>
      <header className={styles.header}>
        <div className={styles.logo}>InvoiceSaaS <span className={styles.roleTag}>| {headerTitle}</span></div>
        <div className={styles.userMenu} style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          {user && (
            <span style={{ fontSize: '0.8rem', color: 'var(--muted-foreground)' }}>{user.email}</span>
          )}
          {user && (
            <button
              onClick={logout}
              style={{ fontSize: '0.8rem', padding: '0.4rem 0.8rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--foreground)', cursor: 'pointer' }}
            >
              Log out
            </button>
          )}
          <div className={styles.avatar}></div>
        </div>
      </header>

      <div className={styles.panesWrapper}>
        <div className={styles.leftPane}>
          {leftPane}
        </div>

        <div className={styles.resizer}></div>

        <div className={styles.rightPane}>
          {rightPane}
        </div>
      </div>
    </div>
  );
}
