// Report Viewer <-> host system (any web application that shows reports), with window.postMessage.
// The viewer runs in an iframe of the host page, or in a tab the host opened (window.open); see public/viewer.js.
//
//   host -> viewer                                              viewer -> host
//   reportviewer:init      { labels?, theme?, layout?, files? } reportviewer:ready     { version }
//   reportviewer:load      { content, format?, name?,           reportviewer:loaded    { name, warnings }
//                            data?: rows[] | { <source>: rows[] }, reportviewer:rendered  { pages }
//                            params?: { <name>: value } }       reportviewer:refresh   (the user clicked Refresh)
//   reportviewer:setData   { name, rows }                       reportviewer:error     { message }
//   reportviewer:setParams { values, refresh? }                 reportviewer:ok        (answer)
//   reportviewer:refresh   { reloadData? }                      reportviewer:file      { name, mime, action, size, base64 }
//   reportviewer:print     {}
//   reportviewer:export    { format: pdf|xlsx|docx|csv|html|png }
//   labels: the viewer's words by the host viewer's keys (rpt_print, rpt_of, …); theme: 'light' | 'dark';
//   layout: 'page' (one page at a time) | 'scroll' (all pages one after another);
//   files: 'browser' (default: exports are downloaded, Print opens the browser's print) | 'host' (every export, and
//   Print as a PDF, goes to the host as reportviewer:file - for apps whose web view cannot download or print, e.g. a
//   Flutter / Android / iOS web view; action = 'download' | 'print')
//
// Every request may carry a requestId; its answer (loaded / ok / error) repeats it.
// Only the page that opened the viewer is answered: ?origins=https://erp.example.com (comma list) or, without it,
// the embedding page (document.referrer) / the first page that talks to it.
import { reactive } from 'vue';
import type { Row } from '../model/types';
import type { OpenOptions } from './load';
import { hostLayout, setLabels, setTheme } from './labels';

export type ExportFormat = 'pdf' | 'xlsx' | 'docx' | 'csv' | 'html' | 'png';
export interface ViewerController {
  open(text: string, o: OpenOptions): Promise<{ name: string; warnings: string[] }>;
  setData(name: string | null, rows: Row[]): Promise<void>;
  setParams(values: Record<string, unknown>, refresh: boolean): Promise<void>;
  refresh(reloadData: boolean): Promise<void>;
  print(): Promise<void>;
  exportAs(format: ExportFormat): Promise<void>;
}

export const viewerHost = reactive({ active: false, files: 'browser' as 'browser' | 'host' });

/** a file for the host: 'download' (an export, the copy-as-image fallback) or 'print' (Print, as a PDF) */
export type FileAction = 'download' | 'print';

/**
 * Hands a file to the host application when it asked for files ('host'): true = sent, false = the browser keeps
 * doing it itself (download / print). The bytes go as base64 so any host can take them, a web view's JavaScript
 * channel included.
 */
export async function deliverFile(blob: Blob, name: string, action: FileAction): Promise<boolean> {
  if (!viewerHost.active || viewerHost.files !== 'host' || !target || !targetOrigin) return false;
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result ?? ''));
    r.onerror = () => reject(r.error ?? new Error('The file could not be read.'));
    r.readAsDataURL(blob);
  });
  const base64 = dataUrl.slice(dataUrl.indexOf(',') + 1);
  target.postMessage({ type: 'reportviewer:file', name, mime: blob.type || 'application/octet-stream', action, size: blob.size, base64 }, targetOrigin);
  return true;
}

let target: Window | null = null;
let targetOrigin = '';
let allowed: string[] = [];
let ctl: ViewerController | null = null;

export function setController(c: ViewerController) {
  ctl = c;
}

export function notifyHost(type: string, data: Record<string, unknown> = {}) {
  if (!target) return;
  // plain data only (reactive objects cannot be copied by postMessage)
  const plain = JSON.parse(JSON.stringify({ type: 'reportviewer:' + type, ...data }));
  // before the host has spoken, only the harmless "ready" may go out without a known origin
  if (!targetOrigin && type !== 'ready') return;
  target.postMessage(plain, targetOrigin || '*');
}

/** Hosted mode when the page was opened with ?embed=1 by another page (iframe parent or window.opener). */
export function initViewerHost(): boolean {
  const p = new URLSearchParams(location.search);
  const flag = p.get('embed');
  if (flag === null || flag === '0' || flag === 'false') return false;
  target = window.parent !== window ? window.parent : (window.opener as Window | null);
  if (!target) return false;
  viewerHost.active = true;
  allowed = (p.get('origins') ?? '')
    .split(',')
    .map((s) => s.trim().replace(/\/$/, ''))
    .filter(Boolean);
  try {
    targetOrigin = allowed.length === 1 ? allowed[0] : allowed.length === 0 && document.referrer ? new URL(document.referrer).origin : '';
  } catch {
    targetOrigin = '';
  }
  window.addEventListener('message', (e) => void onMessage(e));
  notifyHost('ready', { version: 1 });
  return true;
}

const FORMATS: ExportFormat[] = ['pdf', 'xlsx', 'docx', 'csv', 'html', 'png'];

async function onMessage(e: MessageEvent) {
  if (!target || e.source !== target) return;
  if (allowed.length && !allowed.includes(e.origin)) return;
  if (!allowed.length && targetOrigin && e.origin !== targetOrigin) return;
  const m = e.data as Record<string, any>;
  if (!m || typeof m.type !== 'string' || !m.type.startsWith('reportviewer:')) return;
  if (!targetOrigin) targetOrigin = e.origin;
  const requestId = m.requestId;
  const reply = (t: string, data: Record<string, unknown> = {}) => notifyHost(t, { ...data, requestId });
  if (!ctl) return reply('error', { message: 'The viewer is still starting.' });
  try {
    // words, theme and page layout may come with any message (init, load); the application's layout is a default,
    // the user's own choice (toolbar) is not overwritten in their browser
    setLabels(m.labels);
    setTheme(m.theme);
    hostLayout(m.layout);
    if (m.files === 'host' || m.files === 'browser') viewerHost.files = m.files;
    switch (m.type.slice('reportviewer:'.length)) {
      case 'init':
        reply('ok');
        break;
      case 'load': {
        const content = typeof m.content === 'string' ? m.content : JSON.stringify(m.content);
        const r = await ctl.open(content, { name: m.name, format: m.format, data: m.data, params: m.params });
        reply('loaded', r);
        break;
      }
      case 'setData':
        if (!Array.isArray(m.rows)) throw new Error('setData needs a list of rows.');
        await ctl.setData(m.name ? String(m.name) : null, m.rows);
        reply('ok', { rows: m.rows.length });
        break;
      case 'setParams':
        await ctl.setParams(m.values && typeof m.values === 'object' ? m.values : {}, m.refresh !== false);
        reply('ok');
        break;
      case 'refresh':
        await ctl.refresh(!!m.reloadData);
        reply('ok');
        break;
      case 'print':
        await ctl.print();
        reply('ok');
        break;
      case 'export': {
        const f = String(m.format ?? 'pdf').toLowerCase() as ExportFormat;
        if (!FORMATS.includes(f)) throw new Error('Export format must be one of: ' + FORMATS.join(', '));
        await ctl.exportAs(f);
        reply('ok');
        break;
      }
      default:
        reply('error', { message: 'Unknown message ' + m.type });
    }
  } catch (err) {
    reply('error', { message: (err as Error).message });
  }
}
