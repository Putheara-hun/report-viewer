<template>
  <!-- A report screen of your own system: its filter, then the report from your API in the viewer.
       Your API answers { report: <design text>, data: <rows>, params: { ... } } - see the README. -->
  <div class="report-page">
    <form class="filter" @submit.prevent="preview">
      <label>
        Month
        <input v-model="month" type="month" required />
      </label>
      <label>
        Language
        <select v-model="lang">
          <option value="en">English</option>
          <option value="km">ខ្មែរ</option>
        </select>
      </label>
      <button type="submit" :disabled="busy">{{ busy ? "Loading…" : "Preview" }}</button>
      <span class="grow" />
      <!-- optional: the viewer has Print and Export in its own toolbar too -->
      <button type="button" :disabled="!shown" @click="viewer.print()">Print</button>
      <button type="button" :disabled="!shown" @click="viewer.exportAs('pdf')">PDF</button>
      <button type="button" :disabled="!shown" @click="viewer.exportAs('xlsx')">Excel</button>
    </form>

    <p v-if="error" class="error">{{ error }}</p>

    <ReportViewer
      ref="viewer"
      height="calc(100vh - 140px)"
      :labels="lang === 'km' ? KHMER : null"
      @refresh="preview"
      @error="(e) => (error = e.message)"
    />
  </div>
</template>

<script setup>
import { ref } from "vue";
import ReportViewer from "./ReportViewer.vue";

// your API, and how your app proves who is asking (here: the HRMS headers kept at login)
const API = "https://your-api.example.com";
const authHeaders = () => ({
  "x-auth": localStorage.getItem("token") || "",
  "x-cred": localStorage.getItem("crd") || "",
  "x-user": localStorage.getItem("device") || "",
});

// the viewer's words in Khmer (any key you leave out stays English)
const KHMER = { rpt_print: "បោះពុម្ព", rpt_export: "នាំចេញ", rpt_find: "ស្វែងរក", rpt_of: "នៃ", rpt_refresh: "ផ្ទុកឡើងវិញ", rpt_more: "ច្រើនទៀត" };

const viewer = ref(null);
const month = ref(new Date().toISOString().slice(0, 7)); // yyyy-MM
const lang = ref("en");
const busy = ref(false);
const shown = ref(false);
const error = ref("");

async function preview() {
  busy.value = true;
  error.value = "";
  try {
    // 1. ask your API for the report: which report, the filter, the texts printed on it
    const res = await fetch(`${API}/api/report/view`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body: JSON.stringify({
        RPT_CODE: "rpt.payslip",
        PRD_CODE: month.value, // a filter field = a parameter of the report's procedure
        PARAMS: { LANG: lang.value, FILTER: month.value, PRINTED_BY: "Me" },
      }),
    });
    const answer = await res.json();
    if (!res.ok || typeof answer.report !== "string") throw new Error(answer.message || `The report failed (HTTP ${res.status}).`);

    // 2. give the answer to the viewer as it is
    await viewer.value.load(answer);
    shown.value = true;
  } catch (e) {
    error.value = e.message;
  } finally {
    busy.value = false;
  }
}

/* No API of this kind? The viewer only needs the design text and the rows, from anywhere:
     await viewer.value.load({
       report: designText,                 // the text copied from the designer (Copy Text) or saved in your database
       data: rows,                         // [{ EMP_CODE: 'E001', NET_PAY: 500 }, ...] - or { DataSet1: rows, DataSet2: rows2 }
       params: { TITLE: 'Payslip', LANG: 'en' },
     });
*/
</script>

<style scoped>
.report-page {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px;
}
.filter {
  display: flex;
  flex-wrap: wrap;
  align-items: end;
  gap: 10px;
}
.filter label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 13px;
}
.grow {
  flex: 1;
}
.error {
  margin: 0;
  color: #b91c1c;
}
</style>
