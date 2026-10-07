// Pure helpers (no DOM, no IPC) so they can be unit-tested with node:test.
export function shortVersion(v){
  const t=String(v??"").split(/\s+(?:SHA|@?Commit)\b/i)[0].trim();
  return t.length>18?`${t.slice(0,17)}…`:t;
}

// One honest label per installed item. Unknown is never reported as current.
export function versionState(app){
  const s=String(app?.update_status||"");
  const have=shortVersion(app?.version??app?.installed_version);
  const avail=shortVersion(app?.available_version);
  if(s==="update_available"){return {key:"update",label:avail?`Update to ${avail}`:"Update available",avail:avail||"newer",cls:"update"};}
  if(s==="current"||s==="already_current"){return {key:"current",label:"Up to date",avail:avail||have,cls:"current"};}
  if(s==="installed_version_unknown"){return {key:"unknown",label:"Version unknown",avail:avail||"—",cls:"unknown"};}
  return {key:"unmatched",label:"Not tracked",avail:"—",cls:"unmatched"};
}

export function versionSummary(items){
  const out={total:0,update:0,current:0,unknown:0,unmatched:0};
  for(const a of items||[]){out.total+=1;out[versionState(a).key]+=1;}
  return out;
}

export function formatWhen(unixOrIso){
  if(typeof unixOrIso==="number"){return unixOrIso>0?new Date(unixOrIso*1000).toLocaleString():"Unknown";}
  const t=Date.parse(String(unixOrIso||""));
  return Number.isFinite(t)?new Date(t).toLocaleString():"Unknown";
}

// Latest recorded result per winget id from install_history().runs (newest first). Dry runs are ignored.
export function lastInstallByWingetId(history){
  const map=new Map();
  for(const run of history?.runs||[]){
    if(!run.executed){continue;}
    for(const r of run.results||[]){
      const key=String(r.winget_id||"").toLowerCase();
      if(key&&!map.has(key)){map.set(key,{...r,completed_utc:run.completed_utc,integrity:run.integrity});}
    }
  }
  return map;
}
