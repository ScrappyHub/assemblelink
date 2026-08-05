#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{collections::BTreeSet, env, fs::{self, OpenOptions}, io::Write, path::{Path, PathBuf}, process::Command, sync::{Mutex, MutexGuard}, time::{SystemTime, UNIX_EPOCH}};
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use tauri::AppHandle;
use sha2::{Digest, Sha256};
#[cfg(not(debug_assertions))]
use tauri::Manager;

const TRUSTED_RUNTIME_FILES: &[(&str, &[u8])] = &[
  ("catalog/approved_software_sources.v1.json", include_bytes!("../../../catalog/approved_software_sources.v1.json")),
  ("catalog/toolkits.v1.json", include_bytes!("../../../catalog/toolkits.v1.json")),
  ("scripts/engine/al_setup_plan_v1.ps1", include_bytes!("../../../scripts/engine/al_setup_plan_v1.ps1")),
  ("scripts/engine/al_setup_execute_v1.ps1", include_bytes!("../../../scripts/engine/al_setup_execute_v1.ps1")),
  ("scripts/engine/al_update_plan_v1.ps1", include_bytes!("../../../scripts/engine/al_update_plan_v1.ps1")),
  ("scripts/engine/al_software_intelligence_v1.ps1", include_bytes!("../../../scripts/engine/al_software_intelligence_v1.ps1")),
  ("scripts/engine/al_blueprint_export_v1.ps1", include_bytes!("../../../scripts/engine/al_blueprint_export_v1.ps1")),
  ("scripts/engine/al_blueprint_import_v1.ps1", include_bytes!("../../../scripts/engine/al_blueprint_import_v1.ps1")),
  ("scripts/commands/al_driver_profile_v1.ps1", include_bytes!("../../../scripts/commands/al_driver_profile_v1.ps1")),
  ("scripts/commands/al_system_profile_v1.ps1", include_bytes!("../../../scripts/commands/al_system_profile_v1.ps1")),
];
static RUNTIME_OPERATION_LOCK: Mutex<()> = Mutex::new(());
const MAX_SETUP_PROGRESS_BYTES: u64 = 2 * 1024 * 1024;
const MAX_SETUP_PROGRESS_ITEMS: u64 = 5000;
const MAX_SETUP_PLAN_BYTES: u64 = 4 * 1024 * 1024;
const MAX_ASSURANCE_SYSTEM_BYTES: u64 = 1024 * 1024;
const MAX_ASSURANCE_DRIVER_BYTES: u64 = 2 * 1024 * 1024;
const MAX_ASSURANCE_SOFTWARE_BYTES: u64 = 8 * 1024 * 1024;

fn seed_trusted_runtime(root: &Path) -> Result<(), String> {
  for (relative, bytes) in TRUSTED_RUNTIME_FILES {
    let target = root.join(relative);
    if let Some(parent) = target.parent() { fs::create_dir_all(parent).map_err(|e| format!("TRUSTED_DIR_FAILED {}: {e}", parent.display()))?; }
    fs::write(&target, bytes).map_err(|e| format!("TRUSTED_WRITE_FAILED {}: {e}", target.display()))?;
  }
  Ok(())
}

fn copy_tree(source: &Path, target: &Path) -> Result<(), String> {
  fs::create_dir_all(target).map_err(|e| format!("CREATE_DIR_FAILED {}: {e}", target.display()))?;
  for entry in fs::read_dir(source).map_err(|e| format!("READ_DIR_FAILED {}: {e}", source.display()))? {
    let entry = entry.map_err(|e| e.to_string())?;
    let from = entry.path();
    let to = target.join(entry.file_name());
    if from.is_dir() { copy_tree(&from, &to)?; }
    else { fs::copy(&from, &to).map_err(|e| format!("COPY_FAILED {}: {e}", from.display()))?; }
  }
  Ok(())
}

fn runtime_data_root(app: &AppHandle) -> Result<PathBuf, String> {
  #[cfg(debug_assertions)]
  let _ = app;
  #[cfg(debug_assertions)]
  {
    if let Ok(root) = env::var("ASSEMBLELINK_ROOT") {
      let path = PathBuf::from(root);
      if path.join("scripts").is_dir() { return Ok(path); }
    }
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    return path.canonicalize().map_err(|e| format!("DEV_ROOT_FAILED: {e}"));
  }

  #[cfg(not(debug_assertions))]
  {
    Ok(app.path().app_local_data_dir().map_err(|e| format!("APP_DATA_FAILED: {e}"))?.join("runtime"))
  }
}

fn runtime_root(app: &AppHandle) -> Result<PathBuf, String> {
  #[cfg(debug_assertions)]
  {
    runtime_data_root(app)
  }

  #[cfg(not(debug_assertions))]
  {
    let root = runtime_data_root(app)?;
    let resources = app.path().resource_dir().map_err(|e| format!("RESOURCE_DIR_FAILED: {e}"))?.join("engine");
    for name in ["scripts", "catalog", "manifests"] {
      let source = resources.join(name);
      if !source.is_dir() { return Err(format!("PACKAGED_RESOURCE_MISSING: {}", source.display())); }
      copy_tree(&source, &root.join(name))?;
    }
    seed_trusted_runtime(&root)?;
    for name in ["state", "proofs/receipts"] { fs::create_dir_all(root.join(name)).map_err(|e| e.to_string())?; }
    Ok(root)
  }
}

fn locked_runtime(app: &AppHandle) -> Result<(MutexGuard<'static, ()>, PathBuf), String> {
  let guard = RUNTIME_OPERATION_LOCK.lock().map_err(|_| "RUNTIME_OPERATION_LOCK_POISONED".to_owned())?;
  let root = runtime_root(app)?;
  Ok((guard, root))
}

fn run_ps(root: &Path, relative_script: &str, args: &[&str]) -> Result<String, String> {
  let script = root.join(relative_script);
  if !script.is_file() { return Err(format!("ENGINE_SCRIPT_MISSING: {}", script.display())); }
  let mut cmd = Command::new("powershell.exe");
  #[cfg(windows)]
  cmd.creation_flags(0x08000000);
  cmd.args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"])
    .arg(&script).arg("-RepoRoot").arg(root);
  cmd.args(args);
  let output = cmd.output().map_err(|e| format!("POWERSHELL_START_FAILED: {e}"))?;
  let stdout = String::from_utf8_lossy(&output.stdout).to_string();
  let stderr = String::from_utf8_lossy(&output.stderr).to_string();
  if !output.status.success() { return Err(format!("ENGINE_FAILED ({relative_script})\n{stdout}\n{stderr}")); }
  Ok(stdout)
}

fn read_state(root: &Path, name: &str) -> Result<String, String> {
  fs::read_to_string(root.join("state").join(name)).map_err(|e| format!("STATE_READ_FAILED {name}: {e}"))
}

fn read_json_file(path: &Path) -> Result<serde_json::Value, String> {
  let bytes = fs::read(path).map_err(|e| format!("JSON_READ_FAILED {}: {e}", path.display()))?;
  let payload = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(&bytes);
  serde_json::from_slice(payload).map_err(|e| format!("JSON_PARSE_FAILED {}: {e}", path.display()))
}

fn bounded_progress_text(value: Option<&serde_json::Value>, limit: usize) -> String {
  value.and_then(serde_json::Value::as_str).unwrap_or("").chars().take(limit).collect()
}

fn idle_setup_progress(plan_id: &str) -> serde_json::Value {
  serde_json::json!({
    "schema":"assemblelink.setup_execution.progress.v1",
    "plan_id":plan_id,
    "status":"idle",
    "total":0,
    "completed":0,
    "results":[]
  })
}

fn valid_plan_id(plan_id: &str) -> bool {
  plan_id.len() == 64 && plan_id.chars().all(|c| c.is_ascii_hexdigit())
}

fn read_setup_progress(root: &Path, expected_plan_id: &str) -> Result<serde_json::Value, String> {
  let path = root.join("state/setup_execution.progress.json");
  if !path.is_file() { return Ok(idle_setup_progress(expected_plan_id)); }
  let state_dir = root.join("state").canonicalize().map_err(|e| format!("PROGRESS_STATE_RESOLVE_FAILED: {e}"))?;
  let resolved = path.canonicalize().map_err(|e| format!("PROGRESS_RESOLVE_FAILED: {e}"))?;
  if !resolved.starts_with(&state_dir) { return Err("PROGRESS_PATH_ESCAPE_REJECTED".into()); }
  let metadata = fs::metadata(&resolved).map_err(|e| format!("PROGRESS_METADATA_FAILED: {e}"))?;
  if metadata.len() > MAX_SETUP_PROGRESS_BYTES { return Err("PROGRESS_TOO_LARGE".into()); }
  let value = read_json_file(&resolved)?;
  if value.get("schema").and_then(serde_json::Value::as_str) != Some("assemblelink.setup_execution.progress.v1") {
    return Err("PROGRESS_SCHEMA_REJECTED".into());
  }
  if value.get("plan_id").and_then(serde_json::Value::as_str) != Some(expected_plan_id) {
    return Ok(idle_setup_progress(expected_plan_id));
  }
  let status = value.get("status").and_then(serde_json::Value::as_str).ok_or("PROGRESS_STATUS_MISSING")?;
  if !matches!(status, "running" | "dry_run" | "complete") { return Err("PROGRESS_STATUS_REJECTED".into()); }
  let total = value.get("total").and_then(serde_json::Value::as_u64).ok_or("PROGRESS_TOTAL_INVALID")?;
  let completed = value.get("completed").and_then(serde_json::Value::as_u64).ok_or("PROGRESS_COMPLETED_INVALID")?;
  let results = value.get("results").and_then(serde_json::Value::as_array).ok_or("PROGRESS_RESULTS_INVALID")?;
  if total > MAX_SETUP_PROGRESS_ITEMS || completed > total || results.len() as u64 > total || results.len() as u64 != completed {
    return Err("PROGRESS_COUNTS_REJECTED".into());
  }
  let mut safe_results = Vec::with_capacity(results.len());
  for item in results {
    let item = item.as_object().ok_or("PROGRESS_ITEM_INVALID")?;
    safe_results.push(serde_json::json!({
      "id": bounded_progress_text(item.get("id"), 128),
      "name": bounded_progress_text(item.get("name"), 256),
      "winget_id": bounded_progress_text(item.get("winget_id"), 256),
      "status": bounded_progress_text(item.get("status"), 128),
      "exit_code": item.get("exit_code").and_then(serde_json::Value::as_i64),
      "verified": item.get("verified").and_then(serde_json::Value::as_bool).unwrap_or(false),
      "source_verified": item.get("source_verified").and_then(serde_json::Value::as_bool).unwrap_or(false),
      "message": bounded_progress_text(item.get("message"), 1024)
    }));
  }
  Ok(serde_json::json!({
    "schema":"assemblelink.setup_execution.progress.v1",
    "plan_id":expected_plan_id,
    "status":status,
    "total":total,
    "completed":completed,
    "results":safe_results
  }))
}

fn read_setup_recovery(root: &Path) -> Result<serde_json::Value, String> {
  let progress_path = root.join("state/setup_execution.progress.json");
  if !progress_path.is_file() { return Ok(serde_json::json!({"schema":"assemblelink.setup_recovery.v1","available":false})); }
  let metadata = fs::metadata(&progress_path).map_err(|e| format!("RECOVERY_PROGRESS_METADATA_FAILED: {e}"))?;
  if metadata.len() > MAX_SETUP_PROGRESS_BYTES { return Err("RECOVERY_PROGRESS_TOO_LARGE".into()); }
  let raw_progress = read_json_file(&progress_path)?;
  let plan_id = raw_progress.get("plan_id").and_then(serde_json::Value::as_str).ok_or("RECOVERY_PLAN_ID_MISSING")?;
  if !valid_plan_id(plan_id) { return Err("RECOVERY_PLAN_ID_REJECTED".into()); }
  let progress = read_setup_progress(root, plan_id)?;
  let status = progress.get("status").and_then(serde_json::Value::as_str).unwrap_or("idle");
  let total = progress.get("total").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let completed = progress.get("completed").and_then(serde_json::Value::as_u64).unwrap_or(0);
  if status != "running" || completed >= total {
    return Ok(serde_json::json!({"schema":"assemblelink.setup_recovery.v1","available":false}));
  }
  let state_dir = root.join("state").canonicalize().map_err(|e| format!("RECOVERY_STATE_RESOLVE_FAILED: {e}"))?;
  let plan_path = root.join("state").join(format!("setup_plan.{plan_id}.json"));
  let resolved_plan = plan_path.canonicalize().map_err(|e| format!("RECOVERY_PLAN_RESOLVE_FAILED: {e}"))?;
  if !resolved_plan.starts_with(&state_dir) { return Err("RECOVERY_PLAN_PATH_ESCAPE_REJECTED".into()); }
  let plan_metadata = fs::metadata(&resolved_plan).map_err(|e| format!("RECOVERY_PLAN_METADATA_FAILED: {e}"))?;
  if plan_metadata.len() > MAX_SETUP_PLAN_BYTES { return Err("RECOVERY_PLAN_TOO_LARGE".into()); }
  let plan = read_json_file(&resolved_plan)?;
  if plan.get("schema").and_then(serde_json::Value::as_str) != Some("assemblelink.setup_plan.v1")
    || plan.get("plan_id").and_then(serde_json::Value::as_str) != Some(plan_id) {
    return Err("RECOVERY_PLAN_SCHEMA_REJECTED".into());
  }
  let items = plan.get("items").and_then(serde_json::Value::as_array).ok_or("RECOVERY_PLAN_ITEMS_INVALID")?;
  if items.len() as u64 != total || total > MAX_SETUP_PROGRESS_ITEMS { return Err("RECOVERY_PLAN_COUNT_MISMATCH".into()); }
  let mut safe_items = Vec::with_capacity(items.len());
  for item in items {
    let item = item.as_object().ok_or("RECOVERY_PLAN_ITEM_INVALID")?;
    let dependencies: Vec<String> = item.get("dependencies").and_then(serde_json::Value::as_array).map(|values| {
      values.iter().take(100).map(|value| bounded_progress_text(Some(value), 128)).collect()
    }).unwrap_or_default();
    safe_items.push(serde_json::json!({
      "id":bounded_progress_text(item.get("id"),128),
      "name":bounded_progress_text(item.get("name"),256),
      "source":bounded_progress_text(item.get("source"),128),
      "winget_id":bounded_progress_text(item.get("winget_id"),256),
      "license":bounded_progress_text(item.get("license"),128),
      "admin_required":item.get("admin_required").and_then(serde_json::Value::as_bool).unwrap_or(false),
      "reboot_required":item.get("reboot_required").and_then(serde_json::Value::as_bool).unwrap_or(false),
      "dependencies":dependencies,
      "mode":bounded_progress_text(item.get("mode"),128),
      "status":bounded_progress_text(item.get("status"),128)
    }));
  }
  let automatic_count = safe_items.iter().filter(|item| item["mode"] == "winget").count();
  Ok(serde_json::json!({
    "schema":"assemblelink.setup_recovery.v1",
    "available":true,
    "progress":progress,
    "plan":{
      "schema":"assemblelink.setup_plan.v1",
      "plan_id":plan_id,
      "plan_type":bounded_progress_text(plan.get("plan_type"),64),
      "item_count":total,
      "automatic_count":automatic_count,
      "manual_count":items.len().saturating_sub(automatic_count),
      "items":safe_items
    }
  }))
}

fn sha256_hex(bytes: &[u8]) -> String {
  Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

fn read_verified_state(root: &Path, name: &str, max_bytes: u64, expected_schema: &str) -> Result<(serde_json::Value, String), String> {
  let path = root.join("state").join(name);
  let metadata = fs::metadata(&path).map_err(|e| format!("ASSURANCE_STATE_MISSING {name}: {e}"))?;
  if !metadata.is_file() || metadata.len() > max_bytes { return Err(format!("ASSURANCE_STATE_SIZE_REJECTED: {name}")); }
  let bytes = fs::read(&path).map_err(|e| format!("ASSURANCE_STATE_READ_FAILED {name}: {e}"))?;
  let actual = sha256_hex(&bytes);
  let sidecar = PathBuf::from(format!("{}.sha256", path.to_string_lossy()));
  let expected = fs::read_to_string(&sidecar).map_err(|e| format!("ASSURANCE_SIDECAR_MISSING {name}: {e}"))?
    .split_whitespace().next().unwrap_or("").to_ascii_lowercase();
  if expected.len() != 64 || !expected.chars().all(|c| c.is_ascii_hexdigit()) || expected != actual {
    return Err(format!("ASSURANCE_HASH_REJECTED: {name}"));
  }
  let payload = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(&bytes);
  let value: serde_json::Value = serde_json::from_slice(payload).map_err(|e| format!("ASSURANCE_JSON_REJECTED {name}: {e}"))?;
  if value.get("schema").and_then(serde_json::Value::as_str) != Some(expected_schema) {
    return Err(format!("ASSURANCE_SCHEMA_REJECTED: {name}"));
  }
  Ok((value, actual))
}

fn build_workstation_assurance(root: &Path) -> Result<serde_json::Value, String> {
  let (system, system_hash) = read_verified_state(root, "system_profile.latest.json", MAX_ASSURANCE_SYSTEM_BYTES, "assemblelink.system_profile.v2")?;
  let (driver, driver_hash) = read_verified_state(root, "driver_profile.latest.json", MAX_ASSURANCE_DRIVER_BYTES, "assemblelink.driver_profile.v2")?;
  let (software, software_hash) = read_verified_state(root, "software_intelligence.latest.json", MAX_ASSURANCE_SOFTWARE_BYTES, "assemblelink.software_intelligence.v1")?;
  if software.get("evidence_mode").and_then(serde_json::Value::as_str) != Some("live") { return Err("ASSURANCE_FIXTURE_EVIDENCE_REJECTED".into()); }
  let catalog_path = root.join("catalog/approved_software_sources.v1.json");
  let catalog_bytes = fs::read(&catalog_path).map_err(|e| format!("ASSURANCE_CATALOG_READ_FAILED: {e}"))?;
  let catalog = read_json_file(&catalog_path)?;
  let catalog_items = catalog.get("items").and_then(serde_json::Value::as_array).ok_or("ASSURANCE_CATALOG_ITEMS_REJECTED")?.len();
  let summary = software.get("summary").and_then(serde_json::Value::as_object).ok_or("ASSURANCE_SOFTWARE_SUMMARY_REJECTED")?;
  let detected = summary.get("detected").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let matched = summary.get("catalog_matched").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let unmatched = summary.get("unmatched").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let unmatched_applications = summary.get("unmatched_application_candidates").and_then(serde_json::Value::as_u64).unwrap_or(unmatched);
  let unmatched_unique_applications = summary.get("unmatched_unique_applications").and_then(serde_json::Value::as_u64).unwrap_or(unmatched_applications);
  let unmatched_components = summary.get("unmatched_components").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let updates = summary.get("updates_available").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let unknown = summary.get("unknown").and_then(serde_json::Value::as_u64).unwrap_or(0);
  let system_status = system.get("observation_status").and_then(serde_json::Value::as_str).unwrap_or("unknown");
  let driver_status = driver.get("observation_status").and_then(serde_json::Value::as_str).unwrap_or("unknown");
  let driver_recommendations = driver.get("recommendations").and_then(serde_json::Value::as_array).map_or(0, Vec::len);
  let mut attention = Vec::new();
  for drive in system.pointer("/storage/drives").and_then(serde_json::Value::as_array).into_iter().flatten() {
    let free = drive.get("free_percent").and_then(serde_json::Value::as_f64).unwrap_or(0.0);
    if free < 10.0 { attention.push(serde_json::json!({"severity":"critical","code":"storage_critical","label":format!("{} critically low", drive.get("drive").and_then(serde_json::Value::as_str).unwrap_or("Drive")),"detail":format!("{free:.1}% free")})); }
    else if free < 15.0 { attention.push(serde_json::json!({"severity":"warning","code":"storage_low","label":format!("{} getting low", drive.get("drive").and_then(serde_json::Value::as_str).unwrap_or("Drive")),"detail":format!("{free:.1}% free")})); }
  }
  if unknown > 0 { attention.push(serde_json::json!({"severity":"warning","code":"updates_unknown","label":"Update checks incomplete","detail":format!("{unknown} matched tools need provider confirmation")})); }
  if unmatched_applications > 0 { attention.push(serde_json::json!({"severity":"info","code":"catalog_unmatched","label":"Catalog review available","detail":format!("{unmatched_unique_applications} unique app candidates; {unmatched_components} component rows remain inventory-only")})); }
  if driver_recommendations > 0 { attention.push(serde_json::json!({"severity":"info","code":"driver_review","label":"Driver support review","detail":format!("{driver_recommendations} official support paths are available")})); }
  let status = if system_status != "complete" || driver_status != "complete" { "incomplete" } else if attention.iter().any(|item| item.get("severity").and_then(serde_json::Value::as_str) == Some("critical")) { "critical_attention" } else if attention.is_empty() { "verified" } else { "attention" };
  let gpu = system.get("gpu").and_then(serde_json::Value::as_array).and_then(|items| items.first());
  let vram_confidence = gpu.and_then(|item| item.get("vram_confidence")).and_then(serde_json::Value::as_str).unwrap_or("unknown");
  let generated_unix_ms = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e| e.to_string())?.as_millis() as u64;
  Ok(serde_json::json!({
    "schema":"assemblelink.workstation_assurance.v1","generated_unix_ms":generated_unix_ms,"status":status,
    "observed":{"system_utc":system.get("observed_utc"),"driver_utc":driver.get("observed_utc"),"software_utc":software.get("observed_utc")},
    "integrity":{"system":"verified","driver":"verified","software":"verified","catalog":"trusted_embedded"},
    "hashes":{"system":system_hash,"driver":driver_hash,"software":software_hash,"catalog":sha256_hex(&catalog_bytes)},
    "machine":{"name":system.pointer("/machine/name"),"os":system.pointer("/os/caption"),"build":system.pointer("/os/build"),"cpu":system.pointer("/cpu/name"),"memory_gb":system.pointer("/memory/total_gb"),"gpu":gpu.and_then(|item| item.get("name")),"gpu_vram_status":if vram_confidence == "high" {"observed"} else {"unknown"}},
    "inventory":{"detected":detected,"catalog_matched":matched,"unmatched":unmatched,"unmatched_application_candidates":unmatched_applications,"unmatched_unique_applications":unmatched_unique_applications,"unmatched_components":unmatched_components,"updates_available":updates,"update_status_unknown":unknown,"catalog_items":catalog_items},
    "drivers":{"observation_status":driver_status,"official_support_reviews":driver_recommendations,"freshness_claimed":false},
    "attention":attention,
    "limitations":["Driver support paths are not freshness claims.","Unknown update status is never treated as current.","This assurance does not claim malware absence, network security, or firmware freshness."]
  }))
}

fn write_workstation_assurance(root: &Path, assurance: &serde_json::Value) -> Result<(), String> {
  let state_dir = root.join("state"); let receipt_dir = root.join("proofs/receipts");
  fs::create_dir_all(&state_dir).map_err(|e| e.to_string())?; fs::create_dir_all(&receipt_dir).map_err(|e| e.to_string())?;
  let mut bytes = serde_json::to_vec_pretty(assurance).map_err(|e| e.to_string())?; bytes.push(b'\n');
  let hash = sha256_hex(&bytes); let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e| e.to_string())?.as_nanos();
  let immutable = state_dir.join(format!("workstation_assurance.{stamp}.json"));
  let mut file = OpenOptions::new().write(true).create_new(true).open(&immutable).map_err(|e| format!("ASSURANCE_CREATE_FAILED: {e}"))?;
  file.write_all(&bytes).map_err(|e| format!("ASSURANCE_WRITE_FAILED: {e}"))?; file.sync_all().map_err(|e| format!("ASSURANCE_SYNC_FAILED: {e}"))?;
  fs::write(format!("{}.sha256", immutable.to_string_lossy()), format!("{hash}  {}\n", immutable.file_name().and_then(|n| n.to_str()).unwrap_or("workstation_assurance.json"))).map_err(|e| e.to_string())?;
  let latest = state_dir.join("workstation_assurance.latest.json"); fs::write(&latest, &bytes).map_err(|e| e.to_string())?;
  fs::write(format!("{}.sha256", latest.to_string_lossy()), format!("{hash}  workstation_assurance.latest.json\n")).map_err(|e| e.to_string())?;
  let receipt = serde_json::json!({"schema":"assemblelink.workstation_assurance_receipt.v1","state":immutable.file_name().and_then(|n| n.to_str()),"sha256":hash,"status":assurance.get("status"),"generated_unix_ms":assurance.get("generated_unix_ms")});
  let mut receipt_bytes = serde_json::to_vec_pretty(&receipt).map_err(|e| e.to_string())?; receipt_bytes.push(b'\n'); let receipt_hash = sha256_hex(&receipt_bytes);
  let receipt_path = receipt_dir.join(format!("assemblelink.workstation_assurance.{stamp}.json")); let mut receipt_file = OpenOptions::new().write(true).create_new(true).open(&receipt_path).map_err(|e| format!("ASSURANCE_RECEIPT_CREATE_FAILED: {e}"))?;
  receipt_file.write_all(&receipt_bytes).map_err(|e| e.to_string())?; receipt_file.sync_all().map_err(|e| e.to_string())?;
  fs::write(format!("{}.sha256", receipt_path.to_string_lossy()), format!("{receipt_hash}  {}\n", receipt_path.file_name().and_then(|n| n.to_str()).unwrap_or("assurance_receipt.json"))).map_err(|e| e.to_string())?;
  Ok(())
}

fn installed_catalog_ids(intelligence: &serde_json::Value) -> (Vec<String>, usize) {
  let mut ids = BTreeSet::new();
  let mut unmatched = 0;
  for item in intelligence.get("items").and_then(serde_json::Value::as_array).into_iter().flatten() {
    if item.get("installed").and_then(serde_json::Value::as_bool) != Some(true) { continue; }
    match item.get("catalog_id").and_then(serde_json::Value::as_str).filter(|id| !id.is_empty()) {
      Some(id) if id.len() <= 128 && id.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.')) => { ids.insert(id.to_owned()); },
      _ => unmatched += 1,
    }
  }
  (ids.into_iter().collect(), unmatched)
}

fn receipt_index(root: &Path) -> Result<serde_json::Value, String> {
  let dir = root.join("proofs/receipts");
  fs::create_dir_all(&dir).map_err(|e| format!("RECEIPT_DIR_FAILED: {e}"))?;
  let canonical_dir = dir.canonicalize().map_err(|e| format!("RECEIPT_DIR_RESOLVE_FAILED: {e}"))?;
  let mut paths: Vec<PathBuf> = fs::read_dir(&dir).map_err(|e| format!("RECEIPT_LIST_FAILED: {e}"))?
    .filter_map(Result::ok).map(|e| e.path())
    .filter(|p| p.is_file() && !p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.ends_with(".sha256")))
    .filter(|p| p.canonicalize().is_ok_and(|resolved| resolved.starts_with(&canonical_dir)))
    .filter(|p| matches!(p.extension().and_then(|x| x.to_str()).map(str::to_ascii_lowercase).as_deref(), Some("json") | Some("txt"))).collect();
  paths.sort_by_key(|p| std::cmp::Reverse(fs::metadata(p).and_then(|m| m.modified()).ok()));
  let mut items = Vec::new();
  for path in paths.into_iter().take(200) {
    let metadata = fs::metadata(&path).map_err(|e| e.to_string())?;
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("invalid-name").to_owned();
    let modified_unix = metadata.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs()).unwrap_or(0);
    if metadata.len() > 8 * 1024 * 1024 {
      items.push(serde_json::json!({"name":name,"schema":"unknown","bytes":metadata.len(),"modified_unix":modified_unix,"integrity":"too_large","sha256":""}));
      continue;
    }
    let bytes = fs::read(&path).map_err(|e| format!("RECEIPT_READ_FAILED {name}: {e}"))?;
    let actual = sha256_hex(&bytes);
    let sidecar = PathBuf::from(format!("{}.sha256", path.to_string_lossy()));
    let integrity = if sidecar.is_file() {
      match fs::read_to_string(&sidecar).ok().and_then(|s| s.split_whitespace().next().map(str::to_lowercase)) {
        Some(expected) if expected.len() == 64 && expected.chars().all(|c| c.is_ascii_hexdigit()) && expected == actual => "valid",
        Some(expected) if expected.len() == 64 && expected.chars().all(|c| c.is_ascii_hexdigit()) => "mismatch",
        _ => "malformed_sidecar",
      }
    } else { "unverified" };
    let schema = if path.extension().and_then(|x| x.to_str()) == Some("json") {
      serde_json::from_slice::<serde_json::Value>(&bytes).ok().and_then(|v| v.get("schema").and_then(|s| s.as_str()).map(str::to_owned)).unwrap_or_else(|| "unknown".into())
    } else {
      String::from_utf8_lossy(&bytes).lines().find_map(|line| line.strip_prefix("schema=").map(str::to_owned)).unwrap_or_else(|| "unknown".into())
    };
    items.push(serde_json::json!({"name":name,"schema":schema,"bytes":metadata.len(),"modified_unix":modified_unix,"integrity":integrity,"sha256":actual}));
  }
  let valid = items.iter().filter(|x| x["integrity"] == "valid").count();
  let unverified = items.iter().filter(|x| x["integrity"] == "unverified").count();
  let failed = items.len().saturating_sub(valid + unverified);
  Ok(serde_json::json!({"schema":"assemblelink.receipt_index.v1","summary":{"total":items.len(),"valid":valid,"unverified":unverified,"failed":failed},"items":items}))
}

#[tauri::command]
fn get_setup_data(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  let catalog = read_json_file(&root.join("catalog/approved_software_sources.v1.json"))?;
  let toolkits = read_json_file(&root.join("catalog/toolkits.v1.json"))?;
  serde_json::to_string(&serde_json::json!({"catalog":catalog,"toolkits":toolkits})).map_err(|e| e.to_string())
}

#[tauri::command]
fn refresh_software_intelligence(app: AppHandle, force_refresh: bool) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  let args = if force_refresh { vec!["-ForceRefresh"] } else { Vec::new() };
  run_ps(&root, "scripts/engine/al_software_intelligence_v1.ps1", &args)?;
  read_state(&root, "software_intelligence.latest.json")
}

#[tauri::command]
fn build_setup_plan(app: AppHandle, toolkit_ids: Vec<String>, software_ids: Vec<String>) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  fs::create_dir_all(root.join("state")).map_err(|e| e.to_string())?;
  let request_path = root.join("state/setup_request.pending.json");
  let request = serde_json::json!({"schema":"assemblelink.setup_request.v1","toolkit_ids":toolkit_ids,"software_ids":software_ids});
  fs::write(&request_path, serde_json::to_vec_pretty(&request).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
  let request_text = request_path.to_string_lossy().to_string();
  run_ps(&root, "scripts/engine/al_setup_plan_v1.ps1", &["-RequestPath", &request_text])?;
  read_state(&root, "setup_plan.latest.json")
}

#[tauri::command]
fn execute_setup(app: AppHandle, plan_id: String, approved: bool) -> Result<String, String> {
  if !approved { return Err("SETUP_REQUIRES_EXPLICIT_APPROVAL".into()); }
  if !valid_plan_id(&plan_id) { return Err("INVALID_PLAN_ID".into()); }
  let (_guard, root) = locked_runtime(&app)?;
  let plan_path = root.join("state").join(format!("setup_plan.{plan_id}.json"));
  let plan_text = plan_path.to_string_lossy().to_string();
  run_ps(&root, "scripts/engine/al_setup_execute_v1.ps1", &["-PlanPath", &plan_text, "-ApprovalPlanId", &plan_id, "-Execute"])?;
  read_state(&root, "setup_execution.latest.json")
}

#[tauri::command]
fn get_setup_progress(app: AppHandle, plan_id: String) -> Result<String, String> {
  if !valid_plan_id(&plan_id) { return Err("INVALID_PLAN_ID".into()); }
  let root = runtime_data_root(&app)?;
  serde_json::to_string(&read_setup_progress(&root, &plan_id)?).map_err(|e| e.to_string())
}

#[tauri::command]
fn get_setup_recovery(app: AppHandle) -> Result<String, String> {
  let root = runtime_data_root(&app)?;
  serde_json::to_string(&read_setup_recovery(&root)?).map_err(|e| e.to_string())
}

#[tauri::command]
fn resume_setup(app: AppHandle, plan_id: String, approved: bool) -> Result<String, String> {
  if !approved { return Err("SETUP_RESUME_REQUIRES_EXPLICIT_APPROVAL".into()); }
  if !valid_plan_id(&plan_id) { return Err("INVALID_PLAN_ID".into()); }
  let (_guard, root) = locked_runtime(&app)?;
  let plan_path = root.join("state").join(format!("setup_plan.{plan_id}.json"));
  let plan_text = plan_path.to_string_lossy().to_string();
  run_ps(&root, "scripts/engine/al_setup_execute_v1.ps1", &["-PlanPath", &plan_text, "-ApprovalPlanId", &plan_id, "-Execute", "-Resume"])?;
  read_state(&root, "setup_execution.latest.json")
}

#[tauri::command]
fn build_update_plan(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  run_ps(&root, "scripts/engine/al_update_plan_v1.ps1", &[])?;
  read_state(&root, "setup_plan.latest.json")
}

#[tauri::command]
fn export_blueprint(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  let output = run_ps(&root, "scripts/engine/al_blueprint_export_v1.ps1", &[])?;
  output.lines().map(str::trim).find(|line| line.ends_with(".json")).map(str::to_owned).ok_or_else(|| "BLUEPRINT_EXPORT_PATH_MISSING".into())
}

#[tauri::command]
fn export_machine_blueprint(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  run_ps(&root, "scripts/engine/al_software_intelligence_v1.ps1", &["-ForceRefresh"])?;
  let intelligence = read_json_file(&root.join("state/software_intelligence.latest.json"))?;
  let (software_ids, unmatched_installed) = installed_catalog_ids(&intelligence);
  fs::create_dir_all(root.join("state")).map_err(|e| e.to_string())?;
  let request_path = root.join("state/setup_request.machine_export.json");
  let request = serde_json::json!({"schema":"assemblelink.setup_request.v1","toolkit_ids":[],"software_ids":software_ids});
  fs::write(&request_path, serde_json::to_vec_pretty(&request).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
  let request_text = request_path.to_string_lossy().to_string();
  run_ps(&root, "scripts/engine/al_setup_plan_v1.ps1", &["-RequestPath", &request_text])?;
  let plan = read_json_file(&root.join("state/setup_plan.latest.json"))?;
  let output = run_ps(&root, "scripts/engine/al_blueprint_export_v1.ps1", &[])?;
  let path = output.lines().map(str::trim).find(|line| line.ends_with(".json")).ok_or("BLUEPRINT_EXPORT_PATH_MISSING")?;
  serde_json::to_string(&serde_json::json!({
    "schema":"assemblelink.machine_blueprint_export.v1",
    "path":path,
    "catalog_matched_installed":request["software_ids"].as_array().map_or(0, Vec::len),
    "resolved_plan_items":plan.get("item_count").and_then(serde_json::Value::as_u64).unwrap_or(0),
    "unmatched_installed":unmatched_installed
  })).map_err(|e| e.to_string())
}

#[tauri::command]
fn import_blueprint(app: AppHandle, blueprint_path: String) -> Result<String, String> {
  let path = PathBuf::from(&blueprint_path);
  if !path.is_absolute() || path.extension().and_then(|x| x.to_str()) != Some("json") { return Err("INVALID_BLUEPRINT_PATH".into()); }
  let (_guard, root) = locked_runtime(&app)?;
  run_ps(&root, "scripts/engine/al_blueprint_import_v1.ps1", &["-BlueprintPath", &blueprint_path])?;
  read_state(&root, "setup_plan.latest.json")
}

#[tauri::command]
fn get_receipts(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  serde_json::to_string(&receipt_index(&root)?).map_err(|e| e.to_string())
}

#[tauri::command]
fn refresh_driver_profile(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  run_ps(&root, "scripts/commands/al_driver_profile_v1.ps1", &[])?;
  read_state(&root, "driver_profile.latest.json")
}

#[tauri::command]
fn refresh_system_profile(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  run_ps(&root, "scripts/commands/al_system_profile_v1.ps1", &[])?;
  read_state(&root, "system_profile.latest.json")
}

#[tauri::command]
fn get_workstation_assurance(app: AppHandle) -> Result<String, String> {
  let (_guard, root) = locked_runtime(&app)?;
  let assurance = build_workstation_assurance(&root)?;
  write_workstation_assurance(&root, &assurance)?;
  serde_json::to_string(&assurance).map_err(|e| e.to_string())
}

fn main() {
  tauri::Builder::default()
    .setup(|app| {
      runtime_root(app.handle()).map_err(|e| {
        std::io::Error::new(
          std::io::ErrorKind::Other,
          format!("TRUSTED_RUNTIME_STARTUP_FAILED: {e}"),
        )
      })?;
      Ok(())
    })
    .invoke_handler(tauri::generate_handler![get_setup_data, refresh_software_intelligence, build_setup_plan, build_update_plan, execute_setup, get_setup_progress, get_setup_recovery, resume_setup, export_blueprint, export_machine_blueprint, import_blueprint, get_receipts, refresh_driver_profile, refresh_system_profile, get_workstation_assurance])
    .run(tauri::generate_context!())
    .expect("error while running AssembleLink");
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn copy_tree_copies_nested_files() {
    let base = env::temp_dir().join(format!("assemblelink-test-{}", std::process::id()));
    let source = base.join("source"); let target = base.join("target");
    fs::create_dir_all(source.join("nested")).unwrap();
    fs::write(source.join("nested/item.txt"), "ok").unwrap();
    copy_tree(&source, &target).unwrap();
    assert_eq!(fs::read_to_string(target.join("nested/item.txt")).unwrap(), "ok");
    let _ = fs::remove_dir_all(base);
  }
  #[test]
  fn trusted_runtime_replaces_tampered_engine_and_catalog() {
    let base = env::temp_dir().join(format!("assemblelink-trusted-test-{}", std::process::id()));
    fs::create_dir_all(base.join("scripts/engine")).unwrap();
    fs::write(base.join("scripts/engine/al_setup_execute_v1.ps1"), "tampered").unwrap();
    seed_trusted_runtime(&base).unwrap();
    assert_ne!(fs::read(base.join("scripts/engine/al_setup_execute_v1.ps1")).unwrap(), b"tampered");
    assert!(base.join("catalog/approved_software_sources.v1.json").is_file());
    let _ = fs::remove_dir_all(base);
  }
  #[test]
  fn receipt_index_distinguishes_valid_and_tampered_evidence() {
    let base = env::temp_dir().join(format!("assemblelink-receipt-test-{}", std::process::id()));
    let receipts = base.join("proofs/receipts"); fs::create_dir_all(&receipts).unwrap();
    let valid = receipts.join("valid.txt"); fs::write(&valid, "schema=test.receipt.v1\nvalue=ok\n").unwrap();
    let hash = sha256_hex(&fs::read(&valid).unwrap()); fs::write(receipts.join("valid.txt.sha256"), format!("{hash}  valid.txt\n")).unwrap();
    let bad = receipts.join("bad.json"); fs::write(&bad, r#"{"schema":"test.receipt.v1"}"#).unwrap(); fs::write(receipts.join("bad.json.sha256"), format!("{}  bad.json\n", "0".repeat(64))).unwrap();
    let index = receipt_index(&base).unwrap();
    assert_eq!(index["summary"]["valid"], 1); assert_eq!(index["summary"]["failed"], 1);
    assert!(index.to_string().find(&base.to_string_lossy().to_string()).is_none());
    let _ = fs::remove_dir_all(base);
  }
  #[test]
  fn trusted_json_reader_accepts_utf8_bom() {
    let path = env::temp_dir().join(format!("assemblelink-bom-test-{}.json", std::process::id()));
    fs::write(&path, b"\xef\xbb\xbf{\"schema\":\"test.v1\"}").unwrap();
    assert_eq!(read_json_file(&path).unwrap()["schema"], "test.v1");
    let _ = fs::remove_file(path);
  }
  #[test]
  fn setup_progress_reader_bounds_and_normalizes_content() {
    let base = env::temp_dir().join(format!("assemblelink-progress-test-{}", std::process::id()));
    fs::create_dir_all(base.join("state")).unwrap();
    let plan_id = "a".repeat(64);
    fs::write(base.join("state/setup_execution.progress.json"), serde_json::to_vec(&serde_json::json!({
      "schema":"assemblelink.setup_execution.progress.v1",
      "plan_id":plan_id,
      "status":"running",
      "total":2,
      "completed":1,
      "results":[{
        "id":"git",
        "name":"Git<script>",
        "winget_id":"Git.Git",
        "status":"installed_or_already_present",
        "exit_code":0,
        "verified":true,
        "source_verified":true,
        "message":"Exact identity verified.",
        "untrusted_extra":"not returned"
      }]
    })).unwrap()).unwrap();
    let progress = read_setup_progress(&base, &plan_id).unwrap();
    assert_eq!(progress["completed"], 1);
    assert_eq!(progress["results"][0]["name"], "Git<script>");
    assert!(progress["results"][0].get("untrusted_extra").is_none());
    assert_eq!(read_setup_progress(&base, &"b".repeat(64)).unwrap()["status"], "idle");
    fs::write(base.join("state/setup_execution.progress.json"), b"{").unwrap();
    assert!(read_setup_progress(&base, &plan_id).unwrap_err().contains("JSON_PARSE_FAILED"));
    fs::write(base.join("state/setup_execution.progress.json"), vec![b'x'; MAX_SETUP_PROGRESS_BYTES as usize + 1]).unwrap();
    assert_eq!(read_setup_progress(&base, &plan_id).unwrap_err(), "PROGRESS_TOO_LARGE");
    let _ = fs::remove_dir_all(base);
  }
  #[test]
  fn setup_recovery_exposes_only_an_interrupted_matching_plan() {
    let base = env::temp_dir().join(format!("assemblelink-recovery-test-{}", std::process::id()));
    fs::create_dir_all(base.join("state")).unwrap();
    let plan_id = "c".repeat(64);
    fs::write(base.join("state").join(format!("setup_plan.{plan_id}.json")), serde_json::to_vec(&serde_json::json!({
      "schema":"assemblelink.setup_plan.v1","plan_id":plan_id,"plan_type":"setup",
      "items":[{"id":"manual","name":"Manual Tool","source":"official_manual","winget_id":"","license":"manual_review","admin_required":false,"reboot_required":false,"dependencies":[],"mode":"manual_review","status":"manual_review_required","extra":"removed"}]
    })).unwrap()).unwrap();
    fs::write(base.join("state/setup_execution.progress.json"), serde_json::to_vec(&serde_json::json!({
      "schema":"assemblelink.setup_execution.progress.v1","plan_id":plan_id,"status":"running","total":1,"completed":0,"results":[]
    })).unwrap()).unwrap();
    let recovery = read_setup_recovery(&base).unwrap();
    assert_eq!(recovery["available"], true);
    assert_eq!(recovery["plan"]["items"][0]["name"], "Manual Tool");
    assert!(recovery["plan"]["items"][0].get("extra").is_none());
    let mut complete = recovery["progress"].clone();
    complete["status"] = serde_json::json!("complete");
    complete["completed"] = serde_json::json!(1);
    complete["results"] = serde_json::json!([{"id":"manual","name":"Manual Tool","winget_id":"","status":"manual_review_required","verified":false,"source_verified":false,"message":"Manual"}]);
    fs::write(base.join("state/setup_execution.progress.json"), serde_json::to_vec(&complete).unwrap()).unwrap();
    assert_eq!(read_setup_recovery(&base).unwrap()["available"], false);
    let _ = fs::remove_dir_all(base);
  }
  #[test]
  fn machine_blueprint_selection_uses_only_installed_catalog_identities() {
    let intelligence = serde_json::json!({"items":[
      {"installed":true,"catalog_id":"git"},
      {"installed":true,"catalog_id":"git"},
      {"installed":true,"catalog_id":"node-js"},
      {"installed":true,"catalog_id":""},
      {"installed":true},
      {"installed":false,"catalog_id":"python"}
    ]});
    let (ids, unmatched) = installed_catalog_ids(&intelligence);
    assert_eq!(ids, vec!["git", "node-js"]);
    assert_eq!(unmatched, 2);
  }
  #[test]
  fn workstation_assurance_verifies_sources_and_rejects_fixture_or_tampered_state() {
    let base = env::temp_dir().join(format!("assemblelink-assurance-test-{}", std::process::id()));
    let state = base.join("state"); let catalog_dir = base.join("catalog");
    fs::create_dir_all(&state).unwrap(); fs::create_dir_all(&catalog_dir).unwrap();
    let write_sealed = |path: &Path, value: &serde_json::Value| {
      let mut bytes = serde_json::to_vec(value).unwrap(); bytes.push(b'\n'); fs::write(path, &bytes).unwrap();
      fs::write(format!("{}.sha256", path.to_string_lossy()), format!("{}  {}\n", sha256_hex(&bytes), path.file_name().unwrap().to_string_lossy())).unwrap();
    };
    write_sealed(&state.join("system_profile.latest.json"), &serde_json::json!({"schema":"assemblelink.system_profile.v2","observed_utc":"2026-01-01T00:00:00Z","observation_status":"complete","machine":{"name":"fixture"},"os":{"caption":"Windows","build":"1"},"cpu":{"name":"CPU"},"memory":{"total_gb":32},"gpu":[{"name":"GPU","vram_confidence":"unknown"}],"storage":{"drives":[{"drive":"C:","free_percent":5.0}]}}));
    write_sealed(&state.join("driver_profile.latest.json"), &serde_json::json!({"schema":"assemblelink.driver_profile.v2","observed_utc":"2026-01-01T00:00:00Z","observation_status":"complete","recommendations":[]}));
    let software_path = state.join("software_intelligence.latest.json");
    write_sealed(&software_path, &serde_json::json!({"schema":"assemblelink.software_intelligence.v1","observed_utc":"2026-01-01T00:00:00Z","evidence_mode":"live","summary":{"detected":10,"catalog_matched":5,"unmatched":5,"updates_available":0,"unknown":2}}));
    fs::write(catalog_dir.join("approved_software_sources.v1.json"), br#"{"items":[{"id":"git"}]}"#).unwrap();
    let assurance = build_workstation_assurance(&base).unwrap();
    assert_eq!(assurance["schema"], "assemblelink.workstation_assurance.v1"); assert_eq!(assurance["status"], "critical_attention");
    write_workstation_assurance(&base, &assurance).unwrap();
    let latest_assurance = state.join("workstation_assurance.latest.json");
    let latest_bytes = fs::read(&latest_assurance).unwrap();
    let expected = fs::read_to_string(format!("{}.sha256", latest_assurance.to_string_lossy())).unwrap().split_whitespace().next().unwrap().to_owned();
    assert_eq!(expected, sha256_hex(&latest_bytes));
    let receipt_summary = receipt_index(&base).unwrap(); assert_eq!(receipt_summary["summary"]["valid"], 1);
    fs::write(&software_path, br#"{"schema":"assemblelink.software_intelligence.v1"}"#).unwrap();
    assert!(build_workstation_assurance(&base).unwrap_err().contains("ASSURANCE_HASH_REJECTED"));
    write_sealed(&software_path, &serde_json::json!({"schema":"assemblelink.software_intelligence.v1","evidence_mode":"fixture","summary":{}}));
    assert_eq!(build_workstation_assurance(&base).unwrap_err(), "ASSURANCE_FIXTURE_EVIDENCE_REJECTED");
    let _ = fs::remove_dir_all(base);
  }
}
