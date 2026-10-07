import "./style.css";
import {pandaSvg} from "./panda.js";
import {roomSvg} from "./scenes.js";

let workstationHealth = null;

let graph = null;
let systemProfile = null;
let systemProfileError = "";
let driverProfile = null;
let driverLoadError = "";
let softwareInventory = [];
let softwareIntelligence = null;
let errorText = "";
let showTechnical = false;
let operationMessage = "";
let setupData = null;
let setupLoadError = "";
let setupMode = "setup";
let selectedToolkitIds = new Set();
let selectedSoftwareIds = new Set();
let machineType = "desktop";
let maxAllocationGb = 100;
let setupPlan = null;
let setupResult = null;
let setupProgress = null;
let setupRunning = false;
let setupProgressPollActive = false;
let setupRecovery = null;
let setupRecoveryError = "";
let catalogSearch = "";
let catalogCategory = "all";
let receiptIndex = null;
let receiptLoadError = "";
let workstationAssurance = null;
let workstationAssuranceError = "";
let repositoryPath = "";
let repositoryAnalysis = null;
let softwareScanError = "";
let lastViewKey = "";
const countedKeys = new Set();
const escapeHtml=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[ch]));
const rawHtml=html=>({__trustedHtml:String(html)});

function sanitizeStateValue(value, depth=0){
  if(depth>10){return null;}
  if(typeof value==="string"){
    return value.slice(0,4096).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,"").replace(/[&<>"'`]/g,ch=>({"&":"＆","<":"＜",">":"＞","\"":"＂","'":"＇","`":"｀"}[ch]));
  }
  if(typeof value==="number"){return Number.isFinite(value)?value:null;}
  if(typeof value==="boolean"||value===null){return value;}
  if(Array.isArray(value)){return value.slice(0,5000).map(x=>sanitizeStateValue(x,depth+1));}
  if(typeof value==="object"){
    const clean={};
    for(const [key,item] of Object.entries(value).slice(0,5000)){
      if(["__proto__","prototype","constructor"].includes(key)){continue;}
      clean[sanitizeStateValue(key,depth+1)]=sanitizeStateValue(item,depth+1);
    }
    return clean;
  }
  return null;
}

async function invokeDesktop(command, args = {}){
  const invoke = window.__TAURI__?.core?.invoke;
  if(!invoke){ throw new Error("This action requires the installed AssembleLink desktop app."); }
  return invoke(command, args);
}

async function loadSetupData(){
  try{ setupData=JSON.parse(await invokeDesktop("get_setup_data")); setupLoadError=""; }
  catch(err){ setupData=null; setupLoadError=String(err); }
}

async function refreshSoftwareIntelligence(forceRefresh=false){
  softwareIntelligence=JSON.parse(await invokeDesktop("refresh_software_intelligence",{forceRefresh}));
  softwareInventory=(softwareIntelligence.items||[]).filter(x=>x.installed).map(x=>({
    ...x,
    version:x.installed_version,
    available_version:x.available_version,
    source:x.source
  }));
}

async function loadReceipts(){
  try{
    receiptIndex=JSON.parse(await invokeDesktop("get_receipts"));
    receiptLoadError="";
  }catch(err){
    receiptIndex=null;
    receiptLoadError=String(err);
  }
}

async function loadWorkstationAssurance(){
  try{
    workstationAssurance=sanitizeStateValue(JSON.parse(await invokeDesktop("get_workstation_assurance")));
    workstationAssuranceError="";
  }catch(err){
    workstationAssurance=null;
    workstationAssuranceError=String(err);
  }
}

async function loadSetupProgress(planId){
  if(!planId||setupProgressPollActive){return;}
  setupProgressPollActive=true;
  try{
    const next=sanitizeStateValue(JSON.parse(await invokeDesktop("get_setup_progress",{planId})));
    if(next?.schema==="assemblelink.setup_execution.progress.v1"&&next.plan_id===planId&&!(setupRunning&&next.status==="idle")){
      setupProgress=next;
    }
  }catch(_error){
    // The engine replaces this snapshot while it runs; retry a transient partial read.
  }finally{
    setupProgressPollActive=false;
  }
}

async function loadSetupRecovery(){
  try{
    const recovery=sanitizeStateValue(JSON.parse(await invokeDesktop("get_setup_recovery")));
    setupRecovery=recovery?.schema==="assemblelink.setup_recovery.v1"&&recovery.available?recovery:null;
    setupRecoveryError="";
  }catch(err){
    setupRecovery=null;
    setupRecoveryError=String(err);
  }
}

async function refreshDriverProfile(){
  try{
    driverProfile=sanitizeStateValue(JSON.parse(await invokeDesktop("refresh_driver_profile")));
    driverLoadError="";
  }catch(err){
    driverProfile=null;
    driverLoadError=String(err);
  }
}

async function refreshSystemProfile(){
  try{systemProfile=sanitizeStateValue(JSON.parse(await invokeDesktop("refresh_system_profile")));systemProfileError="";}
  catch(err){systemProfile=null;systemProfileError=String(err);}
}

function selectedAllocationEstimate(){
  const catalogItems=setupData?.catalog?.items||[];
  const toolkits=setupData?.toolkits?.toolkits||[];
  const policy=setupData?.allocation_policy;
  if(!policy){return {mib:0,itemCount:0,complete:false};}
  const catalogById=new Map(catalogItems.map(item=>[item.id,item]));
  const selected=new Set(selectedSoftwareIds);
  for(const toolkitId of selectedToolkitIds){
    const toolkit=toolkits.find(item=>item.id===toolkitId);
    for(const id of toolkit?.software_ids||[]){selected.add(id);}
  }
  let changed=true;
  while(changed){
    changed=false;
    for(const id of [...selected]){
      for(const dependency of catalogById.get(id)?.dependencies||[]){
        if(!selected.has(dependency)){selected.add(dependency);changed=true;}
      }
    }
  }
  let mib=0;
  for(const id of selected){
    const item=catalogById.get(id);
    const estimate=policy.item_overrides_mib?.[id]??policy.category_estimates_mib?.[item?.category];
    if(!Number.isInteger(Number(estimate))||Number(estimate)<=0){return {mib,itemCount:selected.size,complete:false};}
    mib+=Number(estimate);
  }
  return {mib,itemCount:selected.size,complete:true};
}

function formatAllocation(mib){
  return mib>=1024?`${(mib/1024).toFixed(mib%1024===0?0:1)} GB`:`${mib} MB`;
}

async function loadOptionalState(name){
  try{
    const response=await fetch(`./state/${name}?ts=${Date.now()}`);
    if(!response.ok){return null;}
    const text=await response.text();if(!text.trim()||text.trim().startsWith("<")){return null;}
    return sanitizeStateValue(JSON.parse(text));
  }catch(_error){return null;}
}

function buildLiveGraph(){
  const kits=setupData?.toolkits?.toolkits||[];const installed=new Set((softwareIntelligence?.items||[]).filter(x=>x.installed&&x.catalog_id).map(x=>x.catalog_id));
  const capabilities=kits.map(kit=>{const ids=kit.software_ids||[];const present=ids.filter(id=>installed.has(id));const missing=ids.filter(id=>!installed.has(id));const score=ids.length?Math.round((present.length/ids.length)*100):0;return {id:kit.id,name:kit.name,job_family:kit.job_family,status:score===100?"ready":score?"partial":"not configured",score,detected:present,missing_required:missing};});
  return {schema:"assemblelink.live_capability_graph.v1",workstation_identity:{label:"This workstation"},software_count:softwareIntelligence?.summary?.detected||softwareInventory.length,capability_count:capabilities.length,capabilities};
}

async function loadGraph(){
  const snapshot=await loadOptionalState("capability_graph.latest.json");const live=buildLiveGraph();
  graph=live.capabilities.length?{...(snapshot||{}),...live,workstation_identity:snapshot?.workstation_identity||live.workstation_identity}:snapshot||live;
  workstationHealth=await loadOptionalState("workstation_health.latest.json");
  if(!softwareIntelligence){const parsed=await loadOptionalState("application_inventory.latest.json");if(parsed){softwareInventory=Array.isArray(parsed)?parsed:[parsed];}}
}

function humanStatus(status){
  const map={
    installed_or_updated:"Installed / updated",
    installed_or_already_present:"Installed / present",
    already_current:"Already current",
    blocked_file_lock:"Blocked: files in use",
    blocked_app_running:"Blocked: app running",
    requires_admin:"Needs admin approval",
    requires_reboot:"Needs reboot",
    hash_verification_failed:"Hash verification failed",
    manual_review_required:"Manual review required",
    install_failed:"Failed",
    ready_for_user_approval:"Ready for approval",
    needs_engine_run:"Needs engine run"
    ,package_manager_unavailable:"Winget unavailable"
    ,dry_run:"Dry run"
    ,update_available:"Update available"
    ,package_identity_unavailable:"Approved package unavailable"
    ,verification_failed:"Verification failed"
    ,current:"Current"
    ,provider_unavailable:"Check unavailable"
    ,installed_version_unknown:"Version unknown"
    ,unmatched:"Not in catalog"
    ,stale_cache:"Check may be stale"
  };
  return map[status] || status || "";
}
function table(headers, rows){
  return `
    <table class="compareTable">
      <thead><tr>${headers.map(h=>`<th>${escapeHtml(h)}</th>`).join("")}</tr></thead>
      <tbody>${rows.map(r=>`<tr>${r.map(c=>`<td>${c&&typeof c==="object"&&"__trustedHtml" in c?c.__trustedHtml:escapeHtml(c)}</td>`).join("")}</tr>`).join("")}</tbody>
    </table>
  `;
}
function renderSystemProfile(){
  if(!systemProfile){ return ""; }

  const cpu = systemProfile.cpu || {};
  const mem = systemProfile.memory || {};
  const storage = systemProfile.storage || {};
  const machine = systemProfile.machine || {};
  const os = systemProfile.os || {};
  const gpus = Array.isArray(systemProfile.gpu) ? systemProfile.gpu : [];
  const drives = storage.drives || [];

  return `
    <section class="panel">
      <h2>System profile</h2>
      <p><b>${machine.name || "This machine"}</b> · ${os.caption || ""} · ${os.architecture || ""}</p>

      <div class="summaryStrip">
        <div><b>${cpu.name || "Unknown CPU"}</b><span>${cpu.cores || "?"} cores / ${cpu.logical_processors || "?"} threads</span></div>
        <div><b>${mem.total_gb || "?"} GB</b><span>system memory</span></div>
        <div><b>${gpus[0]?.name || "Unknown GPU"}</b><span>${gpus[0]?.vram_gb || "?"} GB VRAM reported</span></div>
        <div><b>${storage.free_gb || "?"} GB free</b><span>${storage.total_gb || "?"} GB total storage</span></div>
      </div>

      <h3>Drive free space</h3>
      <table class="compareTable">
        <thead><tr><th>Drive</th><th>Label</th><th>Total</th><th>Free</th><th>Status</th></tr></thead>
        <tbody>
          ${drives.map(d=>{
            const low = Number(d.free_percent) < 10;
            return `<tr>
              <td>${d.drive}</td>
              <td>${d.label || "-"}</td>
              <td>${d.total_gb} GB</td>
              <td>${d.free_gb} GB (${d.free_percent}%)</td>
              <td>${low ? "Needs cleanup" : "OK"}</td>
            </tr>`;
          }).join("")}
        </tbody>
      </table>
    </section>
  `;
}

function renderProofPanel(){
  if(!workstationAssurance){
    return `<section class="panel assuranceCard assurancePending"><div class="sectionHeading"><div><p class="eyebrow">Workstation proof</p><h2>${workstationAssuranceError?"Proof needs attention":"Verifying local evidence…"}</h2><p>${workstationAssuranceError?"One or more live evidence files could not be verified.":"Checking system, drivers, software, and the trusted catalog."}</p></div><button id="refreshAssurance" class="secondaryAction">${workstationAssuranceError?"Rebuild proof":"Refresh proof"}</button></div>${workstationAssuranceError?`<p class="assuranceError" role="status">${escapeHtml(workstationAssuranceError)}</p>`:""}</section>`;
  }
  const status=workstationAssurance.status||"incomplete";
  const statusText={verified:"Verified",attention:"Verified · review items",critical_attention:"Critical attention",incomplete:"Incomplete evidence"}[status]||humanStatus(status);
  const attention=Array.isArray(workstationAssurance.attention)?workstationAssurance.attention:[];
  const integrity=workstationAssurance.integrity||{};
  const verifiedSources=[integrity.system,integrity.driver,integrity.software].filter(x=>x==="verified").length;
  const generated=workstationAssurance.generated_unix_ms?new Date(Number(workstationAssurance.generated_unix_ms)).toLocaleString():"Just now";
  return `<section class="panel assuranceCard ${status}">
    <div class="sectionHeading"><div><p class="eyebrow">Workstation proof</p><h2>${escapeHtml(statusText)}</h2><p>Evidence refreshed ${escapeHtml(generated)} · ${verifiedSources}/3 live sources independently verified</p></div><button id="refreshAssurance" class="secondaryAction">Refresh proof</button></div>
    <div class="assuranceStrip"><div><b>${verifiedSources}/3</b><span>live evidence</span><small>System, drivers, software</small></div><div><b>${escapeHtml(workstationAssurance.inventory?.catalog_matched||0)}</b><span>managed tools</span><small>${escapeHtml((workstationAssurance.inventory?.unmatched_unique_applications ?? workstationAssurance.inventory?.unmatched) || 0)} app candidates to review</small></div><div><b>${escapeHtml(workstationAssurance.inventory?.update_status_unknown||0)}</b><span>update checks unknown</span><small>Unknown never means current</small></div><div><b>${escapeHtml(workstationAssurance.drivers?.official_support_reviews||0)}</b><span>driver reviews</span><small>No freshness claim implied</small></div></div>
    ${attention.length?`<div class="assuranceAttention">${attention.slice(0,5).map(item=>`<div class="${escapeHtml(item.severity||"info")}"><span>${item.severity==="critical"?"!":"i"}</span><p><b>${escapeHtml(item.label)}</b><small>${escapeHtml(item.detail)}</small></p></div>`).join("")}</div>`:`<p class="assuranceClear">All collected evidence passed without an attention item.</p>`}
    <p class="assuranceLimit">Local assurance covers hardware, drivers, software inventory, and catalog integrity. It does not claim malware absence, network security, or firmware freshness.</p>
  </section>`;
}

function softwareCategory(app){
  const s=((app.name||"")+" "+(app.publisher||"")).toLowerCase();

  if(s.includes("adobe") || s.includes("figma") || s.includes("canva") || s.includes("obs") || s.includes("gimp") || s.includes("audacity") || s.includes("elgato") || s.includes("focusrite") || s.includes("vlc") || s.includes("cinema 4d")) return "Creative";

  if(s.includes("unity") || s.includes("unreal") || s.includes("epic games launcher") || s.includes("blender") || s.includes("godot") || s.includes("gamemaker") || s.includes("aseprite") || s.includes("rpg maker") || s.includes("fmod")) return "Game Dev";

  if(s.includes("burp") || s.includes("wireshark") || s.includes("nmap") || s.includes("autopsy") || s.includes("wazuh") || s.includes("npcap") || s.includes("usbpcap") || s.includes("application verifier") || s.includes("ghidra") || s.includes("x64dbg")) return "Security";

  if(s.includes("visual studio") || s.includes("vs code") || s.includes("jetbrains") || s.includes("git") || s.includes("gitkraken") || s.includes("github cli") || s.includes("docker") || s.includes("python") || s.includes("node") || s.includes("rust") || s.includes("go ") || s.includes("android studio") || s.includes("postman") || s.includes("eclipse temurin") || s.includes("jdk")) return "Development";

  if(s.includes("nvidia") || s.includes("ollama") || s.includes("cuda") || s.includes("pytorch") || s.includes("geforce")) return "AI / GPU";

  if(s.includes("amd chipset") || s.includes("amd gpio") || s.includes("amd pci") || s.includes("amd psp") || s.includes("amd ryzen") || s.includes("realtek") || s.includes("driver") || s.includes("bios") || s.includes("uefi") || s.includes("asrock") || s.includes("msi")) return "Drivers / Hardware";

  if(s.includes("runtime") || s.includes("sdk") || s.includes(".net") || s.includes("redistributable") || s.includes("windows sdk") || s.includes("maui") || s.includes("asp.net") || s.includes("targeting pack")) return "Runtime / SDK";

  if(s.includes("steam") || s.includes("epic games") || s.includes("riot") || s.includes("ubisoft") || s.includes("ea app") || s.includes("rockstar") || s.includes("minecraft") || s.includes("xbox")) return "Launcher / Game";

  if(s.includes("chrome") || s.includes("brave") || s.includes("firefox") || s.includes("edge") || s.includes("discord") || s.includes("dropbox") || s.includes("copilot")) return "Everyday Apps";

  return "Other";
}


// ---------- navigation + view state (menu-bar shell) ----------
let view = "home";
let wizardStep = 1;
let openMenu = "";
let planBuilding = false;
let scanning = false;
let kitFamily = "all";
let kitSearch = "";
let invFilter = "all";
let invCategory = "all";
let invSearch = "";
let invSelected = null;
let pandaNote = "";
let uninstallSearch = "";
let uninstallBusy = "";
let uninstallMessage = "";
let selfUninstallAck = false;
let selfUninstalling = false;

const reducedMotion = () => !!window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;

const MENUS = [
  {id:"file", label:"File", items:[["go","home","Get started"],["go","wizard","Set up this computer"],["go","toolkits","Job toolkits"],["go","catalog","Software & CLI catalog"],["go","inventory","Installed software"],["go","readiness","Job readiness"],["go","project","Analyze a project"],["sep"],["act","rescan","Rescan this computer"]]},
  {id:"logs", label:"Logs", items:[["go","blueprints","Blueprints / Rebuild"],["go","receipts","Receipts"],["go","proof","Workstation proof"]]},
  {id:"drivers", label:"Drivers", items:[["go","drivers","Drivers & hardware"],["go","updates","Software updates"],["sep"],["act","rehw","Rescan hardware"]]},
  {id:"help", label:"Help", items:[["go","how","How it works"],["go","safety","Safety promises"],["go","uninstall","Uninstall…"],["sep"],["go","about","About & diagnostics"]]}
];
const VIEW_MENU = {home:"file",wizard:"file",toolkits:"file",catalog:"file",inventory:"file",readiness:"file",project:"file",blueprints:"logs",receipts:"logs",proof:"logs",drivers:"drivers",updates:"drivers",how:"help",safety:"help",uninstall:"help",about:"help"};

function shortVersion(v){
  const t=String(v??"").split(/\s+(?:SHA|@?Commit)\b/i)[0].trim();
  return t.length>18?`${t.slice(0,17)}…`:t;
}
function installedByCatalog(){
  return new Map((softwareIntelligence?.items||[]).filter(x=>x.installed&&x.catalog_id).map(x=>[x.catalog_id,x]));
}
function resetRun(){ setupPlan=null; setupResult=null; setupProgress=null; operationMessage=""; }
function selectionCount(){ return selectedToolkitIds.size+selectedSoftwareIds.size; }
function allocationOk(){
  const e=selectedAllocationEstimate();
  return Number.isInteger(maxAllocationGb)&&maxAllocationGb>=5&&maxAllocationGb<=2048&&e.complete&&e.mib<=maxAllocationGb*1024;
}
function go(next){
  if(next==="wizard"&&!setupRunning&&setupResult){resetRun();wizardStep=1;}
  if(next==="wizard"&&!setupPlan&&!setupRunning){setupMode="setup";}
  view=next; openMenu="";
  render(); window.scrollTo({top:0});
}
function startWizard({toolkit="",step=1,mode="setup"}={}){
  if(setupRunning){view="wizard";wizardStep=4;render();return;}
  if(toolkit){selectedToolkitIds.add(toolkit);}
  setupMode=mode; wizardStep=step; resetRun(); go("wizard");
}
async function buildPlan(){
  planBuilding=true; wizardStep=3; setupResult=null; setupProgress=null; operationMessage=""; render();
  try{
    setupPlan=JSON.parse(await invokeDesktop("build_setup_plan",{toolkitIds:[...selectedToolkitIds],softwareIds:[...selectedSoftwareIds],machineType,maxAllocationGib:maxAllocationGb}));
  }catch(err){ operationMessage=String(err); setupPlan=null; wizardStep=2; }
  planBuilding=false; render(); window.scrollTo({top:0});
}
async function rescanComputer(){
  if(scanning){return;}
  scanning=true; softwareScanError=""; render();
  try{ await refreshSoftwareIntelligence(true); graph=buildLiveGraph(); await loadWorkstationAssurance(); }
  catch(err){ softwareScanError=String(err); }
  scanning=false; render();
}

// ---------- panda voice ----------
function pandaMood(){
  const total=Number(setupProgress?.total)||setupPlan?.item_count||0;
  const done=Math.min(Number(setupProgress?.completed)||0,total);
  const summary=softwareIntelligence?.summary||{};
  if(setupRunning){return {pose:"carry",title:"Carrying your tools over",text:`${done} of ${total} done. Keep me open; I save progress after every tool.`};}
  if(errorText||(!setupData&&setupLoadError)){return {pose:"sad",title:"I could not start",text:"My trusted runtime is not answering. Retry, and open About & diagnostics if it keeps happening."};}
  if(view==="wizard"){
    if(setupResult){return {pose:"happy",title:"All done",text:"Here is exactly what happened for every tool."};}
    if(planBuilding){return {pose:"think",title:"Working out the plan",text:"Resolving dependencies and checking sizes. Nothing is installed."};}
    if(wizardStep===3&&setupPlan){return {pose:"think",title:"Your plan is ready",text:"Check the list. I will not install anything until you approve it."};}
    if(wizardStep===2){const n=selectionCount();return n?{pose:"happy",title:`${n} ${n===1?"pick":"picks"} so far`,text:"Looking good. Press Review plan when you are ready."}:{pose:"idle",title:"What work do you do?",text:"Tick a job toolkit, or add single tools from the catalog."};}
    return {pose:"idle",title:"First, tell me about this computer",text:"A desktop gets more room than a laptop. You also set a storage ceiling."};
  }
  if(view==="inventory"){
    if(pandaNote){return {pose:"think",title:"About your inventory",text:pandaNote};}
    return {pose:"happy",title:"This is my inventory room",text:"Unroll the scroll and search it. Ask me to target updates, unmanaged apps, or anything with an unknown version."};
  }
  if(view==="home"){
    if(softwareScanError){return {pose:"sad",title:"I could not finish looking around",text:"The scan hit a problem. You can still set up tools, or scan again."};}
    if(scanning||!softwareIntelligence){return {pose:"scan",title:"Looking around your computer",text:"Reading installed software and matching the approved catalog."};}
    return {pose:"happy",title:"Ready when you are",text:`I found ${Number(summary.detected)||0} things here.`};
  }
  return {pose:"idle",title:"",text:""};
}
function renderPandaGuide(extra=""){
  const mood=pandaMood();
  return `<section class="pandaGuide" data-pose="${mood.pose}" aria-live="polite"><div class="pandaStage">${pandaSvg(mood.pose)}</div><div class="pandaSpeech"><b>${escapeHtml(mood.title)}</b><p>${escapeHtml(mood.text)}</p>${mood.pose==="scan"?`<div class="scanLine" aria-hidden="true"><span></span></div>`:""}${extra}</div></section>`;
}
function runCountUps(){
  document.querySelectorAll("[data-countup]").forEach(node=>{
    const target=Number(node.getAttribute("data-countup"))||0;
    const key=`${node.getAttribute("data-count-key")||"count"}:${target}`;
    if(reducedMotion()||countedKeys.has(key)||target===0){node.textContent=String(target);countedKeys.add(key);return;}
    countedKeys.add(key);
    const start=performance.now();
    const step=now=>{const t=Math.min(1,(now-start)/700);node.textContent=String(Math.round(target*(1-Math.pow(1-t,3))));if(t<1){requestAnimationFrame(step);}};
    node.textContent="0"; requestAnimationFrame(step);
  });
}

// ---------- shell ----------
function renderMenuBar(){
  const s=softwareIntelligence?.summary;
  const pill=scanning||(!softwareIntelligence&&!softwareScanError)
    ?`<span class="pill working"><i></i>Scanning…</span>`
    :softwareScanError?`<button class="pill warn" id="retryScan"><i></i>Scan needs attention · retry</button>`
    :`<span class="pill ready"><i></i>${Number(s?.detected)||0} detected · ${Number(s?.catalog_matched)||0} managed</span>`;
  const active=VIEW_MENU[view];
  return `<header class="menubar" role="menubar">
    <button class="brandBtn" data-go="home" aria-label="AssembleLink home"><span class="brandMark">${pandaSvg("idle","AssembleLink")}</span><b>AssembleLink</b></button>
    <nav class="menus">${MENUS.map(m=>`<div class="menu ${openMenu===m.id?"open":""} ${active===m.id?"current":""}">
      <button class="menuBtn" data-menu="${m.id}" aria-haspopup="menu" aria-expanded="${openMenu===m.id}">${m.label}</button>
      ${openMenu===m.id?`<div class="menuDrop" role="menu">${m.items.map(it=>it[0]==="sep"?`<hr>`:`<button role="menuitem" class="${it[0]==="go"&&view===it[1]?"on":""}" ${it[0]==="go"?`data-go="${it[1]}"`:`data-act="${it[1]}"`}>${escapeHtml(it[2])}</button>`).join("")}</div>`:""}
    </div>`).join("")}</nav>
    <div class="menuSpacer"></div>${pill}
  </header>`;
}
function pageHead(title,sub="",right=""){
  return `<div class="pageHead"><div><h1>${escapeHtml(title)}</h1>${sub?`<p>${escapeHtml(sub)}</p>`:""}</div>${right}</div>`;
}
function statusLine(){ return operationMessage?`<p class="statusLine" role="status">${escapeHtml(operationMessage)}</p>`:""; }
function noRuntime(){
  return `<section class="card center"><h2>The trusted runtime is unavailable</h2><p>Machine-changing actions are disabled until it answers.</p><button id="retryRuntime" class="btn primary">Retry runtime</button><p class="statusLine" role="status">${escapeHtml(setupLoadError)}</p></section>`;
}


// ---------- Home / splash ----------
function renderSetupRecovery(){
  if(!setupRecovery){return setupRecoveryError?`<p class="statusLine" role="status">Interrupted-run inspection unavailable: ${escapeHtml(setupRecoveryError)}</p>`:"";}
  const completed=Number(setupRecovery.progress?.completed)||0;
  const total=Number(setupRecovery.progress?.total)||0;
  return `<aside class="recoveryNotice"><div><b>Interrupted setup found</b><span>${completed} of ${total} tools were recorded before the run stopped. Completed automatic tools will be independently checked before they are skipped.</span></div><button id="reviewRecovery" class="btn secondary">Review and resume</button></aside>`;
}
function renderHome(){
  const s=softwareIntelligence?.summary||{};
  const receipts=Number(receiptIndex?.summary?.total)||0;
  const returning=receipts>0;
  const mood=pandaMood();
  const updates=Number(s.updates_available)||0;
  const facts=softwareIntelligence?`<p class="splashFacts"><span><b data-countup="${Number(s.detected)||0}" data-count-key="detected">0</b> things found</span><span><b data-countup="${Number(s.catalog_matched)||0}" data-count-key="matched">0</b> tools I manage</span>${updates?`<span><b data-countup="${updates}" data-count-key="updates">0</b> ${updates===1?"update":"updates"} ready</span>`:""}</p>`:"";
  const scanFail=softwareScanError?`<aside class="recoveryNotice warn"><div><b>The software scan could not finish</b><span>Nothing was changed. You can still set up tools.</span></div><button id="retryScan2" class="btn secondary">Scan again</button></aside>`:"";
  return `<section class="splash">
    <div class="splashPanda" data-pose="${mood.pose}">${pandaSvg(mood.pose)}</div>
    <h1>${returning?"Welcome back":"Welcome to AssembleLink"}</h1>
    <p class="lead">${returning?"I remember this computer. Add more tools, check what is installed, or look for updates.":"I am your setup panda. Tell me the work you do and I will gather, check, and install every tool for it, one approved step at a time."}</p>
    <div class="splashCta"><button id="getStarted" class="btn primary big">${returning?"Set up more tools":"Get started"}</button>${returning?`<button class="btn ghost big" data-go="inventory">Open my inventory</button>`:`<button class="btn ghost big" data-go="how">How it works</button>`}</div>
    ${facts}
    ${scanning||(!softwareIntelligence&&!softwareScanError)?`<div class="scanLine center" aria-hidden="true"><span></span></div><p class="splashHint">Looking around your computer…</p>`:""}
    ${scanFail}${renderSetupRecovery()}
    <p class="splashHint">Everything is shown to you first. Nothing installs without your approval.</p>
  </section>`;
}

// ---------- Setup wizard ----------
function renderStepper(){
  const names=["Your computer","Pick tools","Review","Install"];
  return `<ol class="stepper" aria-label="Setup steps">${names.map((n,i)=>{const k=i+1;const cls=k<wizardStep?"done":k===wizardStep?"active":"";return `<li class="${cls}" ${k===wizardStep?'aria-current="step"':""}><b>${k<wizardStep?"✓":k}</b><span>${n}</span></li>`;}).join("")}</ol>`;
}
function renderMachineStep(){
  const estimate=selectedAllocationEstimate();
  const freeGb=Number(systemProfile?.storage?.free_gb);
  const limitMib=maxAllocationGb*1024;
  const overLimit=estimate.complete&&estimate.mib>limitMib;
  return `<section class="card wizCard" aria-labelledby="machineTitle">
    <h2 id="machineTitle">What are you setting up?</h2>
    <div class="bigChoices" role="radiogroup" aria-label="Machine type">
      <label class="bigChoice ${machineType==="desktop"?"selected":""}"><input type="radio" name="machineType" data-machine-type="desktop" ${machineType==="desktop"?"checked":""}><span class="glyph" aria-hidden="true">🖥</span><b>Desktop</b><span>Room for larger SDKs, containers, and local AI.</span></label>
      <label class="bigChoice ${machineType==="laptop"?"selected":""}"><input type="radio" name="machineType" data-machine-type="laptop" ${machineType==="laptop"?"checked":""}><span class="glyph" aria-hidden="true">💻</span><b>Laptop</b><span>Keeps the footprint tighter for portable storage.</span></label>
    </div>
    <div class="ceiling">
      <label for="maxAllocationGb"><b>Maximum planned allocation</b><span>The most storage this plan may use.</span></label>
      <div class="ceilingInput"><input id="maxAllocationGb" type="number" min="5" max="2048" step="1" value="${escapeHtml(maxAllocationGb)}"><span>GB</span></div>
      <small>${Number.isFinite(freeGb)?`${escapeHtml(freeGb)} GB currently free on this computer.`:"Live free space is unavailable."}</small>
    </div>
    ${overLimit?`<p class="allocationWarning" role="alert">Your current picks are about ${formatAllocation(estimate.mib-limitMib)} over this limit. Raise it or remove tools.</p>`:""}
    <p class="fine">Planning estimate only. Projects, package caches, containers, virtual machines, AI models, games, and later SDK downloads are not included.</p>
  </section>${renderSetupRecovery()}`;
}
function renderToolkitGroups(kits){
  const families=[...new Set(kits.map(k=>k.job_family||"Other"))].sort();
  return families.map(family=>`<section class="toolkitFamily"><h4>${escapeHtml(family)}</h4><div class="pickGrid">${kits.filter(k=>(k.job_family||"Other")===family).map(k=>`<label class="pickCard ${selectedToolkitIds.has(k.id)?"isPicked":""}"><input type="checkbox" data-toolkit-id="${escapeHtml(k.id)}" ${selectedToolkitIds.has(k.id)?"checked":""}><i class="tick" aria-hidden="true"></i><b>${escapeHtml(k.name)}</b><span>${escapeHtml(k.description)}</span><small>${k.software_ids.length} reviewed tools</small></label>`).join("")}</div></section>`).join("");
}
function renderPickStep(){
  const kits=setupData?.toolkits?.toolkits||[];
  const items=setupData?.catalog?.items||[];
  const byId=new Map(items.map(x=>[x.id,x]));
  const singles=[...selectedSoftwareIds].map(id=>`<span class="chip">${escapeHtml(byId.get(id)?.name||id)}<button data-remove-software="${escapeHtml(id)}" aria-label="Remove ${escapeHtml(byId.get(id)?.name||id)}">✕</button></span>`).join("");
  return `<section class="card wizCard">
    <h2>Pick a job toolkit</h2>
    <p class="sub">Tick any toolkits that match your work. You can also add single tools.</p>
    <div class="singles"><button class="btn secondary small" data-go="catalog">+ Add single tools from the catalog</button>${singles}</div>
    ${renderToolkitGroups(kits)}
  </section>${statusLine()}`;
}
function renderReviewStep(){
  if(planBuilding||!setupPlan){return `<section class="card center"><h2>Working out your plan…</h2><div class="scanLine center" aria-hidden="true"><span></span></div></section>`;}
  const planItems=setupPlan.items||[];
  const isUpdate=setupPlan.plan_type==="update";
  return `<section class="card planPanel wizCard"><h2>Review ${isUpdate?"update":"setup"} plan</h2>
    <p class="planSummary"><b>${setupPlan.item_count}</b> tools · ${setupPlan.automatic_count} automatic · ${setupPlan.manual_count} manual</p>
    ${setupPlan.machine_profile&&setupPlan.allocation?`<div class="planAllocation"><span>${escapeHtml(setupPlan.machine_profile.machine_type)} profile</span><b>${formatAllocation(setupPlan.allocation.estimated_installed_mib)} of ${formatAllocation(setupPlan.allocation.max_allocation_mib)}</b><small>${formatAllocation(setupPlan.allocation.remaining_planned_mib)} planned headroom</small></div>`:""}
    ${setupPlan.profile_guidance?.caution_count?`<p class="allocationWarning">${escapeHtml(setupPlan.profile_guidance.caution_count)} tools may have substantial storage, battery, memory, GPU, or thermal impact on a laptop.</p>`:""}
    ${setupPlan.manual_count?`<p class="fine">Manual items need your attention after the automatic ones finish; I never guess an installer.</p>`:""}
    ${table(["Tool","Size","Action"],planItems.map(x=>[x.name,x.estimated_installed_mib?formatAllocation(x.estimated_installed_mib):"—",humanStatus(x.status)]))}
    <details class="moreDetails"><summary>Package identity, license, dependencies</summary>${table(["Tool","Machine fit","Package identity","License","Dependencies","Admin / reboot"],planItems.map(x=>[x.name,x.profile_advisory==="review_laptop_resource_impact"?"Review laptop impact":"Compatible",x.winget_id||"—",(x.license||"").replaceAll("_"," "),(x.dependencies||[]).join(", ")||"—",`${x.admin_required?"Admin":"User"}${x.reboot_required?" · reboot possible":""}`]))}</details>
    <button id="exportBlueprint" class="btn ghost small">Export this selection as a blueprint</button>
  </section>${statusLine()}`;
}
function renderInstallStep(){
  const total=Number(setupProgress?.total)||setupPlan?.item_count||0;
  const completed=Math.min(Number(setupProgress?.completed)||0,total);
  const rows=Array.isArray(setupProgress?.results)?setupProgress.results:[];
  const pct=Math.round(completed/Math.max(total,1)*100);
  const status=setupResult||setupProgress?.status==="complete"?"Complete":setupRunning?"Running":"Stopped";
  const resultRows=setupResult?.results||[];
  return `<section class="card setupProgress" aria-live="polite"><h2>${setupResult?"All done":"Installing"}</h2>
    <p><b>${escapeHtml(status)}</b> · ${completed} of ${total} tools finished</p>
    <div class="carryTrack" style="--pct:${pct}%"><div class="carryFill"></div><div class="carryRunner ${setupRunning?"walking":""}">${pandaSvg(setupResult||setupProgress?.status==="complete"?"happy":setupRunning?"carry":"idle","Panda carrying your tools")}</div></div>
    <progress class="srOnly" value="${completed}" max="${Math.max(total,1)}">${completed} of ${total}</progress>
    <p class="fine">Keep AssembleLink open. Progress is saved after every tool.</p>
    ${setupResult?table(["Tool","Outcome","Source verified","Installed verified","Details"],resultRows.map(x=>[x.name,humanStatus(x.status),x.source_verified?"Yes":"No",x.verified?"Yes":"No",x.message])):rows.length?table(["Tool","Outcome","Details"],rows.map(x=>[x.name||x.winget_id||x.id,humanStatus(x.status),x.message])):""}
  </section>${statusLine()}`;
}
function renderWizardNav(){
  const est=selectedAllocationEstimate();
  const sel=selectionCount();
  const info=wizardStep===2?`<span class="navInfo"><b>${sel}</b> ${sel===1?"pick":"picks"}${est.itemCount?` · about ${formatAllocation(est.mib)}`:""}</span>`:`<span class="navInfo"></span>`;
  if(wizardStep===1){return `<footer class="wizNav">${info}<span class="navBtns"><button id="wizNext" class="btn primary" ${Number.isInteger(maxAllocationGb)&&maxAllocationGb>=5?"":"disabled"}>Next: pick tools →</button></span></footer>`;}
  if(wizardStep===2){return `<footer class="wizNav">${info}<span class="navBtns"><button id="wizBack" class="btn ghost">← Back</button><button id="reviewSetup" class="btn primary" ${sel>0&&allocationOk()?"":"disabled"}>Review plan →</button></span></footer>`;}
  if(wizardStep===3){
    const resuming=setupRecovery?.plan?.plan_id===setupPlan?.plan_id;
    return `<footer class="wizNav"><span class="navInfo">${setupPlan?"Nothing installs until you approve.":""}</span><span class="navBtns"><button id="wizBack" class="btn ghost" ${setupRunning?"disabled":""}>← Back</button>${setupPlan?.item_count?`<button id="approveSetup" class="btn primary" ${setupRunning||planBuilding?"disabled":""}>${resuming?"Approve and resume remaining tools":`Approve and ${setupPlan.plan_type==="update"?"update my tools":"set up this computer"}`}</button>`:""}</span></footer>`;
  }
  return `<footer class="wizNav"><span class="navInfo"></span><span class="navBtns">${setupRunning?"":`<button id="wizFinish" class="btn primary">Finish</button><button class="btn ghost" data-go="receipts">View receipts</button>`}</span></footer>`;
}
function renderWizard(){
  if(!setupData){return noRuntime();}
  if(wizardStep===3&&!setupPlan&&!planBuilding){wizardStep=2;}
  if(wizardStep===4&&!setupRunning&&!setupResult&&!setupProgress){wizardStep=2;}
  const body=wizardStep===1?renderMachineStep():wizardStep===2?renderPickStep():wizardStep===3?renderReviewStep():renderInstallStep();
  return `${pageHead("Set up this computer")}${renderStepper()}${renderPandaGuide()}${body}${renderWizardNav()}`;
}

// ---------- Job toolkits gallery ----------
function kitProgress(kit,installed){
  const ids=kit.software_ids||[];
  const have=ids.filter(id=>installed.has(id));
  return {total:ids.length,have:have.length,missing:ids.filter(id=>!installed.has(id)),pct:ids.length?Math.round(have.length/ids.length*100):0};
}
function ring(pct,label){ return `<div class="ring" style="--p:${pct}" role="img" aria-label="${pct}% installed"><b>${label??`${pct}%`}</b></div>`; }
function renderToolkits(){
  if(!setupData){return noRuntime();}
  const kits=setupData.toolkits?.toolkits||[];
  const items=new Map((setupData.catalog?.items||[]).map(x=>[x.id,x]));
  const installed=installedByCatalog();
  const families=["all",...[...new Set(kits.map(k=>k.job_family||"Other"))].sort()];
  const q=kitSearch.toLowerCase();
  const shown=kits.filter(k=>kitFamily==="all"||(k.job_family||"Other")===kitFamily).filter(k=>!q||`${k.name} ${k.description} ${k.job_family}`.toLowerCase().includes(q));
  return `${pageHead("Job toolkits","Hand-picked sets of tools for a kind of work. Pick one and I will build it.")}
    <div class="filterRow"><input id="kitSearch" type="search" placeholder="Search toolkits" value="${escapeHtml(kitSearch)}" aria-label="Search toolkits">${families.map(f=>`<button class="chipBtn ${kitFamily===f?"active":""}" data-kit-family="${escapeHtml(f)}">${f==="all"?"All":escapeHtml(f)}</button>`).join("")}</div>
    <div class="kitGrid">${shown.map(k=>{const p=kitProgress(k,installed);return `<article class="kitCard" data-family="${escapeHtml((k.job_family||"Other").toLowerCase().replace(/[^a-z]+/g,"-"))}">
      <header>${ring(p.pct)}<div><span class="familyTag">${escapeHtml(k.job_family||"Other")}</span><h3>${escapeHtml(k.name)}</h3></div></header>
      <p>${escapeHtml(k.description)}</p>
      <small>${p.total} tools · ${p.have} already installed</small>
      <details><summary>See the ${p.total} tools</summary><ul class="toolList">${(k.software_ids||[]).map(id=>`<li class="${installed.has(id)?"have":""}">${escapeHtml(items.get(id)?.name||id)}</li>`).join("")}</ul></details>
      <button class="btn primary small" data-kit-start="${escapeHtml(k.id)}">${p.pct===100?"Review anyway":"Start with this"}</button>
    </article>`;}).join("")||`<p class="empty">No toolkits match that search.</p>`}</div>`;
}

// ---------- Catalog ----------
function renderCatalog(){
  if(!setupData){return noRuntime();}
  const items=setupData?.catalog?.items||[];
  const installed=installedByCatalog();
  const categories=["all",...new Set(items.map(x=>x.category||"other"))].sort();
  const q=catalogSearch.toLowerCase();
  const visible=items.filter(x=>catalogCategory==="all"||(x.category||"other")===catalogCategory).filter(x=>!q||`${x.name} ${x.category||""} ${(x.capabilities||[]).join(" ")}`.toLowerCase().includes(q));
  const n=selectionCount();
  return `${pageHead("Software & CLI catalog","Approved software and CLI catalog. Every entry has a reviewed package identity.")}
    <div class="filterRow"><input id="catalogSearch" type="search" placeholder="Search Git, Python, Docker, security…" value="${escapeHtml(catalogSearch)}" aria-label="Search tools"><select id="catalogCategorySelect" aria-label="Category">${categories.map(c=>`<option value="${escapeHtml(c)}" ${catalogCategory===c?"selected":""}>${escapeHtml(c==="all"?"All categories":c.replaceAll("-"," "))}</option>`).join("")}</select><span class="count">${visible.length} of ${items.length}</span></div>
    <div class="catList">${visible.map(x=>{const inst=installed.get(x.id);const v=inst?.installed_version;return `<label class="catRow ${selectedSoftwareIds.has(x.id)?"isPicked":""}">
      <input type="checkbox" data-software-id="${escapeHtml(x.id)}" ${selectedSoftwareIds.has(x.id)?"checked":""}>
      <span class="catName"><b>${escapeHtml(x.name)}</b><small>${escapeHtml(x.winget_id||"Manual review")}</small></span>
      <span class="tag">${escapeHtml((x.category||"software").replaceAll("-"," "))}</span>
      <span class="lic">${escapeHtml((x.license||"license review").replaceAll("_"," "))}</span>
      <span class="inst ${inst?"yes":""}" ${v?`title="${escapeHtml(v)}"`:""}>${inst?`<i></i>${v?escapeHtml(shortVersion(v)):"Installed"}`:""}</span>
    </label>`;}).join("")||`<p class="empty">Nothing matches that search.</p>`}</div>
    ${n?`<div class="stickyBar"><span><b>${n}</b> ${n===1?"item":"items"} in your setup</span><button id="addToSetup" class="btn primary">Continue to setup →</button></div>`:""}`;
}


// ---------- Installed software: the panda's inventory room ----------
function invRows(){
  const q=invSearch.toLowerCase();
  return softwareInventory.map((a,i)=>({a,i,cat:softwareCategory(a)})).filter(({a,cat})=>{
    if(invFilter==="managed"&&!a.catalog_id){return false;}
    if(invFilter==="updates"&&a.update_status!=="update_available"){return false;}
    if(invFilter==="apps"&&a.inventory_kind!=="application_candidate"){return false;}
    if(invFilter==="components"&&(a.catalog_id||a.inventory_kind==="application_candidate")){return false;}
    if(invFilter==="unknown"&&!(a.catalog_id&&!["current","update_available"].includes(a.update_status))){return false;}
    if(invCategory!=="all"&&cat!==invCategory){return false;}
    return !q||`${a.name||""} ${a.publisher||""} ${a.version||""}`.toLowerCase().includes(q);
  });
}
function renderInventoryDetail(){
  const app=invSelected===null?null:softwareInventory[invSelected];
  if(!app){return "";}
  const managed=!!app.catalog_id;
  return `<div class="invDetail"><div class="invDetailTop"><h3>${escapeHtml(app.name||"Unknown software")}</h3><button id="closeInvDetail" class="btn ghost small">Close</button></div>
    <dl><div><dt>Category</dt><dd>${escapeHtml(softwareCategory(app))}</dd></div><div><dt>Installed version</dt><dd title="${escapeHtml(app.version||"")}">${escapeHtml(shortVersion(app.version)||"Unknown")}</dd></div><div><dt>Available version</dt><dd>${escapeHtml(shortVersion(app.available_version)||"Unknown")}</dd></div><div><dt>Update status</dt><dd>${escapeHtml(humanStatus(app.update_status||"unmatched"))}</dd></div><div><dt>Publisher</dt><dd>${escapeHtml(app.publisher||"Unknown")}</dd></div><div><dt>Catalog identity</dt><dd>${escapeHtml(app.winget_id||app.catalog_id||"Unmatched")}</dd></div><div><dt>Provider state</dt><dd>${escapeHtml(humanStatus(app.provider_status||"not checked"))}</dd></div><div><dt>Inventory class</dt><dd>${escapeHtml(humanStatus(app.inventory_kind||"unclassified"))}</dd></div><div><dt>Catalog action</dt><dd>${escapeHtml(humanStatus(app.catalog_action||"review"))}</dd></div></dl>
    <div class="invActions">${app.update_status==="update_available"?`<button class="btn primary small" data-go="updates">Review update</button>`:""}<button class="btn secondary small" data-find-catalog="${escapeHtml(app.name||"")}">Find in catalog</button>${managed?`<button class="btn danger small" data-uninstall-search="${escapeHtml(app.name||"")}">Uninstall…</button>`:""}</div>
    <p class="fine">Executable uninstall commands and full install paths are intentionally excluded from this view.</p></div>`;
}
function renderInventory(){
  const s=softwareIntelligence?.summary||{};
  const rows=invRows();
  const cats=["all","Creative","Game Dev","Security","Development","AI / GPU","Drivers / Hardware","Runtime / SDK","Launcher / Game","Everyday Apps","Other"];
  const managed=softwareInventory.filter(a=>a.catalog_id).length;
  const apps=Number(s.unmatched_unique_applications??s.unmatched_application_candidates??s.unmatched)||0;
  const comps=Number(s.unmatched_components)||0;
  const updates=Number(s.updates_available)||0;
  const unknown=Number(s.unknown)||0;
  const mood=pandaMood();
  const filters=[["all",`All ${softwareInventory.length}`],["managed",`Managed ${managed}`],["updates",`Needs update ${updates}`],["apps",`Apps to review ${apps}`],["components",`Components ${comps}`],["unknown",`Unknown version ${unknown}`]];
  return `${pageHead("Installed software","Everything I found on this computer, kept in my inventory room.",`<button id="refreshSoftware" class="btn secondary">Rescan</button>`)}
  ${statusLine()}
  <section class="room">${roomSvg()}
    <div class="roomPanda" data-pose="${mood.pose}">${pandaSvg(mood.pose)}</div>
    <div class="roomSpeech"><b>${escapeHtml(mood.title)}</b><p>${escapeHtml(mood.text)}</p>
      <div class="askRow"><button class="chipBtn" data-panda-ask="updates">What needs updating?</button><button class="chipBtn" data-panda-ask="managed">What can you manage?</button><button class="chipBtn" data-panda-ask="apps">Apps I have not reviewed</button><button class="chipBtn" data-panda-ask="unknown">Unknown versions</button></div>
    </div>
  </section>
  <section class="scrollWrap" aria-label="Inventory scroll">
    <div class="rod" aria-hidden="true"></div>
    <div class="scrollPaper">
      <div class="scrollTools"><input id="softwareSearch" type="search" placeholder="Search software, publisher, version…" value="${escapeHtml(invSearch)}" aria-label="Search installed software"><select id="invCategory" aria-label="Category">${cats.map(c=>`<option ${invCategory===c?"selected":""} value="${escapeHtml(c)}">${c==="all"?"All categories":escapeHtml(c)}</option>`).join("")}</select></div>
      <div class="filterRow tight">${filters.map(([id,label])=>`<button class="chipBtn ${invFilter===id?"active":""}" data-inv-filter="${id}">${escapeHtml(label)}</button>`).join("")}</div>
      <p class="count">Showing ${Math.min(rows.length,250)} of ${rows.length} matching · ${softwareInventory.length} detected</p>
      ${renderInventoryDetail()}
      <div class="scrollBody">${rows.slice(0,250).map(({a,i,cat})=>`<button class="invRow ${invSelected===i?"on":""}" data-inv-index="${i}"><span class="invName"><b>${escapeHtml(a.name||"")}</b><small>${escapeHtml(a.publisher||"")}</small></span><span class="tag">${escapeHtml(cat)}</span><span class="invVer" title="${escapeHtml(a.version||"")}">${escapeHtml(shortVersion(a.version))}</span><span class="invStat ${escapeHtml(a.update_status||"unmatched")}">${escapeHtml(humanStatus(a.update_status||"unmatched"))}</span></button>`).join("")||`<p class="empty">${softwareInventory.length?"Nothing matches. Try a different filter.":"Run a scan and I will fill this shelf."}</p>`}</div>
    </div>
    <div class="rod" aria-hidden="true"></div>
  </section>
  <p class="fine">“Current” requires both a known installed version and a successful approved-provider check. Offline, stale, malformed, or unavailable provider checks stay unknown and never become a false green status.</p>`;
}

// ---------- Job readiness ----------
function renderReadiness(){
  if(!setupData){return noRuntime();}
  const kits=setupData.toolkits?.toolkits||[];
  const items=new Map((setupData.catalog?.items||[]).map(x=>[x.id,x]));
  const installed=installedByCatalog();
  const rows=kits.map(k=>({k,p:kitProgress(k,installed)}));
  const groups=[["Ready","ready",rows.filter(r=>r.p.pct===100)],["Almost there","almost",rows.filter(r=>r.p.pct>=50&&r.p.pct<100)],["Getting started","started",rows.filter(r=>r.p.pct>0&&r.p.pct<50)],["Not started","none",rows.filter(r=>r.p.pct===0)]];
  const ready=groups[0][2].length;
  const note=softwareIntelligence?"":`<p class="fine">Waiting for the first scan to finish before I can score each toolkit.</p>`;
  return `${pageHead("Job readiness","How complete each job toolkit is on this computer.")}
    <section class="readySummary"><div><b data-countup="${ready}" data-count-key="ready">0</b><span>toolkits ready</span></div><div><b>${rows.length}</b><span>toolkits tracked</span></div><div><b>${softwareIntelligence?Number(softwareIntelligence.summary?.catalog_matched)||0:"—"}</b><span>managed tools found</span></div></section>${note}
    ${groups.filter(g=>g[2].length).map(([label,cls,list])=>`<section class="readyGroup ${cls}"><h3>${label} <small>${list.length}</small></h3><div class="readyGrid">${list.map(({k,p})=>`<article class="readyCard">${ring(p.pct,`${p.have}/${p.total}`)}<div class="readyText"><b>${escapeHtml(k.name)}</b><small>${escapeHtml(k.job_family||"Other")}</small>${p.missing.length?`<p>Missing: ${escapeHtml(p.missing.slice(0,5).map(id=>items.get(id)?.name||id).join(", "))}${p.missing.length>5?` and ${p.missing.length-5} more`:""}</p>`:`<p class="okText">Everything in this toolkit is installed.</p>`}${p.missing.length?`<button class="btn secondary small" data-kit-start="${escapeHtml(k.id)}">Complete this toolkit</button>`:""}</div></article>`).join("")}</div></section>`).join("")}`;
}

// ---------- Updates ----------
function renderUpdates(){
  const list=softwareInventory.filter(a=>a.update_status==="update_available");
  return `${pageHead("Software updates","Compare what you have with approved sources. Nothing updates without your approval.",`<button id="scanUpdates" class="btn primary">Check for updates and build a plan</button>`)}
    ${statusLine()}
    <section class="card"><h2>${list.length?`${list.length} ${list.length===1?"update is":"updates are"} ready`:"No updates reported"}</h2>
      ${list.length?table(["Tool","Installed","Available"],list.map(a=>[a.name,shortVersion(a.version),shortVersion(a.available_version)||"—"])):`<p>${softwareIntelligence?"The last scan found nothing newer. Unknown statuses are never treated as current; check Installed software for any unknown versions.":"Run a check and I will tell you what is newer."}</p>`}
      <p class="fine">I ask Winget about exact approved package identities only. You will see the full plan and approve it before anything changes.</p>
    </section>`;
}

// ---------- Drivers ----------
function renderDrivers(){
  const head=pageHead("Drivers & hardware","Live inventory of chipset, GPU, network, audio, BIOS, and official vendor support paths.",`<button id="refreshDrivers" class="btn secondary">${driverProfile?"Rescan hardware":"Scan hardware"}</button>`);
  if(!driverProfile){
    return `${head}<section class="card"><h2>Safe state</h2><p>Driver execution is disabled until hardware is detected and an official vendor source is verified. AssembleLink will not guess a driver or silently install one.</p><p class="statusLine" role="status">${escapeHtml(driverLoadError)}</p></section>`;
  }
  const p=driverProfile.platform||{};
  const recs=Array.isArray(driverProfile.recommendations)?driverProfile.recommendations:[];
  const graphics=Array.isArray(driverProfile.graphics)?driverProfile.graphics:[];
  const network=Array.isArray(driverProfile.network)?driverProfile.network:[];
  const audio=Array.isArray(driverProfile.audio)?driverProfile.audio:[];
  const errors=Array.isArray(driverProfile.collection_errors)?driverProfile.collection_errors:[];
  const dev=x=>[x.name,x.manufacturer||"—",shortVersion(x.driver_version)||"Unknown",x.device_status||"Unknown"];
  return `${head}<p class="statusLine" role="status">${escapeHtml(driverLoadError)}</p>
    <section class="readySummary"><div><b>${graphics.length}</b><span>graphics devices</span></div><div><b>${network.length}</b><span>network devices</span></div><div><b>${audio.length}</b><span>audio devices</span></div><div><b>${recs.length}</b><span>support paths</span></div></section>
    <section class="card"><h2>Platform</h2>${table(["Component","Detected identity"],[["Computer",`${p.machine_manufacturer||""} ${p.machine_model||""}`.trim()],["Motherboard",`${p.motherboard_vendor||""} ${p.motherboard_product||""}`.trim()],["CPU",p.cpu||"Unknown"],["BIOS",`${p.bios_vendor||""} ${p.bios_version||""}`.trim()]])}</section>
    <section class="card"><h2>Detected driver inventory</h2>
      <details open><summary>Graphics (${graphics.length})</summary>${table(["Device","Vendor","Installed driver","Status"],graphics.map(dev))}</details>
      <details><summary>Network (${network.length})</summary>${table(["Device","Vendor","Installed driver","Status"],network.map(dev))}</details>
      <details><summary>Audio (${audio.length})</summary>${table(["Device","Vendor","Installed driver","Status"],audio.map(dev))}</details></section>
    <section class="card"><h2>Official support paths</h2>${table(["Component","Why it is shown","Official source","Safety"],recs.map(r=>[r.name||r.id,r.reason||"",`${r.official_vendor||"Vendor"} (${r.official_domain||"official source"}) — ${r.official_direction||""}`,`${r.install_mode||"recommend_only"}; update ${r.update_status||"not checked"}`]))}</section>
    <section class="card"><h2>Safety policy</h2><p>Drivers and BIOS remain recommendation-only. Installed versions are inventory evidence, not proof that an update exists. Any future installation requires administrator approval, an official vendor source, a restore point, and post-install device verification.</p><p>${errors.length?`${errors.length} hardware data sources were unavailable, so this scan is partial.`:"Hardware collection completed without reported source failures."}</p></section>`;
}

// ---------- Logs ----------
function renderBlueprints(){
  return `${pageHead("Blueprints / Rebuild","Save this computer as a blueprint, or rebuild from one.")}${statusLine()}
  <div class="twoCol">
    <section class="card"><h2>Export this machine</h2><p>Create a verified rebuild blueprint from every currently installed application that matches an approved AssembleLink catalog identity. Unmatched applications are counted but never converted into guessed installers.</p><button id="exportMachineBlueprint" class="btn primary">Export this machine blueprint</button><p class="fine">The blueprint contains catalog IDs and setup policy—not personal files, secrets, arbitrary commands, or installer URLs. A matching SHA-256 sidecar and receipt are created with it.</p></section>
    <section class="card"><h2>Restore a verified blueprint</h2><p>Copy the blueprint and its <code>.sha256</code> file to this computer, then enter its full path.</p><input id="blueprintPath" placeholder="C:\\Users\\you\\Downloads\\AssembleLink-Blueprint.json" aria-label="Blueprint path"><button id="importBlueprint" class="btn primary">Validate and review blueprint</button></section>
  </div>`;
}
function renderReceipts(){
  const summary=receiptIndex?.summary||{total:0,valid:0,unverified:0,failed:0};
  const rows=(receiptIndex?.items||[]).map(item=>[item.name,item.schema,humanStatus(item.integrity),`${Math.max(0,Number(item.bytes)||0).toLocaleString()} bytes`,item.modified_unix?new Date(item.modified_unix*1000).toLocaleString():"Unknown",item.sha256?`${item.sha256.slice(0,16)}…`:"—"]);
  return `${pageHead("Receipts","Local evidence for setup runs and other machine operations. AssembleLink verifies adjacent SHA-256 files before showing evidence as valid.",`<button id="refreshReceipts" class="btn secondary">Refresh evidence</button>`)}
    <section class="readySummary"><div><b>${summary.total}</b><span>receipts</span></div><div><b>${summary.valid}</b><span>integrity valid</span></div><div><b>${summary.unverified}</b><span>legacy / unverified</span></div><div><b>${summary.failed}</b><span>integrity failures</span></div></section>
    <section class="card"><p class="statusLine" role="status">${escapeHtml(receiptLoadError)}</p>${rows.length?table(["Receipt","Schema","Integrity","Size","Created","SHA-256"],rows):"<p>No local receipts have been created yet. Completing a setup or export operation will create evidence here.</p>"}<p class="fine"><b>Unverified</b> means an older receipt has no integrity sidecar. <b>Mismatch</b>, <b>malformed sidecar</b>, and <b>too large</b> are failures and must not be trusted.</p></section>`;
}
function renderProof(){
  return `${pageHead("Workstation proof","A sealed snapshot of this computer's hardware, drivers, software, and catalog integrity.")}${statusLine()}${renderProofPanel()}${renderSystemProfile()}`;
}
function renderProject(){
  return `${pageHead("Analyze a project","Point me at a folder and I will tell you which tools it needs.")}${statusLine()}<section class="card">${renderRepositoryAnalyzer()}</section>`;
}
function renderRepositoryAnalyzer(){
  const result=repositoryAnalysis;
  return `<h2>Analyze a development project</h2><p>Choose a local project folder. AssembleLink reads supported top-level manifests, maps required runtimes to approved catalog identities, and creates sealed evidence. It never executes project files.</p><div class="repositoryPath"><input id="repositoryPath" value="${escapeHtml(repositoryPath)}" placeholder="C:\\dev\\my-project" autocomplete="off" aria-label="Project folder"><button id="analyzeRepository" class="btn primary">Analyze project</button></div>${result?`<div class="repositoryResult"><h3>${escapeHtml(result.repository?.name||"Project")} · ${escapeHtml(result.summary?.status||"analyzed")}</h3><p>${escapeHtml(result.summary?.recognized_manifests||0)} manifests · ${escapeHtml(result.summary?.resolved_catalog_items||0)} approved tools recommended</p>${(result.requirements||[]).length?table(["Requirement","Evidence","Version","Approved tools"],result.requirements.map(x=>[x.kind,x.evidence,x.version_constraint||"Review latest compatible",(x.catalog_ids||[]).join(", ")])):`<p>No supported top-level manifests were found.</p>`}${(result.recommended_software_ids||[]).length?`<button id="useRepositoryRecommendations" class="btn primary">Review recommended setup</button>`:""}</div>`:""}`;
}

// ---------- Help ----------
function renderHow(){
  const steps=[["1","Tell me about the computer","Desktop or laptop, and how much storage the plan may use."],["2","Pick your tools","Choose job toolkits, or add single tools from the approved catalog."],["3","Review the plan","I show every tool, its size, and its package identity. Nothing has been installed yet."],["4","Approve and watch","You approve once. I install tool by tool, verify each one, and save a receipt."]];
  return `${pageHead("How it works","Four calm steps, and you stay in charge.")}
    <section class="howGrid">${steps.map(([n,t,d])=>`<article class="howCard"><b>${n}</b><h3>${t}</h3><p>${d}</p></article>`).join("")}</section>
    <section class="card"><h2>Where to find things</h2><ul class="plainList"><li><b>File</b> opens setup, toolkits, the catalog, your installed software, and job readiness.</li><li><b>Logs</b> keeps blueprints, receipts, and workstation proof.</li><li><b>Drivers</b> shows hardware, driver inventory, and software updates.</li><li><b>Help</b> explains how I work and lets you uninstall programs, or me.</li></ul><button class="btn primary" data-go="wizard">Start setting up</button></section>`;
}
function renderSafety(){
  const items=[["Approval first","Nothing installs, updates, or uninstalls until you approve the exact list."],["Approved sources only","I use reviewed catalog entries and exact Winget package identities. I never guess an installer or run a download from a project."],["Project files are read, never run","Analyzing a folder only reads manifests."],["Drivers and BIOS stay manual","I recommend official vendor pages; I do not install drivers silently."],["Receipts you can verify","Every machine operation writes a receipt with a SHA-256 hash."],["Windows 10 and 11 (64-bit) only","macOS and Linux are not supported."]];
  return `${pageHead("Safety promises","What I will never do.")}<section class="card"><ul class="promiseList">${items.map(([t,d])=>`<li><i aria-hidden="true">✓</i><div><b>${t}</b><p>${d}</p></div></li>`).join("")}</ul></section>`;
}
function renderAbout(){
  return `${pageHead("About & diagnostics")}
    <section class="card"><h2>AssembleLink</h2><p>Version 0.1.0 · MIT license · Windows 10/11 x64 · local-first, approval-bound setup with SHA-256 receipts.</p><p class="fine">Source: github.com/ScrappyHub/assemblelink</p></section>
    <section class="card"><h2>Technical details</h2><p>Only needed when something goes wrong.</p><button id="toggleTechnical" class="btn secondary small">${showTechnical?"Hide":"Show"} technical details</button>${showTechnical?`<pre class="techPre">${escapeHtml(JSON.stringify(graph,null,2))}</pre>`:""}</section>`;
}

// ---------- Uninstall ----------
function renderUninstall(){
  const catalog=new Map((setupData?.catalog?.items||[]).map(x=>[x.id,x]));
  const q=uninstallSearch.toLowerCase();
  const rows=[...installedByCatalog().values()].filter(x=>catalog.get(x.catalog_id)?.winget_id).filter(x=>!q||`${x.name||""} ${x.catalog_id}`.toLowerCase().includes(q)).sort((a,b)=>String(a.name||a.catalog_id).localeCompare(String(b.name||b.catalog_id)));
  if(selfUninstalling){
    return `<section class="splash"><div class="splashPanda" data-pose="sad">${pandaSvg("sad")}</div><h1>Goodbye for now</h1><p class="lead">AssembleLink is removing itself silently. This window will close in a moment.</p></section>`;
  }
  return `${pageHead("Uninstall","Remove programs I manage, or remove AssembleLink itself. Both run silently.")}
    <section class="card"><h2>Uninstall a program</h2>
      <p>Only tools in the approved catalog can be removed here. For any other app, use Windows Settings → Apps → Installed apps.</p>
      <input id="uninstallSearch" type="search" placeholder="Search installed tools" value="${escapeHtml(uninstallSearch)}" aria-label="Search installed tools">
      ${uninstallMessage?`<p class="statusLine" role="status">${escapeHtml(uninstallMessage)}</p>`:""}
      <div class="uninstallList">${rows.map(x=>`<div class="uninstallRow"><span class="catName"><b>${escapeHtml(x.name||x.catalog_id)}</b><small title="${escapeHtml(x.installed_version||"")}">${escapeHtml(shortVersion(x.installed_version)||"version unknown")} · ${escapeHtml(catalog.get(x.catalog_id).winget_id)}</small></span><button class="btn danger small" data-uninstall="${escapeHtml(x.catalog_id)}" ${uninstallBusy?"disabled":""}>${uninstallBusy===x.catalog_id?"Removing…":"Uninstall"}</button></div>`).join("")||`<p class="empty">${softwareIntelligence?"No managed tools match.":"Waiting for the first scan."}</p>`}</div>
      <p class="fine">A confirmation is shown first. Removal runs without installer windows, and a receipt with a SHA-256 hash is saved. A program that is running or needs administrator approval may refuse; nothing else is touched.</p>
    </section>
    <section class="card dangerCard"><h2>Uninstall AssembleLink</h2>
      <p>This closes AssembleLink and removes it silently, with no installer windows or prompts. Programs I installed for you stay installed. Receipts and blueprints stay in your user profile.</p>
      <label class="ack"><input id="selfAck" type="checkbox" ${selfUninstallAck?"checked":""}> I understand AssembleLink will close and remove itself.</label>
      <button id="uninstallSelf" class="btn danger" ${selfUninstallAck?"":"disabled"}>Uninstall AssembleLink</button>
    </section>`;
}


// ---------- router + render ----------
function renderPanel(){
  switch(view){
    case "wizard": return renderWizard();
    case "toolkits": return renderToolkits();
    case "catalog": return renderCatalog();
    case "inventory": return renderInventory();
    case "readiness": return renderReadiness();
    case "project": return renderProject();
    case "blueprints": return renderBlueprints();
    case "receipts": return renderReceipts();
    case "proof": return renderProof();
    case "drivers": return renderDrivers();
    case "updates": return renderUpdates();
    case "how": return renderHow();
    case "safety": return renderSafety();
    case "uninstall": return renderUninstall();
    case "about": return renderAbout();
    default: return renderHome();
  }
}

function render(){
  const el=document.getElementById("app");
  if(!el){document.body.innerHTML="<pre>APP_ROOT_MISSING</pre>";return;}
  const keepScroll=el.querySelector(".scrollBody")?.scrollTop||0;
  el.innerHTML=`<div class="appShell">${renderMenuBar()}<main class="page view-${escapeHtml(view)}" id="main">${errorText?`<section class="card"><h2>Something went wrong</h2><pre class="techPre">${escapeHtml(errorText)}</pre></section>`:renderPanel()}</main></div>`;
  const viewKey=`${view}|${wizardStep}`;
  if(viewKey!==lastViewKey){el.querySelector(".page")?.classList.add("viewEnter");}
  lastViewKey=viewKey;
  const body=el.querySelector(".scrollBody"); if(body){body.scrollTop=keepScroll;}
  runCountUps();
}

function refocus(id,pos){
  render();
  const next=document.getElementById(id);
  if(next){next.focus();try{next.setSelectionRange(pos,pos);}catch(_e){/* not a text field */}}
}

async function approveAndRun(){
  if(setupRunning){return;}
  const resuming=setupRecovery?.available&&setupRecovery.plan?.plan_id===setupPlan?.plan_id;
  const automatic=(setupPlan?.items||[]).filter(x=>x.mode==="winget");
  const manual=(setupPlan?.items||[]).filter(x=>x.mode==="manual_review");
  const approvalLead=resuming?"Resume this exact interrupted setup plan? Completed automatic identities will be checked again before they are skipped.":"Approve this exact setup plan?";
  const allocationSummary=setupPlan?.allocation?`\n\nMachine: ${setupPlan.machine_profile.machine_type}\nPlanned storage: ${formatAllocation(setupPlan.allocation.estimated_installed_mib)} of ${formatAllocation(setupPlan.allocation.max_allocation_mib)}`:"";
  const approved=window.confirm(`${approvalLead}${allocationSummary}\n\nAutomatic (${automatic.length}):\n• ${automatic.map(x=>x.name).join("\n• ")}\n\nManual follow-up (${manual.length}):\n• ${manual.map(x=>x.name).join("\n• ")}\n\nA durable receipt and integrity hash will be created.`);
  if(!approved){operationMessage="Setup cancelled. Nothing was installed.";render();return;}
  const planId=setupPlan.plan_id;
  setupRunning=true; wizardStep=4;
  if(!resuming){setupProgress={schema:"assemblelink.setup_execution.progress.v1",plan_id:planId,status:"running",total:setupPlan.item_count,completed:0,results:[]};}
  operationMessage=resuming?"Resuming this computer setup. Previous outcomes are being revalidated…":"Setting up this computer. Progress is saved after every tool…";
  render(); window.scrollTo({top:0});
  const poll=async()=>{await loadSetupProgress(planId);render();};
  const progressTimer=window.setInterval(poll,750);
  void poll();
  try{
    const response=resuming?await invokeDesktop("resume_setup",{planId,approved:true}):await invokeDesktop("execute_setup",{planId,approved:true});
    setupResult=sanitizeStateValue(JSON.parse(response));
    operationMessage="Setup finished. Refreshing installed software and evidence…";
  }catch(err){
    operationMessage=`Setup stopped: ${String(err)}. Refreshing the machine inventory for any completed work…`;
  }finally{
    window.clearInterval(progressTimer);
    await loadSetupProgress(planId);
    setupRunning=false;
    render();
    const refreshIssues=[];
    try{await refreshSoftwareIntelligence(true);graph=buildLiveGraph();}
    catch(err){refreshIssues.push(`inventory refresh failed: ${String(err)}`);}
    await loadReceipts();
    await loadSetupRecovery();
    if(receiptLoadError){refreshIssues.push(`receipt refresh failed: ${receiptLoadError}`);}
    if(setupResult){operationMessage=refreshIssues.length?`Setup completed, but ${refreshIssues.join("; ")}.`:"Setup completed. Installed versions, readiness, and receipts are refreshed.";}
    else if(refreshIssues.length){operationMessage+=` ${refreshIssues.join("; ")}.`;}
  }
  render();
}

async function uninstallProgram(catalogId){
  const entry=(setupData?.catalog?.items||[]).find(x=>x.id===catalogId);
  if(!entry||uninstallBusy){return;}
  const ok=window.confirm(`Uninstall ${entry.name}?\n\nThis runs silently through Winget (${entry.winget_id}). Nothing else is touched. A receipt with an integrity hash will be saved.`);
  if(!ok){uninstallMessage="Cancelled. Nothing was removed.";render();return;}
  uninstallBusy=catalogId; uninstallMessage=`Removing ${entry.name}…`; render();
  try{
    const r=sanitizeStateValue(JSON.parse(await invokeDesktop("uninstall_software",{catalogId,approved:true})));
    uninstallMessage=r.receipt?.status==="uninstalled"?`${entry.name} was uninstalled. Receipt ${String(r.sha256||"").slice(0,12)}…`:`${entry.name} could not be uninstalled (exit code ${r.receipt?.exit_code??"unknown"}). Close the app and try again. Nothing else was changed.`;
  }catch(err){uninstallMessage=String(err);}
  uninstallBusy=""; render();
  try{await refreshSoftwareIntelligence(true);graph=buildLiveGraph();}catch(_e){/* the next scan will correct the list */}
  render();
}

async function uninstallSelfNow(){
  if(!selfUninstallAck){return;}
  const ok=window.confirm("Uninstall AssembleLink?\n\nThe app will close and remove itself silently, with no further prompts.\nPrograms it installed stay installed. Receipts and blueprints stay in your user profile.");
  if(!ok){return;}
  try{
    await invokeDesktop("uninstall_assemblelink",{approved:true});
    selfUninstalling=true; render();
  }catch(err){uninstallMessage=String(err);render();}
}

const actions={
  getStarted:()=>startWizard(),
  retryScan:()=>rescanComputer(), retryScan2:()=>rescanComputer(), refreshSoftware:()=>rescanComputer(),
  wizNext:()=>{wizardStep=2;render();window.scrollTo({top:0});},
  wizBack:()=>{
    if(wizardStep===2){wizardStep=1;}
    else if(wizardStep===3){const m=setupMode;setupPlan=null;operationMessage="";if(m==="update"){setupMode="setup";go("updates");return;}if(m==="restore"){setupMode="setup";go("blueprints");return;}wizardStep=2;}
    render();window.scrollTo({top:0});
  },
  reviewSetup:()=>buildPlan(),
  wizFinish:()=>{resetRun();selectedToolkitIds.clear();selectedSoftwareIds.clear();wizardStep=1;setupMode="setup";go("home");},
  addToSetup:()=>startWizard({step:2}),
  approveSetup:()=>approveAndRun(),
  reviewRecovery:()=>{setupPlan=setupRecovery.plan;setupProgress=setupRecovery.progress;setupResult=null;setupMode=setupPlan.plan_type==="update"?"update":"setup";wizardStep=3;operationMessage="Review the interrupted plan, then explicitly approve the remaining work.";go("wizard");},
  retryRuntime:async()=>{setupLoadError="Retrying trusted desktop runtime…";render();await loadSetupData();if(setupData){await loadSetupRecovery();await refreshSystemProfile();try{await refreshSoftwareIntelligence(false);}catch(err){softwareScanError=String(err);}await refreshDriverProfile();await loadReceipts();graph=buildLiveGraph();}render();},
  exportBlueprint:async()=>{try{operationMessage=`Blueprint exported to ${await invokeDesktop("export_blueprint")}. Keep the matching .sha256 file with it.`;}catch(err){operationMessage=String(err);}render();},
  exportMachineBlueprint:async()=>{
    operationMessage="Refreshing installed software and building a verified machine blueprint…";render();
    try{
      const result=sanitizeStateValue(JSON.parse(await invokeDesktop("export_machine_blueprint",{machineType,maxAllocationGib:maxAllocationGb})));
      operationMessage=`Blueprint exported to ${result.path}. ${result.catalog_matched_installed} installed catalog identities resolved to ${result.resolved_plan_items} plan items; ${result.unmatched_installed} unmatched installed entries were not guessed.`;
      await loadReceipts();
    }catch(err){operationMessage=String(err);}
    render();
  },
  importBlueprint:async()=>{
    const blueprintPath=document.getElementById("blueprintPath")?.value.trim()||"";
    operationMessage="Validating blueprint integrity and catalog identities…";render();
    try{setupPlan=JSON.parse(await invokeDesktop("import_blueprint",{blueprintPath,machineType,maxAllocationGib:maxAllocationGb}));setupResult=null;setupProgress=null;setupMode="restore";wizardStep=3;operationMessage="";go("wizard");return;}
    catch(err){setupPlan=null;operationMessage=String(err);}
    render();
  },
  scanUpdates:async()=>{
    operationMessage="Scanning installed software and checking approved providers…";setupPlan=null;render();
    try{
      await refreshSoftwareIntelligence(true);
      const plan=JSON.parse(await invokeDesktop("build_update_plan"));
      if(plan.package_manager_available&&plan.item_count){setupPlan=plan;setupResult=null;setupProgress=null;setupMode="update";wizardStep=3;operationMessage="";go("wizard");return;}
      operationMessage=plan.package_manager_available?"No approved updates were reported. Check unknown statuses before assuming everything is current.":"Winget is unavailable. Install or repair Windows App Installer, then try again.";
    }catch(err){operationMessage=String(err);}
    render();
  },
  analyzeRepository:async()=>{
    repositoryPath=document.getElementById("repositoryPath")?.value.trim()||"";repositoryAnalysis=null;operationMessage="Reading supported project manifests…";render();
    try{repositoryAnalysis=sanitizeStateValue(JSON.parse(await invokeDesktop("analyze_repository",{repositoryPath})));operationMessage="Project requirements mapped to the approved catalog. Nothing was installed.";}
    catch(err){operationMessage=String(err);}
    render();
  },
  useRepositoryRecommendations:()=>{selectedToolkitIds.clear();selectedSoftwareIds=new Set(repositoryAnalysis?.recommended_software_ids||[]);startWizard({step:2});operationMessage="Repository recommendations selected. Check your storage ceiling, then review the plan.";render();},
  refreshAssurance:async()=>{
    operationMessage="Rebuilding trusted workstation evidence…";render();
    try{await refreshSystemProfile();await refreshDriverProfile();await refreshSoftwareIntelligence(true);graph=buildLiveGraph();await loadWorkstationAssurance();await loadReceipts();operationMessage="Workstation proof refreshed and sealed.";}
    catch(err){workstationAssurance=null;workstationAssuranceError=String(err);operationMessage="Workstation proof could not be completed.";}
    render();
  },
  refreshReceipts:async()=>{receiptLoadError="Refreshing local evidence…";render();await loadReceipts();render();},
  refreshDrivers:async()=>{driverLoadError="Scanning local hardware and installed driver versions…";render();await refreshDriverProfile();await loadReceipts();render();},
  closeInvDetail:()=>{invSelected=null;render();},
  toggleTechnical:()=>{showTechnical=!showTechnical;render();},
  uninstallSelf:()=>uninstallSelfNow()
};

function onClick(e){
  const t=e.target; if(!(t instanceof Element)){return;}
  let el;
  if((el=t.closest("[data-menu]"))){const id=el.getAttribute("data-menu");openMenu=openMenu===id?"":id;render();return;}
  if((el=t.closest("[data-act]"))){openMenu="";const a=el.getAttribute("data-act");if(a==="rescan"){rescanComputer();}else if(a==="rehw"){view="drivers";actions.refreshDrivers();}return;}
  if((el=t.closest("[data-kit-start]"))){startWizard({toolkit:el.getAttribute("data-kit-start"),step:2});return;}
  if((el=t.closest("[data-go]"))){go(el.getAttribute("data-go"));return;}
  if((el=t.closest("[data-kit-family]"))){kitFamily=el.getAttribute("data-kit-family");render();return;}
  if((el=t.closest("[data-inv-filter]"))){invFilter=el.getAttribute("data-inv-filter");invSelected=null;pandaNote="";render();return;}
  if((el=t.closest("[data-inv-index]"))){const i=Number(el.getAttribute("data-inv-index"));invSelected=invSelected===i?null:i;render();return;}
  if((el=t.closest("[data-panda-ask]"))){
    const ask=el.getAttribute("data-panda-ask");const s=softwareIntelligence?.summary||{};
    invFilter=ask;invSelected=null;
    const n=ask==="updates"?Number(s.updates_available)||0:ask==="managed"?softwareInventory.filter(a=>a.catalog_id).length:ask==="apps"?Number(s.unmatched_unique_applications??s.unmatched)||0:Number(s.unknown)||0;
    pandaNote={updates:`${n} ${n===1?"tool has":"tools have"} an update ready. Tap one on the scroll to review it.`,managed:`${n} tools are ones I can install, update, and remove for you.`,apps:`${n} apps are on this computer but not in my approved catalog. I will not touch them unless you ask.`,unknown:`${n} tools have a version I could not confirm. Unknown never means current.`}[ask];
    render();return;
  }
  if((el=t.closest("[data-find-catalog]"))){catalogSearch=el.getAttribute("data-find-catalog")||"";catalogCategory="all";go("catalog");return;}
  if((el=t.closest("[data-uninstall-search]"))){uninstallSearch=el.getAttribute("data-uninstall-search")||"";go("uninstall");return;}
  if((el=t.closest("[data-uninstall]"))){uninstallProgram(el.getAttribute("data-uninstall"));return;}
  if((el=t.closest("[data-remove-software]"))){selectedSoftwareIds.delete(el.getAttribute("data-remove-software"));render();return;}
  if((el=t.closest("button[id]"))&&actions[el.id]){actions[el.id](el);return;}
  if(openMenu&&!t.closest(".menu")){openMenu="";render();}
}

function onChange(e){
  const t=e.target; if(!(t instanceof HTMLElement)){return;}
  if(t.hasAttribute("data-toolkit-id")){const id=t.getAttribute("data-toolkit-id");t.checked?selectedToolkitIds.add(id):selectedToolkitIds.delete(id);setupPlan=null;render();return;}
  if(t.hasAttribute("data-software-id")){const id=t.getAttribute("data-software-id");t.checked?selectedSoftwareIds.add(id):selectedSoftwareIds.delete(id);setupPlan=null;render();return;}
  if(t.hasAttribute("data-machine-type")){
    machineType=t.getAttribute("data-machine-type")==="laptop"?"laptop":"desktop";
    if(machineType==="laptop"&&maxAllocationGb===100){maxAllocationGb=50;}
    if(machineType==="desktop"&&maxAllocationGb===50){maxAllocationGb=100;}
    setupPlan=null;render();return;
  }
  if(t.id==="maxAllocationGb"){const next=Number(t.value);maxAllocationGb=Number.isInteger(next)?Math.max(5,Math.min(2048,next)):maxAllocationGb;setupPlan=null;render();return;}
  if(t.id==="catalogCategorySelect"){catalogCategory=t.value||"all";render();return;}
  if(t.id==="invCategory"){invCategory=t.value||"all";render();return;}
  if(t.id==="selfAck"){selfUninstallAck=t.checked;render();}
}

function onInput(e){
  const t=e.target; if(!(t instanceof HTMLInputElement)){return;}
  const pos=t.selectionStart??0;
  if(t.id==="catalogSearch"){catalogSearch=t.value;refocus("catalogSearch",pos);}
  else if(t.id==="softwareSearch"){invSearch=t.value;refocus("softwareSearch",pos);}
  else if(t.id==="kitSearch"){kitSearch=t.value;refocus("kitSearch",pos);}
  else if(t.id==="uninstallSearch"){uninstallSearch=t.value;refocus("uninstallSearch",pos);}
  else if(t.id==="repositoryPath"){repositoryPath=t.value;}
}

async function boot(){
  const app=document.getElementById("app");
  app?.addEventListener("click",onClick);
  app?.addEventListener("change",onChange);
  app?.addEventListener("input",onInput);
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&openMenu){openMenu="";render();}});
  try{
    render();
    await loadSetupData();
    await loadSetupRecovery();
    await loadReceipts();
    graph=buildLiveGraph();render();
    await refreshSystemProfile();render();
    try{await refreshSoftwareIntelligence(false);graph=buildLiveGraph();}catch(err){softwareScanError=String(err);}
    render();
    await loadGraph();
    await refreshDriverProfile();
    await loadWorkstationAssurance();
    render();
  }catch(err){
    errorText=String(err&&err.stack?err.stack:err);
    render();
  }
}

boot();
