'use strict';
(() => {
  const audit = JSON.parse(document.getElementById('audit-data').textContent);
  const $ = id => document.getElementById(id);
  const list = value => Array.isArray(value) ? value : value == null ? [] : [value];
  const text = value => value == null || value === '' ? '—' : String(value);
  const human = value => text(value).replaceAll('-', ' ');
  const details = (label, values) => {
    const container = document.createElement('details');
    const summary = document.createElement('summary'); summary.textContent = label.replace(/^1 (configurations|paths)$/,(_,word)=>`1 ${word.slice(0,-1)}`);
    const body = document.createElement('pre'); body.textContent = list(values).join('\n');
    container.append(summary, body); return container;
  };
  const pill = value => {
    const node = document.createElement('span'); node.className = 'pill'; node.textContent = human(value);
    if (value === 'warning' || value === 'Unavailable') node.classList.add('warning');
    return node;
  };
  const views = {
    runtimes: {title:'Runtime folders',help:'Candidate environments grouped by directory. Neither grouping nor absence of observed dependents proves that a runtime is safe to remove.',columns:['Folder','Category','File versions','Observed venv dependents','Executable paths'],rows:list(audit.runtimes),values:r=>[r.Root,pill(r.Category),list(r.FileVersions).join(', '),list(r.ObservedDependentEnvironments).length ? details(`${list(r.ObservedDependentEnvironments).length} configurations`,r.ObservedDependentEnvironments) : 'None observed',details(`${r.Paths} paths`,r.Executables)]},
    dependencies: {title:'Base Python → virtual environments',help:'Relations come from the home field in pyvenv.cfg. Accessible means the directory was found, not that an interpreter was executed successfully.',columns:['Resolved base directory','Accessibility','Dependent configurations'],rows:list(audit.dependencies),values:r=>[r.ResolvedBaseHome,pill(r.Accessible?'Accessible':'Unavailable'),details(`${list(r.Environments).length} configurations`,r.Environments)]},
    files: {title:'All executable paths',help:'Every matching Windows executable path found by the scan, including aliases, templates and backups. Classification is based on filesystem evidence and documented path heuristics.',columns:['Path','Category','File version metadata','Configured base'],rows:list(audit.files),values:r=>[r.Path,pill(r.Category),r.FileVersion,r.BaseHome]},
    commands: {title:'Command resolution',help:'Resolution in the auditor PowerShell process. Your interactive shell profile can add aliases or functions. No discovered command was executed.',columns:['Command','Priority','Type','Source'],rows:list(audit.commands),values:r=>[r.Command,r.Priority,r.Type,r.Source]},
    findings: {title:'Findings to review',help:'Review the evidence before any change. This tool does not delete files, uninstall software, modify PATH or assert that an environment is unused.',columns:['Severity','Finding','Path','Evidence'],rows:list(audit.findings),values:r=>[pill(r.Severity),human(r.Code),r.Path,r.Message]},
    issues: {title:'Scan issues',help:'Access denials, inaccessible link targets and unreadable metadata limit completeness. Multiple operations can report the same directory.',columns:['Path','Operation','Details'],rows:list(audit.issues),values:r=>[r.Path,human(r.Operation),r.Reason]}
  };
  $('metric-paths').textContent = text(audit.summary.ExecutablePaths);
  $('metric-runtimes').textContent = text(audit.summary.RuntimeFolders);
  $('metric-venvs').textContent = text(audit.summary.VirtualEnvironments);
  $('metric-findings').textContent = text(audit.summary.Findings);
  $('coverage').textContent = audit.scan.IsSynthetic ? 'Synthetic demonstration — no filesystem was scanned. All paths and values below are examples.' : `${audit.scan.Completed ? 'Completed' : 'Partial'} · ${Number(audit.scan.DirectoriesVisited).toLocaleString()} directories · ${audit.scan.ElapsedSeconds} s · Roots: ${list(audit.scan.Roots).join(', ')}`;
  if (audit.scan.IsSynthetic) document.querySelector('.status').textContent='Synthetic demo';
  let current = 'runtimes';
  function render() {
    const view=views[current], query=$('search').value.toLocaleLowerCase();
    const rows=view.rows.filter(row=>JSON.stringify(row).toLocaleLowerCase().includes(query));
    $('section-title').textContent=view.title; $('section-help').textContent=view.help;
    const head=document.createElement('tr');
    for (const label of view.columns) { const cell=document.createElement('th');cell.scope='col';cell.textContent=label;head.append(cell); }
    $('table-head').replaceChildren(head);
    const fragment=document.createDocumentFragment();
    for (const row of rows) {
      const line=document.createElement('tr');
      for (const value of view.values(row)) {
        const cell=document.createElement('td');
        if (value instanceof Node) cell.append(value);
        else { cell.textContent=text(value); if (typeof value==='string' && (value.includes('\\') || value.includes('/'))) cell.className='path'; }
        line.append(cell);
      }
      fragment.append(line);
    }
    $('table-body').replaceChildren(fragment);
    $('empty-state').hidden=rows.length>0;
    $('result-count').textContent=`${rows.length} of ${view.rows.length} ${view.rows.length===1?'entry':'entries'}`;
    for (const button of document.querySelectorAll('[data-view]')) button.setAttribute('aria-pressed',String(button.dataset.view===current));
  }
  $('search').addEventListener('input',render);
  $('tabs').addEventListener('click',event=>{const button=event.target.closest('button[data-view]');if (!button) return;current=button.dataset.view;$('search').value='';render();});
  render();
})();
