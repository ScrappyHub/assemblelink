import test from "node:test";
import assert from "node:assert/strict";
import { shortVersion, versionState, versionSummary, lastInstallByWingetId, formatWhen } from "../src/lib.js";

test("shortVersion strips commit tails and truncates", () => {
  assert.equal(shortVersion("7.6.6 SHA: 078a44cc9f3e1b2aa"), "7.6.6");
  assert.equal(shortVersion("8.0.100 @Commit: 901ca1f2"), "8.0.100");
  assert.equal(shortVersion(null), "");
  assert.equal(shortVersion("1.2.3.4.5.6.7.8.9.10.11.12").length, 18);
});

test("versionState never reports unknown or untracked as current", () => {
  assert.equal(versionState({update_status:"current",version:"1.0"}).key, "current");
  assert.equal(versionState({update_status:"update_available",version:"1.0",available_version:"2.0"}).label, "Update to 2.0");
  assert.equal(versionState({update_status:"installed_version_unknown"}).key, "unknown");
  assert.equal(versionState({update_status:"unmatched"}).key, "unmatched");
  assert.equal(versionState({}).key, "unmatched");
  assert.equal(versionState({update_status:"something_new"}).key, "unmatched");
});

test("versionSummary counts every item exactly once", () => {
  const s = versionSummary([{update_status:"current"},{update_status:"update_available"},{update_status:"installed_version_unknown"},{update_status:"unmatched"},{}]);
  assert.deepEqual(s, {total:5,update:1,current:1,unknown:1,unmatched:2});
  assert.deepEqual(versionSummary(null), {total:0,update:0,current:0,unknown:0,unmatched:0});
});

test("lastInstallByWingetId uses the newest real run and ignores dry runs", () => {
  const history = {runs:[
    {executed:false,completed_utc:"2026-03-01T00:00:00Z",results:[{winget_id:"Git.Git",status:"dry"}]},
    {executed:true,completed_utc:"2026-02-01T00:00:00Z",integrity:"valid",results:[{winget_id:"Git.Git",status:"installed"}]},
    {executed:true,completed_utc:"2026-01-01T00:00:00Z",results:[{winget_id:"Git.Git",status:"old"}]},
  ]};
  const m = lastInstallByWingetId(history);
  assert.equal(m.get("git.git").status, "installed");
  assert.equal(m.get("git.git").integrity, "valid");
  assert.equal(lastInstallByWingetId(null).size, 0);
});

test("formatWhen tolerates bad input", () => {
  assert.equal(formatWhen(0), "Unknown");
  assert.equal(formatWhen("not a date"), "Unknown");
  assert.notEqual(formatWhen("2026-01-01T00:00:00Z"), "Unknown");
});
