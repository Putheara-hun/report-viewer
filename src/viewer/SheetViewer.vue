<script setup lang="ts">
import { computed, markRaw, nextTick, onBeforeUnmount, onMounted, reactive, ref, shallowRef, toRaw, watch } from 'vue';
import type { RenderedDoc } from '../engine/doc';
import { paramValues, renderReport } from '../engine/renderer';
import { ensureReportFonts } from '../engine/fonts';
import { pageToSvg } from '../export/svg';
import type { Row } from '../model/types';
import { dataErrors, ensureData, isStaleVersionError, rowsFor, state } from '../store/designer';
import { labels, prefs, setLayout } from './labels';
import { deliverFile, viewerHost, type FileAction } from './host';
const emit = defineEmits<{ rendered: [pages: number]; failed: [message: string]; refresh: [] }>();
const L = labels;
const doc = shallowRef<RenderedDoc | null>(null);
const busy = ref(false);
const error = ref('');
const root = ref<HTMLElement>();
const body = ref<HTMLElement>();
const viewH = ref(600);
const scrollTop = ref(0);
const isScroll = computed(() => prefs.layout === 'scroll');
/** a phone (or any narrow frame): a short toolbar with a "more" menu, pages fitted to the width */
const COMPACT_BELOW = 640;
const compact = ref(false);
const GAP = 18;
const pad = computed(() => (compact.value ? 8 : 20));
const ZMIN = 25;
const ZMAX = 200;
const zoom = ref(100);
const scale = computed(() => zoom.value / 100);
/** the zoom follows the width of the view (Fit to width); any zoom the user picks ends it */
const fit = ref(false);
let userZoomed = false;
function setZoom(v: string | number) {
  fit.value = false;
  userZoomed = true;
  zoom.value = Math.min(ZMAX, Math.max(ZMIN, Math.trunc(Number(v)) || 100));
}
const zoomBy = (d: number) => setZoom(Math.round((zoom.value + d) / 5) * 5);
function applyFit() {
  const el = body.value;
  const pages = doc.value?.pages;
  if (!fit.value || !el || !pages?.length) return;
  const widest = pages.reduce((w, p) => Math.max(w, p.width), 0);
  const avail = el.clientWidth - 2 * pad.value - 2; // the sheet's border
  if (widest > 0 && avail > 0) zoom.value = Math.min(ZMAX, Math.max(ZMIN, Math.floor((avail / widest) * 100)));
}
function toggleFit() {
  fit.value = !fit.value;
  if (fit.value) applyFit();
  else setZoom(100);
}
watch([doc, pad], applyFit);
const tops = computed(() => {
  const out: number[] = [];
  let y = pad.value;
  for (const p of doc.value?.pages ?? []) {
    out.push(y);
    y += p.height * scale.value + GAP;
  }
  return out;
});
const page = ref(1);
const totalPages = computed(() => Math.max(1, doc.value?.pages.length ?? 1));
function goTo(n: number, y = 0) {
  const t = Math.min(Math.max(1, Math.trunc(n) || 1), totalPages.value);
  page.value = t;
  void nextTick(() => {
    const el = body.value;
    if (!el) return;
    const focus = y ? y * scale.value - viewH.value / 3 : -10;
    el.scrollTop = Math.max(0, (isScroll.value ? tops.value[t - 1] ?? 0 : 0) + focus);
    updateRest(); 
  });
}
const goFirst = () => goTo(1);
const goPrev = () => goTo(page.value - 1);
const goNext = () => goTo(page.value + 1);
const goLast = () => goTo(totalPages.value);
watch(totalPages, () => {
  if (page.value > totalPages.value) page.value = totalPages.value;
});
/* A zoom that keeps a point of the page where it is on the screen (the point between the fingers, under the mouse,
   the one tapped twice): anchor = that point in the content at the old zoom (x, y: scroll + view point) and where it
   must be in the view (fx, fy). Any other zoom or layout change keeps the page the user is on. */
let anchor: { x: number; y: number; fx: number; fy: number } | null = null;
watch([isScroll, scale], ([s, sc], [s0, sc0]) => {
  const el = body.value;
  const a = anchor;
  anchor = null;
  if (el && a && s === s0 && sc0) {
    const k = sc / sc0;
    const p = pad.value;
    void nextTick(() => {
      el.scrollLeft = Math.max(0, (a.x - p) * k + p - a.fx);
      el.scrollTop = Math.max(0, (a.y - p) * k + p - a.fy);
      updateRest();
    });
    return;
  }
  goTo(page.value);
});
/** zoom to z keeping the content point at (fx0, fy0) of the view where it is, or moving it to (fx, fy) */
function zoomAt(z: number, fx0: number, fy0: number, fx = fx0, fy = fy0) {
  const el = body.value;
  const target = Math.min(ZMAX, Math.max(ZMIN, Math.round(z)));
  if (!el) return setZoom(target);
  const a = { x: el.scrollLeft + fx0, y: el.scrollTop + fy0, fx, fy };
  if (target === zoom.value) {
    // the same zoom: only the move
    el.scrollLeft = Math.max(0, a.x - fx);
    el.scrollTop = Math.max(0, a.y - fy);
    return;
  }
  anchor = a;
  setZoom(target);
}
const viewPoint = (clientX: number, clientY: number) => {
  const r = body.value?.getBoundingClientRect();
  return r ? { x: clientX - r.left, y: clientY - r.top } : { x: 0, y: 0 };
};

/* ---- live zoom: while two fingers pinch (or a touchpad pinches / Ctrl + wheel turns) the pages are only scaled on
   screen - smooth, nothing is drawn again; when the hand stops the zoom is applied and the pages are drawn sharp */
const live = reactive({ s: 1, tx: 0, ty: 0, ox: 0, oy: 0 });
let liveStart: { z: number; fx: number; fy: number } | null = null;
const pagesStyle = computed(() =>
  live.s === 1 && !live.tx && !live.ty
    ? undefined
    : { transform: `translate(${live.tx}px, ${live.ty}px) scale(${live.s})`, transformOrigin: `${live.ox}px ${live.oy}px`, willChange: 'transform' },
);
function liveBegin(fx: number, fy: number) {
  const el = body.value;
  if (!el) return;
  stopGlide();
  liveStart = { z: zoom.value, fx, fy };
  // the scaling turns round the point under the fingers / the mouse (pages' own coordinates)
  live.ox = el.scrollLeft + fx - pad.value;
  live.oy = el.scrollTop + fy - pad.value;
  live.s = 1;
  live.tx = live.ty = 0;
}
function liveUpdate(s: number, fx: number, fy: number) {
  const st = liveStart;
  if (!st) return;
  live.s = Math.min(ZMAX / st.z, Math.max(ZMIN / st.z, s));
  live.tx = fx - st.fx;
  live.ty = fy - st.fy;
}
function liveEnd() {
  const st = liveStart;
  liveStart = null;
  if (!st) return;
  const z = st.z * live.s;
  const fx = st.fx + live.tx;
  const fy = st.fy + live.ty;
  live.s = 1;
  live.tx = live.ty = 0;
  zoomAt(z, st.fx, st.fy, fx, fy);
}

// ---- touch: two fingers zoom (live), a double tap zooms in / back, a long press opens the copy menu
let pinchD = 0;
let press: { x: number; y: number; t: number; target: Element | null } | null = null;
let pressTimer = 0;
const fingers = (t: TouchList) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
const midpoint = (t: TouchList) => viewPoint((t[0].clientX + t[1].clientX) / 2, (t[0].clientY + t[1].clientY) / 2);
function cancelPress() {
  clearTimeout(pressTimer);
  press = null;
}
function onTouchStart(e: TouchEvent) {
  stopGlide();
  if (e.touches.length === 2) {
    cancelPress();
    pinchD = fingers(e.touches) || 1;
    const m = midpoint(e.touches);
    liveBegin(m.x, m.y);
  } else if (e.touches.length === 1) {
    const t = e.touches[0];
    press = { x: t.clientX, y: t.clientY, t: Date.now(), target: e.target as Element | null };
    clearTimeout(pressTimer);
    pressTimer = window.setTimeout(() => {
      if (press) openMenu(press.target, press.x, press.y);
      press = null;
    }, 550);
  }
}
function onTouchMove(e: TouchEvent) {
  if (liveStart && e.touches.length === 2) {
    e.preventDefault();
    const m = midpoint(e.touches);
    liveUpdate(fingers(e.touches) / pinchD, m.x, m.y);
  } else if (press) {
    const t = e.touches[0];
    if (!t || Math.hypot(t.clientX - press.x, t.clientY - press.y) > 10) cancelPress();
  }
}
function onTouchEnd(e: TouchEvent) {
  if (e.touches.length < 2 && liveStart) liveEnd();
  // a short touch that did not move: a tap (two quick taps zoom)
  if (press && Date.now() - press.t < 300) tapped(press.x, press.y);
  cancelPress();
}

/* ---- two quick taps / a double click: zoom in there; again: back to the page width (a phone) or 100% */
let lastTap: { x: number; y: number; t: number } | null = null;
function tapped(clientX: number, clientY: number) {
  const now = Date.now();
  const prev = lastTap;
  if (prev && now - prev.t < 320 && Math.hypot(clientX - prev.x, clientY - prev.y) < 30) {
    lastTap = null;
    const f = viewPoint(clientX, clientY);
    const zoomedIn = fit.value ? false : zoom.value >= (compact.value ? 90 : 150);
    if (!zoomedIn) zoomAt(Math.min(ZMAX, Math.max(zoom.value * 2, 100)), f.x, f.y);
    else if (compact.value) {
      fit.value = true;
      applyFit();
    } else setZoom(100);
    return;
  }
  lastTap = { x: clientX, y: clientY, t: now };
}

/* ---- the hand: with the mouse, press on the pages and drag them (faster than the scroll bars); let go while moving
   and they glide on and slow down. (Fingers scroll by themselves.) Copying stays on the right-click menu. */
const dragging = ref(false);
let drag: { x: number; y: number; left: number; top: number; moved: boolean; vx: number; vy: number; lx: number; ly: number; lt: number } | null = null;
let glideRaf = 0;
function stopGlide() {
  cancelAnimationFrame(glideRaf);
  glideRaf = 0;
}
function onPointerDown(e: PointerEvent) {
  if (e.pointerType !== 'mouse' || e.button !== 0) return;
  const el = body.value;
  if (!el || (e.target as Element | null)?.closest?.('input, textarea, select, button, a')) return;
  stopGlide();
  e.preventDefault(); // the page moves, no text is selected
  window.focus(); // the arrow keys still turn the pages
  drag = { x: e.clientX, y: e.clientY, left: el.scrollLeft, top: el.scrollTop, moved: false, vx: 0, vy: 0, lx: e.clientX, ly: e.clientY, lt: performance.now() };
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);
  window.addEventListener('pointercancel', onPointerUp);
}
function onPointerMove(e: PointerEvent) {
  const d = drag;
  const el = body.value;
  if (!d || !el) return;
  const dx = e.clientX - d.x;
  const dy = e.clientY - d.y;
  if (!d.moved && Math.hypot(dx, dy) < 3) return;
  d.moved = true;
  dragging.value = true;
  el.scrollLeft = d.left - dx;
  el.scrollTop = d.top - dy;
  // the speed of the last moves (px per ms), for the glide
  const now = performance.now();
  const dt = Math.max(1, now - d.lt);
  d.vx = 0.7 * ((d.lx - e.clientX) / dt) + 0.3 * d.vx;
  d.vy = 0.7 * ((d.ly - e.clientY) / dt) + 0.3 * d.vy;
  d.lx = e.clientX;
  d.ly = e.clientY;
  d.lt = now;
}
function onPointerUp(e: PointerEvent) {
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
  window.removeEventListener('pointercancel', onPointerUp);
  const d = drag;
  drag = null;
  dragging.value = false;
  if (!d) return;
  if (!d.moved) {
    if (e.type === 'pointerup') tapped(e.clientX, e.clientY); // a click (two quick ones zoom)
    return;
  }
  if (performance.now() - d.lt > 80) return; // the mouse had stopped before it was let go
  let vx = d.vx;
  let vy = d.vy;
  let last = performance.now();
  const step = (now: number) => {
    const el = body.value;
    if (!el) return;
    const dt = Math.min(40, now - last);
    last = now;
    el.scrollLeft += vx * dt;
    el.scrollTop += vy * dt;
    const k = Math.pow(0.994, dt);
    vx *= k;
    vy *= k;
    glideRaf = Math.hypot(vx, vy) > 0.02 ? requestAnimationFrame(step) : 0;
  };
  glideRaf = requestAnimationFrame(step);
}

let restAtBottom = false;
let restAtTop = true;
let restTimer = 0;
function updateRest() {
  const el = body.value;
  if (!el) return;
  restAtBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 2;
  restAtTop = el.scrollTop <= 0;
}
function onScroll() {
  const el = body.value;
  if (!el) return;
  scrollTop.value = el.scrollTop;
  menu.value = null;
  restAtBottom = restAtTop = false;
  clearTimeout(restTimer);
  restTimer = window.setTimeout(updateRest, 150);
  if (!isScroll.value) return;
  // the page that fills the upper third of the view
  const probe = el.scrollTop + viewH.value / 3;
  let lo = 0;
  let hi = tops.value.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (tops.value[mid] <= probe) lo = mid;
    else hi = mid - 1;
  }
  page.value = lo + 1;
}
/** one page at a time: scrolling on past the end of a page opens the next one (past the top: the previous one) */
let lastFlip = 0;
let wheelTimer = 0;
function onWheel(e: WheelEvent) {
  menu.value = null;
  stopGlide();
  const el = body.value;
  if (!el) return;
  // a touchpad pinch (the browser sends it as Ctrl + wheel) or Ctrl + the mouse wheel: zoom round the mouse - live,
  // applied when the wheel stops
  if (e.ctrlKey) {
    e.preventDefault();
    const f = viewPoint(e.clientX, e.clientY);
    if (!liveStart) liveBegin(f.x, f.y);
    const dy = e.deltaMode === 1 ? e.deltaY * 33 : e.deltaY;
    const k = Math.abs(dy) >= 40 ? (dy < 0 ? 1.12 : 1 / 1.12) : Math.exp(-dy * 0.01);
    liveUpdate(live.s * k, f.x, f.y);
    clearTimeout(wheelTimer);
    wheelTimer = window.setTimeout(liveEnd, 180);
    return;
  }
  if (isScroll.value) return;
  const now = Date.now();
  if (now - lastFlip < 450) return;
  if (e.deltaY > 0 && restAtBottom && page.value < totalPages.value) {
    lastFlip = now;
    goTo(page.value + 1);
  } else if (e.deltaY < 0 && restAtTop && page.value > 1) {
    lastFlip = now;
    page.value--;
    void nextTick(() => {
      if (body.value) body.value.scrollTop = body.value.scrollHeight;
      updateRest();
    });
  }
}
/** continuous layout: only pages near the view are drawn */
const near = (i: number) => {
  const t = tops.value[i] ?? 0;
  const h = (doc.value?.pages[i]?.height ?? 0) * scale.value;
  return t < scrollTop.value + viewH.value * 2 && t + h > scrollTop.value - viewH.value;
};

/** "12 records": the rows of the report's main data source */
const recordCount = computed(() => (state.report.dataSourceId ? rowsFor(state.report.dataSourceId).length : -1));
const recordsText = computed(() => `${recordCount.value} ${recordCount.value === 1 ? L.rpt_record : L.rpt_records}`);

// ---- find in report (every page)
const findOpen = ref(false);
const find = ref('');
const hitIdx = ref(0);
const findInput = ref<HTMLInputElement>();
const hits = computed(() => {
  const q = find.value.trim().toLowerCase();
  const out: { page: number; x: number; y: number; w: number; h: number }[] = [];
  if (!q || !doc.value) return out;
  doc.value.pages.forEach((p, pi) => {
    for (const pr of p.prims) if (pr.k === 'text' && pr.text.toLowerCase().includes(q)) out.push({ page: pi, x: pr.x, y: pr.y, w: pr.w, h: pr.h });
  });
  return out;
});
const findCountText = computed(() =>
  hits.value.length ? L.rpt_hit_of.replace('{a}', String(hitIdx.value + 1)).replace('{b}', String(hits.value.length)) : find.value.trim() ? L.rpt_no_matches : '',
);
function jumpToHit() {
  const h = hits.value[hitIdx.value];
  if (h) goTo(h.page + 1, h.y);
}
const nextHit = () => {
  if (!hits.value.length) return;
  hitIdx.value = (hitIdx.value + 1) % hits.value.length;
  jumpToHit();
};
const prevHit = () => {
  if (!hits.value.length) return;
  hitIdx.value = (hitIdx.value - 1 + hits.value.length) % hits.value.length;
  jumpToHit();
};
watch(find, () => {
  hitIdx.value = 0;
  jumpToHit();
});
function toggleFind() {
  findOpen.value = !findOpen.value;
  if (!findOpen.value) find.value = '';
  else setTimeout(() => findInput.value?.focus(), 0);
}

// ---- drawing: a page as SVG (lines on whole screen pixels at this zoom), cached
const svgCache = new Map<number, string>();
watch([doc, scale, hits, hitIdx], () => svgCache.clear());
function svgOf(i: number) {
  let s = svgCache.get(i);
  const p = doc.value?.pages[i];
  if (s === undefined && p) {
    const hl = hits.value.filter((h) => h.page === i).map((h) => ({ ...h, active: hits.value[hitIdx.value] === h }));
    s = pageToSvg(p, { highlights: hl, scale: scale.value, pixelScale: scale.value * (window.devicePixelRatio || 1) });
    svgCache.set(i, s);
  }
  return s ?? '';
}
const sizeOf = (i: number) => {
  const p = doc.value?.pages[i];
  return { width: (p?.width ?? 0) * scale.value + 'px', height: (p?.height ?? 0) * scale.value + 'px' };
};

/** the drawing under way: Print and Export wait for it (a host may ask for them right after loading the report) */
let drawing: Promise<void> = Promise.resolve();
function generate(reloadData = false) {
  drawing = draw(reloadData);
  return drawing;
}
async function draw(reloadData: boolean) {
  busy.value = true;
  error.value = '';
  try {
    await ensureData(reloadData);
    await ensureReportFonts(state.report); // web fonts must be loaded before text is measured
    await new Promise((r) => setTimeout(r, 10));
    const data: Record<string, Row[]> = {};
    for (const ds of state.report.dataSources) data[ds.id] = rowsFor(ds.id);
    const d = renderReport({ report: toRaw(state.report), data, params: paramValues(state.report, toRaw(state.paramValues)) });
    doc.value = markRaw(d);
    if (page.value > d.pages.length) page.value = Math.max(1, d.pages.length);
    void nextTick(updateRest);
    emit('rendered', d.pages.length);
  } catch (e) {
    error.value = (e as Error).message;
    emit('failed', error.value);
  } finally {
    busy.value = false;
  }
}
function refresh() {
  find.value = '';
  hitIdx.value = 0;
  goTo(1);
  emit('refresh'); // the application may send fresh rows
  void generate(true);
}

// ---- copy: right-click a page
interface TextBox {
  x: number;
  y: number;
  w: number;
  h: number;
  text: string;
}
/** the text boxes of a page (one per value / label), empty ones left out */
function boxesOf(pi: number): TextBox[] {
  const p = doc.value?.pages[pi];
  if (!p) return [];
  const src: TextBox[] = p.cells?.length ? p.cells : p.prims.filter((x): x is Extract<typeof x, { k: 'text' }> => x.k === 'text');
  return src.filter((b) => String(b.text ?? '').trim() !== '').map((b) => ({ x: b.x, y: b.y, w: b.w, h: b.h, text: String(b.text) }));
}
const centre = (b: TextBox) => b.y + b.h / 2;
const sameLine = (a: TextBox, b: TextBox) => (centre(b) >= a.y && centre(b) <= a.y + a.h) || (centre(a) >= b.y && centre(a) <= b.y + b.h);
/** boxes grouped into lines (top to bottom), each line left to right */
function linesOf(boxes: TextBox[]): TextBox[][] {
  const lines: TextBox[][] = [];
  for (const b of [...boxes].sort((a, c) => centre(a) - centre(c) || a.x - c.x)) {
    const line = lines[lines.length - 1];
    if (line && sameLine(line[0], b)) line.push(b);
    else lines.push([b]);
  }
  return lines.map((l) => l.sort((a, c) => a.x - c.x));
}
/** a line as tab-separated values: pasted into Excel each value gets its own column */
const lineText = (l: TextBox[]) => l.map((b) => b.text.replace(/\s*\n\s*/g, ' ')).join('\t');
const pageText = (pi: number) => linesOf(boxesOf(pi)).map(lineText).join('\n');
const allText = () => (doc.value?.pages ?? []).map((_, i) => pageText(i)).join('\n\n');

const menu = ref<null | { x: number; y: number; page: number; value: string; row: string; sel: string }>(null);
/** the copy menu for the point (clientX, clientY) of a page; false = not on a page */
function openMenu(target: Element | null, clientX: number, clientY: number): boolean {
  const el = target?.closest?.('.rv-sheet') as HTMLElement | null;
  if (!el || !doc.value) return false;
  const pi = Number(el.dataset.page);
  const r = el.getBoundingClientRect();
  const x = (clientX - r.left) / scale.value;
  const y = (clientY - r.top) / scale.value;
  const boxes = boxesOf(pi);
  const hit = boxes.find((b) => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h);
  const line = hit ? linesOf(boxes).find((l) => l.includes(hit)) : undefined;
  menu.value = {
    x: Math.max(4, Math.min(clientX, window.innerWidth - 240)),
    y: Math.max(4, Math.min(clientY, window.innerHeight - 270)),
    page: pi,
    value: hit?.text ?? '',
    row: line ? lineText(line) : '',
    sel: String(window.getSelection() ?? '').trim(),
  };
  return true;
}
function onMenu(e: MouseEvent) {
  // the browser's own menu outside the pages
  if (openMenu(e.target as Element | null, e.clientX, e.clientY)) e.preventDefault();
}
const short = (s: string) => (s.length > 28 ? s.slice(0, 27) + '…' : s);
/** the note in the toolbar after copying ("Copied", "Image copied …"); empty = hidden */
const copied = ref('');
let copiedTimer = 0;
function note(text: string, ms = 1600) {
  copied.value = text;
  clearTimeout(copiedTimer);
  if (ms) copiedTimer = window.setTimeout(() => (copied.value = ''), ms);
}

/**
 * The page as a picture on the clipboard (twice the screen size: sharp when pasted into a chat, Word or an email).
 * The PNG is handed to the clipboard as a promise, so the copy starts inside the click — browsers allow it only
 * then. Where images cannot be put on the clipboard, the picture is downloaded instead.
 */
async function copyImage(pi: number) {
  menu.value = null;
  const p = doc.value?.pages[pi];
  if (!p) return;
  note(L.rpt_copying, 0);
  const ex = import('../export');
  const png = ex.then((m) => m.pageToPng(p, 2));
  try {
    await navigator.clipboard.write([new ClipboardItem({ 'image/png': png })]);
    note(L.rpt_copied_image, 2600);
  } catch {
    try {
      const m = await ex;
      await save(await png, `${m.safeFileName(state.report.name)}_page${pi + 1}.png`);
      note(L.rpt_image_saved, 3500);
    } catch (e) {
      note('');
      error.value = viewerError(e);
    }
  }
}

async function copy(text: string) {
  menu.value = null;
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // no clipboard permission (e.g. an iframe without allow="clipboard-write"): the classic way
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
  note(L.rpt_copied);
}

// ---- export / print
const exportOpen = ref(false);
const exportRoot = ref<HTMLElement>();
const moreOpen = ref(false);
const moreRoot = ref<HTMLElement>();
const menuEl = ref<HTMLElement>();
const onDocPointer = (e: PointerEvent) => {
  if (exportRoot.value && !exportRoot.value.contains(e.target as Node)) exportOpen.value = false;
  if (moreRoot.value && !moreRoot.value.contains(e.target as Node)) moreOpen.value = false;
  if (menuEl.value && !menuEl.value.contains(e.target as Node)) menu.value = null;
};
/** a choice in the phone's "more" menu: the menu closes first */
function fromMore(run: () => unknown) {
  moreOpen.value = false;
  void run();
}
/** a file made here: to the host application when it takes the files (a phone app's web view), else downloaded */
async function save(blob: Blob, name: string, action: FileAction = 'download') {
  if (await deliverFile(blob, name, action)) return;
  (await import('../export')).downloadBlob(blob, name);
}
async function exportAs(kind: 'pdf' | 'xlsx' | 'docx' | 'csv' | 'html' | 'png') {
  exportOpen.value = false;
  moreOpen.value = false;
  await drawing;
  if (!doc.value) return;
  busy.value = true;
  try {
    const ex = await import('../export');
    const base = ex.safeFileName(state.report.name);
    await new Promise((r) => setTimeout(r, 10));
    if (kind === 'pdf') await save(await ex.exportPdf(doc.value, state.report.name), base + '.pdf');
    else if (kind === 'xlsx') await save(await ex.exportXlsx(doc.value, state.report.name, { margins: state.report.page.margins }), base + '.xlsx');
    else if (kind === 'docx') await save(await ex.exportDocx(doc.value, state.report.name), base + '.docx');
    else if (kind === 'csv') await save(ex.exportCsv(doc.value), base + '.csv');
    else if (kind === 'html') await save(new Blob([ex.exportHtml(doc.value, state.report.name)], { type: 'text/html' }), base + '.html');
    else {
      const r = await ex.exportPng(doc.value, base);
      await save(r.blob, r.name);
    }
  } catch (e) {
    error.value = viewerError(e);
  } finally {
    busy.value = false;
  }
}
/** an error in plain words: "Failed to fetch dynamically imported module" = the site was updated while open */
function viewerError(e: unknown) {
  return isStaleVersionError(e) ? 'The Report Viewer was updated on the server while this page was open. Reload the page (F5) to export, print or copy.' : (e as Error).message;
}
async function print() {
  moreOpen.value = false;
  await drawing;
  if (!doc.value) return;
  try {
    const ex = await import('../export');
    // a web view of a phone app cannot print: the host gets the report as a PDF and prints it itself
    if (viewerHost.active && viewerHost.files === 'host') {
      busy.value = true;
      try {
        if (await deliverFile(await ex.exportPdf(doc.value, state.report.name), ex.safeFileName(state.report.name) + '.pdf', 'print')) return;
      } finally {
        busy.value = false;
      }
    }
    ex.printDoc(doc.value, state.report.name);
  } catch (e) {
    error.value = viewerError(e);
  }
}

// arrow keys / Page Up / Page Down turn pages (not while typing); Esc closes the copy menu
function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape' && menu.value) {
    menu.value = null;
    return;
  }
  const t = e.target as HTMLElement;
  if (t?.closest?.('input, textarea, select')) return;
  if (e.key === 'ArrowRight' || e.key === 'PageDown') goNext();
  else if (e.key === 'ArrowLeft' || e.key === 'PageUp') goPrev();
  else if (e.key === 'Home') goFirst();
  else if (e.key === 'End') goLast();
  else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'f') {
    e.preventDefault();
    if (!findOpen.value) toggleFind();
    else findInput.value?.focus();
  } else return;
}

let ro: ResizeObserver | null = null;
/** the size of the view: narrow = compact toolbar, and on a phone the pages start fitted to the width */
function onResize() {
  viewH.value = body.value?.clientHeight ?? 600;
  const w = root.value?.clientWidth ?? 0;
  if (w > 0) {
    compact.value = w < COMPACT_BELOW;
    if (compact.value && !userZoomed) fit.value = true;
    if (!compact.value) moreOpen.value = false;
  }
  applyFit();
}
defineExpose({ generate, print, exportAs });
onMounted(() => {
  document.addEventListener('pointerdown', onDocPointer);
  window.addEventListener('keydown', onKey);
  ro = new ResizeObserver(onResize);
  if (root.value) ro.observe(root.value);
  if (body.value) ro.observe(body.value);
  onResize();
  void generate();
});
onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', onDocPointer);
  window.removeEventListener('keydown', onKey);
  ro?.disconnect();
  clearTimeout(copiedTimer);
  clearTimeout(restTimer);
  clearTimeout(pressTimer);
  clearTimeout(wheelTimer);
  stopGlide();
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
  window.removeEventListener('pointercancel', onPointerUp);
});
</script>

<template>
  <div ref="root" class="rv" :class="{ compact }">
    <!-- a phone or a narrow frame: pages, find and one "more" menu with everything else -->
    <div v-if="compact" class="rv-bar compact">
      <button class="vbtn" :disabled="page === 1" :title="L.rpt_prev_page" @click="goPrev">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6" /></svg>
      </button>
      <input class="pagebox tnum" type="text" inputmode="numeric" :value="page" :title="L.rpt_page_number" @change="goTo(Number(($event.target as HTMLInputElement).value))" />
      <span class="pageof">{{ L.rpt_of }} {{ totalPages }}</span>
      <button class="vbtn" :disabled="page === totalPages" :title="L.rpt_next_page" @click="goNext">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6" /></svg>
      </button>
      <div class="vspacer" />
      <span v-if="copied" class="rv-copied">{{ copied === L.rpt_copying ? '' : '✓ ' }}{{ copied }}</span>
      <slot name="actions" />
      <button class="vbtn" :class="{ on: findOpen }" :title="L.rpt_find" @click="toggleFind">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3-3" /></svg>
      </button>
      <div ref="moreRoot" class="exp">
        <button class="vbtn" :class="{ on: moreOpen }" :title="L.rpt_more" @click="moreOpen = !moreOpen">
          <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="12" cy="19" r="1.8" /></svg>
        </button>
        <div v-if="moreOpen" class="exp-menu more-menu">
          <button type="button" :disabled="!doc" @click="print">{{ L.rpt_print }}</button>
          <div class="rv-menu-sep" />
          <div class="more-head">{{ L.rpt_export }}</div>
          <button type="button" :disabled="!doc" @click="exportAs('pdf')">{{ L.rpt_export_pdf }}</button>
          <button type="button" :disabled="!doc" @click="exportAs('xlsx')">{{ L.rpt_export_excel }}</button>
          <button type="button" :disabled="!doc" @click="exportAs('docx')">{{ L.rpt_export_word }}</button>
          <button type="button" :disabled="!doc" @click="exportAs('png')">{{ L.rpt_export_png }}</button>
          <button type="button" :disabled="!doc" @click="exportAs('csv')">{{ L.rpt_export_csv }}</button>
          <button type="button" :disabled="!doc" @click="exportAs('html')">{{ L.rpt_export_html }}</button>
          <div class="rv-menu-sep" />
          <div class="more-zoom">
            <button type="button" :title="L.rpt_zoom_out" @click="zoomBy(-10)">−</button>
            <span class="tnum">{{ zoom }}%</span>
            <button type="button" :title="L.rpt_zoom_in" @click="zoomBy(10)">+</button>
          </div>
          <button type="button" :class="{ on: fit }" @click="fromMore(toggleFit)">{{ fit ? L.rpt_actual_size : L.rpt_fit_width }}</button>
          <button type="button" @click="fromMore(() => setLayout(isScroll ? 'page' : 'scroll'))">{{ isScroll ? L.rpt_layout_page : L.rpt_layout_scroll }}</button>
          <button type="button" @click="fromMore(refresh)">{{ L.rpt_refresh }}</button>
          <div v-if="recordCount >= 0" class="more-foot">{{ recordsText }}</div>
        </div>
      </div>
    </div>

    <div v-else class="rv-bar">
      <button class="vbtn" :disabled="page === 1" :title="L.rpt_first_page" @click="goFirst">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 17 13 12l5-5M7 6v12" /></svg>
      </button>
      <button class="vbtn" :disabled="page === 1" :title="L.rpt_prev_page" @click="goPrev">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6" /></svg>
      </button>
      <input class="pagebox tnum" type="text" :value="page" :title="L.rpt_page_number" @change="goTo(Number(($event.target as HTMLInputElement).value))" />
      <span class="pageof">{{ L.rpt_of }} {{ totalPages }}</span>
      <button class="vbtn" :disabled="page === totalPages" :title="L.rpt_next_page" @click="goNext">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6" /></svg>
      </button>
      <button class="vbtn" :disabled="page === totalPages" :title="L.rpt_last_page" @click="goLast">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 17 5-5-5-5M17 6v12" /></svg>
      </button>

      <div class="vsep" />

      <input class="zoombox tnum" type="text" :value="zoom" :title="L.rpt_zoom_pct" @change="setZoom(($event.target as HTMLInputElement).value)" />
      <input class="zoomslider" type="range" :min="ZMIN" :max="ZMAX" step="5" :value="zoom" :title="L.rpt_zoom" @input="setZoom(($event.target as HTMLInputElement).value)" />
      <button class="vbtn" :class="{ on: fit }" :title="fit ? L.rpt_actual_size : L.rpt_fit_width" @click="toggleFit">
        <!-- arrows to both sides: the page as wide as the view -->
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18M7 8l-4 4 4 4M17 8l4 4-4 4" /></svg>
      </button>
      <button class="vbtn layout" :class="{ on: isScroll }" :title="isScroll ? L.rpt_layout_scroll : L.rpt_layout_page" @click="setLayout(isScroll ? 'page' : 'scroll')">
        <!-- pages one after another / one page -->
        <svg v-if="isScroll" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="6" y="2" width="12" height="8" rx="1" /><rect x="6" y="14" width="12" height="8" rx="1" />
        </svg>
        <svg v-else viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="5" y="3" width="14" height="18" rx="1" /><path d="M9 8h6M9 12h6M9 16h4" />
        </svg>
      </button>

      <div class="vsep" />

      <div ref="exportRoot" class="exp">
        <button class="vbtn" :class="{ on: exportOpen }" :disabled="!doc" :title="L.rpt_export" @click="exportOpen = !exportOpen">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12M7 10l5 5 5-5M4 21h16" /></svg>
          <svg class="caret" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="m6 9 6 6 6-6" /></svg>
        </button>
        <div v-if="exportOpen" class="exp-menu">
          <button type="button" @click="exportAs('xlsx')">{{ L.rpt_export_excel }}</button>
          <button type="button" @click="exportAs('docx')">{{ L.rpt_export_word }}</button>
          <button type="button" @click="exportAs('pdf')">{{ L.rpt_export_pdf }}</button>
          <button type="button" @click="exportAs('html')">{{ L.rpt_export_html }}</button>
          <button type="button" @click="exportAs('csv')">{{ L.rpt_export_csv }}</button>
          <button type="button" @click="exportAs('png')">{{ L.rpt_export_png }}</button>
        </div>
      </div>
      <button class="vbtn" :disabled="!doc" :title="L.rpt_print" @click="print">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9V3h12v6M6 18H4v-6h16v6h-2M8 14h8v7H8z" /></svg>
      </button>
      <button class="vbtn" :class="{ on: findOpen }" :title="L.rpt_find" @click="toggleFind">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3-3" /></svg>
      </button>
      <button class="vbtn" :title="L.rpt_refresh" @click="refresh">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3-6.7L21 8" /><path d="M21 3v5h-5" /></svg>
      </button>

      <div class="vspacer" />
      <span v-if="copied" class="rv-copied">{{ copied === L.rpt_copying ? '' : '✓ ' }}{{ copied }}</span>
      <slot name="actions" />
      <span v-if="recordCount >= 0" class="vcount">{{ recordsText }}</span>
    </div>

    <div v-if="findOpen" class="find-bar" :class="{ compact }">
      <input ref="findInput" v-model="find" :placeholder="L.rpt_find_placeholder" @keydown.enter="$event.shiftKey ? prevHit() : nextHit()" @keydown.esc="toggleFind" />
      <span class="find-count">{{ findCountText }}</span>
      <button class="vbtn" :disabled="!hits.length" :title="L.rpt_prev_match" @click="prevHit">‹</button>
      <button class="vbtn" :disabled="!hits.length" :title="L.rpt_next_match" @click="nextHit">›</button>
      <button class="vbtn" :title="L.rpt_close" @click="toggleFind">✕</button>
    </div>

    <div v-if="error" class="rv-msg err">{{ error }}</div>
    <template v-for="ds in state.report.dataSources" :key="ds.id">
      <div v-if="dataErrors[ds.id]" class="rv-msg err">{{ L.rpt_data_source }} "{{ ds.name }}": {{ dataErrors[ds.id] }}</div>
    </template>
    <div v-for="w in doc?.warnings ?? []" :key="w" class="rv-msg">{{ w }}</div>

    <div
      ref="body"
      class="rv-body"
      :class="{ scroll: isScroll, compact, dragging }"
      @scroll="onScroll"
      @wheel="onWheel"
      @contextmenu="onMenu"
      @pointerdown="onPointerDown"
      @touchstart.passive="onTouchStart"
      @touchmove="onTouchMove"
      @touchend.passive="onTouchEnd"
      @touchcancel.passive="onTouchEnd"
    >
      <!-- a document preview: the sheet stays light in dark mode, as it prints; rv-pages is scaled on screen while a
           hand zooms (live), then the pages are drawn at the new zoom -->
      <div v-if="doc && doc.pages.length" class="rv-pages" :style="pagesStyle">
        <template v-if="isScroll">
          <div v-for="(p, i) in doc.pages" :key="i" class="rv-sheet" :data-page="i" :style="sizeOf(i)">
            <div v-if="near(i)" class="rv-svg" v-html="svgOf(i)" />
          </div>
        </template>
        <div v-else class="rv-sheet" :data-page="page - 1" :style="sizeOf(page - 1)">
          <div class="rv-svg" v-html="svgOf(page - 1)" />
        </div>
      </div>
      <div v-else-if="!busy && !error" class="rv-empty">{{ L.rpt_no_data }}</div>
    </div>
    <div v-if="busy" class="rv-busy"><span class="rv-spin" /> {{ L.rpt_loading }}</div>

    <!-- right-click on a page -->
    <div v-if="menu" ref="menuEl" class="rv-menu" :style="{ left: menu.x + 'px', top: menu.y + 'px' }" @contextmenu.prevent>
      <button type="button" class="rv-menu-image" @click="copyImage(menu.page)">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="9" cy="10" r="2" /><path d="m21 17-5-5-9 8" /></svg>
        {{ L.rpt_copy_image }} <span class="rv-menu-hint">{{ L.rpt_page_n.replace('{n}', String(menu.page + 1)) }}</span>
      </button>
      <div class="rv-menu-sep" />
      <button v-if="menu.sel" type="button" @click="copy(menu.sel)">{{ L.rpt_copy }}</button>
      <button v-if="menu.value" type="button" @click="copy(menu.value)">
        {{ L.rpt_copy_value }} <span class="rv-menu-hint">{{ short(menu.value) }}</span>
      </button>
      <button v-if="menu.row" type="button" @click="copy(menu.row)">{{ L.rpt_copy_row }}</button>
      <div v-if="menu.sel || menu.value || menu.row" class="rv-menu-sep" />
      <button type="button" @click="copy(pageText(menu.page))">{{ L.rpt_copy_page.replace('{n}', String(menu.page + 1)) }}</button>
      <button type="button" @click="copy(allText())">{{ L.rpt_copy_all }}</button>
    </div>
  </div>
</template>

<style scoped>
.rv {
  position: relative;
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--surface);
  color: var(--ink);
}
.rv-bar {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 3px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--border-soft);
  background: var(--surface-2);
}
.vbtn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 1px;
  min-width: 28px;
  height: 28px;
  padding: 0 6px;
  border: 1px solid transparent;
  border-radius: 7px;
  background: none;
  color: var(--ink);
  cursor: pointer;
  font-family: inherit;
  font-size: 13px;
}
.vbtn svg {
  width: 16px;
  height: 16px;
}
.vbtn svg.caret {
  width: 11px;
  height: 11px;
  opacity: 0.7;
}
.vbtn:hover:not(:disabled),
.vbtn.on {
  background: var(--teal-soft);
  color: var(--teal-deep);
  border-color: var(--border-soft);
}
.vbtn:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}
.vbtn.layout {
  margin-left: 4px;
}
.pagebox,
.zoombox {
  width: 46px;
  height: 28px;
  padding: 0 6px;
  border: 1px solid var(--border);
  border-radius: 7px;
  background: var(--surface);
  color: var(--ink);
  font-family: inherit;
  font-size: 12.5px;
  text-align: center;
}
.tnum {
  font-variant-numeric: tabular-nums;
}
.pageof {
  padding: 0 4px;
  color: var(--muted);
  font-size: 12.5px;
  white-space: nowrap;
}
.zoomslider {
  width: 110px;
  accent-color: var(--teal-deep);
  cursor: pointer;
}
.vsep {
  width: 1px;
  height: 20px;
  margin: 0 3px;
  background: var(--border-soft);
}
.vspacer {
  flex: 1;
}
.vcount {
  color: var(--muted);
  font-size: 12px;
  white-space: nowrap;
  padding-left: 6px;
}
.rv-copied {
  padding: 3px 9px;
  border-radius: 999px;
  background: var(--teal-soft);
  color: var(--teal-deep);
  font-size: 12px;
  font-weight: 500;
  white-space: nowrap;
}
.exp {
  position: relative;
}
.exp-menu,
.rv-menu {
  padding: 6px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--surface);
  box-shadow: var(--shadow-lg);
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.exp-menu {
  position: absolute;
  z-index: 40;
  top: calc(100% + 6px);
  left: 0;
  min-width: 150px;
}
.rv-menu {
  position: fixed;
  z-index: 60;
  min-width: 210px;
}
.exp-menu button,
.rv-menu button {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 8px 10px;
  border: none;
  border-radius: 7px;
  background: none;
  color: var(--ink);
  cursor: pointer;
  font-family: inherit;
  font-size: 13px;
  text-align: left;
}
.exp-menu button:hover,
.rv-menu button:hover {
  background: var(--teal-soft);
  color: var(--teal-deep);
}
.rv-menu .rv-menu-image {
  align-items: center;
  font-weight: 500;
}
.rv-menu-image svg {
  width: 15px;
  height: 15px;
  flex: none;
}
.rv-menu-hint {
  margin-left: auto;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--muted);
  font-size: 11.5px;
}
.rv-menu-sep {
  height: 1px;
  margin: 3px 4px;
  background: var(--border-soft);
}
.find-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 7px 12px;
  border-bottom: 1px solid var(--border-soft);
  background: var(--surface);
}
.find-bar input {
  width: 240px;
  max-width: 50vw;
  height: 28px;
  padding: 0 9px;
  border: 1px solid var(--border);
  border-radius: 7px;
  background: var(--surface);
  color: var(--ink);
  font-family: inherit;
  font-size: 13px;
  outline: none;
}
.find-count {
  min-width: 80px;
  color: var(--muted);
  font-size: 12px;
}
.rv-msg {
  padding: 6px 14px;
  font-size: 12.5px;
  background: var(--amber-soft);
  color: var(--ink);
  border-bottom: 1px solid var(--border-soft);
}
.rv-msg.err {
  background: var(--red-soft);
}
.rv-body {
  flex: 1;
  min-height: 0;
  padding: 20px;
  background: var(--surface-2);
  overflow: auto;
  /* fingers scroll the pages; two fingers zoom them (onTouchMove), not the whole viewer */
  touch-action: pan-x pan-y;
  -webkit-overflow-scrolling: touch;
}
.rv-body.compact {
  padding: 8px;
}
/* the hand: with a mouse the pages are grabbed and dragged (copying is on the right-click menu) */
@media (pointer: fine) {
  .rv-body {
    cursor: grab;
  }
  .rv-body .rv-sheet {
    user-select: none;
  }
}
.rv-body.dragging,
.rv-body.dragging * {
  cursor: grabbing;
}

/* ---- phone / narrow frame */
.rv-bar.compact {
  flex-wrap: nowrap;
  gap: 2px;
  padding: 6px 8px;
}
.rv-bar.compact .vbtn {
  min-width: 36px;
  height: 36px;
}
.rv-bar.compact .pagebox {
  width: 42px;
  height: 32px;
}
.more-menu {
  left: auto;
  right: 0;
  min-width: 220px;
  max-height: calc(100vh - 70px);
  overflow-y: auto;
}
.more-menu button:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.more-menu button.on {
  color: var(--teal-deep);
  font-weight: 600;
}
.more-head {
  padding: 6px 10px 2px;
  color: var(--muted);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.more-foot {
  padding: 6px 10px 2px;
  color: var(--muted);
  font-size: 12px;
}
.more-zoom {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 2px 4px;
}
.more-menu .more-zoom button {
  flex: none;
  justify-content: center;
  width: 42px;
  padding: 4px 0;
  border: 1px solid var(--border);
  font-size: 18px;
  line-height: 1;
}
.more-zoom span {
  flex: 1;
  text-align: center;
  font-size: 13px;
}
.find-bar.compact {
  padding: 6px 8px;
}
.find-bar.compact input {
  flex: 1;
  width: auto;
  min-width: 0;
  max-width: none;
}
.find-bar.compact .find-count {
  min-width: 0;
  white-space: nowrap;
}
/* fingers need bigger targets than a mouse */
@media (pointer: coarse) {
  .exp-menu button,
  .rv-menu button {
    padding: 11px 12px;
  }
  .vbtn {
    min-width: 34px;
    height: 34px;
  }
}
.rv-sheet {
  margin: 0 auto;
  background: #fff;
  border: 1px solid #d8dce6;
  border-radius: 4px;
  box-shadow: 0 6px 22px rgba(15, 23, 42, 0.12);
  overflow: hidden;
  user-select: text;
}
.rv-body.scroll .rv-sheet + .rv-sheet {
  margin-top: 18px;
}
.rv-svg,
.rv-svg :deep(svg) {
  display: block;
}
.rv-empty {
  padding: 60px 0;
  color: var(--muted);
  text-align: center;
  font-size: 13px;
}
.rv-busy {
  position: absolute;
  top: 56px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--surface);
  box-shadow: var(--shadow-lg);
  font-size: 13px;
}
.rv-spin {
  width: 14px;
  height: 14px;
  border: 2px solid var(--border);
  border-top-color: var(--teal);
  border-radius: 50%;
  animation: rv-spin 0.8s linear infinite;
}
@keyframes rv-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
