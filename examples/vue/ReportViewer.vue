<template>
  <!-- The Report Viewer inside any Vue 3 application. Copy this file into your project, then:
         <ReportViewer ref="viewer" height="80vh" @refresh="preview" />
         await viewer.value.load(await api.post('/api/report/view', filter))   // { report, data, params }
       The viewer is another site (an iframe): it draws the report, with its own toolbar (pages, zoom, find, export,
       print). It works the same on a computer and on a phone (short toolbar, pages fitted to the width, pinch zoom). -->
  <div ref="box" class="report-viewer" :style="{ height }"></div>
</template>

<script setup>
import { onBeforeUnmount, onMounted, ref, watch } from "vue";

const props = defineProps({
  // where the viewer is published (the folder of viewer.js and viewer.html)
  viewerUrl: { type: String, default: "https://report-viewer-h88h.onrender.com/" },
  theme: { type: String, default: "light" }, // "light" | "dark"
  layout: { type: String, default: "scroll" }, // "scroll" (all pages) | "page" (one at a time)
  labels: { type: Object, default: null }, // the viewer's words in your language, e.g. { rpt_print: "បោះពុម្ព" }
  // true: Export and Print come to you as @file instead of a download / the browser's print - for an app shown in a
  // web view (Capacitor, Cordova, a phone app) that cannot download or print by itself
  hostFiles: { type: Boolean, default: false },
  height: { type: String, default: "100%" },
});
const emit = defineEmits(["ready", "rendered", "refresh", "error", "file"]);

const box = ref(null);
let viewer = null; // the viewer's API (viewer.js)
let opening = null; // the viewer being opened

/* viewer.js is loaded once per page, from the viewer's own site */
const sdks = new Map();
function loadSdk(url) {
  const base = url.replace(/\/?$/, "/");
  if (!sdks.has(base)) {
    sdks.set(
      base,
      new Promise((resolve, reject) => {
        if (window.ReportViewer) return resolve(window.ReportViewer);
        const s = document.createElement("script");
        s.src = base + "viewer.js";
        s.onload = () => (window.ReportViewer ? resolve(window.ReportViewer) : reject(new Error("viewer.js has no ReportViewer")));
        s.onerror = () => {
          sdks.delete(base);
          s.remove();
          reject(new Error(`The Report Viewer could not be loaded from ${base}`));
        };
        document.head.appendChild(s);
      }),
    );
  }
  return sdks.get(base);
}

async function open() {
  const sdk = await loadSdk(props.viewerUrl);
  viewer = sdk.embed(box.value, {
    theme: props.theme,
    layout: props.layout,
    labels: props.labels || undefined,
    onRendered: (pages) => emit("rendered", pages),
    onRefresh: () => emit("refresh"), // the viewer's Refresh button: ask your API again
    onError: (e) => emit("error", e),
    // file = { name, mime, size, action: "download" | "print", base64, blob(), download() }
    ...(props.hostFiles ? { onFile: (file) => emit("file", file) } : {}),
  });
  await viewer.ready;
  emit("ready");
  return viewer;
}
const api = async () => viewer || (await (opening ||= open()));

/** show a report: your API's answer { report, data, params } as is - or { report: designText, data: rows, params } */
async function load(answer, extraParams = {}) {
  const v = await api();
  return v.load({ ...answer, params: { ...(answer.params || {}), ...extraParams } });
}
const print = async () => (await api()).print();
const exportAs = async (format = "pdf") => (await api()).exportAs(format); // pdf | xlsx | docx | csv | html | png
const setData = async (name, rows) => (await api()).setData(name, rows); // new rows, drawn again
const setParams = async (values) => (await api()).setParams(values);
const refresh = async () => (await api()).refresh();

watch(
  () => props.theme,
  (t) => viewer?.setTheme(t).catch(() => {}),
);
onMounted(() => {
  // open the viewer at once (its site may need a moment the first time), so the first report shows faster
  opening = open();
  opening.catch((e) => emit("error", e));
});
onBeforeUnmount(() => viewer?.destroy());

defineExpose({ load, print, exportAs, setData, setParams, refresh });
</script>

<style scoped>
.report-viewer {
  width: 100%;
  min-height: 420px;
}
</style>
