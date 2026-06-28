// Shared client-side auth helpers. Tokens live in localStorage and are attached
// as Authorization: Bearer <token> on every API call -- the backend trusts
// nothing else (no X-Tenant-ID header, no client-submitted role).
"use client";

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';

export const API_BASE = 'http://localhost:8000/api/v1';

export interface AuthUser {
  id: string;
  email: string;
  full_name: string;
  role: 'ADMIN' | 'WORKER' | 'MANAGER' | 'FINANCE';
  organization_id: string;
}

const TOKEN_KEY = 'invoice_saas_token';
const USER_KEY = 'invoice_saas_user';

export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function getUser(): AuthUser | null {
  if (typeof window === 'undefined') return null;
  const raw = localStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as AuthUser;
  } catch {
    return null;
  }
}

export function setSession(token: string, user: AuthUser) {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export function dashboardPathForRole(role: string): string {
  switch (role) {
    case 'ADMIN':
      return '/dashboard/admin';
    case 'WORKER':
      return '/dashboard/worker';
    case 'MANAGER':
    case 'FINANCE':
      return '/dashboard/reviewer';
    default:
      return '/login';
  }
}

export async function login(email: string, password: string): Promise<AuthUser> {
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error || 'Login failed');
  }
  setSession(data.token, data.user);
  return data.user;
}

export function logout() {
  clearSession();
  window.location.href = '/login';
}

// useRequireAuth redirects to /login if there's no session, and returns the
// current user once known (null while that check is still in flight).
export function useRequireAuth(): AuthUser | null {
  const router = useRouter();
  const [user, setUser] = useState<AuthUser | null>(null);

  useEffect(() => {
    const u = getUser();
    const token = getToken();
    if (!u || !token) {
      router.push('/login');
      return;
    }
    setUser(u);
  }, [router]);

  return user;
}

// authFetch attaches the bearer token automatically and redirects to /login on 401.
export async function authFetch(path: string, options: RequestInit = {}): Promise<Response> {
  const token = getToken();
  const headers = new Headers(options.headers || {});
  if (token) headers.set('Authorization', `Bearer ${token}`);
  // FormData needs the browser to set its own multipart boundary in
  // Content-Type -- setting it ourselves would break upload parsing.
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  if (res.status === 401) {
    clearSession();
    window.location.href = '/login';
  }
  return res;
}
