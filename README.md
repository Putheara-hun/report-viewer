# Report Viewer

Shows a report from its **text** — the XML (RDL), HTML or JSON copied with **Copy Text** in the ReportTool
designer (or an RDL file from Report Builder). It looks like a report viewer of the host application: one sheet at a
time, page navigation, zoom (box + slider), find, export (Excel, PDF, HTML, CSV, image), print, refresh and the
record count — no parameters panel and nothing to edit. Khmer text and Google / Khmer OS fonts are supported.

It runs completely in the browser, so it is hosted as a static website (see `render.yaml`).

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
| `viewer.refresh()` · `viewer.print()` · `viewer.exportAs('pdf')` | re-render · print · download (`pdf`, `xlsx`, `csv`, `html`, `png`) |
| `ReportViewer.open({ report, data, params })` | the viewer in a new browser tab (call it from a click) |

- **Rows:** `data` is keyed by the data source **name** in the design (name it e.g. `DataSet1` in the designer).
  Those rows replace the data source; without them the data saved in the text is used. A data source that reads from
  a database needs its rows sent — the viewer says which one.
- **Parameters:** `params` fill `{?NAME}` in the design, also names the design does not declare (TITLE, LOGO …).
- **Words** (`labels`) use the keys of the application's viewer: `rpt_first_page`, `rpt_prev_page`, `rpt_next_page`,
  `rpt_last_page`, `rpt_page_number`, `rpt_of`, `rpt_zoom_pct`, `rpt_zoom`, `rpt_export`, `rpt_export_excel`,
  `rpt_export_pdf`, `rpt_export_html`, `rpt_export_csv`, `rpt_export_png`, `rpt_print`, `rpt_find`,
  `rpt_find_placeholder`, `rpt_hit_of` (`{a} of {b}`), `rpt_no_matches`, `rpt_prev_match`, `rpt_next_match`,
  `rpt_close`, `rpt_refresh`, `rpt_record`, `rpt_records`, `rpt_no_data`, `rpt_loading`, `rpt_waiting`,
  `rpt_data_source`, `rpt_layout_scroll`, `rpt_layout_page`, and the right-click menu: `rpt_copy_image`,
  `rpt_page_n` (`page {n}`), `rpt_copy`, `rpt_copy_value`, `rpt_copy_row`, `rpt_copy_page` (`Copy page {n}`),
  `rpt_copy_all`, `rpt_copied`, `rpt_copying`, `rpt_copied_image`, `rpt_image_saved`.
- **Right-click** on a page: **Copy as image** (the page as a picture — paste it into a chat, Word or an email with
  Ctrl+V), copy a value, a row, a page or all pages as text. `viewer.js` gives the iframe `allow="clipboard-write"`;
  if you write the `<iframe>` yourself, add it too (without it the picture is downloaded instead).
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
