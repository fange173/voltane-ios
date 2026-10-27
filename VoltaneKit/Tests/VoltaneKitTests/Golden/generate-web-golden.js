// 在 voltane 网页版页面（已登录）的控制台里执行：先整段执行，再执行 `const R = await window.__H.run(); window.__H.R = R;`。
window.__H = {};
(() => {
const VEH = {
  phev: {},
  phevL: { fuel_gauge_mode: 'liters' },
  phevB: { fuel_gauge_mode: 'bars', fuel_gauge_bars: 8 },
  bev: { energy_type: 'bev', has_fuel: false, has_elec: true, tank_capacity_l: null, battery_usable_kwh: 75, charge_limit_pct: 80 },
  ice: { energy_type: 'ice', has_fuel: true, has_elec: false, tank_capacity_l: 50, battery_usable_kwh: null },
};
const TOU = { id: 11, name: '家里车位', kind: 'home_charger', tou_tariff: [{ from: '22:00', to: '08:00', price: 0.3 }, { from: '08:00', to: '22:00', price: 0.62 }], default_charge_type: 'home', default_fuel_grade: null, last_unit_price: null, lat: null, lng: null, use_count: 5, is_hidden: false };
const GAS = { id: 12, name: '中石化', kind: 'gas_station', tou_tariff: [], default_charge_type: null, default_fuel_grade: '95', last_unit_price: 7.62, lat: null, lng: null, use_count: 3, is_hidden: false };
const PUB = { id: 13, name: '公司桩', kind: 'charge_station', tou_tariff: [], default_charge_type: 'dc', default_fuel_grade: null, last_unit_price: 1.5, lat: null, lng: null, use_count: 2, is_hidden: false };
const P = { k: 0.2, k_source: 'learned', last: null, last_odo: 10000, last_odo_ts: '2026-10-20T08:00', odo_points: [['2026-10-01T08:00', 9500], ['2026-10-20T08:00', 10000]],last_soc: 50, last_fuel_pct: 60, places: [TOU, GAS, PUB], recent_notes: [], in_progress: [], daily_km: 50 };
const T = (n, v) => ['type', n, v];
const C = [];
const add = (name, veh, kind, act, extra = {}) => C.push({ name, veh, kind, act, ...extra });
// 加油：三填二与加满推算
add('f_qty_price_full', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_liters', '20'), T('fuel_unit_price', '7.5')]);
add('f_qty_price_notfull', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_liters', '20'), T('fuel_unit_price', '7.5')]);
add('f_qty_amount', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_liters', '30'), T('amount', '225')]);
add('f_price_amount', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_unit_price', '7.62'), T('amount', '300')]);
add('f_amount_expr', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_unit_price', '7.5'), T('amount', '200+15')]);
add('f_full_before', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_level_before_pct', '30'), T('fuel_unit_price', '7.5')]);
add('f_full_liters_to_before', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_liters', '33.5')]);
add('f_notfull_after', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_level_before_pct', '20'), T('fuel_liters', '24')]);
add('f_liters_gauge_liters_typed', 'phevL', 'fuel', [T('odometer_km', '10350'), T('fuel_liters', '30')]);
add('f_liters_gauge_lit', 'phevL', 'fuel', [T('odometer_km', '10350'), ['lit', 'fuel_level_before_pct', '12']]);
add('f_bars_bar', 'phevB', 'fuel', [T('odometer_km', '10350'), ['bar', 'fuel_level_before_pct', 3]]);
add('f_bars_liters', 'phevB', 'fuel', [T('odometer_km', '10350'), T('fuel_liters', '30')]);
add('f_user_all', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_level_before_pct', '30'), T('fuel_liters', '10'), T('fuel_unit_price', '7')]);
add('f_amount_price_before', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_unit_price', '7.5'), T('amount', '225'), T('fuel_level_before_pct', '40')]);
add('f_ice_full', 'ice', 'fuel', [T('odometer_km', '10350'), T('fuel_liters', '40')]);
add('f_zero_liters', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_liters', '0'), T('fuel_unit_price', '7.5')]);
add('f_price_only', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_unit_price', '7.5')]);
add('f_same_last', 'phev', 'fuel', [['same']], { prefill: { last: { id: 9, kind: 'fuel', fuel_grade: '95', fuel_unit_price: 7.8, place_id: 12, place_name: '中石化', fuel_is_full: false, occurred_at: '2026-10-20T08:00' } } });
add('f_place_gas', 'phev', 'fuel', [T('odometer_km', '10350'), ['place', 12]]);
add('f_extra_fee', 'phev', 'fuel', [T('odometer_km', '10350'), ['check', 'fuel_is_full', false], T('fuel_liters', '20'), T('fuel_unit_price', '7.5'), T('extra_fee', '10')]);
add('f_grade_chip', 'phev', 'fuel', [T('odometer_km', '10350'), T('fuel_liters', '20'), ['chip', 'grade', '98'], T('note', '  备注  ')]);
// 里程提示
add('odo_delta', 'phev', 'fuel', [T('odometer_km', '10350')]);
add('odo_negative', 'phev', 'fuel', [T('odometer_km', '9900')]);
add('odo_big', 'phev', 'fuel', [T('odometer_km', '13000')]);
add('odo_backfill', 'phev', 'fuel', [T('occurred_at', '2026-10-10T08:00'), T('odometer_km', '9800')]);
add('odo_backfill_greater', 'phev', 'fuel', [T('occurred_at', '2026-10-10T08:00'), T('odometer_km', '10500')]);
add('odo_backfill_between', 'phev', 'fuel', [T('occurred_at', '2026-10-15T08:00'), T('odometer_km', '9800')]);
add('odo_trip_backfill', 'phev', 'fuel', [T('occurred_at', '2026-10-15T08:00'), ['check', 'trip_mode', true], T('odometer_km', '120'), T('fuel_liters', '20')]);
add('odo_trip','phev', 'fuel', [['check', 'trip_mode', true], T('odometer_km', '120'), T('fuel_liters', '20')]);
add('odo_unknown', 'phev', 'fuel', [['check', 'odo_unknown', true], T('fuel_liters', '20')]);
add('odo_none', 'phev', 'fuel', [T('fuel_liters', '20')]);
add('odo_no_last', 'phev', 'fuel', [T('odometer_km', '500'), T('fuel_liters', '20')], { prefill: { last_odo: null, last_odo_ts: null } });
// 充电
add('c_soc_to_kwh', 'phev', 'charge', [T('odometer_km', '10100'), T('soc_before_pct', '10'), T('soc_after_pct', '90')]);
add('c_kwh_to_soc', 'phev', 'charge', [T('odometer_km', '10100'), T('soc_before_pct', '10'), T('charge_kwh', '14')]);
add('c_to_limit_bev', 'bev', 'charge', [T('odometer_km', '10100'), T('soc_before_pct', '20'), ['check', 'charge_to_limit', true]], { prefill: { k: 0.75 } });
add('c_swap', 'phev', 'charge', [T('odometer_km', '10100'), ['chip', 'ctype', 'swap'], T('soc_before_pct', '20'), T('soc_after_pct', '100')]);
add('c_tou_basic', 'phev', 'charge', [T('occurred_at', '2026-10-27T23:00'), T('odometer_km', '10100'), ['place', 11], T('charge_kwh', '10')]);
add('c_tou_minutes', 'phev', 'charge', [T('occurred_at', '2026-10-27T20:30'), T('odometer_km', '10100'), ['place', 11], T('charge_kwh', '18.3'), T('charge_minutes', '120')]);
add('c_tou_midnight', 'phev', 'charge', [T('occurred_at', '2026-10-27T23:00'), T('odometer_km', '10100'), ['place', 11], T('charge_kwh', '30'), T('charge_minutes', '300')]);
add('c_tou_day', 'phev', 'charge', [T('occurred_at', '2026-10-27T12:07'), T('odometer_km', '10100'), ['place', 11], T('charge_kwh', '7.7')]);
add('c_tou_user_price', 'phev', 'charge', [T('odometer_km', '10100'), ['place', 11], T('charge_kwh', '10'), T('charge_unit_price', '0.5')]);
add('c_tou_user_amount', 'phev', 'charge', [T('odometer_km', '10100'), ['place', 11], T('charge_kwh', '10'), T('amount', '4')]);
add('c_fee_sum', 'phev', 'charge', [T('odometer_km', '10100'), T('energy_fee', '8'), T('service_fee', '2.5')]);
add('c_kwh_price', 'phev', 'charge', [T('odometer_km', '10100'), T('charge_kwh', '12.3'), T('charge_unit_price', '0.456')]);
add('c_kwh_amount', 'phev', 'charge', [T('odometer_km', '10100'), T('charge_kwh', '20'), T('amount', '10')]);
add('c_amount_then_kwh', 'phev', 'charge', [T('odometer_km', '10100'), T('amount', '30'), T('charge_kwh', '40'), T('charge_kwh', '50')]);
add('c_paid_default', 'phev', 'charge', [T('odometer_km', '10100'), T('charge_kwh', '10'), T('charge_unit_price', '1.2')]);
add('c_soc_price_amount', 'phev', 'charge', [T('odometer_km', '10100'), T('soc_before_pct', '10'), T('soc_after_pct', '90'), T('charge_unit_price', '0.3')]);
add('c_fuel_level', 'phev', 'charge', [T('odometer_km', '10100'), T('fuel_level_before_pct', '40'), T('charge_kwh', '9')]);
add('c_pub_place', 'phev', 'charge', [T('odometer_km', '10100'), ['place', 13], T('charge_kwh', '20')]);
add('c_start_only', 'phev', 'charge', [T('odometer_km', '10100'), T('soc_before_pct', '20'), ['place', 11], ['start']]);
add('c_missed', 'phev', 'charge', [T('odometer_km', '10100'), ['check', 'missed_before', true], T('charge_kwh', '9')]);
// 快照与校验
add('s_basic', 'phev', 'snapshot', [T('odometer_km', '10100'), T('soc_before_pct', '55'), ['chip', 'snap', 'before_park']]);
add('s_empty', 'phev', 'snapshot', [['check', 'odo_unknown', true]]);
add('s_fuel_only', 'phev', 'snapshot', [T('odometer_km', '10100'), T('fuel_level_before_pct', '40')]);
add('s_bars', 'phevB', 'snapshot', [T('odometer_km', '10100'), ['bar', 'fuel_level_before_pct', 5]]);
add('v_fuel_empty', 'phev', 'fuel', [T('odometer_km', '10100')]);
add('v_soc_range', 'phev', 'charge', [T('odometer_km', '10100'), T('soc_before_pct', '120')]);
add('src_backfill', 'phev', 'fuel', [T('occurred_at', '2026-09-01T08:00'), T('odometer_km', '8000'), T('fuel_liters', '20')]);
// 编辑已保存的记录
const CH = { kind: 'charge', occurred_at: '2026-10-26T20:00', odometer_km: 10100, odometer_estimated: false, charge_type: 'home', charge_kwh: 16, soc_before_pct: 10, soc_after_pct: 90, amount_cents: 480, charge_unit_price: 0.3, estimated_fields: ['charge_kwh'], source: 'manual', note: 'x', place_id: 11, place_name: '家里车位', missed_before: false };
add('e_charge_est', 'phev', 'charge', [], { record: CH });
add('e_charge_change_soc', 'phev', 'charge', [T('soc_after_pct', '80')], { record: CH });
add('e_charge_change_kwh', 'phev', 'charge', [T('charge_kwh', '15')], { record: CH });
add('e_charge_clear_kwh', 'phev', 'charge', [T('charge_kwh', '')], { record: CH });
const DELIVERY = { kind: 'snapshot', occurred_at: '2025-12-31T09:00', odometer_km: 12, odometer_estimated: false, snapshot_tag: 'delivery', fuel_level_before_pct: 10.42, soc_before_pct: null, estimated_fields: ['fuel_before_pct'], source: 'manual', note: '提车' };
add('e_delivery_snapshot', 'phev', 'snapshot', [], { record: DELIVERY });
add('e_delivery_snapshot_odo', 'phev', 'snapshot', [T('odometer_km', '15')], { record: DELIVERY });
add('e_delivery_snapshot_fuel_changed', 'phev', 'snapshot', [T('fuel_level_before_pct', '20')], { record: DELIVERY });
add('e_ledger_start', 'phev', 'snapshot', [], { record: { kind: 'snapshot', occurred_at: '2026-06-01T08:00', odometer_km: 9800, snapshot_tag: 'ledger_start', soc_before_pct: 40, fuel_level_before_pct: 40, estimated_fields: [], source: 'manual', note: '' } });
add('e_odo_estimated', 'phev', 'fuel', [], { record: { kind: 'fuel', occurred_at: '2026-10-25T08:00', odometer_km: 10050, odometer_estimated: true, fuel_liters: 20, fuel_unit_price: 7.5, amount_cents: 15000, fuel_is_full: false, fuel_grade: '92', estimated_fields: ['odometer_km'], source: 'manual', note: '' } });
add('e_source_import', 'phev', 'fuel', [], { record: { kind: 'fuel', occurred_at: '2026-01-25T08:00', odometer_km: 5050, odometer_estimated: false, fuel_liters: 20, fuel_unit_price: 7.5, amount_cents: 15000, fuel_is_full: true, fuel_grade: '92', estimated_fields: [], source: 'import', note: '导入' } });
const FE = { kind: 'fuel', occurred_at: '2026-10-25T08:00', odometer_km: 10050, odometer_estimated: false, fuel_liters: 33.6, fuel_unit_price: 7.5, amount_cents: 25200, fuel_is_full: true, fuel_grade: '92', fuel_level_before_pct: 30, estimated_fields: ['fuel_l', 'fuel_before_pct'], source: 'manual', note: '' };
add('e_fuel_est', 'phev', 'fuel', [], { record: FE });
add('e_fuel_est_price', 'phev', 'fuel', [T('fuel_unit_price', '7.6')], { record: FE });
add('e_fuel_est_liters', 'phev', 'fuel', [T('fuel_liters', '30')], { record: FE });
add('e_fuel_est_toggle_full', 'phev', 'fuel', [['check', 'fuel_is_full', false]], { record: FE });

const AMT = ['200+15', '(1+2)*3', '1/3', '2*-3', '1,000.5', '¥12', '1++2', '', 'abc', '5.', '.5', '1/0', '--1', '12 + 3', '0.1+0.2', '3*(2+', '1e3', '１２', '2*3+4*5', '10/4', '-5', '+5'];
const NUMS = [[1234.5, 2], [30, 2], [null, 2], [0.1 + 0.2, 2], [1234.567, 2], [0.125, 2], [2.5, 0], [-2.5, 0], [1e6, 2], [12345.678, 1], [0, 2], [100, 0], [18.35, 1], [1.005, 2]];
const MONEY = [[0], [1], [99], [12345], [1000000], [-550], [100000000], [null], [123456.7], [5, true], [-5, true], [999999]];
const GAUGE = [[40, 'pct', null, null], [40.4, 'pct', null, null], [37.5, 'liters', 48, null], [37.5, 'bars', null, 8], [null, 'pct', null, null], [0, 'pct', null, null], [100, 'liters', 48, null], [20, 'liters', null, null]];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
window.__H.cases = C; window.__H.AMT = AMT; window.__H.NUMS = NUMS; window.__H.MONEY = MONEY; window.__H.GAUGE = GAUGE;
window.__H.VEH = VEH; window.__H.P = P; window.__H.sleep = sleep;
// odo / 路径类算例补一个加油量，避免被「请至少填写加油量或金额」拦住
const L = ['fuel_liters', '20'];
for (const c of C) {
  if (['odo_delta', 'odo_negative', 'odo_big', 'odo_backfill', 'odo_backfill_greater', 'odo_backfill_between', 'f_place_gas'].includes(c.name)) c.act.push(['type', ...L]);
  if (c.name === 'f_same_last') c.act.push(['type', 'odometer_km', '10350'], ['type', 'fuel_liters', '20']);
  if (c.record) c.record = { id: 1, ...c.record };
}
})();

window.__H.run = async () => {
  const H = window.__H;
  const rf = await import('/static/js/record-form.js');
  const util = await import('/static/js/util.js');
  const stt = await import('/static/js/state.js');
  const sleep = H.sleep;
  const realFetch = window.__realFetch || (window.__realFetch = window.fetch.bind(window));
  const json = (o) => new Response(JSON.stringify(o), { status: 200, headers: { 'content-type': 'application/json' } });
  const NUMF = ['odometer_km', 'fuel_liters', 'fuel_unit_price', 'amount', 'paid', 'extra_fee', 'fuel_level_before_pct', 'fuel_level_after_pct', 'soc_before_pct', 'soc_after_pct', 'charge_kwh', 'charge_unit_price', 'charge_minutes', 'energy_fee', 'service_fee'];
  const results = [];
  // 用户的油量单位偏好会影响推算位数，生成时按未设置处理
  if (stt.state.user?.settings) delete stt.state.user.settings.fuel_unit;
  for (const c of H.cases) {
    Object.keys(localStorage).filter((k) => k.startsWith('vt:draft') || k.startsWith('vt:place')).forEach((k) => localStorage.removeItem(k));
    document.querySelectorAll('.sheet-root').forEach((e) => e.remove());
    const vehicle = { id: 1, name: 'T', plate: '', energy_type: 'phev', has_fuel: true, has_elec: true, tank_capacity_l: 48, battery_usable_kwh: 18.3, charge_limit_pct: 100, default_fuel_grade: '92', default_charge_type: 'home', fuel_gauge_mode: 'pct', fuel_gauge_bars: null, factory_fuel_l: 5, record_style: 'detailed', role: 'owner', is_archived: false, ...H.VEH[c.veh] };
    const prefill = { ...H.P, ...(c.prefill || {}) };
    let captured = null;
    window.fetch = async (url, opts = {}) => {
      const u = String(url);
      if (u.startsWith('/api/records/prefill')) return json(prefill);
      if (u.includes('/members')) return json([]);
      if ((u === '/api/records' || /^\/api\/records\/\d+$/.test(u)) && (opts.method === 'POST' || opts.method === 'PUT')) {
        captured = JSON.parse(opts.body);
        return json({ record: { ...captured, id: 1, version: 1, vehicle_id: 1 }, segments: [], warnings: [] });
      }
      return realFetch(url, opts);
    };
    const record = c.record ? { type: 'record', vehicle_id: 1, version: 1, ...c.record } : null;
    const done = rf.openRecordForm({ kind: c.kind, vehicle, record, finish: false });
    for (let i = 0; i < 100 && !document.querySelector('form.rec-form [name=occurred_at]'); i++) await sleep(20);
    await sleep(40);
    const form = document.querySelector('form.rec-form');
    const q = (s) => form.querySelector(s);
    const fire = (el, ev) => el.dispatchEvent(new Event(ev, { bubbles: true }));
    if (!record) { form.occurred_at.value = '2026-10-27T08:30'; fire(form.occurred_at, 'input'); }
    for (const a of c.act) {
      const [t, n, v] = a;
      if (t === 'type') { const i = form.elements[n]; i.value = v; fire(i, 'input'); }
      else if (t === 'check') { const i = form.elements[n]; i.checked = v; fire(i, 'change'); }
      else if (t === 'chip') q(`[data-${n}] .chip[data-v="${v}"]`).click();
      else if (t === 'place') q(`[data-place-chips] .chip[data-v="${n}"]`).click();
      else if (t === 'bar') q(`[data-f="${n}"] [data-b="${v}"]`).click();
      else if (t === 'lit') { const i = q(`[data-f="${n}"] [data-lit]`); i.value = v; fire(i, 'input'); }
      else if (t === 'same') q('[data-same]').click();
      else if (t === 'start') q('[data-start-charge] button').click();
      await sleep(5);
    }
    await sleep(30);
    const f = {};
    for (const n of NUMF) {
      const i = form.elements[n];
      if (!i || i.value === '') continue;
      f[n] = [i.value, i.dataset.auto ? 'a' : i.dataset.user ? 'u' : ''];
    }
    const lit = q('[data-lit]');
    const lv = {};
    form.querySelectorAll('.lv-val').forEach((e) => { if (e.textContent) lv[e.closest('[data-f]').dataset.f] = e.textContent; });
    const note = q('.tariff-note');
    const chips = {};
    for (const k of ['fuel_grade', 'charge_type', 'snapshot_tag']) if (form.dataset[k]) chips[k] = form.dataset[k];
    const sel = {};
    ['trip_mode', 'odo_unknown', 'fuel_is_full', 'charge_to_limit', 'missed_before'].forEach((n) => { if (form.elements[n]) sel[n] = form.elements[n].checked; });
    const out = {
      f, lv, chips, sel,
      lit: lit ? lit.value : undefined,
      odo: q('.odo-delta') ? { t: q('.odo-delta').textContent, w: q('.odo-delta').classList.contains('warn-c') } : undefined,
      odoPh: form.odometer_km ? form.odometer_km.placeholder : undefined,
      odoDisabled: form.odometer_km ? form.odometer_km.disabled : undefined,
      paidPh: form.paid ? form.paid.placeholder : undefined,
      disc: q('.discount') ? q('.discount').textContent : undefined,
      tariff: note && !note.classList.contains('hidden') ? note.textContent : undefined,
      place: q('[data-place-chips] .chip.on') ? q('[data-place-chips] .chip.on').dataset.v : undefined,
    };
    const btn = c.act.some((a) => a[0] === 'start') ? null : document.querySelector('.sheet-foot [data-save]');
    if (btn) { btn.click(); await sleep(120); } else await sleep(120);
    const err = document.querySelector('form.rec-form .form-error');
    out.err = err ? err.textContent : '';
    if (captured) {
      const b = { ...captured };
      delete b.client_id; delete b.version;
      for (const k of Object.keys(b)) if (b[k] === null) delete b[k];
      out.body = b;
    }
    const x = document.querySelector('.sheet-x'); if (x) x.click();
    await Promise.race([done, sleep(500)]);
    await sleep(60);
    results.push({ ...c, expected: out });
  }
  window.fetch = realFetch;
  const util_ = {
    amount: H.AMT.map((s) => [s, util.evalAmount(s)]),
    num: H.NUMS.map(([x, d]) => [x, d, util.num(x, d), util.fixed(x, d)]),
    km: [0, 12.5, 12345.6, 999.5, 1000, null].map((x) => [x, util.km(x)]),
    money: H.MONEY.map(([c, s]) => [c, !!s, util.money(c, { sign: !!s })]),
    gauge: H.GAUGE.map(([p, m, t, b]) => [p, m, t, b, stt.fuelLevelText(p, { fuel_gauge_mode: m, tank_capacity_l: t, fuel_gauge_bars: b })]),
    pct: [[null, null], [5, 0.5], [0, 0]].map(([a, b]) => [a, b, util.pctChange(a, b)]),
  };
  return { vehicles: H.VEH, prefill: H.P, cases: results, util: util_ };
};
