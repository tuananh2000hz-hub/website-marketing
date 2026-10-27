// Google Apps Script - nhan du lieu tu EA TPBalancer va hien thi dashboard.
// Gan script nay vao 1 Google Sheet (Extensions > Apps Script).

const WEB_KEY = 'doi-ma-bi-mat-nay'; // trung voi InpWebKey trong EA
const VIEW_PIN = '1234';             // ma PIN de xem dashboard
const LOG_EVERY_MS = 5 * 60 * 1000;  // ghi lich su equity moi 5 phut

function doPost(e) {
  const d = JSON.parse(e.postData.contents);
  if (d.key !== WEB_KEY) return ContentService.createTextOutput('bad key');
  delete d.key;
  d.receivedAt = new Date().toISOString();

  const id = d.account + '_' + d.symbol;
  const props = PropertiesService.getScriptProperties();
  props.setProperty('status_' + id, JSON.stringify(d));

  const last = Number(props.getProperty('lastlog_' + id) || 0);
  if (Date.now() - last > LOG_EVERY_MS) {
    const ss = SpreadsheetApp.getActive();
    const sh = ss.getSheetByName('Log') || ss.insertSheet('Log');
    if (sh.getLastRow() === 0) {
      sh.appendRow(['Time', 'Account', 'Symbol', 'Balance', 'Equity', 'Cycle', 'Dir',
        'Steps', 'Lots', 'Avg', 'SL', 'TP', 'Risk', 'Reward', 'Floating']);
    }
    sh.appendRow([new Date(), d.account, d.symbol, d.balance, d.equity, d.cycle, d.dir,
      d.steps, d.lots, d.avg, d.sl, d.tp, d.risk, d.reward, d.floating]);
    props.setProperty('lastlog_' + id, String(Date.now()));
  }
  return ContentService.createTextOutput('ok');
}

function doGet() {
  return HtmlService.createHtmlOutputFromFile('Dashboard')
    .setTitle('TP Balancer')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

// Goi tu Dashboard.html
function getData(pin) {
  if (pin !== VIEW_PIN) throw new Error('Sai PIN');
  const all = PropertiesService.getScriptProperties().getProperties();
  const accounts = Object.keys(all)
    .filter(k => k.indexOf('status_') === 0)
    .map(k => JSON.parse(all[k]));

  const sh = SpreadsheetApp.getActive().getSheetByName('Log');
  let equity = [];
  if (sh && sh.getLastRow() > 1) {
    const n = Math.min(sh.getLastRow() - 1, 500);
    equity = sh.getRange(sh.getLastRow() - n + 1, 1, n, 5).getValues()
      .map(r => ({ t: new Date(r[0]).toISOString(), acc: String(r[1]), sym: r[2], bal: r[3], eq: r[4] }));
  }
  return { accounts, equity };
}
