'use strict';
(() => {
  const audit = JSON.parse(document.getElementById('audit-data').textContent);
  const $ = id => document.getElementById(id);
  const list = value => Array.isArray(value) ? value : value == null ? [] : [value];
  const text = value => value == null || value === '' ? '—' : String(value);
  const human = value => text(value).replaceAll('-', ' ');
  const dateCell = (value, source) => {
    if (!value) return null;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return null;
    const cell = document.createElement('time');
    cell.dateTime = value;
    cell.dataset.sortValue = value;
    cell.textContent = /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : date.toLocaleString();
    cell.title = source || 'Filesystem timestamp; not a verified installation date';
    return cell;
  };
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
    packages: {title:'Packages by environment',help:'Find Open WebUI, PyTorch or any distribution by name, version or path. Entries come from local METADATA / PKG-INFO files. Different environments and duplicate versions remain separate. No interpreter or package was executed.',columns:['Package','Version','Environment / scope','Estimated size','RECORD coverage','Description','Metadata location','Declared dependencies'],rows:list(audit.packages),values:r=>[r.Name,r.Version,r.EnvironmentRoot,sizeCell(r),pill(r.SizeCoverage),r.Summary,details(r.MetadataStatus==='read'?r.MetadataKind:'Incomplete metadata',[r.MetadataPath,`Package directory: ${r.SitePackages}`,`Scope: ${r.Scope}`,`${r.FilesWithDeclaredSize} of ${r.RecordedFiles} recorded files have declared sizes`]),list(r.RequiresDist).filter(Boolean).length?details(`${list(r.RequiresDist).filter(Boolean).length} declarations`,r.RequiresDist):'None recorded']},
    packageLocations: {title:'Package inventory coverage',help:'Known package directories examined at analysis time, independently of the earlier executable scan. Missing or inaccessible locations do not prove that an environment has no packages. No .pth, .start or custom startup code is followed.',columns:['Environment / scope','Package location','Status','Metadata entries'],rows:list(audit.packageLocations),values:r=>[packageScope(r.EnvironmentId)?.Root||r.EnvironmentId,r.Path,pill(r.Status),r.Packages]},
    packageIssues: {title:'Package metadata issues',help:'Unreadable, oversized or malformed metadata and linked locations excluded from the package inventory. Executable scan errors are listed separately.',columns:['Path','Operation','Details'],rows:list(audit.packageIssues),values:r=>[r.Path,human(r.Operation),r.Reason]},
    runtimes: {title:'Runtime folders',help:'Candidate environments grouped by directory. File created is the earliest executable creation timestamp in each group. Neither grouping nor absence of observed dependents proves that a runtime is safe to remove.',columns:['Folder','Category','File versions','Install date (registry)','File created','Observed venv dependents','Executable paths'],rows:list(audit.runtimes),values:r=>[r.Root,pill(r.Category),list(r.FileVersions).join(', '),dateCell(r.RegisteredInstallDate,list(r.InstallDateSources).join('\n')),dateCell(r.FirstFileCreatedUtc),list(r.ObservedDependentEnvironments).length ? details(`${list(r.ObservedDependentEnvironments).length} configurations`,r.ObservedDependentEnvironments) : 'None observed',details(`${r.Paths} paths`,r.Executables)]},
    dependencies: {title:'Base Python → virtual environments',help:'Relations come from the home field in pyvenv.cfg. Accessible means the directory was found, not that an interpreter was executed successfully.',columns:['Resolved base directory','Accessibility','Dependent configurations'],rows:list(audit.dependencies),values:r=>[r.ResolvedBaseHome,pill(r.Accessible?'Accessible':'Unavailable'),details(`${list(r.Environments).length} configurations`,r.Environments)]},
    files: {title:'All executable paths',help:'Every matching Windows executable path found by the scan, including aliases, templates and backups. Hover dates to inspect their source. Classification is based on filesystem evidence and documented path heuristics.',columns:['Path','Category','File version metadata','Configured base','Install date (registry)','File created','File modified'],rows:list(audit.files),values:r=>[r.Path,pill(r.Category),r.FileVersion,r.BaseHome,dateCell(r.RegisteredInstallDate,r.InstallDateSource),dateCell(r.CreationTimeUtc,r.FileDateSource),dateCell(r.LastWriteTimeUtc,r.FileDateSource)]},
    commands: {title:'Command resolution',help:'Resolution in the auditor PowerShell process. Your interactive shell profile can add aliases or functions. No discovered command was executed.',columns:['Command','Priority','Type','Source'],rows:list(audit.commands),values:r=>[r.Command,r.Priority,r.Type,r.Source]},
    findings: {title:'Findings to review',help:'Review the evidence before any change. This tool does not delete files, uninstall software, modify PATH or assert that an environment is unused.',columns:['Severity','Finding','Path','Evidence'],rows:list(audit.findings),values:r=>[pill(r.Severity),human(r.Code),r.Path,r.Message]},
    issues: {title:'Scan issues',help:'Access denials, inaccessible link targets and unreadable metadata limit completeness. Multiple operations can report the same directory.',columns:['Path','Operation','Details'],rows:list(audit.issues),values:r=>[r.Path,human(r.Operation),r.Reason]}
  };
  const packageEnvironments = list(audit.packageEnvironments);
  const packageScope = id => packageEnvironments.find(environment=>environment.Id===id);
  const sizeCell = row => {
    if (row.EstimatedBytes == null) return null;
    const node=document.createElement('span'), bytes=Number(row.EstimatedBytes);
    node.dataset.sortValue=String(bytes);
    const unit=bytes>=1073741824?'GiB':bytes>=1048576?'MiB':bytes>=1024?'KiB':'B';
    const divisor={GiB:1073741824,MiB:1048576,KiB:1024,B:1}[unit];
    node.textContent=`${(bytes/divisor).toLocaleString(undefined,{maximumFractionDigits:1})} ${unit}`;
    node.title=`${bytes.toLocaleString()} declared bytes; ${row.SizeCoverage} RECORD coverage. Not measured disk usage.`;
    return node;
  };
  const packageLink = root => {
    const scope=packageScope(root);if (!scope) return null;
    const node=document.createElement('button');node.type='button';node.className='package-link';
    node.dataset.packageEnvironment=root;node.dataset.sortValue=String(scope.PackageCount);
    node.textContent=`View ${scope.PackageCount} packages`;
    node.setAttribute('aria-label',`View package metadata in ${root}`);return node;
  };
  views.runtimes.columns.push('Packages');
  const runtimeValues=views.runtimes.values;
  views.runtimes.columns[0]='Runtime / folder';
  views.runtimes.values=row=>{
    const values=runtimeValues(row);
    // Older reports still get a readable Store label from the observed path convention.
    const store=row.Root.match(/\\WindowsApps\\PythonSoftwareFoundation\.Python\.(\d+\.\d+)_/i);
    const displayName=row.DisplayName||(store?`Python ${list(row.FileVersions).join(', ')||store[1]} · Microsoft Store`:null);
    if (displayName) {
      const node=document.createElement('div');node.className='runtime-root';node.dataset.sortValue=row.Root;
      const name=document.createElement('strong');name.textContent=displayName;
      const path=document.createElement('code');path.textContent=row.Root;node.append(name,path);values[0]=node;
    }
    return [...values,packageLink(row.Root)];
  };
  $('metric-paths').textContent = text(audit.summary.ExecutablePaths);
  $('metric-runtimes').textContent = text(audit.summary.RuntimeFolders);
  $('metric-venvs').textContent = text(audit.summary.VirtualEnvironments);
  $('metric-findings').textContent = text(audit.summary.Findings);
  $('coverage').textContent = audit.scan.IsSynthetic ? 'Synthetic demonstration — no filesystem was scanned. All paths and values below are examples.' : `${audit.scan.Completed ? 'Completed' : 'Partial'} · ${Number(audit.scan.DirectoriesVisited).toLocaleString()} directories · ${audit.scan.ElapsedSeconds} s · Roots: ${list(audit.scan.Roots).join(', ')}`;
  if (audit.scan.IsSynthetic) document.querySelector('.status').textContent='Synthetic demo';
  let current = 'runtimes';
  const sorts = {runtimes:{index:4,direction:-1},files:{index:5,direction:-1},packages:{index:0,direction:1}};
  for (const environment of packageEnvironments) {
    const option=document.createElement('option');option.value=environment.Id;
    option.textContent=`${environment.Root} · ${environment.PackageCount} packages${environment.Scope==='user-site'?' · shared user-site candidate':''}`;
    $('package-environment').append(option);
  }
  const sortValue = value => value instanceof Node ? value.dataset?.sortValue ?? value.textContent : value;
  const collator = new Intl.Collator(undefined,{numeric:true,sensitivity:'base'});
  function render() {
    const view=views[current], query=$('search').value.toLocaleLowerCase();
    const selected=$('package-environment').value;
    const rows=view.rows.filter(row=>(!['packages','packageLocations'].includes(current)||!selected||row.EnvironmentId===selected)&&(JSON.stringify(row)+(current==='runtimes'&&/\\WindowsApps\\PythonSoftwareFoundation\.Python\./i.test(row.Root)?' Microsoft Store':'')).toLocaleLowerCase().includes(query)).map(row=>({values:view.values(row)}));
    const sort=sorts[current];
    if (sort) rows.sort((a,b)=>{
      const left=sortValue(a.values[sort.index]),right=sortValue(b.values[sort.index]);
      const leftMissing=left==null||left==='',rightMissing=right==null||right==='';
      if (leftMissing||rightMissing) return leftMissing===rightMissing?0:leftMissing?1:-1;
      if (current==='packages'&&sort.index===3) return (Number(left)-Number(right))*sort.direction;
      return collator.compare(String(left),String(right))*sort.direction;
    });
    $('section-title').textContent=view.title; $('section-help').textContent=view.help;
    const packageView=['packages','packageLocations','packageIssues'].includes(current);
    $('runtime-controls').hidden=current!=='runtimes';
    for(const button of document.querySelectorAll('[data-runtime-filter]'))button.setAttribute('aria-pressed',String(button.dataset.runtimeFilter.toLocaleLowerCase()===query));
    $('package-controls').hidden=!['packages','packageLocations'].includes(current);
    $('package-help').hidden=!packageView;
    $('package-help').textContent=audit.packageSummary?`${audit.packageSummary.Packages.toLocaleString()} metadata entries · ${audit.packageSummary.Environments} environment scopes · ${audit.packageSummary.LocationsScanned} locations scanned · ${audit.packageSummary.Issues} issues. Size = sum of declared RECORD bytes; blank sizes remain unknown. Editable sources, unlisted files and shared files can make estimates incomplete; totals are not reclaimable space.`:'Package inventory is not present in this older report. Run the package inventory and regenerate the HTML from the existing report directory; no full drive scan is needed.';
    const environment=packageScope(selected);
    $('package-scope-info').textContent=environment?`${environment.PackageCount} metadata entries · ${environment.LocationsScanned} locations scanned · ${environment.Issues} issues. ${environment.Scope==='user-site'?'Shared user-site candidate: visibility to a particular interpreter is not verified.':'Local package metadata only; inherited base/user packages are not merged.'}`:'Each package keeps its environment. Shared user sites appear separately; importability and active dependency markers are not verified.';
    const head=document.createElement('tr');
    view.columns.forEach((label,index)=>{
      const cell=document.createElement('th');cell.scope='col';
      const active=sort?.index===index;
      cell.setAttribute('aria-sort',active?(sort.direction===1?'ascending':'descending'):'none');
      const button=document.createElement('button');button.type='button';button.className='sort-button';button.dataset.sortColumn=String(index);
      button.textContent=label+(active?(sort.direction===1?' ↑':' ↓'):' ↕');
      button.setAttribute('aria-label',`Sort by ${label}, ${active&&sort.direction===1?'descending':'ascending'}`);
      cell.append(button);head.append(cell);
    });
    $('table-head').replaceChildren(head);
    const fragment=document.createDocumentFragment();
    for (const row of rows) {
      const line=document.createElement('tr');
      for (const value of row.values) {
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
  $('runtime-controls').addEventListener('click',event=>{
    const button=event.target.closest('[data-runtime-filter]');if(!button)return;
    $('search').value=button.dataset.runtimeFilter;render();
  });
  $('package-environment').addEventListener('change',render);
  $('table-body').addEventListener('click',event=>{
    const button=event.target.closest('[data-package-environment]');if(!button)return;
    current='packages';$('package-environment').value=button.dataset.packageEnvironment;$('search').value='';render();
    $('section-title').scrollIntoView({block:'nearest'});$('package-environment').focus();
  });
  $('table-head').addEventListener('click',event=>{
    const button=event.target.closest('button[data-sort-column]');if(!button)return;
    const index=Number(button.dataset.sortColumn),previous=sorts[current];
    sorts[current]={index,direction:previous?.index===index?-previous.direction:1};render();
    $('table-head').querySelector(`[data-sort-column="${index}"]`)?.focus();
  });
  $('tabs').addEventListener('click',event=>{const button=event.target.closest('button[data-view]');if (!button) return;current=button.dataset.view;$('search').value='';render();});
  render();
})();
