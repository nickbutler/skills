'use strict';

const STATUS = ['passing', 'in progress', 'ready', 'draft', 'failing', 'deferred', 'no status'];
const VAR = s => `var(--${(s || 'draft').replace(/\s/g, '')})`;
const $ = s => document.querySelector(s);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};
const get = async path => {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${r.status} ${path}`);
  return r.json();
};

let SPEC = null;

/* --- a small markdown renderer -------------------------------------------
   Enough for the shapes the spec templates produce. No CDN: the viewer has
   to work offline, on a plane, against a repo that has no network. */
const esc = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, (_, c) => `<code>${c}</code>`)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|\W)\*([^*\n]+)\*/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, t, href) => `<a href="${route(href)}">${t}</a>`);
}

/* Links between spec files become in-app routes, so the docs navigate. */
function route(href) {
  const m = href.match(/(?:\.\.\/)?(features|ADR|changes)\/(?:archive\/)?([^/)]+)\.(?:md|feature)$/);
  if (m) return `#/${{ features: 'feature', ADR: 'adr', changes: 'change' }[m[1]]}/${m[2]}`;
  const sib = href.match(/^\.?\/?([\w.-]+)\.(?:md|feature)$/);
  if (sib && SPEC && [...SPEC.features, ...SPEC.archived].some(f => f.slug === sib[1]))
    return `#/feature/${sib[1]}`;
  if (/^(ARCHITECTURE|DATA_MODEL|INDEX|SYNC_REPORT)\.md$/.test(href))
    return `#/doc/${href.replace('.md', '').toLowerCase().replace('_', '-')}`;
  if (/^GAPS\.md$/.test(href)) return '#/gaps';
  return href;
}

/* Does this line open a new block? Anything that doesn't is a continuation of
   the one before it — markdown's lazy wrapping, which the spec templates use
   heavily in bullets and blockquotes. */
const starts = line => /^(\s*(?:[-*]|\d+\.)\s|#{1,6}\s|>|\||```|\s*(?:-{3,}|\*{3,})\s*$)/.test(line);

function markdown(src) {
  const out = [];
  const lines = (src || '').split('\n');
  let i = 0, list = null;
  const closeList = () => { if (list) { out.push(`</${list}>`); list = null; } };

  while (i < lines.length) {
    const line = lines[i];
    if (/^```/.test(line)) {                                     // fenced code
      const buf = [];
      for (i++; i < lines.length && !/^```/.test(lines[i]); i++) buf.push(lines[i]);
      i++;
      closeList();
      out.push(`<pre>${esc(buf.join('\n'))}</pre>`);
      continue;
    }
    if (/^\|/.test(line) && /^\|[\s:|-]+\|?\s*$/.test(lines[i + 1] || '')) {   // table
      const row = l => l.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
      const head = row(line);
      i += 2;
      const body = [];
      while (i < lines.length && /^\|/.test(lines[i])) body.push(row(lines[i++]));
      closeList();
      out.push('<table><thead><tr>' + head.map(c => `<th>${inline(c)}</th>`).join('')
        + '</tr></thead><tbody>'
        + body.map(r => '<tr>' + r.map(c => `<td>${inline(c)}</td>`).join('') + '</tr>').join('')
        + '</tbody></table>');
      continue;
    }
    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) { closeList(); out.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`); i++; continue; }
    if (/^\s*(-{3,}|\*{3,})\s*$/.test(line)) { closeList(); out.push('<hr>'); i++; continue; }
    if (/^>\s?/.test(line)) {                                   // blockquote, possibly wrapped
      closeList();
      const buf = [];
      while (i < lines.length && (/^>\s?/.test(lines[i]) || (buf.length && lines[i].trim() && !starts(lines[i]))))
        buf.push(lines[i++].replace(/^>\s?/, ''));
      out.push(`<blockquote>${inline(buf.join(' '))}</blockquote>`);
      continue;
    }

    const task = line.match(/^\s*[-*]\s+\[([ xX])\]\s+(.*)$/);
    if (task) {
      closeList();
      out.push(`<div class="task${task[1] === ' ' ? '' : ' done'}"><span class="box">`
        + `${task[1] === ' ' ? '☐' : '☑'}</span><span>${inline(task[2])}</span></div>`);
      i++; continue;
    }
    const li = line.match(/^\s*([-*]|\d+\.)\s+(.*)$/);
    if (li) {                                                   // list item, possibly wrapped
      const want = /^\d/.test(li[1]) ? 'ol' : 'ul';
      if (list !== want) { closeList(); out.push(`<${want}>`); list = want; }
      const buf = [li[2]];
      i++;
      while (i < lines.length && lines[i].trim() && !starts(lines[i])) buf.push(lines[i++].trim());
      out.push(`<li>${inline(buf.join(' '))}</li>`);
      continue;
    }
    if (!line.trim()) { closeList(); i++; continue; }
    const buf = [];
    while (i < lines.length && lines[i].trim() && !starts(lines[i])) buf.push(lines[i++]);
    closeList();
    out.push(`<p>${inline(buf.join(' '))}</p>`);
  }
  closeList();
  return out.join('\n');
}

const prose = src => {
  const d = el('div', 'prose');
  d.innerHTML = markdown(src);
  return d;
};

/* --- chrome --------------------------------------------------------------- */
function pill(status) {
  const p = el('span', 'pill', status || 'no status');
  p.style.color = VAR(status);
  return p;
}

function renderHeader() {
  $('#setname').textContent = SPEC.name;
  const bar = $('#progress');
  bar.innerHTML = '';
  const total = SPEC.features.length || 1;
  for (const s of STATUS) {
    const n = SPEC.progress[s] || 0;
    if (!n) continue;
    const seg = el('span');
    seg.style.width = `${(n / total) * 100}%`;
    seg.style.background = VAR(s);
    seg.title = `${n} ${s}`;
    bar.append(seg);
  }
  const h = $('#health');
  const bad = SPEC.validation.errors.length;
  h.className = 'health' + (bad ? ' bad' : '');
  h.textContent = bad ? `${bad} problem${bad > 1 ? 's' : ''}` : 'valid';
}

function renderNav(filter = '') {
  const nav = $('#nav');
  nav.innerHTML = '';
  const q = filter.trim().toLowerCase();
  const hit = t => !q || (t || '').toLowerCase().includes(q);

  const group = (title, items) => {
    if (!items.length) return;
    const g = el('div', 'group');
    g.append(el('h4', null, title));
    for (const it of items) g.append(it);
    nav.append(g);
  };
  const link = (href, label, colour, right) => {
    const a = el('a', 'item');
    a.href = href;
    if (location.hash === href) a.classList.add('on');
    if (colour) { const d = el('span', 'dot'); d.style.background = colour; a.append(d); }
    a.append(el('span', 'label', label));
    if (right) a.append(el('span', 'count', right));
    return a;
  };

  group('Overview', [
    link('#/', 'All features'),
    ...(SPEC.gaps ? [link('#/gaps', 'Gaps')] : []),
    link('#/validate', 'Validation', null, SPEC.validation.errors.length || ''),
  ].filter(a => hit(a.textContent)));

  group('Features', SPEC.features
    .filter(f => hit(f.slug) || hit(f.title) || hit(f.description) || hit(f.status))
    .map(f => link(`#/feature/${f.slug}`, f.title || f.slug, VAR(f.status),
      f.draft ? `${f.draft} draft` : '')));

  const open = SPEC.changes.filter(c => !c.archived);
  group('Changes', open.filter(c => hit(c.title) || hit(c.slug))
    .map(c => link(`#/change/${c.slug}`, c.title, VAR('in progress'), `${c.done}/${c.total}`)));

  // An open question must not look settled, and a rejection must stay visible:
  // negative and unresolved memory is the reason the log exists.
  const ADR_COLOUR = {
    accepted: VAR('passing'), rejected: VAR('failing'), open: VAR('in progress'),
    proposed: VAR('ready'), superseded: VAR('archived'), deprecated: VAR('archived'),
  };
  group('Decisions', SPEC.adrs.filter(a => hit(a.slug) || hit(a.description))
    .map(a => {
      const item = link(`#/adr/${a.slug}`, a.slug.replace(/^\d{4}-\d{2}-\d{2}-/, ''),
        ADR_COLOUR[a.status] || VAR('draft'), a.status);
      item.classList.add(`adr-${a.status || 'unknown'}`);
      return item;
    }));

  group('Archived', [
    ...SPEC.archived.filter(f => hit(f.slug)).map(f => link(`#/feature/${f.slug}`, f.slug, VAR('archived'))),
    ...SPEC.changes.filter(c => c.archived && hit(c.title))
      .map(c => link(`#/change/${c.slug}`, c.title, VAR('archived'))),
  ]);
}

/* --- views ---------------------------------------------------------------- */
function viewOverview(main) {
  main.append(el('h1', null, SPEC.name));
  main.append(el('p', 'sub', SPEC.validation.summary));

  main.append(el('h2', null, 'Features'));
  const grid = el('div', 'grid');
  for (const f of SPEC.features) {
    const c = el('div', 'card');
    c.onclick = () => { location.hash = `#/feature/${f.slug}`; };
    const head = el('div', 'meta');
    head.style.marginBottom = '6px';
    head.append(pill(f.status));
    c.append(head, el('h3', null, f.title || f.slug));
    if (f.description) c.append(el('div', 'meta', f.description));
    const m = el('div', 'meta');
    m.style.marginTop = '8px';
    m.append(el('span', null, `${f.scenarios} scenario${f.scenarios === 1 ? '' : 's'}`));
    if (f.draft) { const t = el('span', 'tag draft', `${f.draft} draft`); m.append(t); }
    c.append(m);
    grid.append(c);
  }
  main.append(grid);

  const open = SPEC.changes.filter(c => !c.archived);
  if (open.length) {
    main.append(el('h2', null, 'Changes in flight'));
    for (const c of open) {
      const card = el('div', 'card');
      card.onclick = () => { location.hash = `#/change/${c.slug}`; };
      card.style.cursor = 'pointer';
      card.append(el('h3', null, c.title));
      card.append(el('div', 'meta', `${c.done}/${c.total} tasks · touches ${c.features.join(', ') || '—'}`));
      main.append(card);
    }
  }
}

function scenarioNode(sc) {
  const box = el('div', 'scenario' + (sc.draft ? ' is-draft' : ''));
  const name = el('div', 'name');
  name.append(el('span', 'kw', sc.keyword + ':'), el('span', null, sc.name));
  for (const t of sc.tags || []) name.append(el('span', 'tag' + (t === '@draft' ? ' draft' : ''), t));
  box.append(name);

  const steps = el('div', 'steps');
  for (const s of sc.steps) {
    const line = el('div', 'step');
    line.append(el('span', `k ${s.keyword}`, s.keyword), el('span', null, ' ' + s.text));
    steps.append(line);
    if (s.doc && s.doc.length) steps.append(Object.assign(el('pre'), { textContent: s.doc.join('\n') }));
    if (s.table && s.table.length) steps.append(tableNode(s.table));
  }
  box.append(steps);
  if (sc.examples && sc.examples.length) {
    box.append(el('div', 'kw', 'Examples:'));
    box.append(tableNode(sc.examples));
  }
  return box;
}

function tableNode(rows) {
  const t = el('table');
  const head = el('tr');
  for (const c of rows[0]) head.append(el('th', null, c));
  t.append(head);
  for (const r of rows.slice(1)) {
    const tr = el('tr');
    for (const c of r) tr.append(el('td', null, c));
    t.append(tr);
  }
  return t;
}

/* The page header already shows the name and the status pill, so drop the
   heading and Status line the feature file opens with. */
const withoutFrontMatter = md => (md || '')
  .replace(/^\s*#\s+.*\n/, '')
  .replace(/^\s*\*\*Status\*\*:.*\n/m, '')
  .replace(/^\s+/, '');

async function viewFeature(main, slug, sha) {
  const f = await get(`/api/feature/${slug}`);
  const head = el('div', 'meta');
  head.append(pill(f.status));
  main.append(head, el('h1', null, (f.parsed && f.parsed.name) || slug));
  if (f.raw_status && f.raw_status !== f.status)
    main.append(el('p', 'sub', f.raw_status));

  if (f.changes.length) {
    const m = el('p', 'sub');
    m.append(document.createTextNode('Touched by '));
    f.changes.forEach((c, n) => {
      const a = el('a', null, c.title);
      a.href = `#/change/${c.slug}`;
      m.append(a, document.createTextNode(n < f.changes.length - 1 ? ', ' : ''));
    });
    main.append(m);
  }

  main.append(prose(withoutFrontMatter(f.markdown)));

  main.append(el('h2', null, 'Scenarios'));
  if (!f.parsed || !f.parsed.scenarios.length) main.append(el('p', 'empty', 'No scenarios.'));
  else for (const sc of f.parsed.scenarios) main.append(scenarioNode(sc));

  main.append(el('h2', null, 'History'));
  const list = el('div');
  const pane = el('div');
  main.append(list, pane);
  const { commits } = await get(`/api/history/${slug}`);
  if (!commits.length) { list.append(el('p', 'empty', 'No commits touch this feature yet.')); return; }
  const rows = new Map();
  for (const c of commits) {
    const row = el('a', 'commit');
    row.href = `#/feature/${slug}/${c.short}`;      // a diff is a link, so it is shareable
    row.append(el('span', 'sha', c.short), el('span', 'subject', c.subject),
      el('span', 'when', new Date(c.date).toLocaleDateString(undefined,
        { year: 'numeric', month: 'short', day: 'numeric' })));
    rows.set(c.short, { row, c });
    list.append(row);
  }
  HISTORY = { slug, rows, list, pane };
  if (sha) await openDiff(sha);
}

/* Selecting a commit is a route, not a click handler, so the browser's back
   button walks the history you have been reading. */
let HISTORY = null;

async function openDiff(sha) {
  if (!HISTORY) return;
  const hit = HISTORY.rows.get(sha)
    || [...HISTORY.rows.values()].find(v => v.c.sha.startsWith(sha));
  [...HISTORY.list.children].forEach(n => n.classList.remove('on'));
  if (hit) hit.row.classList.add('on');
  HISTORY.pane.innerHTML = '';
  const { diff } = await get(`/api/diff/${hit ? hit.c.sha : sha}/${HISTORY.slug}`);
  const box = el('pre', 'diff');
  for (const line of diff.split('\n')) {
    const cls = line.startsWith('+') && !line.startsWith('+++') ? 'p'
      : line.startsWith('-') && !line.startsWith('---') ? 'm'
        : /^(diff |index |@@|--- |\+\+\+ )/.test(line) ? 'h' : '';
    box.append(el('div', cls, line || ' '));
  }
  HISTORY.pane.append(box);
  if (hit) hit.row.scrollIntoView({ block: 'nearest' });
}

async function viewChange(main, slug) {
  const c = await get(`/api/change/${slug}`);
  const head = el('div', 'meta');
  head.append(pill(c.archived ? 'archived' : (c.status || 'in progress')));
  main.append(head, el('h1', null, c.title));
  const bar = el('div', 'progress');
  bar.style.maxWidth = '320px';
  const seg = el('span');
  seg.style.width = `${c.total ? (c.done / c.total) * 100 : 0}%`;
  seg.style.background = VAR('passing');
  bar.append(seg);
  main.append(bar, el('p', 'sub', `${c.done} of ${c.total} tasks done`));
  main.append(prose(c.body));
}

async function viewAdr(main, slug) {
  const a = await get(`/api/adr/${slug}`);
  const head = el('div', 'meta');
  head.append(pill(a.status));
  main.append(head);
  main.append(prose(a.body));
}

async function viewDoc(main, name) {
  const d = await get(`/api/doc/${name}`);
  main.append(prose(d.body));
}

async function viewGaps(main) {
  const g = await get('/api/gaps');
  main.append(prose(g.body || '# Gaps\n\nNone recorded.'));
}

function viewValidate(main) {
  const v = SPEC.validation;
  main.append(el('h1', null, v.ok ? 'Structure is valid' : 'Structural problems'));
  main.append(el('p', 'sub', v.summary));
  for (const e of v.errors) main.append(el('div', 'problem', e));
  for (const n of v.notes) main.append(el('p', 'sub', n));
  if (v.ok) main.append(el('p', 'empty', 'Every structural invariant holds. This says nothing about whether the specs are true — only that the set is well formed.'));
}

/* --- routing -------------------------------------------------------------- */
let SHOWING = '';

async function render() {
  const where = location.hash.replace(/^#\//, '').split('/');
  // Opening a commit on the feature already shown swaps the diff pane only,
  // so the page does not jump back to the top mid-read.
  if (where[0] === 'feature' && SHOWING === `feature/${where[1]}` && HISTORY) {
    renderNav($('#filter').value);
    return where[2] ? openDiff(where[2]) : undefined;
  }
  const main = $('#main');
  main.innerHTML = '';
  HISTORY = null;
  SHOWING = where.slice(0, 2).join('/');
  try {
    switch (where[0]) {
      case 'feature': await viewFeature(main, where[1], where[2]); break;
      case 'change': await viewChange(main, where[1]); break;
      case 'adr': await viewAdr(main, where[1]); break;
      case 'doc': await viewDoc(main, where[1]); break;
      case 'gaps': await viewGaps(main); break;
      case 'validate': viewValidate(main); break;
      default: viewOverview(main);
    }
  } catch (err) {
    main.append(el('h1', null, 'Not found'));
    main.append(el('p', 'sub', String(err.message || err)));
  }
  renderNav($('#filter').value);
  window.scrollTo(0, 0);
}

async function boot() {
  SPEC = await get('/api/spec');
  renderHeader();
  await render();
}

addEventListener('hashchange', render);
$('#filter').addEventListener('input', e => renderNav(e.target.value));
addEventListener('keydown', e => {
  if (e.key === '/' && document.activeElement !== $('#filter')) { e.preventDefault(); $('#filter').focus(); }
  if (e.key === 'Escape') { $('#filter').value = ''; renderNav(''); $('#filter').blur(); }
});
boot();
