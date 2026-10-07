let workstationHealth = null;
import "./style.css";
import {pandaSvg} from "./panda.js";

let graph = null;
let capabilityStatusIndex = null;
let missionConsole = null;
let systemProfile = null;
let systemProfileError = "";
let driverProfile = null;
let driverLoadError = "";
let softwareInventory = [];
let softwareIntelligence = null;
let softwareFilter = "all";
let softwareKindFilter = "all";
let softwareSearch = "";
let selectedSoftwareIndex = null;
let errorText = "";
let activeTab = "home";
let sidebarContext = "overview";
let showTechnical = false;
let selectedCapabilityId = null;
let activeHomeAction = null;
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

function renderMachineProfile(){
  const estimate=selectedAllocationEstimate();
  const limitMib=maxAllocationGb*1024;
  const freeGb=Number(systemProfile?.storage?.free_gb);
  const overLimit=estimate.complete&&estimate.mib>limitMib;
  const overFree=Number.isFinite(freeGb)&&estimate.mib>freeGb*1024;
  return `<section class="machinePlanner compactPlanner" aria-labelledby="machinePlannerTitle">
    <h3 id="machinePlannerTitle" class="plannerTitle">What are you setting up?</h3>
    <div class="plannerRow">
      <div class="machineTypeChoices" role="radiogroup" aria-label="Machine type">
        <label class="${machineType==="desktop"?"selected":""}"><input type="radio" name="machineType" data-machine-type="desktop" ${machineType==="desktop"?"checked":""}><b>Desktop</b><span>Room for larger SDKs, containers, and local AI.</span></label>
        <label class="${machineType==="laptop"?"selected":""}"><input type="radio" name="machineType" data-machine-type="laptop" ${machineType==="laptop"?"checked":""}><b>Laptop</b><span>Keeps the footprint tighter for portable storage.</span></label>
      </div>
      <div class="allocationControl">
        <label for="maxAllocationGb"><b>Maximum planned allocation</b><span>Storage this plan may use</span></label>
        <div><input id="maxAllocationGb" type="number" min="5" max="2048" step="1" value="${escapeHtml(maxAllocationGb)}"><span>GB</span></div>
      </div>
      <div class="allocationReadout ${overLimit||overFree?"overLimit":""}">
        <div><span>Selected estimate</span><b>${estimate.itemCount?formatAllocation(estimate.mib):"Choose tools"}</b><small>${estimate.itemCount} resolved tools</small></div>
        <div><span>Your ceiling</span><b>${escapeHtml(maxAllocationGb)} GB</b><small>${Number.isFinite(freeGb)?`${escapeHtml(freeGb)} GB currently free`:"Live free space unavailable"}</small></div>
      </div>
    </div>
    ${overLimit?`<p class="allocationWarning" role="alert">This selection is about ${formatAllocation(estimate.mib-limitMib)} over your chosen limit. Remove tools or raise the ceiling.</p>`:""}
    ${!overLimit&&overFree?`<p class="allocationWarning" role="alert">This estimate is larger than the currently reported free storage.</p>`:""}
    <p class="allocationLimit">Planning estimate only. Projects, package caches, containers, virtual machines, AI models, games, and later SDK downloads are not included.</p>
  </section>`;
}

function pandaMood(){
  const total=Number(setupProgress?.total)||setupPlan?.item_count||0;
  const done=Math.min(Number(setupProgress?.completed)||0,total);
  const count=selectedToolkitIds.size+selectedSoftwareIds.size;
  if(setupRunning){return {pose:"carry",title:"Carrying your tools over",text:`${done} of ${total} done. Keep me open; I save progress after every tool.`};}
  if(errorText||(!setupData&&setupLoadError)){return {pose:"sad",title:"I could not start",text:"My trusted runtime is not answering. Retry, and open technical details if it keeps happening."};}
  if(setupResult){return {pose:"happy",title:"All done",text:"Here is exactly what happened for every tool."};}
  if(setupPlan){return {pose:"think",title:"Your plan is ready",text:"Check the list below. I will not install anything until you approve it."};}
  if(softwareScanError){return {pose:"sad",title:"I could not finish looking around",text:"The software scan hit a problem. You can still pick tools, or ask me to scan again."};}
  if(!softwareIntelligence){return {pose:"scan",title:"Looking around your computer",text:"Reading installed software, checking Winget, and matching the approved catalog."};}
  const summary=softwareIntelligence.summary||{};
  if(sidebarContext==="overview"){
    const updates=Number(summary.updates_available)||0;
    return {pose:"happy",title:`I found ${Number(summary.detected)||0} things on this computer`,text:`${Number(summary.catalog_matched)||0} are tools I can manage${updates?`, and ${updates} ${updates===1?"has":"have"} an update ready`:""}. What shall we do?`};
  }
  if(count>0){return {pose:"happy",title:`${count} ${count===1?"pick":"picks"} so far`,text:"Looking good. Review the plan when you are ready; nothing installs yet."};}
  const idle={
    setup:["Let us build your computer","Tell me the work you do, pick a toolkit, and I will gather every tool for it."],
    browse:["Pick tools one by one","Search the approved catalog and tick what you want."],
    update:["Let us check your tools","I will compare what you have with approved sources."],
    repository:["Show me a project","Point me at a folder. I read its manifests and never run them."],
    restore:["Restore a setup","Give me a verified blueprint and I will rebuild from it."]
  };
  const [title,text]=idle[setupMode]||idle.setup;
  return {pose:"idle",title,text};
}

function renderPandaGuide(extra=""){
  const mood=pandaMood();
  return `<section class="pandaGuide" data-pose="${mood.pose}" aria-live="polite"><div class="pandaStage">${pandaSvg(mood.pose)}</div><div class="pandaSpeech"><b>${escapeHtml(mood.title)}</b><p>${escapeHtml(mood.text)}</p>${extra}</div></section>`;
}

function renderScanCard(){
  if(softwareScanError){
    return `<section class="scanCard scanFailed"><div><b>The software scan could not finish</b><p>Nothing was changed. You can still set up tools, or try the scan again.</p></div><button id="retryScan" class="secondaryAction">Scan again</button><details><summary>Technical details</summary><pre>${escapeHtml(softwareScanError)}</pre></details></section>`;
  }
  if(softwareIntelligence){return "";}
  return `<section class="scanCard scanning" aria-live="polite"><div class="radar" aria-hidden="true"><i></i><i></i><i></i><span></span></div><ul class="scanSteps"><li>Reading installed software</li><li>Checking Winget</li><li>Matching the approved catalog</li></ul><div class="scanBar" aria-hidden="true"><span></span></div></section>`;
}

function renderReturningSummary(){
  const total=Number(receiptIndex?.summary?.total)||0;
  const newest=(receiptIndex?.items||[]).map(x=>Number(x.modified_unix)||0).sort((a,b)=>b-a)[0];
  const scanned=softwareIntelligence?.observed_utc?new Date(softwareIntelligence.observed_utc).toLocaleString():"";
  const parts=[scanned?`Scanned ${scanned}`:"",total?`${total} verified ${total===1?"receipt":"receipts"} on this computer`:"",newest?`Last setup record ${new Date(newest*1000).toLocaleDateString()}`:""].filter(Boolean);
  return parts.length?`<p class="returningLine">${parts.map(escapeHtml).join(" · ")}</p>`:"";
}

function runCountUps(){
  const reduce=window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
  document.querySelectorAll("[data-countup]").forEach(node=>{
    const target=Number(node.getAttribute("data-countup"))||0;
    const key=`${node.getAttribute("data-count-key")||"count"}:${target}`;
    if(reduce||countedKeys.has(key)||target===0){node.textContent=String(target);countedKeys.add(key);return;}
    countedKeys.add(key);
    const start=performance.now();
    const step=now=>{
      const t=Math.min(1,(now-start)/700);
      node.textContent=String(Math.round(target*(1-Math.pow(1-t,3))));
      if(t<1){requestAnimationFrame(step);}
    };
    node.textContent="0";
    requestAnimationFrame(step);
  });
}

function renderSetupConsole(){
  const kits=setupData?.toolkits?.toolkits || [];
  const items=setupData?.catalog?.items || [];
  const categories=["all",...new Set(items.map(x=>x.category||"other"))];
  const visibleItems=items.filter(x=>catalogCategory==="all"||(x.category||"other")===catalogCategory).filter(x=>`${x.name} ${x.category||""} ${(x.capabilities||[]).join(" ")}`.toLowerCase().includes(catalogSearch.toLowerCase()));
  if(!setupData){ return `<section class="panel"><h2>Set up this computer</h2><p>The trusted desktop runtime is unavailable, so machine-changing actions are disabled.</p><button id="retryRuntime">Retry runtime</button><p role="status">${escapeHtml(setupLoadError)}</p></section>`; }
  const planItems=setupPlan?.items || [];
  const installedByCatalogId=new Map((softwareIntelligence?.items||[]).filter(x=>x.installed&&x.catalog_id).map(x=>[x.catalog_id,x]));
  const selectedCount=selectedToolkitIds.size+selectedSoftwareIds.size;
  const allocationEstimate=selectedAllocationEstimate();
  const allocationValid=Number.isInteger(maxAllocationGb)&&maxAllocationGb>=5&&maxAllocationGb<=2048&&allocationEstimate.complete&&allocationEstimate.mib<=maxAllocationGb*1024;
  const canReview=selectedCount>0&&allocationValid;
  return `
    <section class="panel setupConsole">
      <ol class="setupSteps" aria-label="Setup process">
        <li class="active"><b>1</b><span>Choose tools</span></li>
        <li class="${setupPlan?"active":""}"><b>2</b><span>Review plan</span></li>
        <li class="${setupRunning||setupResult?"active":""}"><b>3</b><span>Approve &amp; install</span></li>
      </ol>
      ${setupPlan?`<div class="reviewBar"><span><b>${setupRunning?"Installing.":setupResult?"Finished.":"Selection locked in."}</b> ${setupRunning?"Keep AssembleLink open; each tool is verified after it installs.":setupResult?"Every outcome is recorded in a receipt.":"Review the plan below; nothing is installed until you approve."}</span>${setupRunning?"":`<button id="editSelection" class="secondaryAction">← Change selection</button>`}</div>`:`
      ${renderSetupRecovery()}
      <div class="modeTabs" role="tablist" aria-label="Setup mode">
        ${[["setup","Set Up This Computer","Install complete curated toolkits."],["browse","Browse All Software","Build a custom toolkit."],["update","Update My Tools","Find approved installed-tool upgrades."],["repository","Analyze a Project","Detect runtimes and toolchains from repository manifests."],["restore","Restore Previous Setup","Load a verified AssembleLink blueprint."]].map(([mode,label,hint])=>`<button role="tab" aria-selected="${setupMode===mode}" class="${setupMode===mode?"active":""}" data-setup-mode="${mode}" title="${hint}">${label}</button>`).join("")}
      </div>
      ${!['update','repository'].includes(setupMode)?renderMachineProfile():""}
      ${setupMode==="setup"?`<h3 class="sectionTitle">Choose a job toolkit</h3>${renderToolkitGroups(kits)}`:""}
      ${setupMode==="browse"?`<h3>Approved software and CLI catalog</h3><div class="catalogToolbar"><label><span>Search tools</span><input id="catalogSearch" type="search" placeholder="Try Git, Python, Docker, or security" value="${escapeHtml(catalogSearch)}"></label><label><span>Category</span><select id="catalogCategorySelect">${categories.sort().map(c=>`<option value="${escapeHtml(c)}" ${catalogCategory===c?"selected":""}>${escapeHtml(c==="all"?"All categories":c.replaceAll("-"," "))}</option>`).join("")}</select></label></div><p class="catalogCount">${visibleItems.length} of ${items.length} trusted catalog entries shown</p><div class="setupChoices softwareChoices">${visibleItems.map(x=>{const installed=installedByCatalogId.get(x.id);return `<label class="${installed?"isInstalled":""}"><input type="checkbox" data-software-id="${escapeHtml(x.id)}" ${selectedSoftwareIds.has(x.id)?"checked":""}><b>${escapeHtml(x.name)}${installed?` <em class="installedMark">Installed${installed.installed_version?` · ${escapeHtml(installed.installed_version)}`:""}</em>`:""}</b><span>${escapeHtml((x.category||x.capabilities?.[0]||"software").replaceAll("-"," "))} · ${escapeHtml((x.license||"license review").replaceAll("_"," "))}</span><small>${escapeHtml(x.winget_id||"Manual review")}</small></label>`;}).join("")}</div>`:""}
      ${setupMode==="repository"?renderRepositoryAnalyzer():setupMode==="restore"?`<h3>Restore a verified blueprint</h3><p>Copy the blueprint and its <code>.sha256</code> file to this computer, then enter its full path.</p><input id="blueprintPath" placeholder="C:\\Users\\you\\Downloads\\AssembleLink-Blueprint.json"><button id="importBlueprint" class="primaryAction">Validate and review blueprint</button>`:setupMode==="update"?`<h3>Check approved tools for updates</h3><p>AssembleLink asks Winget about exact approved package identities. Review is still required before updating.</p><button id="scanUpdates" class="primaryAction">Check for updates</button>`:`<div class="selectionSummary"><span><b>${selectedCount}</b> ${selectedCount===1?"selection":"selections"} · ${allocationEstimate.itemCount?`${formatAllocation(allocationEstimate.mib)} estimated`:"no footprint yet"}</span><button id="reviewSetup" class="primaryAction" ${canReview?"":"disabled"}>Review download &amp; setup plan</button></div>${selectedCount===0?`<p class="selectionHint">Choose at least one toolkit or software item to continue.</p>`:!allocationValid?`<p class="selectionHint">Adjust the storage ceiling before continuing.</p>`:""}`}
`}
      ${setupPlan?`<button id="exportBlueprint" class="secondaryAction">Export this selection as a blueprint</button>`:""}
      <p role="status">${escapeHtml(operationMessage)}</p>
    </section>
    ${setupPlan&&!setupRunning&&!setupResult?`<section class="panel planPanel"><h2>Review ${setupPlan.plan_type==="update"?"update":"setup"} plan</h2><p><b>${setupPlan.item_count}</b> tools · ${setupPlan.automatic_count} automatic · ${setupPlan.manual_count} manual</p>${setupPlan.machine_profile?`<div class="planAllocation"><span>${escapeHtml(setupPlan.machine_profile.machine_type)} profile</span><b>${formatAllocation(setupPlan.allocation.estimated_installed_mib)} estimated of ${formatAllocation(setupPlan.allocation.max_allocation_mib)}</b><small>${formatAllocation(setupPlan.allocation.remaining_planned_mib)} planned headroom</small></div>${setupPlan.profile_guidance?.caution_count?`<p class="allocationWarning">${escapeHtml(setupPlan.profile_guidance.caution_count)} tools may have substantial storage, battery, memory, GPU, or thermal impact on a laptop.</p>`:""}`:""}${table(["Tool","Estimated size","Machine fit","Package identity","License","Dependencies","Admin / reboot","Action"],planItems.map(x=>[x.name,x.estimated_installed_mib?formatAllocation(x.estimated_installed_mib):"—",x.profile_advisory==="review_laptop_resource_impact"?"Review laptop impact":"Compatible",x.winget_id||"—",x.license.replaceAll("_"," "),(x.dependencies||[]).join(", ")||"—",`${x.admin_required?"Admin":"User"}${x.reboot_required?" · reboot possible":""}`,humanStatus(x.status)]))}${setupPlan.item_count?`<button id="approveSetup" class="primaryAction" ${setupRunning?"disabled":""}>${setupRunning?"Setup running…":setupRecovery?.plan?.plan_id===setupPlan.plan_id?"Approve and resume remaining tools":`Approve and ${setupPlan.plan_type==="update"?"update my tools":"set up this computer"}`}</button>`:""}</section>`:""}
    ${renderSetupProgress()}
    ${setupResult?renderSetupResult():""}
  `;
}

function renderSetupRecovery(){
  if(!setupRecovery){return setupRecoveryError?`<p role="status">Interrupted-run inspection unavailable: ${escapeHtml(setupRecoveryError)}</p>`:"";}
  const completed=Number(setupRecovery.progress?.completed)||0;
  const total=Number(setupRecovery.progress?.total)||0;
  return `<aside class="recoveryNotice">
    <b>Interrupted setup found</b>
    <span>${completed} of ${total} tools were recorded before the run stopped. Completed automatic tools will be independently checked before they are skipped.</span>
    <button id="reviewRecovery" class="secondaryAction">Review and resume</button>
  </aside>`;
}

function renderSetupProgress(){
  if(!setupProgress||setupProgress.plan_id!==setupPlan?.plan_id||(!setupRunning&&setupProgress.status==="idle")){return "";}
  const total=Number(setupProgress.total)||setupPlan?.item_count||0;
  const completed=Math.min(Number(setupProgress.completed)||0,total);
  const rows=Array.isArray(setupProgress.results)?setupProgress.results:[];
  const status=setupProgress.status==="complete"?"Complete":setupRunning?"Running":"Stopped";
  return `<section class="panel setupProgress" aria-live="polite">
    <h2>Setup progress</h2>
    <p><b>${escapeHtml(status)}</b> · ${completed} of ${total} tools finished</p>
    <div class="carryTrack" style="--pct:${Math.round(completed/Math.max(total,1)*100)}%"><div class="carryFill"></div><div class="carryRunner ${setupRunning?"walking":""}">${pandaSvg(setupProgress.status==="complete"?"happy":setupRunning?"carry":"idle","Panda carrying your tools")}</div></div>
    <progress class="srOnly" value="${completed}" max="${Math.max(total,1)}">${completed} of ${total}</progress>
    <p>Keep AssembleLink open. Progress is saved after every tool.</p>
    ${rows.length?table(["Tool","Outcome","Details"],rows.map(x=>[x.name||x.winget_id||x.id,humanStatus(x.status),x.message])):""}
  </section>`;
}

function renderToolkitGroups(kits){
  const families=[...new Set(kits.map(k=>k.job_family||"Other"))].sort();
  return families.map(family=>`<section class="toolkitFamily"><h4>${escapeHtml(family)}</h4><div class="setupChoices">${kits.filter(k=>(k.job_family||"Other")===family).map(k=>`<label class="toolkitCard ${selectedToolkitIds.has(k.id)?"isPicked":""}"><input type="checkbox" data-toolkit-id="${escapeHtml(k.id)}" ${selectedToolkitIds.has(k.id)?"checked":""}><i class="tick" aria-hidden="true"></i><b>${escapeHtml(k.name)}</b><span>${escapeHtml(k.description)}</span><small>${k.software_ids.length} reviewed tools</small></label>`).join("")}</div></section>`).join("");
}

function renderRepositoryAnalyzer(){
  const result=repositoryAnalysis;
  return `<section class="repositoryAnalyzer"><h3>Analyze a development project</h3><p>Choose a local project folder. AssembleLink reads supported top-level manifests, maps required runtimes to approved catalog identities, and creates sealed evidence. It never executes project files.</p><div class="repositoryPath"><input id="repositoryPath" value="${escapeHtml(repositoryPath)}" placeholder="C:\\dev\\my-project" autocomplete="off"><button id="analyzeRepository" class="primaryAction">Analyze project</button></div>${result?`<div class="repositoryResult"><h4>${escapeHtml(result.repository?.name||"Project")} · ${escapeHtml(result.summary?.status||"analyzed")}</h4><p>${escapeHtml(result.summary?.recognized_manifests||0)} manifests · ${escapeHtml(result.summary?.resolved_catalog_items||0)} approved tools recommended</p>${(result.requirements||[]).length?table(["Requirement","Evidence","Version","Approved tools"],result.requirements.map(x=>[x.kind,x.evidence,x.version_constraint||"Review latest compatible",(x.catalog_ids||[]).join(", ")])):`<p>No supported top-level manifests were found.</p>`}${(result.recommended_software_ids||[]).length?`<button id="useRepositoryRecommendations" class="primaryAction">Review recommended setup</button>`:""}</div>`:""}</section>`;
}

function renderSetupResult(){
  const rows=setupResult?.results||[];
  return `<section class="panel"><h2>Setup results</h2>${table(["Tool","Outcome","Source verified","Installed verified","Details"],rows.map(x=>[x.name,humanStatus(x.status),x.source_verified?"Yes":"No",x.verified?"Yes":"No",x.message]))}</section>`;
}

async function loadMissionConsole(){
  try{
    const res = await fetch("./state/mission_console.latest.json?ts=" + Date.now());
    if(!res.ok){ missionConsole = null; return; }
    const txt = await res.text();
    if(txt.trim().startsWith("<")){ missionConsole = null; return; }
    missionConsole = sanitizeStateValue(JSON.parse(txt));
  }catch(_e){
    missionConsole = null;
  }
}

function renderMissionConsole(){
  if(!missionConsole){ return ""; }
  const missions = Array.isArray(missionConsole.missions) ? missionConsole.missions : [];
  return `
    <section class="panel missionConsole">
      <p class="eyebrow">Mission console</p>
      <h2>Workstation missions</h2>
      <p class="sectionLead">Finish setup, review installs, or open a workspace.</p>
      <div class="missionList">
        ${missions.map(m=>`
          <article class="missionRow">
            <div class="missionMain">
              <h3>${m.title || ""}</h3>
              <p class="missionImpact">${m.impact || "Developer workstation capability"}</p>
              <p class="missionNext">${m.next_action || "Open workspace"}</p>
            </div>
            <div class="missionScore"><b>${m.completion_percent || 0}%</b><span>${m.status || ""}</span></div>
            <div class="missionMini"><b>${m.installed_count || 0}</b><span>tracked</span></div>
            <div class="missionMini"><b>${m.missing_count || 0}</b><span>missing</span></div>
            <div class="missionMini"><b>${m.recommended_install_count || 0}</b><span>installable</span></div>
            <div class="missionRowActions">
              <button class="primaryAction" data-review="${m.capability_id}">${m.missing_count > 0 ? "Finish" : "Open"}</button>
              <button class="secondaryAction" data-stack-plan="${m.capability_id}">${m.recommended_install_count > 0 ? "Install" : "Plan"}</button>
            </div>
          </article>
        `).join("")}
      </div>
    </section>
  `;
}

function renderBlueprintReadiness(){
  if(!missionConsole?.blueprint_readiness){ return ""; }
  const b = missionConsole.blueprint_readiness;
  return `
    <details class="panel blueprintPanel">
      <summary>Blueprint readiness</summary>
      <p class="eyebrow">Rebuild readiness</p>
      <h2>Blueprint readiness · ${b.readiness_percent || 0}%</h2>
      <div class="blueprintGrid">
        <div>
          <h3>Tracked</h3>
          <ul>${(b.tracked || []).map(x=>`<li>✓ ${x}</li>`).join("")}</ul>
        </div>
        <div>
          <h3>Missing</h3>
          <ul>${(b.missing || []).map(x=>`<li>• ${x}</li>`).join("")}</ul>
        </div>
      </div>
      <button class="primaryAction" data-tab-jump="export">${b.next_action || "Open Export"}</button>
    </details>
  `;
}

function renderWorkstationValueStrip(){
  if(!missionConsole){ return ""; }
  const ready = (missionConsole.missions || []).filter(m=>m.completion_percent >= 90);
  return `
    <section class="panel valueStrip">
      <p class="eyebrow">Capability summary</p>
      <h2>This workstation can currently support</h2>
      <div class="valueTags">
        ${ready.map(m=>`<span>✓ ${m.capability_name}</span>`).join("")}
      </div>
    </section>
  `;
}
async function loadCapabilityStatusIndex(){
  try{
    const res = await fetch("./state/capability_status_index.latest.json?ts=" + Date.now());
    if(!res.ok){ capabilityStatusIndex = null; return; }
    const txt = await res.text();
    if(txt.trim().startsWith("<")){ capabilityStatusIndex = null; return; }
    capabilityStatusIndex = sanitizeStateValue(JSON.parse(txt));
  }catch(_e){
    capabilityStatusIndex = null;
  }
}

function getCapabilityStatus(id){
  const caps = Array.isArray(capabilityStatusIndex?.capabilities) ? capabilityStatusIndex.capabilities : [];
  return caps.find(x => x.capability_id === id) || null;
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

function nav(id,label){
  const active=id==="home"?activeTab==="home"&&sidebarContext==="overview":activeTab===id;
  return `<button class="${active ? "active" : ""}" data-tab="${id}">${label}</button>`;
}
function setupNav(mode,label,badge=""){
  return `<button class="navAction ${activeTab==="home"&&sidebarContext===mode?"active":""}" data-setup-jump="${mode}"><span>${label}</span>${badge?`<b>${escapeHtml(badge)}</b>`:""}</button>`;
}

function capCard(c){
  const detected = Array.isArray(c.detected) ? c.detected.slice(0,6) : [];
  const score=Math.max(0,Math.min(100,Number(c.score)||0));
  return `
    <article class="capCard">
      <div class="capTop">
        <h2>${escapeHtml(c.name)}</h2>
        <span>${escapeHtml(c.status)}</span>
      </div>
      <div class="scoreRow">
        <div class="scoreBar"><div style="width:${score}%"></div></div>
        <b>${score}%</b>
      </div>
      <p>${escapeHtml(detected.length ? detected.join(", ") : "Matched through capability rules.")}</p>
      <div class="capabilityActions">
        <button class="primaryAction" data-review="${escapeHtml(c.id)}">Open</button>
        <button class="secondaryAction" data-stack-plan="${escapeHtml(c.id)}">Plan</button>
      </div>
    </article>
  `;
}

function softwareRecommendations(cap){
  const map = {
    "game-development": [
      ["Unity Hub", "Installed / account gated", "Unity account required", "Official installer or winget"],
      ["Unreal / Epic", "Installed / account gated", "Epic account required", "Epic Games Launcher"],
      ["Blender", "Installed", "Free/open-source", "Official installer or winget"],
      ["Visual Studio Build Tools", "Recommended", "Free", "Microsoft installer"],
      ["Godot", "Installed", "Free/open-source", "Official installer or winget"],
      ["Aseprite", "Installed", "Paid/commercial", "Steam or official store"]
    ],
    "content-creation": [
      ["Adobe Creative Cloud", "Installed / subscription", "Adobe subscription required", "Adobe installer"],
      ["OBS Studio", "Recommended", "Free/open-source", "Official installer or winget"],
      ["Figma", "Installed / account", "Figma account optional/required by workflow", "Official installer"],
      ["Canva", "Installed / account", "Account/subscription possible", "Official installer"],
      ["GIMP", "Installed", "Free/open-source", "Official installer or winget"],
      ["Audacity", "Installed", "Free/open-source", "Official installer or winget"]
    ],
    "cybersecurity": [
      ["Wireshark", "Installed", "Free/open-source", "Official installer or winget"],
      ["Nmap", "Installed", "Free/open-source", "Official installer or winget"],
      ["Burp Suite Community", "Installed", "Free tier / pro available", "PortSwigger installer"],
      ["Autopsy", "Installed", "Free/open-source", "Official installer"],
      ["Ghidra", "Recommended", "Free/open-source", "Official NSA GitHub release"],
      ["x64dbg", "Recommended", "Free/open-source", "Official release"]
    ],
    "software-development": [
      ["Git", "Installed", "Free/open-source", "Official installer or winget"],
      ["VS Code", "Installed", "Free", "Microsoft installer or winget"],
      ["Visual Studio", "Installed", "Community/free or licensed", "Visual Studio Installer"],
      ["JetBrains IDEs", "Installed / licensed", "Account/subscription possible", "JetBrains Toolbox"],
      ["Docker Desktop", "Installed", "License depends on org size/use", "Docker installer"],
      ["Python / Node / Go / Rust", "Installed", "Free/open-source", "Official installers"]
    ],
    "local-ai": [
      ["Ollama", "Installed", "Free", "Official installer"],
      ["Python", "Installed", "Free/open-source", "Official installer"],
      ["Docker", "Installed", "License depends on org size/use", "Docker installer"],
      ["NVIDIA CUDA Toolkit", "Recommended", "Free", "NVIDIA installer"],
      ["PyTorch CUDA", "Recommended", "Free/open-source", "pip/conda"],
      ["Model cache location", "Needs mapping", "Depends on models", "Local path config"]
    ],
    "infrastructure": [
      ["Docker Desktop", "Installed", "License depends on org size/use", "Docker installer"],
      ["WSL", "Detected/recommended", "Free", "Windows feature"],
      ["VirtualBox", "Installed", "Free", "Official installer"],
      ["PostgreSQL", "Installed", "Free/open-source", "Official installer"],
      ["PowerShell 7", "Installed", "Free/open-source", "Microsoft installer"],
      ["TablePlus", "Optional", "Paid/commercial", "Official installer"]
    ]
  };

  return map[cap.id] || [];
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
function renderCapabilityDetail(){
  if(!graph){ return renderHome(); }

  const caps = Array.isArray(graph.capabilities) ? graph.capabilities : [];
  const cap = caps.find(x => x.id === selectedCapabilityId);
  if(!cap){ return renderHome(); }

  const detected = Array.isArray(cap.detected) ? cap.detected : [];
  const missing = Array.isArray(cap.missing_required) ? cap.missing_required : [];
  const recs = softwareRecommendations(cap);

  return `
    <section class="hero">
      <div>
        <button id="backHome">← Back</button>
        <h1>${cap.name}</h1>
        <p>This view explains what AssembleLink found, what it recommends, and what install/licensing path each tool needs.</p>
      </div>
    </section>

    <section class="summaryStrip">
      <div><b>${cap.score}%</b><span>readiness</span></div>
      <div><b>${cap.status}</b><span>status</span></div>
      <div><b>${detected.length}</b><span>detected examples</span></div>
      <div><b>${missing.length}</b><span>missing required</span></div>
    </section>

    ${renderSoftwareDetail()}

    <section class="panel">
      <h2>Detected software</h2>
      <div class="detectedBlock">
        ${detected.length ? detected.map(x=>`<span class="detectedPill">${escapeHtml(x)}</span>`).join("") : "<p>No reviewed detected examples matched this capability.</p>"}
      </div>
    </section>

    ${cap.hardware_support ? `
      <section class="panel">
        <h2>Hardware support</h2>
        <p><b>Status:</b> ${cap.hardware_support.status}</p>
        <p><b>CPU:</b> ${cap.hardware_support.cpu || "Unknown"}</p>
        <p><b>GPU:</b> ${cap.hardware_support.gpu || "Unknown"} ${cap.hardware_support.vram_gb ? `(${cap.hardware_support.vram_gb} GB VRAM)` : ""}</p>
        <p><b>RAM:</b> ${cap.hardware_support.ram_gb || "?"} GB</p>
        <p><b>Free storage:</b> ${cap.hardware_support.free_storage_gb || "?"} GB</p>
        <div class="detectedBlock">
          ${(cap.hardware_support.notes || []).map(x=>`<span class="detectedPill">${x}</span>`).join("")}
        </div>
      </section>
    ` : ""}

    <section class="panel">
      <h2>Recommended software and install direction</h2>
      ${table(["Software","State","License / account","Install direction"], recs)}
    </section>

    <section class="panel">
      <h2>What should happen next</h2>
      <p>AssembleLink uses the live inventory and approved catalog to build one reviewable, content-hashed setup plan. Manual and license-gated tools stay outside automatic execution.</p>
      <button class="primaryAction" data-install-recommended="${cap.id}">Configure Approved Toolkit</button>
      <button class="secondaryAction" data-browse-approved>Browse Approved Software</button>
      <p role="status">${escapeHtml(operationMessage)}</p>
    </section>
  `;
}

function table(headers, rows){
  return `
    <table class="compareTable">
      <thead><tr>${headers.map(h=>`<th>${escapeHtml(h)}</th>`).join("")}</tr></thead>
      <tbody>${rows.map(r=>`<tr>${r.map(c=>`<td>${c&&typeof c==="object"&&"__trustedHtml" in c?c.__trustedHtml:escapeHtml(c)}</td>`).join("")}</tr>`).join("")}</tbody>
    </table>
  `;
}
function renderWorkstationSnapshotHero(){
  const machine = systemProfile?.machine || {};
  const os = systemProfile?.os || {};
  const cpu = systemProfile?.cpu || {};
  const mem = systemProfile?.memory || {};
  const storage = systemProfile?.storage || {};
  const gpu = Array.isArray(systemProfile?.gpu) ? systemProfile.gpu[0] : null;

  return `
    <section class="panel workstationHero">
      <div>
        <p class="eyebrow">Workstation snapshot</p>
        <h2>${machine.name || "This PC"}</h2>
        <p>${os.caption || "Windows"} · ${os.architecture || "64-bit"}</p>
      </div>
      <div class="heroSpecGrid">
        <div><b>${cpu.name || "CPU unknown"}</b><span>processor</span></div>
        <div><b>${gpu?.name || "GPU unknown"}</b><span>${gpu?.vram_gb || "?"} GB VRAM</span></div>
        <div><b>${mem.total_gb || "?"} GB</b><span>RAM</span></div>
        <div><b>${storage.free_gb || "?"} GB</b><span>free storage</span></div>
      </div>
    </section>
  `;
}

function renderPrimaryActions(){
  const drives=Array.isArray(systemProfile?.storage?.drives)?systemProfile.storage.drives:[];
  const low=drives.filter(d=>(Number(d.free_percent)||0)<15).map(d=>d.drive);
  const storageMessage=systemProfileError?"Live storage inventory unavailable.":low.length?`${low.join(", ")} need cleanup attention.`:"Review capacity and free space by drive.";
  return `
    <section class="panel actionConsole">
      <p class="eyebrow">What can AssembleLink do now?</p>
      <h2>Workstation actions</h2>
      <div class="actionGrid">
        <button class="bigAction" data-home-action="install">Install Recommended Software<span>Use approved queues and stamped receipts.</span></button>
        <button class="bigAction" data-home-action="missing">Scan For Missing Tools<span>Find gaps by capability lane.</span></button>
        <button class="bigAction" data-home-action="export">Export Blueprint<span>Prepare this machine for rebuild.</span></button>
        <button class="bigAction" data-home-action="storage">Review Storage Health<span>${escapeHtml(storageMessage)}</span></button>
      </div>
      ${renderHomeActionResult()}
    </section>
  `;
}

function renderHomeActionResult(){
  if(!activeHomeAction){ return ""; }

  const caps = Array.isArray(graph?.capabilities) ? graph.capabilities : [];
  if(activeHomeAction === "install"){
    return `
      <div class="actionResult">
        <h3>Install Recommended Software</h3>
        <p>Choose a lane below, then click Open. AssembleLink will show approved tools, install status, and receipts.</p>
        ${table(["Capability","Readiness","Next step"], caps.map(c=>[
          c.name || "",
          (c.score || 0)+"%",
          rawHtml(`<button class="primaryAction" data-review="${escapeHtml(c.id)}">Open</button>`)
        ]))}
      </div>
    `;
  }

  if(activeHomeAction === "missing"){
    return `
      <div class="actionResult">
        <h3>Missing tool scan</h3>
        <p>Current capability graph shows ${caps.length} capability lanes. Missing-required counts are shown per lane when available.</p>
        ${table(["Capability","Missing required","Status"], caps.map(c=>[
          c.name || "",
          Array.isArray(c.missing_required) ? c.missing_required.length : 0,
          c.status || ""
        ]))}
      </div>
    `;
  }

  if(activeHomeAction === "export"){
    return `
      <div class="actionResult">
        <h3>Export Blueprint</h3>
        <p>Next implementation target: export system profile, software inventory, capability graph, install queues, and receipts as a rebuild profile.</p>
        <button class="primaryAction" data-tab-jump="export">Open Rebuild / Export</button>
      </div>
    `;
  }

  if(activeHomeAction === "storage"){
    const drives = Array.isArray(systemProfile?.storage?.drives) ? systemProfile.storage.drives : [];
    const bad = drives.filter(d => Number(d.free_percent || 0) < 10);
    return `
      <div class="actionResult">
        <h3>Storage Health</h3>
        <p>${bad.length} drive(s) need cleanup. Low free space is the main reason workstation health is below 90%.</p>
        ${table(["Drive","Free","Status"], bad.map(d=>[
          d.drive || "",
          `${d.free_gb} GB (${d.free_percent}%)`,
          "Needs cleanup"
        ]))}
      </div>
    `;
  }

  return "";
}

function renderRecommendedActionsHome(){
  const drives = Array.isArray(systemProfile?.storage?.drives) ? systemProfile.storage.drives : [];
  const lowDrives = drives.filter(d => Number(d.free_percent || 0) < 10);
  const caps = Array.isArray(graph?.capabilities) ? graph.capabilities : [];
  const ai = caps.find(c => c.id === "local-ai");

  const actions = [];
  lowDrives.forEach(d=>{
    actions.push({
      level:"High",
      title:`Clean up drive ${d.drive}`,
      detail:`Only ${d.free_gb} GB free (${d.free_percent}%). Move caches, games, models, or build artifacts.`,
      action:"View storage"
    });
  });

  if(ai){
    actions.push({
      level:"Recommended",
      title:"Review Local AI toolchain",
      detail:"CUDA/model runtime support should be verified against the detected RTX 4060.",
      action:"Open Local AI"
    });
  }

  if(actions.length === 0){ return ""; }

  return `
    <details class="panel recommendedNow">
      <summary>Recommended next actions</summary>
      <p class="eyebrow">Recommended next actions</p>
      <h2>Fix these first</h2>
      <div class="recommendationList">
        ${actions.map(a=>`
          <article>
            <b>${a.level}</b>
            <h3>${a.title}</h3>
            <p>${a.detail}</p>
          </article>
        `).join("")}
      </div>
    </section>
  `;
}
function renderWorkstationHealth(){
  if(!workstationHealth){ return ""; }

  const areas = Array.isArray(workstationHealth.areas) ? workstationHealth.areas : [];

  return `
    <section class="panel">
      <h2>Workstation health</h2>
      <div class="summaryStrip">
        <div><b>${workstationHealth.score}%</b><span>overall health</span></div>
        ${areas.map(a=>`<div><b>${a.score}%</b><span>${a.name}</span></div>`).join("")}
      </div>
      <p>Storage is currently the main thing pulling this workstation down.</p>
    </section>
  `;
}
function renderCapabilityCard(c){
  const s = getCapabilityStatus(c.id);
  const miniStats = s;
  const installed = miniStats ? miniStats.installed : (Array.isArray(c.detected) ? c.detected.length : 0);
  const missing = miniStats ? miniStats.missing : (Array.isArray(c.missing_required) ? c.missing_required.length : 0);
  return `
    <article class="capabilityCard compactCapability">
      <div class="cardTop">
        <h3>${c.name || "Capability"}</h3>
        <span>${humanStatus(s?.status || c.status || "")}</span>
      </div>
      <div class="scoreLine"><b>${c.score || 0}%</b><span> readiness</span></div>
      <div class="simpleCapabilityStats">
        <div><b>${installed}</b><span>installed / tracked</span></div>
        <div><b>${missing}</b><span>missing</span></div>
      </div>
      <div class="capabilityActions">
        <button class="primaryAction" data-review="${c.id}">Open Workspace</button>
        <button class="secondaryAction" data-stack-plan="${c.id}">${missing > 0 ? "Install Missing" : "Review Plan"}</button>
      </div>
    </article>
  `;
}
function renderCapabilityOverview(){
  if(!graph){ return ""; }
  const caps = Array.isArray(graph.capabilities) ? graph.capabilities : [];
  return `
    <section class="panel capabilityStart" style="display:none">
      <h2>Start here</h2>
      <p class="sectionLead">Choose a capability to review tools, generate an install path, and stamp AssembleLink receipts.</p>
      <div class="capGrid">
        ${caps.map(c=>renderCapabilityCard(c)).join("")}
      </div>
    </section>
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

function renderDashboardQuickStart(){
  return `<section class="quickStart">
    <div class="sectionHeading"><div><p class="eyebrow">Start here</p><h2>What do you want to do?</h2></div></div>
    <div class="quickStartGrid">
      <button class="quickCard primaryQuick" data-setup-jump="setup"><span class="quickIcon">＋</span><b>Set up this computer</b><small>Choose a job and install a complete reviewed toolkit.</small><em>Start setup →</em></button>
      <button class="quickCard" data-setup-jump="browse"><span class="quickIcon">⌕</span><b>Find software & CLI tools</b><small>Search ${setupData?.catalog?.items?.length||0} approved downloads in one place.</small><em>Browse catalog →</em></button>
      <button class="quickCard" data-setup-jump="update"><span class="quickIcon">↻</span><b>Check for updates</b><small>Compare installed versions against approved providers.</small><em>Check versions →</em></button>
      <button class="quickCard" data-tab-jump="export"><span class="quickIcon">⇧</span><b>Rebuild another computer</b><small>Export or restore a verified machine blueprint.</small><em>Open rebuild →</em></button>
    </div>
  </section>`;
}

function renderDashboardInventory(){
  const summary=softwareIntelligence?.summary||{};
  const known=Number(summary.catalog_matched)||0;
  const detected=Number(summary.detected)||0;
  const updates=Number(summary.updates_available)||0;
  const unknown=Number(summary.unknown)||0;
  const appCandidates=Number(summary.unmatched_unique_applications ?? summary.unmatched_application_candidates ?? summary.unmatched)||0;
  const components=Number(summary.unmatched_components)||0;
  const provider=softwareIntelligence?.provider_health?.winget;
  const scanTime=softwareIntelligence?.observed_utc?new Date(softwareIntelligence.observed_utc).toLocaleString():"Scan still loading";
  return `<section class="panel inventoryOverview">
    <div class="sectionHeading">
      <div><p class="eyebrow">What you have</p><h2>Your software at a glance</h2><p>Last local scan: ${escapeHtml(scanTime)}</p></div>
      <button id="refreshSoftware" class="secondaryAction">Rescan computer</button>
    </div>
    <div class="inventoryMetrics">
      <button data-tab-jump="software"><b data-countup="${known}" data-count-key="known">${known}</b><span>known tools</span><small>Matched to approved downloads</small></button>
      <button data-tab-jump="software"><b data-countup="${detected}" data-count-key="detected">${detected}</b><span>detected entries</span><small>${appCandidates} app candidates · ${components} components</small></button>
      <button data-setup-jump="update" class="${updates?"metricAttention":""}"><b data-countup="${updates}" data-count-key="updates">${updates}</b><span>updates available</span><small>${updates?"Ready to review":"No approved updates reported"}</small></button>
      <button data-tab-jump="software" class="${unknown?"metricCaution":""}"><b data-countup="${unknown}" data-count-key="unknown">${unknown}</b><span>versions to review</span><small>Unknown never means current</small></button>
    </div>
    ${provider==="package_manager_unavailable"?`<div class="inlineNotice"><b>Winget needs attention</b><span>Windows App Installer is unavailable, so package updates cannot be checked or installed automatically.</span></div>`:""}
  </section>`;
}

function renderDashboardAssurance(){
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

function renderDashboardMachine(){
  const machine=systemProfile?.machine||{};
  const os=systemProfile?.os||{};
  const cpu=systemProfile?.cpu||{};
  const memory=systemProfile?.memory||{};
  const storage=systemProfile?.storage||{};
  const gpu=Array.isArray(systemProfile?.gpu)?systemProfile.gpu[0]:null;
  const drives=Array.isArray(storage.drives)?storage.drives:[];
  const low=drives.filter(d=>Number(d.free_percent)<15);
  const updates=Number(softwareIntelligence?.summary?.updates_available)||0;
  const unknown=Number(softwareIntelligence?.summary?.unknown)||0;
  const issues=[
    ...(updates?[`${updates} approved software update${updates===1?"":"s"} available`]:[]),
    ...(unknown?[`${unknown} installed version${unknown===1?" needs":"s need"} review`]:[]),
    ...low.map(d=>`${d.drive} has ${d.free_percent}% free space`)
  ];
  return `<section class="dashboardTwoColumn">
    <article class="panel machineCard">
      <div class="sectionHeading"><div><p class="eyebrow">This computer</p><h2>${escapeHtml(machine.name||"Windows PC")}</h2><p>${escapeHtml(os.caption||"Windows")} · ${escapeHtml(os.architecture||"64-bit")}</p></div><button data-tab-jump="software" class="textButton">View inventory →</button></div>
      <div class="machineFacts">
        <div><span>Processor</span><b>${escapeHtml(cpu.name||"Scanning…")}</b></div>
        <div><span>Graphics</span><b>${escapeHtml(gpu?.name||"Scanning…")}</b></div>
        <div><span>Memory</span><b>${escapeHtml(memory.total_gb||"?")} GB RAM</b></div>
        <div><span>Storage</span><b>${escapeHtml(storage.free_gb||"?")} GB free</b></div>
      </div>
    </article>
    <article class="panel attentionCard">
      <div class="sectionHeading"><div><p class="eyebrow">Needs attention</p><h2>${issues.length?`${issues.length} item${issues.length===1?"":"s"} to review`:"Everything looks clear"}</h2></div></div>
      ${issues.length?`<ul class="attentionList">${issues.slice(0,5).map(issue=>`<li><span>!</span>${escapeHtml(issue)}</li>`).join("")}</ul>`:`<p>No approved updates, unknown versions, or low-space drives were reported.</p>`}
      <div class="inlineActions"><button data-setup-jump="update" class="secondaryAction">Review updates</button><button data-tab-jump="drivers" class="secondaryAction">Review drivers</button></div>
    </article>
  </section>`;
}

function renderDashboardToolkits(){
  const preferred=["developer-essentials","cloud-infrastructure","cybersecurity","local-ai","game-development","content-creation"];
  const all=setupData?.toolkits?.toolkits||[];
  const kits=preferred.map(id=>all.find(k=>k.id===id)).filter(Boolean);
  if(!kits.length){return "";}
  return `<section class="panel starterToolkits">
    <div class="sectionHeading"><div><p class="eyebrow">Download by job</p><h2>Popular workstation setups</h2><p>Pick a role and AssembleLink will prepare the full reviewed tool list.</p></div><button data-setup-jump="setup" class="textButton">See all ${all.length} toolkits →</button></div>
    <div class="toolkitPreviewGrid">${kits.map(kit=>`<article>
      <span>${escapeHtml(kit.job_family||"Toolkit")}</span>
      <h3>${escapeHtml(kit.name)}</h3>
      <p>${escapeHtml(kit.description)}</p>
      <div><small>${kit.software_ids?.length||0} reviewed tools</small><button data-quick-toolkit="${escapeHtml(kit.id)}">Choose</button></div>
    </article>`).join("")}</div>
  </section>`;
}

function renderDashboardInstalled(){
  const items=(softwareIntelligence?.items||[]).filter(item=>item.installed&&item.catalog_id).slice(0,10);
  if(!items.length){return "";}
  return `<section class="panel installedPreview">
    <div class="sectionHeading"><div><p class="eyebrow">Recognized software</p><h2>Tools AssembleLink can manage</h2></div><button data-tab-jump="software" class="textButton">View all installed software →</button></div>
    <div class="installedChips">${items.map(item=>`<button data-tab-jump="software"><b>${escapeHtml(item.name)}</b><span>${escapeHtml(item.installed_version||"Version unknown")}</span><em class="${item.update_status==="update_available"?"needsUpdate":""}">${escapeHtml(humanStatus(item.update_status))}</em></button>`).join("")}</div>
  </section>`;
}

function renderSetupWorkspace(){
  return `${renderPandaGuide()}${renderScanCard()}${renderSetupConsole()}`;
}

function renderHome(){
  if(errorText){
    return `<section class="panel"><h1>Something could not start</h1><p>The setup catalog and inventory remain available where possible.</p><pre>${escapeHtml(errorText)}</pre></section>`;
  }

  if(!graph){
    return `<section class="panel"><h1>Loading workstation graph...</h1></section>`;
  }

  if(sidebarContext!=="overview"){return renderSetupWorkspace();}

  return `
    ${renderPandaGuide(renderReturningSummary())}
    ${renderScanCard()}
    ${setupRecovery?renderSetupRecovery():""}
    ${renderDashboardQuickStart()}
    ${softwareIntelligence?renderDashboardInventory():""}
    ${renderDashboardMachine()}
    ${renderDashboardInstalled()}
    <details class="proofDetails"><summary>Workstation proof and evidence</summary>${renderDashboardAssurance()}</details>
  `;
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

function licenseGuess(app){
  const s=((app.name||"")+" "+(app.publisher||"")).toLowerCase();
  if(s.includes("adobe")) return "Subscription / account";
  if(s.includes("jetbrains")) return "Commercial / account";
  if(s.includes("unity") || s.includes("unreal") || s.includes("epic")) return "Account / license gated";
  if(s.includes("docker")) return "License depends on organization/use";
  if(s.includes("git") || s.includes("python") || s.includes("blender") || s.includes("nmap") || s.includes("wireshark") || s.includes("gimp") || s.includes("audacity")) return "Free/open-source or free tier";
  if(s.includes("driver") || s.includes("nvidia") || s.includes("amd") || s.includes("realtek")) return "Driver/admin approval";
  return "Unknown / needs classification";
}

function installDirectionGuess(app){
  const s=((app.name||"")+" "+(app.publisher||"")).toLowerCase();
  if(s.includes("adobe")) return "Adobe Creative Cloud / official Adobe installer";
  if(s.includes("nvidia")) return "NVIDIA official driver/app source";
  if(s.includes("amd")) return "AMD official source or motherboard vendor page";
  if(s.includes("realtek")) return "Motherboard vendor page first";
  if(s.includes("microsoft") || s.includes("visual studio") || s.includes("vs code")) return "Microsoft official installer or winget";
  if(s.includes("jetbrains")) return "JetBrains Toolbox / official installer";
  if(s.includes("python")) return "Python.org or winget";
  if(s.includes("git")) return "Git official installer or winget";
  if(s.includes("docker")) return "Docker official installer";
  if(s.includes("blender")) return "Blender official installer or winget";
  return "Classify source before install";
}

function renderSoftwareDetail(){
  if(selectedSoftwareIndex === null){ return ""; }

  const app=softwareInventory[selectedSoftwareIndex];
  if(!app){ return ""; }

  const category=softwareCategory(app);

  return `
    <section class="panel">
      <div class="cardTop">
        <h2>${escapeHtml(app.name || "Unknown software")}</h2>
        <button id="closeSoftwareDetail">Close</button>
      </div>

      <div class="summaryStrip">
        <div><b>${escapeHtml(category)}</b><span>category</span></div>
        <div><b>${escapeHtml(app.version || "Unknown")}</b><span>installed version</span></div>
        <div><b>${escapeHtml(app.available_version || "Unknown")}</b><span>available version</span></div>
        <div><b>${escapeHtml(humanStatus(app.update_status||"unmatched"))}</b><span>update status</span></div>
      </div>

      <h3>Install and licensing direction</h3>
      <table class="compareTable">
        <tbody>
          <tr><th>Publisher</th><td>${escapeHtml(app.publisher||"Unknown")}</td></tr>
          <tr><th>Catalog identity</th><td>${escapeHtml(app.winget_id||app.catalog_id||"Unmatched")}</td></tr>
          <tr><th>Provider state</th><td>${escapeHtml(humanStatus(app.provider_status||"not checked"))}</td></tr>
          <tr><th>Observation freshness</th><td>${escapeHtml(app.freshness||"unknown")}</td></tr>
          <tr><th>Inventory class</th><td>${escapeHtml(humanStatus(app.inventory_kind||"unclassified"))}</td></tr>
          <tr><th>Catalog action</th><td>${escapeHtml(humanStatus(app.catalog_action||"review"))}</td></tr>
        </tbody>
      </table>

      <p>Executable uninstall commands and full install paths are intentionally excluded from this dashboard evidence.</p>
    </section>
  `;
}
function renderSoftware(){
  const rows = softwareInventory
    .map(a=>({...a, category: softwareCategory(a)}))
    .filter(a=> softwareKindFilter==="all" || (softwareKindFilter==="managed" && !!a.catalog_id) || (softwareKindFilter==="applications" && a.inventory_kind==="application_candidate") || (softwareKindFilter==="components" && !a.catalog_id && a.inventory_kind!=="application_candidate"))
    .filter(a=> softwareFilter==="all" || a.category===softwareFilter)
    .filter(a=> {
      const q=softwareSearch.toLowerCase();
      return !q || ((a.name||"")+" "+(a.publisher||"")+" "+(a.version||"")).toLowerCase().includes(q);
    })
    .slice(0,120);

  const cats=["all","Creative","Game Dev","Security","Development","AI / GPU","Drivers / Hardware","Runtime / SDK","Launcher / Game","Everyday Apps","Other"];
  const managedCount=softwareInventory.filter(a=>a.catalog_id).length;
  const appCandidateCount=Number(softwareIntelligence?.summary?.unmatched_unique_applications ?? softwareIntelligence?.summary?.unmatched_application_candidates ?? softwareIntelligence?.summary?.unmatched)||0;
  const componentCount=Number(softwareIntelligence?.summary?.unmatched_components)||0;

  return `
    <section class="hero">
      <div>
        <h1>Software intelligence</h1>
        <p>Detected local software, grouped by what it enables. Use this to find missing tools, licensed apps, runtimes, SDKs, launchers, and workstation dependencies.</p>
      </div>
    </section>

    <section class="panel">
      <h2>Inventory controls</h2>
      <button id="refreshSoftware" class="primaryAction">Scan this computer and check versions</button>
      <p role="status">${escapeHtml(operationMessage)}</p>
      ${softwareIntelligence?`<div class="summaryStrip"><div><b>${softwareIntelligence.summary.detected}</b><span>detected</span></div><div><b>${softwareIntelligence.summary.catalog_matched}</b><span>catalog matched</span></div><div><b>${softwareIntelligence.summary.unmatched_unique_applications ?? softwareIntelligence.summary.unmatched}</b><span>app candidates</span></div><div><b>${softwareIntelligence.summary.unmatched_components||0}</b><span>components</span></div><div><b>${softwareIntelligence.summary.updates_available}</b><span>updates</span></div><div><b>${softwareIntelligence.summary.unknown}</b><span>unknown</span></div></div>`:""}
      <input id="softwareSearch" placeholder="Search software, publisher, version..." value="${escapeHtml(softwareSearch)}" />
      <div class="detectedBlock inventoryKindFilters" aria-label="Inventory type">
        ${[["all",`All ${softwareInventory.length}`],["managed",`Managed ${managedCount}`],["applications",`Apps to review ${appCandidateCount}`],["components",`Components ${componentCount}`]].map(([id,label])=>`<button class="filterBtn ${softwareKindFilter===id?"active":""}" data-inventory-kind="${id}">${escapeHtml(label)}</button>`).join("")}
      </div>
      <div class="detectedBlock">
        ${cats.map(c=>`<button class="filterBtn ${softwareFilter===c?"active":""}" data-software-filter="${c}">${c}</button>`).join("")}
      </div>
      <p>Showing ${rows.length} of ${softwareInventory.length} detected entries.</p>
    </section>

    ${renderSoftwareDetail()}

    <section class="panel">
      <h2>Detected software</h2>
      ${table(["Software","Installed","Available","Update status","Class","Identity"], rows.map(a=>[
        rawHtml(`<button class="linkBtn" data-software-index="${softwareInventory.indexOf(a)}">${escapeHtml(a.name || "")}</button>`),
        a.version || "",
        a.available_version || "",
        humanStatus(a.update_status||"unmatched"),
        humanStatus(a.inventory_kind||"unclassified"),
        a.winget_id || a.catalog_id || "Unmatched"
      ]))}
    </section>

    <section class="panel">
      <h2>What the status means</h2>
      <p>“Current” requires both a known installed version and a successful approved-provider check. Offline, stale, malformed, or unavailable provider checks stay unknown and never become a false green status.</p>
    </section>
  `;
}

function renderStacks(){
  const caps = graph && Array.isArray(graph.capabilities) ? graph.capabilities : [];
  return `
    <section class="hero"><div><h1>Workstation stacks</h1><p>Stacks compare what a role needs against this machine.</p></div></section>
    <section class="panel">
      <table class="compareTable">
        <thead>
          <tr>
            <th>Stack</th>
            <th>Readiness</th>
            <th>Detected examples</th>
            <th>Next actions</th>
            <th>Controls</th>
          </tr>
        </thead>
        <tbody>
          ${caps.map(c=>`
            <tr>
              <td><b>${c.name}</b></td>
              <td>${c.status} · ${c.score}%</td>
              <td>${Array.isArray(c.detected) ? c.detected.slice(0,4).join(", ") : ""}</td>
              <td>${Array.isArray(c.actions) ? c.actions.slice(0,2).join(", ") : ""}</td>
              <td>
                <div class="rowControls">
                  <button class="controlBtn primary" data-review="${c.id}">Review</button>
                  <button class="controlBtn" data-stack-plan="${c.id}">Plan</button>
                </div>
              </td>
            </tr>
          `).join("")}
        </tbody>
      </table>
    </section>
  `;
}

function renderLicensing(){
  const items=setupData?.catalog?.items||[];
  const rules={
    free:["Automatic","Free distribution; exact package identity still required."],
    free_open_source:["Automatic","Open-source license recorded; exact package identity still required."],
    account_required:["Review","Installation may be automated, but sign-in or account terms remain with the user."],
    license_review_required:["Manual","License acceptance and usage terms must be reviewed before installation."],
    source_available_license_review:["Manual","Source is available, but its license requires explicit review."]
  };
  const groups=[...new Set(items.map(x=>x.license||"unknown"))].sort().map(license=>{
    const matching=items.filter(x=>(x.license||"unknown")===license);
    const rule=rules[license]||["Manual","No approved automatic-install policy is defined."];
    return [license.replaceAll("_"," "),matching.length,rule[0],rule[1]];
  });
  const automatic=items.filter(x=>["free","free_open_source"].includes(x.license)).length;
  return `
    <section class="hero"><div><h1>Licensing</h1><p>Every catalog entry carries an install policy so account, commercial, and source-license terms are visible before approval.</p></div></section>
    <section class="summaryStrip"><div><b>${items.length}</b><span>reviewed entries</span></div><div><b>${automatic}</b><span>automatic eligible</span></div><div><b>${items.length-automatic}</b><span>review required</span></div></section>
    <section class="panel">
      ${table(["Catalog license class","Tools","Install mode","Rule"],groups)}
      <p>Drivers remain recommend-only and require separate administrator approval, an official vendor source, and recovery planning.</p>
    </section>
  `;
}

function renderExport(){
  return `
    <section class="hero"><div><h1>Rebuild / Export</h1><p>Export this workstation blueprint and compare it against a new machine.</p></div></section>
    <section class="panel">
      <h2>Export this machine</h2>
      <p>Create a verified rebuild blueprint from every currently installed application that matches an approved AssembleLink catalog identity. Unmatched applications are counted but never converted into guessed installers.</p>
      <button id="exportMachineBlueprint" class="primaryAction">Export this machine blueprint</button>
      <button data-setup-jump="restore">Restore or compare a blueprint</button>
      <p id="profileOperation" role="status">${escapeHtml(operationMessage)}</p>
      <p>The blueprint contains catalog IDs and setup policy—not personal files, secrets, arbitrary commands, or installer URLs. A matching SHA-256 sidecar and receipt are created with it.</p>
    </section>
  `;
}

function renderReceipts(){
  const summary=receiptIndex?.summary||{total:0,valid:0,unverified:0,failed:0};
  const rows=(receiptIndex?.items||[]).map(item=>[
    item.name,
    item.schema,
    humanStatus(item.integrity),
    `${Math.max(0,Number(item.bytes)||0).toLocaleString()} bytes`,
    item.modified_unix?new Date(item.modified_unix*1000).toLocaleString():"Unknown",
    item.sha256?`${item.sha256.slice(0,16)}…`:"—"
  ]);
  return `
    <section class="hero"><div><h1>Receipts</h1><p>Local, append-only evidence for setup runs and other machine operations. AssembleLink verifies adjacent SHA-256 files before showing evidence as valid.</p></div></section>
    <section class="summaryStrip"><div><b>${summary.total}</b><span>receipts</span></div><div><b>${summary.valid}</b><span>integrity valid</span></div><div><b>${summary.unverified}</b><span>legacy / unverified</span></div><div><b>${summary.failed}</b><span>integrity failures</span></div></section>
    <section class="panel">
      <button id="refreshReceipts">Refresh evidence</button>
      <p role="status">${escapeHtml(receiptLoadError)}</p>
      ${rows.length?table(["Receipt","Schema","Integrity","Size","Created","SHA-256"],rows):"<p>No local receipts have been created yet. Completing a setup or export operation will create evidence here.</p>"}
      <p><b>Unverified</b> means an older receipt has no integrity sidecar. <b>Mismatch</b>, <b>malformed sidecar</b>, and <b>too large</b> are failures and must not be trusted.</p>
    </section>
  `;
}
function renderDrivers(){
  if(!driverProfile){
    return `
      <section class="hero"><div><h1>Drivers and vendor setup</h1><p>No current driver profile is available for this machine.</p></div></section>
      <section class="panel"><h2>Safe state</h2><p>Driver execution is disabled until hardware is detected and an official vendor source is verified. AssembleLink will not guess a driver or silently install one.</p><button id="refreshDrivers">Scan hardware</button><p role="status">${escapeHtml(driverLoadError)}</p></section>
    `;
  }

  const p = driverProfile.platform || {};
  const recs = Array.isArray(driverProfile.recommendations) ? driverProfile.recommendations : [];
  const graphics=Array.isArray(driverProfile.graphics)?driverProfile.graphics:[];
  const network=Array.isArray(driverProfile.network)?driverProfile.network:[];
  const audio=Array.isArray(driverProfile.audio)?driverProfile.audio:[];
  const errors=Array.isArray(driverProfile.collection_errors)?driverProfile.collection_errors:[];

  return `
    <section class="hero">
      <div>
        <h1>Drivers and vendor setup</h1>
        <p>Live local inventory of chipset, GPU, network, audio, BIOS, and official vendor support paths. Detection does not claim that a newer driver exists.</p>
      </div>
    </section>

    <section class="summaryStrip"><div><b>${graphics.length}</b><span>graphics devices</span></div><div><b>${network.length}</b><span>physical network devices</span></div><div><b>${audio.length}</b><span>audio devices</span></div><div><b>${recs.length}</b><span>support paths</span></div></section>

    <section class="panel">
      <h2>Platform</h2>
      ${table(["Component","Detected identity"],[["Computer",`${p.machine_manufacturer||""} ${p.machine_model||""}`.trim()],["Motherboard",`${p.motherboard_vendor||""} ${p.motherboard_product||""}`.trim()],["CPU",p.cpu||"Unknown"],["BIOS",`${p.bios_vendor||""} ${p.bios_version||""}`.trim()]])}
      <button id="refreshDrivers">Rescan hardware</button><p role="status">${escapeHtml(driverLoadError)}</p>
    </section>

    <section class="panel">
      <h2>Detected driver inventory</h2>
      <h3>Graphics</h3>${table(["Device","Vendor","Installed driver","Device status"],graphics.map(x=>[x.name,x.manufacturer||"—",x.driver_version||"Unknown",x.device_status||"Unknown"]))}
      <h3>Network</h3>${table(["Device","Vendor","Installed driver","Device status"],network.map(x=>[x.name,x.manufacturer||"—",x.driver_version||"Unknown",x.device_status||"Unknown"]))}
      <h3>Audio</h3>${table(["Device","Vendor","Installed driver","Device status"],audio.map(x=>[x.name,x.manufacturer||"—",x.driver_version||"Unknown",x.device_status||"Unknown"]))}
    </section>

    <section class="panel">
      <h2>Official support paths</h2>
      ${table(["Component","Why it is shown","Official source","Safety"], recs.map(r=>[
        r.name || r.id,
        r.reason || "",
        `${r.official_vendor||"Vendor"} (${r.official_domain||"official source"}) — ${r.official_direction||""}`,
        `${r.install_mode||"recommend_only"}; update ${r.update_status||"not checked"}`
      ]))}
    </section>

    <section class="panel">
      <h2>Safety policy</h2>
      <p>Drivers and BIOS remain recommendation-only. Installed versions are inventory evidence, not proof that an update exists. Any future installation requires administrator approval, an official vendor source, a restore point, and post-install device verification.</p>
      <p>${errors.length?`${errors.length} hardware data sources were unavailable, so this scan is partial.`:"Hardware collection completed without reported source failures."}</p>
    </section>
  `;
}
function renderGenericPage(title, text){
  return `
    <section class="hero">
      <div>
        <h1>${escapeHtml(title)}</h1>
        <p>${escapeHtml(text)}</p>
      </div>
    </section>
    <section class="panel">
      <p>No current local evidence is available for this view.</p>
    </section>
  `;
}

function renderPanel(){
  if(selectedCapabilityId){ return renderCapabilityDetail(); }

  if(activeTab === "home"){ return renderHome(); }
  if(activeTab === "stacks"){ return renderStacks(); }
  if(activeTab === "software"){ return renderSoftware(); }
  if(activeTab === "licensing"){ return renderLicensing(); }
  if(activeTab === "drivers"){ return renderDrivers(); }
  if(activeTab === "export"){ return renderExport(); }
  if(activeTab === "receipts"){ return renderReceipts(); }

  return renderHome();
}
function render(){
  const el = document.getElementById("app");
  if(!el){
    document.body.innerHTML = "<pre>APP_ROOT_MISSING</pre>";
    return;
  }

  el.innerHTML = `
    <main class="shell">
      <aside class="sidebar">
        <div class="brandRow"><span class="brandPanda">${pandaSvg("idle","AssembleLink")}</span><div><div class="brand">AssembleLink</div><div class="subtitle">Set up, inspect, and rebuild this machine</div></div></div>
        <nav class="primaryNav">
          <small>GET STARTED</small>
          ${nav("home","Overview")}
          ${setupNav("setup","Job toolkits",String(setupData?.toolkits?.toolkits?.length||""))}
          ${setupNav("browse","Software & CLI catalog",String(setupData?.catalog?.items?.length||""))}
          ${setupNav("update","Updates",softwareIntelligence?.summary?.updates_available?String(softwareIntelligence.summary.updates_available):"")}
          ${setupNav("repository","Analyze a project","")}
          <small>THIS MACHINE</small>
          ${nav("software","Installed software")}
          ${nav("stacks","Job readiness")}
          ${nav("drivers","Drivers")}
          <small>PORTABILITY & TRUST</small>
          ${nav("export","Blueprints / Rebuild")}
          ${nav("receipts","Receipts")}
        </nav>
        <div class="sidebarStatus"><span class="statusDot ${softwareIntelligence?"ready":softwareScanError?"warn":"working"}"></span><div><b>${softwareIntelligence?`${softwareIntelligence.summary.detected} detected`:softwareScanError?"Scan needs attention":"Scanning machine"}</b><small>${softwareIntelligence?`${softwareIntelligence.summary.catalog_matched} catalog matched · ${softwareIntelligence.summary.unknown} unknown`:softwareScanError?"Open the dashboard to retry":"Local inventory is loading"}</small></div></div>
      </aside>
      <section class="workspace">
        ${renderPanel()}
        <footer class="techFooter">
          <button id="toggleTechnical" class="ghostBtn">${showTechnical ? "Hide" : "Show"} technical details</button>
          ${showTechnical ? `<pre>${escapeHtml(JSON.stringify(graph,null,2))}</pre>` : ""}
        </footer>
      </section>
    </main>
  `;

  const viewKey=`${activeTab}|${sidebarContext}|${setupMode}|${selectedCapabilityId||""}`;
  if(viewKey!==lastViewKey){el.querySelector(".workspace")?.classList.add("viewEnter");}
  lastViewKey=viewKey;
  runCountUps();
  document.querySelectorAll("[data-tab]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      activeTab = btn.getAttribute("data-tab");
      sidebarContext=activeTab==="home"?"overview":"";
      selectedCapabilityId = null;
      render();
    });
  });
  document.querySelectorAll("[data-setup-jump]").forEach(btn=>btn.addEventListener("click",()=>{activeTab="home";selectedCapabilityId=null;setupMode=btn.getAttribute("data-setup-jump")||"setup";sidebarContext=setupMode;setupPlan=null;setupResult=null;setupProgress=null;render();}));

  document.querySelectorAll("[data-home-action]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      activeHomeAction = btn.getAttribute("data-home-action");
      render();
    });
  });

  document.querySelectorAll("[data-setup-mode]").forEach(btn=>btn.addEventListener("click",()=>{
    setupMode=btn.getAttribute("data-setup-mode");sidebarContext=setupMode; setupPlan=null; setupResult=null; setupProgress=null; render();
  }));
  const updateSelectionSummary=()=>{
    const count=selectedToolkitIds.size+selectedSoftwareIds.size;
    const summary=document.querySelector(".selectionSummary span");
    const review=document.getElementById("reviewSetup");
    const hint=document.querySelector(".selectionHint");
    if(summary){summary.textContent=`${count} ${count===1?"selection":"selections"} ready to review`;}
    if(review){review.disabled=count===0;}
    if(hint){hint.hidden=count>0;}
  };
  document.querySelectorAll("[data-toolkit-id]").forEach(input=>input.addEventListener("change",()=>{
    const id=input.getAttribute("data-toolkit-id"); input.checked?selectedToolkitIds.add(id):selectedToolkitIds.delete(id); setupPlan=null; render();
  }));
  document.querySelectorAll("[data-software-id]").forEach(input=>input.addEventListener("change",()=>{
    const id=input.getAttribute("data-software-id"); input.checked?selectedSoftwareIds.add(id):selectedSoftwareIds.delete(id); setupPlan=null; render();
  }));
  document.querySelectorAll("[data-machine-type]").forEach(input=>input.addEventListener("change",()=>{
    machineType=input.getAttribute("data-machine-type")==="laptop"?"laptop":"desktop";
    if(machineType==="laptop"&&maxAllocationGb===100){maxAllocationGb=50;}
    if(machineType==="desktop"&&maxAllocationGb===50){maxAllocationGb=100;}
    setupPlan=null;render();
  }));
  const maxAllocationInput=document.getElementById("maxAllocationGb");
  if(maxAllocationInput){maxAllocationInput.addEventListener("change",()=>{
    const next=Number(maxAllocationInput.value);
    maxAllocationGb=Number.isInteger(next)?Math.max(5,Math.min(2048,next)):maxAllocationGb;
    setupPlan=null;render();
  });}
  const catalogSearchInput=document.getElementById("catalogSearch");
  if(catalogSearchInput){catalogSearchInput.addEventListener("input",()=>{catalogSearch=catalogSearchInput.value;const pos=catalogSearchInput.selectionStart;render();const next=document.getElementById("catalogSearch");next?.focus();next?.setSelectionRange(pos,pos);});}
  const catalogCategorySelect=document.getElementById("catalogCategorySelect");
  if(catalogCategorySelect){catalogCategorySelect.addEventListener("change",()=>{catalogCategory=catalogCategorySelect.value||"all";render();});}
  const editSelection=document.getElementById("editSelection");
  if(editSelection){editSelection.addEventListener("click",()=>{setupPlan=null;setupResult=null;setupProgress=null;operationMessage="";render();});}
  const retryScan=document.getElementById("retryScan");
  if(retryScan){retryScan.addEventListener("click",async()=>{
    softwareScanError="";softwareIntelligence=null;render();
    try{await refreshSoftwareIntelligence(true);graph=buildLiveGraph();}catch(err){softwareScanError=String(err);}
    render();
  });}
  const reviewSetup=document.getElementById("reviewSetup");
  if(reviewSetup){ reviewSetup.addEventListener("click",async()=>{
    operationMessage="Building a deterministic setup plan…"; setupResult=null; setupProgress=null; render();
    try{
      setupPlan=JSON.parse(await invokeDesktop("build_setup_plan",{toolkitIds:[...selectedToolkitIds],softwareIds:[...selectedSoftwareIds],machineType,maxAllocationGib:maxAllocationGb}));
      operationMessage="Review every tool below. Nothing has been installed.";
    }catch(err){ operationMessage=String(err); setupPlan=null; }
    render();
    document.querySelector(".planPanel")?.scrollIntoView({behavior:window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches?"auto":"smooth",block:"start"});
  }); }
  const scanUpdates=document.getElementById("scanUpdates");
  if(scanUpdates){scanUpdates.addEventListener("click",async()=>{
    operationMessage="Scanning installed software and checking approved providers…";setupPlan=null;render();
    try{await refreshSoftwareIntelligence(true);setupPlan=JSON.parse(await invokeDesktop("build_update_plan"));operationMessage=setupPlan.package_manager_available?(setupPlan.item_count?`${setupPlan.item_count} approved updates found.`:"No approved updates were reported. Check unknown statuses before assuming everything is current."):"Winget is unavailable. Install or repair Windows App Installer to check Winget-managed updates.";}
    catch(err){operationMessage=String(err);}render();
  });}
  const repositoryPathInput=document.getElementById("repositoryPath");
  if(repositoryPathInput){repositoryPathInput.addEventListener("input",()=>{repositoryPath=repositoryPathInput.value;});}
  const analyzeRepository=document.getElementById("analyzeRepository");
  if(analyzeRepository){analyzeRepository.addEventListener("click",async()=>{
    repositoryPath=repositoryPathInput?.value.trim()||"";repositoryAnalysis=null;operationMessage="Reading supported project manifests…";render();
    try{repositoryAnalysis=sanitizeStateValue(JSON.parse(await invokeDesktop("analyze_repository",{repositoryPath})));operationMessage="Project requirements mapped to the approved catalog. Nothing was installed.";}
    catch(err){operationMessage=String(err);}render();
  });}
  const useRepositoryRecommendations=document.getElementById("useRepositoryRecommendations");
  if(useRepositoryRecommendations){useRepositoryRecommendations.addEventListener("click",()=>{
    selectedToolkitIds.clear();selectedSoftwareIds=new Set(repositoryAnalysis?.recommended_software_ids||[]);setupMode="browse";sidebarContext="browse";setupPlan=null;operationMessage="Repository recommendations selected. Choose a machine profile, review storage, then build the plan.";render();
  });}
  const refreshSoftware=document.getElementById("refreshSoftware");
  if(refreshSoftware){refreshSoftware.addEventListener("click",async()=>{
    operationMessage="Scanning installed software and checking approved providers…";render();
    try{await refreshSoftwareIntelligence(true);await loadWorkstationAssurance();operationMessage=`Scan complete: ${softwareIntelligence.summary.updates_available} updates, ${softwareIntelligence.summary.unknown} unknown.`;}
    catch(err){operationMessage=String(err);}render();
  });}
  const refreshAssurance=document.getElementById("refreshAssurance");
  if(refreshAssurance){refreshAssurance.addEventListener("click",async()=>{
    operationMessage="Rebuilding trusted workstation evidence…";render();
    try{await refreshSystemProfile();await refreshDriverProfile();await refreshSoftwareIntelligence(true);graph=buildLiveGraph();await loadWorkstationAssurance();await loadReceipts();operationMessage="Workstation proof refreshed and sealed.";}
    catch(err){workstationAssurance=null;workstationAssuranceError=String(err);operationMessage="Workstation proof could not be completed.";}
    render();
  });}
  const exportBlueprint=document.getElementById("exportBlueprint");
  if(exportBlueprint){exportBlueprint.addEventListener("click",async()=>{
    try{operationMessage=`Blueprint exported to ${await invokeDesktop("export_blueprint")}. Keep the matching .sha256 file with it.`;}
    catch(err){operationMessage=String(err);} render();
  });}
  const importBlueprint=document.getElementById("importBlueprint");
  if(importBlueprint){importBlueprint.addEventListener("click",async()=>{
    const blueprintPath=document.getElementById("blueprintPath")?.value.trim()||"";
    operationMessage="Validating blueprint integrity and catalog identities…";render();
    try{setupPlan=JSON.parse(await invokeDesktop("import_blueprint",{blueprintPath,machineType,maxAllocationGib:maxAllocationGb}));operationMessage="Blueprint verified against this machine profile and allocation limit. Review the resolved setup plan below.";}
    catch(err){setupPlan=null;operationMessage=String(err);}render();
  });}
  const approveSetup=document.getElementById("approveSetup");
  if(approveSetup){ approveSetup.addEventListener("click",async()=>{
    if(setupRunning){return;}
    const resuming=setupRecovery?.available&&setupRecovery.plan?.plan_id===setupPlan?.plan_id;
    const automatic=(setupPlan?.items||[]).filter(x=>x.mode==="winget");
    const manual=(setupPlan?.items||[]).filter(x=>x.mode==="manual_review");
    const approvalLead=resuming?"Resume this exact interrupted setup plan? Completed automatic identities will be checked again before they are skipped.":"Approve this exact setup plan?";
    const allocationSummary=setupPlan?.allocation?`\n\nMachine: ${setupPlan.machine_profile.machine_type}\nPlanned storage: ${formatAllocation(setupPlan.allocation.estimated_installed_mib)} of ${formatAllocation(setupPlan.allocation.max_allocation_mib)}`:"";
    const approved=window.confirm(`${approvalLead}${allocationSummary}\n\nAutomatic (${automatic.length}):\n• ${automatic.map(x=>x.name).join("\n• ")}\n\nManual follow-up (${manual.length}):\n• ${manual.map(x=>x.name).join("\n• ")}\n\nA durable receipt and integrity hash will be created.`);
    if(!approved){ operationMessage="Setup cancelled. Nothing was installed."; render(); return; }
    const planId=setupPlan.plan_id;
    setupRunning=true;
    if(!resuming){setupProgress={schema:"assemblelink.setup_execution.progress.v1",plan_id:planId,status:"running",total:setupPlan.item_count,completed:0,results:[]};}
    operationMessage=resuming?"Resuming this computer setup. Previous outcomes are being revalidated…":"Setting up this computer. Progress is saved after every tool…"; render(); window.scrollTo({top:0});
    const poll=async()=>{await loadSetupProgress(planId);render();};
    const progressTimer=window.setInterval(poll,750);
    void poll();
    try{
      const response=resuming
        ?await invokeDesktop("resume_setup",{planId,approved:true})
        :await invokeDesktop("execute_setup",{planId,approved:true});
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
      try{
        await refreshSoftwareIntelligence(true);
        graph=buildLiveGraph();
      }catch(err){
        refreshIssues.push(`inventory refresh failed: ${String(err)}`);
      }
      await loadReceipts();
      await loadSetupRecovery();
      if(receiptLoadError){refreshIssues.push(`receipt refresh failed: ${receiptLoadError}`);}
      if(setupResult){
        operationMessage=refreshIssues.length
          ?`Setup completed, but ${refreshIssues.join("; ")}.`
          :"Setup completed. Installed versions, readiness, and receipts are refreshed.";
      }else if(refreshIssues.length){
        operationMessage+=` ${refreshIssues.join("; ")}.`;
      }
    }
    render();
  }); }

  const reviewRecovery=document.getElementById("reviewRecovery");
  if(reviewRecovery){reviewRecovery.addEventListener("click",()=>{
    setupPlan=setupRecovery.plan;
    setupProgress=setupRecovery.progress;
    setupMode=setupPlan.plan_type==="update"?"update":"setup";
    activeTab="home";
    sidebarContext=setupMode;
    operationMessage="Review the interrupted plan, then explicitly approve the remaining work.";
    render();
  });}

  const exportMachineBlueprint=document.getElementById("exportMachineBlueprint");
  if(exportMachineBlueprint){exportMachineBlueprint.addEventListener("click",async()=>{
    operationMessage="Refreshing installed software and building a verified machine blueprint…";render();
    try{
      const result=sanitizeStateValue(JSON.parse(await invokeDesktop("export_machine_blueprint",{machineType,maxAllocationGib:maxAllocationGb})));
      operationMessage=`Blueprint exported to ${result.path}. ${result.catalog_matched_installed} installed catalog identities resolved to ${result.resolved_plan_items} plan items; ${result.unmatched_installed} unmatched installed entries were not guessed.`;
      await loadReceipts();
    }catch(err){operationMessage=String(err);}
    render();
  });}

  const refreshReceipts=document.getElementById("refreshReceipts");
  if(refreshReceipts){refreshReceipts.addEventListener("click",async()=>{receiptLoadError="Refreshing local evidence…";render();await loadReceipts();render();});}
  const refreshDrivers=document.getElementById("refreshDrivers");
  if(refreshDrivers){refreshDrivers.addEventListener("click",async()=>{driverLoadError="Scanning local hardware and installed driver versions…";render();await refreshDriverProfile();await loadReceipts();render();});}
  const retryRuntime=document.getElementById("retryRuntime");
  if(retryRuntime){retryRuntime.addEventListener("click",async()=>{setupLoadError="Retrying trusted desktop runtime…";render();await loadSetupData();if(setupData){await loadSetupRecovery();await refreshSystemProfile();try{await refreshSoftwareIntelligence(false)}catch(err){operationMessage=String(err)};await refreshDriverProfile();await loadReceipts();graph=buildLiveGraph()}render();});}

  document.querySelectorAll("[data-tab-jump]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      activeTab = btn.getAttribute("data-tab-jump");
      selectedCapabilityId = null;
      render();
    });
  });

  document.querySelectorAll("[data-review]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      selectedCapabilityId = btn.getAttribute("data-review");
      render();
    });
  });

  const back = document.getElementById("backHome");
  if(back){
    back.addEventListener("click",()=>{
      selectedCapabilityId = null;
      render();
    });
  }

  document.querySelectorAll("[data-stack-plan]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      const id=btn.getAttribute("data-stack-plan");
      const toolkitByCapability={"software-development":"developer-essentials","local-ai":"local-ai","infrastructure":"cloud-infrastructure","game-development":"game-development","cybersecurity":"cybersecurity","content-creation":"content-creation"};
      const toolkitId=toolkitByCapability[id];if(toolkitId){selectedToolkitIds.add(toolkitId);}
      selectedCapabilityId=null;activeTab="home";setupMode="setup";sidebarContext="setup";setupPlan=null;setupResult=null;
      operationMessage=toolkitId?"Toolkit selected. Review it and build the deterministic setup plan.":"Choose a reviewed toolkit below.";render();
    });
  });

  document.querySelectorAll("[data-quick-toolkit]").forEach(btn=>btn.addEventListener("click",()=>{
    const toolkitId=btn.getAttribute("data-quick-toolkit");
    if(toolkitId){selectedToolkitIds.add(toolkitId);}
    activeTab="home";setupMode="setup";sidebarContext="setup";setupPlan=null;setupResult=null;setupProgress=null;
    operationMessage="Toolkit selected. Review the included tools, then build the setup plan.";
    render();
  }));

  document.querySelectorAll("[data-install-recommended]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      const id=btn.getAttribute("data-install-recommended");
      const toolkitByCapability={"software-development":"developer-essentials","local-ai":"local-ai","infrastructure":"cloud-infrastructure","game-development":"game-development","cybersecurity":"cybersecurity","content-creation":"content-creation"};
      const toolkitId=toolkitByCapability[id];if(toolkitId){selectedToolkitIds.add(toolkitId);}
      selectedCapabilityId=null;activeTab="home";setupMode="setup";sidebarContext="setup";setupPlan=null;setupResult=null;
      operationMessage=toolkitId?"Toolkit selected. Review it and build the deterministic setup plan.":"Choose a reviewed toolkit below.";render();
    });
  });

  document.querySelectorAll("[data-browse-approved]").forEach(btn=>btn.addEventListener("click",()=>{
    selectedCapabilityId=null;activeTab="home";setupMode="browse";sidebarContext="browse";setupPlan=null;setupResult=null;render();
  }));

  document.querySelectorAll("[data-software-index]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      selectedSoftwareIndex=Number(btn.getAttribute("data-software-index"));
      render();
    });
  });

  const closeSoftware=document.getElementById("closeSoftwareDetail");
  if(closeSoftware){
    closeSoftware.addEventListener("click",()=>{
      selectedSoftwareIndex=null;
      render();
    });
  }

  const search=document.getElementById("softwareSearch");
  if(search){
    search.addEventListener("input",()=>{
      softwareSearch=search.value;
      render();
    });
  }

  document.querySelectorAll("[data-software-filter]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      softwareFilter=btn.getAttribute("data-software-filter");
      render();
    });
  });

  document.querySelectorAll("[data-inventory-kind]").forEach(btn=>{
    btn.addEventListener("click",()=>{
      softwareKindFilter=btn.getAttribute("data-inventory-kind");
      selectedSoftwareIndex=null;
      render();
    });
  });

  const t = document.getElementById("toggleTechnical");
  if(t){
    t.addEventListener("click",()=>{
      showTechnical = !showTechnical;
      render();
    });
  }
}

async function boot(){
  try{
    render();
    await loadSetupData();
    await loadSetupRecovery();
    graph=buildLiveGraph();render();
    await refreshSystemProfile();render();
    try{await refreshSoftwareIntelligence(false);graph=buildLiveGraph();render();}catch(err){softwareScanError=String(err);render();}
    await loadGraph();
    await refreshDriverProfile();
    await loadWorkstationAssurance();
    await loadReceipts();
    await loadCapabilityStatusIndex();
    await loadMissionConsole();
    render();
  }catch(err){
    errorText = String(err && err.stack ? err.stack : err);
    render();
  }
}

boot();
