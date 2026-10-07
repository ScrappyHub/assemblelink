import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../src/main.js", import.meta.url), "utf8");

test("all installs use the hardened plan approval flow", () => {
  assert.doesNotMatch(source, /invokeDesktop\("prepare_install"/);
  assert.doesNotMatch(source, /invokeDesktop\("execute_install"/);
  assert.match(source, /invokeDesktop\("build_setup_plan"/);
  assert.match(source, /window\.confirm/);
  assert.match(source, /invokeDesktop\("execute_setup"/);
});

test("machine rebuild export uses live catalog identities", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /id="exportMachineBlueprint"/);
  assert.match(source, /invokeDesktop\("export_machine_blueprint",\{machineType,maxAllocationGib:maxAllocationGb\}\)/);
  assert.match(source, /Unmatched applications are counted but never converted into guessed installers/);
  assert.doesNotMatch(source, /invokeDesktop\("export_profile"|invokeDesktop\("import_latest_profile"/);
  assert.match(rust, /fn export_machine_blueprint/);
  assert.match(rust, /installed_catalog_ids/);
  assert.doesNotMatch(rust, /fn export_profile|fn import_latest_profile/);
});

test("repository manifests map to approved setup recommendations", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source,/Analyze a project/);
  assert.match(source,/invokeDesktop\("analyze_repository",\{repositoryPath\}\)/);
  assert.match(source,/recommended_software_ids/);
  assert.match(rust,/fn analyze_repository/);
  assert.match(rust,/al_repository_requirements_v1\.ps1/);
});

test("browser preview cannot impersonate a successful install", () => {
  assert.match(source, /requires the installed AssembleLink desktop app/);
  assert.doesNotMatch(source, /role="status">\$\{operationMessage\}/);
});

test("new-machine setup is toolkit driven and approval bound", () => {
  assert.match(source, /Set up this computer/);
  assert.match(source, /invokeDesktop\("build_setup_plan"/);
  assert.match(source, /invokeDesktop\("execute_setup"/);
  assert.match(source, /const planId=setupPlan\.plan_id/);
  assert.match(source, /invokeDesktop\("execute_setup",\{planId,approved:true\}\)/);
  assert.match(source, /data-machine-type="desktop"/);
  assert.match(source, /data-machine-type="laptop"/);
  assert.match(source, /id="maxAllocationGb"/);
  assert.match(source, /maxAllocationGib:maxAllocationGb/);
  assert.match(source, /Maximum planned allocation/);
  assert.match(source, /Planning estimate only/);
});

test("update and verified blueprint flows are exposed", () => {
  assert.match(source, /update my tools/);
  assert.match(source, /Software updates/);
  assert.match(source, /invokeDesktop\("build_update_plan"/);
  assert.match(source, /invokeDesktop\("export_blueprint"/);
  assert.match(source, /invokeDesktop\("import_blueprint"/);
});

test("live software inventory and version intelligence are wired", () => {
  assert.match(source, /invokeDesktop\("refresh_software_intelligence"/);
  assert.match(source, /installed_version/);
  assert.match(source, /available_version/);
  assert.match(source, /provider_status/);
  assert.match(source, /never become a false green status/);
});

test("job families and software categories are navigable", () => {
  assert.match(source, /job_family/);
  assert.match(source, /renderToolkitGroups/);
  assert.match(source, /id="catalogCategorySelect"/);
  assert.match(source, /Approved software and CLI catalog/);
});

test("desktop boot fails soft when bundled state snapshots are unavailable", () => {
  assert.match(source, /async function loadOptionalState/);
  assert.match(source, /catch\(_error\)\{return null;\}/);
  assert.match(source, /const live=buildLiveGraph\(\)/);
  assert.doesNotMatch(source, /Could not load capability graph/);
});

test("desktop runtime failures are visible and retryable", () => {
  assert.match(source, /setupLoadError=String\(err\)/);
  assert.match(source, /id="retryRuntime"/);
  assert.match(source, /Retrying trusted desktop runtime/);
});

test("menu bar exposes File, Logs, Drivers and Help workflows", () => {
  assert.match(source, /role="menubar"/);
  for(const label of ["File","Logs","Drivers","Help"]){assert.match(source,new RegExp(`label:"${label}"`));}
  for(const label of ["Get started","Set up this computer","Job toolkits","Software & CLI catalog","Installed software","Job readiness","Analyze a project","Blueprints / Rebuild","Receipts","Workstation proof","Drivers & hardware","Software updates","How it works","Uninstall"]){assert.match(source,new RegExp(label.replace(/[&/.]/g,"\\$&")));}
  assert.match(source, /e\.key==="Escape"/);
  assert.doesNotMatch(source, /class="sidebar"/);
});

test("desktop runtime suppresses background PowerShell console windows", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(rust,/creation_flags\(0x08000000\)/);
  assert.match(rust,/RUNTIME_OPERATION_LOCK/);
  assert.match(rust,/locked_runtime/);
});

test("local snapshot strings are sanitized before legacy panels render", () => {
  assert.match(source, /function sanitizeStateValue/);
  assert.match(source, /return sanitizeStateValue\(JSON\.parse\(text\)\)/);
  assert.match(source, /escapeHtml\(JSON\.stringify\(graph,null,2\)\)/);
  assert.match(source, /value="\$\{escapeHtml\(invSearch\)\}"/);
});

test("receipt browser verifies and presents local evidence", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /invokeDesktop\("get_receipts"\)/);
  assert.match(source, /integrity failures/);
  assert.match(source, /id="refreshReceipts"/);
  assert.match(rust, /fn receipt_index/);
  assert.match(rust, /"mismatch"/);
  assert.doesNotMatch(source, /Receipt browser connects next/);
});

test("catalog licensing and absent drivers fail safe without milestone placeholders", () => {
  assert.match(source, /const items=setupData\?\.catalog\?\.items/);
  assert.match(source, /Driver execution is disabled/);
  assert.doesNotMatch(source, /will be connected/);
  assert.doesNotMatch(source, /planned for the next milestone/);
});

test("driver inventory is live, recommendation-only, and evidence backed", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /invokeDesktop\("refresh_driver_profile"\)/);
  assert.match(source, /Installed versions are inventory evidence, not proof that an update exists/);
  assert.match(source, /id="refreshDrivers"/);
  assert.match(rust, /al_driver_profile_v1\.ps1/);
  assert.match(rust, /refresh_driver_profile/);
});

test("overview hardware and storage metrics come from live desktop IPC", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /invokeDesktop\("refresh_system_profile"\)/);
  assert.doesNotMatch(source, /C: and S: need cleanup attention/);
  assert.match(rust, /al_system_profile_v1\.ps1/);
  assert.match(rust, /refresh_system_profile/);
});

test("setup execution exposes bounded live progress and refreshes machine truth", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /invokeDesktop\("get_setup_progress",\{planId\}\)/);
  assert.match(source, /window\.setInterval\(poll,750\)/);
  assert.match(source, /Keep AssembleLink open\. Progress is saved after every tool\./);
  assert.match(source, /await refreshSoftwareIntelligence\(true\)/);
  assert.match(source, /graph=buildLiveGraph\(\)/);
  assert.match(source, /await loadReceipts\(\)/);
  assert.match(rust, /MAX_SETUP_PROGRESS_BYTES/);
  assert.match(rust, /PROGRESS_PATH_ESCAPE_REJECTED/);
  assert.match(rust, /fn get_setup_progress/);
  const progressCommand=rust.match(/fn get_setup_progress\([\s\S]*?\n\}/)?.[0]||"";
  assert.doesNotMatch(progressCommand, /locked_runtime/);
  assert.match(progressCommand, /runtime_data_root/);
});

test("interrupted setup is discoverable and requires explicit resume approval", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /invokeDesktop\("get_setup_recovery"\)/);
  assert.match(source, /Interrupted setup found/);
  assert.match(source, /Completed automatic tools will be independently checked before they are skipped/);
  assert.match(source, /window\.confirm/);
  assert.match(source, /invokeDesktop\("resume_setup",\{planId,approved:true\}\)/);
  assert.match(rust, /fn read_setup_recovery/);
  assert.match(rust, /RECOVERY_PLAN_PATH_ESCAPE_REJECTED/);
  assert.match(rust, /fn resume_setup/);
  assert.match(rust, /"-Resume"/);
});

test("capability actions converge on approved setup without false legacy controls", () => {
  assert.match(source, /data-kit-start/);
  assert.match(source, /id="addToSetup"/);
  assert.doesNotMatch(source, /saveCustomSoftware|CLI save wiring comes next/);
  assert.doesNotMatch(source, /function renderInstallQueue|function renderInstallPlan/);
  assert.doesNotMatch(source, /\.\/state\/install_queue|\.\/state\/install_plan/);
});

test("home is a get-started splash and the inventory is the panda's room", () => {
  assert.match(source, /function renderHome/);
  assert.match(source, /id="getStarted"/);
  assert.match(source, /Welcome to AssembleLink/);
  assert.match(source, /Welcome back/);
  assert.match(source, /function renderInventory/);
  assert.match(source, /roomSvg/);
  assert.match(source, /data-panda-ask/);
  assert.match(source, /Apps to review/);
  assert.match(source, /Unknown version/);
  assert.match(source, /Inventory class/);
  assert.match(source, /Catalog action/);
  assert.match(source, /shortVersion/);
});

test("job toolkits and readiness have their own screens", () => {
  assert.match(source, /function renderToolkits/);
  assert.match(source, /function renderReadiness/);
  assert.match(source, /Complete this toolkit/);
  assert.match(source, /kitGrid/);
  assert.match(source, /readyGrid/);
});

test("workstation assurance is integrity checked, visible, and refreshable", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source,/invokeDesktop\("get_workstation_assurance"\)/);
  assert.match(source,/function renderProofPanel/);
  assert.match(source,/Unknown never means current/);
  assert.match(source,/id="refreshAssurance"/);
  assert.match(rust,/fn read_verified_state/);
  assert.match(rust,/ASSURANCE_FIXTURE_EVIDENCE_REJECTED/);
  assert.match(rust,/workstation_assurance_receipt\.v1/);
  assert.match(rust,/get_workstation_assurance/);
});

test("the panda guide leads setup, scanning, review, install, and error states", async () => {
  const panda = await readFile(new URL("../src/panda.js", import.meta.url), "utf8");
  const css = await readFile(new URL("../src/style.css", import.meta.url), "utf8");
  for (const pose of ["idle", "scan", "think", "happy", "sad", "carry"]) {
    assert.match(panda, new RegExp(`"${pose}"`));
    if (pose !== "idle") { assert.match(css, new RegExp(`\\.panda\\[data-pose="${pose}"\\]`)); }
  }
  assert.match(panda, /Bamboo|bamboo/);
  assert.match(panda, /role="img"/);
  assert.match(source, /import \{pandaSvg\} from "\.\/panda\.js"/);
  assert.match(source, /function pandaMood/);
  assert.match(source, /pose:"carry"/);
  assert.match(source, /id="retryScan"/);
  assert.match(source, /data-countup/);
  assert.match(source, /carryTrack/);
  assert.match(css, /prefers-reduced-motion: reduce/);
});

test("setup is a four-step click-through with Back and Next", () => {
  assert.match(source, /class="stepper"/);
  assert.match(source, /id="wizNext"/);
  assert.match(source, /id="wizBack"/);
  assert.match(source, /id="reviewSetup"/);
  assert.match(source, /id="approveSetup"/);
  assert.match(source, /class="card planPanel/);
  assert.doesNotMatch(source, /nav\("licensing"/);
});

test("uninstalling programs and AssembleLink is approval bound and silent", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source, /invokeDesktop\("uninstall_software",\{catalogId,approved:true\}\)/);
  assert.match(source, /invokeDesktop\("uninstall_assemblelink",\{approved:true\}\)/);
  assert.match(source, /window\.confirm\(`Uninstall \$\{entry\.name\}/);
  assert.match(source, /id="selfAck"/);
  assert.match(rust, /fn uninstall_software/);
  assert.match(rust, /UNINSTALL_REQUIRES_EXPLICIT_APPROVAL/);
  assert.match(rust, /UNINSTALL_TARGET_NOT_IN_CATALOG/);
  assert.match(rust, /"--silent"/);
  assert.match(rust, /"--exact"/);
  assert.match(rust, /fn uninstall_assemblelink/);
  assert.match(rust, /uninstall\.exe/);
  assert.match(rust, /\/S/);
  assert.match(rust, /uninstall_software,\s*uninstall_assemblelink/);
});

test("app icon set is wired for the window, taskbar and installer", async () => {
  const conf=JSON.parse(await readFile(new URL("../src-tauri/tauri.conf.json",import.meta.url),"utf8"));
  for(const icon of ["icons/icon.ico","icons/icon.png","icons/32x32.png","icons/128x128.png"]){assert.ok(conf.bundle.icon.includes(icon),icon);}
});

test("the panda dock is dismissible and remembered, and specs live on the dashboard", () => {
  assert.match(source, /function renderWelcome/);
  assert.doesNotMatch(source, /specSentence|Here is what I am working with/);
  assert.match(source, /class="pandaDock/);
  assert.doesNotMatch(source, /welcomeVeil/);
  assert.match(source, /writePref\("welcomeSeen",true\)/);
  assert.match(source, /let welcomeOpen = !readPrefs\(\)\.welcomeSeen/);
  assert.match(source, /id="welcomeSkip"/);
  assert.match(source, /class="specGrid"/);
});

test("the inventory room is a click-through visual-novel tour with the reading panda", async () => {
  const scenes = await readFile(new URL("../src/scenes.js", import.meta.url), "utf8");
  assert.match(source, /function invSteps/);
  assert.match(source, /id="invNext"/);
  assert.match(source, /See results below/);
  assert.match(source, /writePref\("inventoryTourSeen",true\)/);
  assert.match(scenes, /export function readerSvg/);
  assert.match(scenes, /class="glasses"/);
  assert.match(scenes, /class="chair"/);
  assert.match(scenes, /class="sprig"/);
});

test("the pages the user called out are visible tabs as well as menu items", () => {
  assert.match(source, /class="tabStrip"/);
  for(const label of ["Overview","Set up this computer","Job toolkits","Software & CLI catalog","Installed software","Job readiness"]){assert.match(source,new RegExp(`\\["[a-z]+","${label.replace(/[&]/g,"\\$&")}"\\]`));}
});

test("install history is read-only, integrity-checked and linked from Logs", async () => {
  const rust = await readFile(new URL("../src-tauri/src/main.rs", import.meta.url), "utf8");
  assert.match(rust, /fn get_install_history/);
  assert.match(rust, /get_install_history\s*\]/);
  assert.match(rust, /fn is_execution_record_name/);
  assert.match(rust, /MAX_HISTORY_FILE_BYTES/);
  assert.match(source, /invokeDesktop\("get_install_history"\)/);
  assert.match(source, /\["go","history","Install history"\]/);
  assert.match(source, /function renderHistory/);
  assert.match(source, /Mismatch — do not trust/);
});

test("version availability is visible in inventory, catalog and updates", () => {
  assert.match(source, /class="invHead"/);
  assert.match(source, /invAvail/);
  assert.match(source, /versionSummary\(softwareInventory\)/);
  assert.match(source, /Installed by AssembleLink/);
});

test("self-uninstall rejects cmd metacharacters and both uninstall commands require approval", async () => {
  const rust = await readFile(new URL("../src-tauri/src/main.rs", import.meta.url), "utf8");
  assert.match(rust, /fn safe_cmd_path/);
  assert.match(rust, /UNINSTALLER_PATH_REJECTED/);
  assert.match(source, /invokeDesktop\("uninstall_software",\{catalogId,approved:true\}\)/);
  assert.match(source, /invokeDesktop\("uninstall_assemblelink",\{approved:true\}\)/);
});

test("UI source has no dynamic code execution, inline handlers, or outside network calls", async () => {
  const conf = JSON.parse(await readFile(new URL("../src-tauri/tauri.conf.json", import.meta.url), "utf8"));
  const csp = JSON.stringify(conf?.app?.security?.csp ?? "");
  for (const file of ["main.js", "lib.js", "scenes.js", "panda.js"]) {
    const text = await readFile(new URL(`../src/${file}`, import.meta.url), "utf8");
    assert.doesNotMatch(text, /\beval\s*\(|new Function\s*\(|document\.write\s*\(/, file);
    assert.doesNotMatch(text, /\son[a-z]+\s*=\s*["']/i, `${file} inline handler`);
    assert.doesNotMatch(text, /fetch\(\s*["']https?:/i, `${file} external fetch`);
    assert.doesNotMatch(text, /XMLHttpRequest|WebSocket|sendBeacon/, file);
  }
  assert.doesNotMatch(csp, /unsafe-eval/);
});

test("self-uninstall shows a waving, head-spinning goodbye overlay", async () => {
  const css = await readFile(new URL("../src/style.css", import.meta.url), "utf8");
  const panda = await readFile(new URL("../src/panda.js", import.meta.url), "utf8");
  assert.match(source, /function renderBye/);
  assert.match(source, /selfUninstalling\?renderBye\(\)/);
  assert.match(panda, /"wave"/);
  assert.match(css, /@keyframes byeSpin/);
  assert.match(css, /@keyframes byeWave/);
});

test("engines are time-limited and the toolkit refresh reuses the cached scan", async () => {
  const rust = await readFile(new URL("../src-tauri/src/main.rs", import.meta.url), "utf8");
  assert.match(rust, /fn engine_time_limit/);
  assert.match(rust, /ENGINE_TIMEOUT/);
  assert.match(rust, /al_setup_execute_v1\.ps1" => None/);
  const fn = source.slice(source.indexOf("async function updateToolkit"), source.indexOf("const actions={"));
  assert.doesNotMatch(fn, /refreshSoftwareIntelligence\(true\)/);
});
