# Report Viewer

Shows a report from its **text** — the XML (RDL), HTML or JSON copied with **Copy Text** in the ReportTool
designer (or an RDL file from Report Builder). It looks like a report viewer of the host application: one sheet at a
time, page navigation, zoom (box + slider), find, export (Excel, PDF, HTML, CSV, image), print, refresh and the
record count — no parameters panel and nothing to edit. Khmer text and Google / Khmer OS fonts are supported.

It runs completely in the browser, so it is hosted as a static website (see `render.yaml`).

It works on a computer and on a phone, in a web application and in a mobile app. In a narrow frame (under 640 px)
the toolbar is short (pages, find, and a **⋮** menu with print, export, zoom, layout and refresh), the pages start
fitted to the width, two fingers zoom the pages and a long press opens the copy menu. The ↔ button (or **⋮ > Fit to
width**) fits the pages to the width on any screen.

**Code to copy** for your own system:

| | |
| --- | --- |
| Vue 3 | [`examples/vue/ReportViewer.vue`](examples/vue/ReportViewer.vue) (the viewer as a component) and [`examples/vue/PayslipReport.vue`](examples/vue/PayslipReport.vue) (a report screen: filter, your API, the viewer) |
| Flutter (Android, iOS, web) | [`flutter/report_viewer`](flutter/report_viewer) (a package: `ReportViewer` widget, `ReportViewerPage`, `ReportApi`) and its [`example/lib/main.dart`](flutter/report_viewer/example/lib/main.dart) |
| Any web page | the `viewer.js` example below |

## How an application uses it

1. The application's screen asks for the criteria (dates, branch …) as it does today.
2. Its **API controller** runs the report's procedure and answers with the report text (saved from the designer in
   its database) and the rows: `{ report, data: { DataSet1: rows }, params: { TITLE: … } }`.
3. The screen hands that answer to the viewer in an iframe.

```html
<!-- once, in the application's index.html -->
<script src="https://<viewer-site>/viewer.js"></script>
```

```js
const viewer = ReportViewer.embed(document.getElementById('report'), {
  theme: 'light',                                   // or 'dark'
  labels: { rpt_print: 'Print', rpt_of: 'of' },     // optional: your words (keys below)
  onRefresh: () => show(lastCriteria),              // the user clicked Refresh: send fresh rows
  onError: (err) => alert(err.message),
});
async function show(criteria) {
  const answer = await fetch('/api/reportviewer/LOAN_OS?' + new URLSearchParams(criteria)).then((r) => r.json());
  await viewer.load(answer);                         // { report, data, params } as is
}
```

| Call | What it does |
| --- | --- |
| `viewer.load(answer)` or `viewer.load(text, { data, params })` | show a report |
| `viewer.setData(name, rows)` | new rows for one data source, re-rendered |
| `viewer.setParams({ TITLE: '…' })` | new parameter values, re-rendered |
| `viewer.setTheme('dark')` · `viewer.setLabels({...})` | colours · words |
| `viewer.refresh()` · `viewer.print()` · `viewer.exportAs('pdf')` | re-render · print · download (`pdf`, `xlsx`, `docx`, `csv`, `html`, `png`); they wait until the report is drawn |
| `ReportViewer.open({ report, data, params })` | the viewer in a new browser tab (call it from a click) |

- **Files to your app** (`onFile`): a web view inside a phone app (Flutter, Capacitor, Cordova, Android / iOS) can
  neither download nor print. Give `embed` an `onFile` and every export, and Print (as a PDF), comes to your page
  instead: `file = { name, mime, size, action: 'download' | 'print', base64, blob(), download() }` — share it, save
  it or print it the app's way. Without `onFile` the browser downloads and prints as before.

  ```js
  ReportViewer.embed(box, { onFile: (file) => MyApp.postMessage(JSON.stringify(file)) });
  ```

- **Rows:** `data` is keyed by the data source **name** in the design (name it e.g. `DataSet1` in the designer).
  Those rows replace the data source; without them the data saved in the text is used. A data source that reads from
  a database needs its rows sent — the viewer says which one.
- **Parameters:** `params` fill `{?NAME}` in the design, also names the design does not declare (TITLE, LOGO …).
- **Words** (`labels`) use the keys of the application's viewer: `rpt_first_page`, `rpt_prev_page`, `rpt_next_page`,
  `rpt_last_page`, `rpt_page_number`, `rpt_of`, `rpt_zoom_pct`, `rpt_zoom`, `rpt_export`, `rpt_export_excel`, `rpt_export_word`,
  `rpt_export_pdf`, `rpt_export_html`, `rpt_export_csv`, `rpt_export_png`, `rpt_print`, `rpt_find`,
  `rpt_find_placeholder`, `rpt_hit_of` (`{a} of {b}`), `rpt_no_matches`, `rpt_prev_match`, `rpt_next_match`,
  `rpt_close`, `rpt_refresh`, `rpt_record`, `rpt_records`, `rpt_no_data`, `rpt_loading`, `rpt_waiting`,
  `rpt_data_source`, `rpt_layout_scroll`, `rpt_layout_page`, the phone's menu and zoom: `rpt_more`, `rpt_fit_width`,
  `rpt_actual_size`, `rpt_zoom_in`, `rpt_zoom_out`, and the right-click menu: `rpt_copy_image`,
  `rpt_page_n` (`page {n}`), `rpt_copy`, `rpt_copy_value`, `rpt_copy_row`, `rpt_copy_page` (`Copy page {n}`),
  `rpt_copy_all`, `rpt_copied`, `rpt_copying`, `rpt_copied_image`, `rpt_image_saved`.
- **Right-click** (on a phone: a long press) on a page: **Copy as image** (the page as a picture — paste it into a
  chat, Word or an email with Ctrl+V), copy a value, a row, a page or all pages as text. `viewer.js` gives the iframe `allow="clipboard-write"`;
  if you write the `<iframe>` yourself, add it too (without it the picture is downloaded instead).
- **Excel / Word** exports look like the preview: fonts (Khmer too), colours, fills, borders, alignment, column widths
  and row heights. In Excel, numbers and dates stay numbers and dates with the report's format, and the pages follow
  one another (the page header once, no page footers). Word keeps one Word page per report page with its pictures.
- Only the page that opened the viewer can talk to it (`viewer.js` passes its address).

### Example API controller (ASP.NET Core + Dapper)

```csharp
[ApiController, Route("api/reportviewer")]
public class ReportViewerController(IDbConnection db) : ControllerBase
{
    // GET api/reportviewer/LOAN_OS?FromDate=2026-01-01&ToDate=2026-01-31&Branch=001
    [HttpGet("{reportId}")]
    public async Task<IActionResult> Get(string reportId, [FromQuery] Dictionary<string, string?> criteria)
    {
        // your own table: the text copied from the designer (Copy Text) and the procedure that feeds it
        var rpt = await db.QuerySingleAsync<(string Text, string Proc, string Title)>(
            "SELECT REPORT_TEXT, PROC_NAME, TITLE FROM REPORT_DESIGN WHERE REPORT_ID = @reportId", new { reportId });
        var args = new DynamicParameters();
        foreach (var (name, value) in criteria) args.Add(name, value);
        var rows = await db.QueryAsync(rpt.Proc, args, commandType: CommandType.StoredProcedure);
        return Ok(new
        {
            report = rpt.Text,
            data = new Dictionary<string, object> { ["DataSet1"] = rows },
            @params = new { TITLE = rpt.Title },
        });
    }
}
```

## Opened by hand

Open the site, paste the report text (or open / drop a file) and click **Show report**.

## Develop

```
npm install
npm run dev        # http://localhost:5175
npm run build      # dist/
```

The report engine and the viewer are written in the **ReportTool** designer project. After a change there, copy it
here and commit:

```
npm run sync       # copies from ../ReportTool (or: npm run sync -- D:\path\to\ReportTool)
```

`src/` holds copies only — change the files in ReportTool, then sync.
