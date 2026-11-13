# Report Viewer

Shows a report from its **text** — the XML (RDL), HTML or JSON copied with **Copy Text** in the ReportTool
designer (or an RDL file from Report Builder) — with pages, zoom, find, parameters, refresh, print and export
(PDF, Excel, CSV, HTML, PNG). Nothing can be edited. Khmer text and Google / Khmer OS fonts are supported.

It runs completely in the browser, so it is hosted as a static website (see `render.yaml`).

## Use it

**By hand:** open the site, paste the report text (or open / drop a file) and click **Show report**.

**From your application** — include `viewer.js` from the viewer site:

```html
<div id="report" style="height: 80vh"></div>
<script src="https://<viewer-site>/viewer.js"></script>
<script>
  const viewer = ReportViewer.embed(document.getElementById('report'), {
    report: textFromYourDatabase,            // XML / HTML / JSON text
    data: { DataSet1: rows },               // optional: rows per data source NAME in the design
    params: { TITLE: 'Loan Outstanding' },   // optional: parameter values ({?TITLE} works even if not declared)
    onRendered: (pages) => {},
    onError: (err) => alert(err.message),
  });
</script>
```

| Call | What it does |
| --- | --- |
| `viewer.load(text, { data, params, name })` | show another report |
| `viewer.setData(name, rows)` | new rows for one data source, re-rendered |
| `viewer.setParams({ BRANCH: 'HQ' })` | new parameter values, re-rendered |
| `viewer.refresh()` · `viewer.print()` | re-render · print dialog |
| `viewer.exportAs('pdf')` | download: `pdf`, `xlsx`, `csv`, `html`, `png` |
| `ReportViewer.open({ report, data, params })` | the viewer in a new browser tab (call it from a click) |

**Where the rows come from:** rows your application sends (`data`) replace the data source with that name; otherwise
the data saved in the text is used (JSON / CSV sources, or rows sent while designing). A data source that reads from
a database needs its rows sent by the application — the viewer says so on the page.

Only the page that opened the viewer can talk to it (`origins` is set by `viewer.js`).

### Example: a Vue screen

```vue
<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue';
const box = ref<HTMLElement>();
let viewer: any;
onMounted(async () => {
  // your API: the report text you saved from the designer, and the rows of its procedure
  const [report, rows] = await Promise.all([fetch('/api/reports/42/text').then((r) => r.text()), fetch('/api/reports/42/rows').then((r) => r.json())]);
  viewer = (window as any).ReportViewer.embed(box.value, { report, data: { DataSet1: rows }, params: { TITLE: 'Loan Outstanding' } });
});
onBeforeUnmount(() => viewer?.destroy());
</script>
<template><div ref="box" style="height: 80vh" /></template>
```
(add `<script src="https://<viewer-site>/viewer.js"></script>` to the application's `index.html`).

## Develop

```
npm install
npm run dev        # http://localhost:5175
npm run build      # dist/
```

The report engine, the preview and the viewer itself are written in the **ReportTool** designer project. After a
change there, copy it here and commit:

```
npm run sync       # copies from ../ReportTool (or: npm run sync -- D:\path\to\ReportTool)
```

`src/` holds copies only — change the files in ReportTool, then sync.
