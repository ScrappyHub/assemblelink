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
  assert.match(source,/Analyze a Project/);
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
  assert.match(source, /Set Up This Computer/);
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
  assert.match(source, /Update My Tools/);
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

test("sidebar exposes the actual setup and machine workflows", () => {
  for(const label of ["Job toolkits","Software & CLI catalog","Updates","Installed software","Job readiness","Blueprints / Rebuild"]){assert.match(source,new RegExp(label.replace(/[&/]/g,"\\$&")));}
  assert.match(source, /data-setup-jump/);
  assert.match(source, /sidebarStatus/);
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
  assert.match(source, /value="\$\{escapeHtml\(softwareSearch\)\}"/);
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
  assert.match(source, /Review Storage Health/);
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
  assert.match(source, /Browse Approved Software/);
  assert.match(source, /data-browse-approved/);
  assert.match(source, /data-stack-plan/);
  assert.doesNotMatch(source, /saveCustomSoftware|CLI save wiring comes next/);
  assert.doesNotMatch(source, /function renderInstallQueue|function renderInstallPlan/);
  assert.doesNotMatch(source, /\.\/state\/install_queue|\.\/state\/install_plan/);
});

test("opening dashboard explains setup, downloads, updates, and installed software", () => {
  assert.match(source, /function renderDashboardQuickStart/);
  assert.match(source, /Set up this computer/);
  assert.match(source, /Find software & CLI tools/);
  assert.match(source, /Check for updates/);
  assert.match(source, /function renderDashboardInventory/);
  assert.match(source, /known tools/);
  assert.match(source, /app candidates/);
  assert.match(source, /components/);
  assert.match(source, /Inventory class/);
  assert.match(source, /Catalog action/);
  assert.match(source, /data-inventory-kind/);
  assert.match(source, /Apps to review/);
  assert.match(source, /softwareKindFilter/);
  assert.match(source, /versions to review/);
  assert.match(source, /function renderDashboardMachine/);
  assert.match(source, /function renderDashboardToolkits/);
  assert.match(source, /data-quick-toolkit/);
  assert.match(source, /sidebarContext!=="overview"/);
});

test("workstation assurance is integrity checked, visible, and refreshable", async () => {
  const rust=await readFile(new URL("../src-tauri/src/main.rs",import.meta.url),"utf8");
  assert.match(source,/invokeDesktop\("get_workstation_assurance"\)/);
  assert.match(source,/function renderDashboardAssurance/);
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
    assert.match(css, new RegExp(`\\.panda\\[data-pose="${pose}"\\]|\\.pandaGuide\\[data-pose="${pose}"\\]`));
  }
  assert.match(panda, /Bamboo|bamboo/);
  assert.match(panda, /role="img"/);
  assert.match(source, /import \{pandaSvg\} from "\.\/panda\.js"/);
  assert.match(source, /function pandaMood/);
  assert.match(source, /pose:"carry"/);
  assert.match(source, /renderScanCard/);
  assert.match(source, /id="retryScan"/);
  assert.match(source, /data-countup/);
  assert.match(source, /carryTrack/);
  assert.match(css, /prefers-reduced-motion: reduce/);
});

test("setup keeps one decision visible and locks the selection while the plan is reviewed", () => {
  assert.match(source, /class="modeTabs"/);
  assert.match(source, /id="editSelection"/);
  assert.match(source, /class="panel planPanel"/);
  assert.doesNotMatch(source, /nav\("licensing"/);
});
