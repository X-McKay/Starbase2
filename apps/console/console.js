"use strict";
const $ = (s) => document.querySelector(s),
  esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
const terminal = (s) => ["completed", "failed", "cancelled"].includes(s),
  pretty = (s) => String(s ?? "unknown").replaceAll("_", " "),
  stamp = (s) => new Date(s * 1000).toLocaleString();
let snapshot = null,
  connected = false,
  busy = false,
  before = null,
  page = [],
  selected = null,
  lastSeen = 0,
  rowsSignature = "",
  crewSignature = "",
  dutySignature = "",
  progressionSignature = "";
async function api(path, body) {
  const r = await fetch(
    path,
    body === undefined
      ? {}
      : {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        },
  );
  if (!r.ok) {
    let message = "Request failed (" + r.status + ")";
    try {
      message = (await r.json()).error || message;
    } catch {}
    if (r.status === 403)
      message =
        "Operator session expired or denied. Reload the journal and try again.";
    throw Error(message);
  }
  return r.json();
}
function notice(message) {
  $("#notice").textContent = message;
  if ($("#inspector").open) $("#inspection-notice").textContent = message;
}
function stableRender(selector, html, key) {
  if (key === "crew" && html === crewSignature) return;
  if (key === "duty" && html === dutySignature) return;
  if (key === "rows" && html === rowsSignature) return;
  const id = document.activeElement?.id;
  $(selector).innerHTML = html;
  if (id && document.getElementById(id))
    document.getElementById(id).focus({ preventScroll: true });
  if (key === "crew") crewSignature = html;
  if (key === "duty") dutySignature = html;
  if (key === "rows") rowsSignature = html;
}
function badge(value) {
  return `<span class="badge ${esc(value)}">${esc(pretty(value))}</span>`;
}
function render() {
  const active = snapshot.active,
    activeCount =
      active.length +
      (snapshot.repairs || []).filter((r) => !terminal(r.state)).length,
    worker = connected && snapshot.worker.available;
  $("#connection").textContent = worker
    ? "Core connected · worker available"
    : "Core connected · worker unavailable";
  $("#connection").className = "connection" + (worker ? " live" : "");
  $("#station-state").textContent = activeCount
    ? `${activeCount} active run${activeCount === 1 ? "" : "s"}. ${worker ? "Follow the live records below." : "Dispatch or progress may be delayed."}`
    : "No active runs. Choose a review, or start a controlled experiment.";
  stableRender(
    "#crew",
    snapshot.crew
      .map((c) => {
        const runs =
          c.id === "mender"
            ? (snapshot.repairs || []).filter((r) => !terminal(r.state))
            : active.filter(
                (r) =>
                  (r.input.request.kind === "evaluation") ===
                  (c.id === "trainer"),
              );
        return `<article class="crew-card"><span class="avatar" aria-hidden="true">${c.id === "trainer" ? "◇" : "⌁"}</span><div><h3>${esc(c.name)}</h3><p>${esc(c.role)} · ${c.xp} verified XP</p></div><span class="crew-state">${worker ? (runs.length ? `${runs.length} active · ${esc(pretty(runs[0].state))}` : "Idle · no assigned work") : "Worker unavailable"}</span></article>`;
      })
      .join(""),
    "crew",
  );
  stableRender(
    "#duty-list",
    snapshot.duties
      .map(
        (d) =>
          `<div class="duty-row"><span><strong>${esc(d.id)}</strong> · ${esc(d.target)} · every ${d.interval_seconds}s · ${d.enabled ? "enabled" : "paused"}<br><small>Configuration ${d.generation}; worker ${worker ? "reconciling durable timer" : "unavailable"}</small></span><button id="duty-${esc(d.id)}" class="ghost" data-duty="${esc(d.id)}">${d.enabled ? "Pause" : "Resume"}</button></div>`,
      )
      .join(""),
    "duty",
  );
  const activeOnly = $("#run-view").value === "active";
  const rows = activeOnly
    ? snapshot.active
    : before === null
      ? snapshot.recent
      : page;
  page = rows;
  stableRender(
    "#runs",
    rows.length
      ? rows
          .map((r) => {
            const i = r.input.request,
              summary = r.report?.summary;
            return `<tr><td>${esc(i.id)}<small>${esc(i.target)} · ${i.kind === "evaluation" || i.target === "sample" ? "synthetic input" : "real local input"}</small></td><td>${esc(pretty(i.kind))}<small>${esc(i.profile)}</small></td><td>${badge(!terminal(r.state) && !worker ? "unknown" : r.state)}${!terminal(r.state) && !worker ? "<small>Last known: " + esc(pretty(r.state)) + "</small>" : ""}</td><td>${summary ? badge(summary.outcome) : "<small>No retained result</small>"}</td><td><button id="inspect-${esc(i.id)}" class="ghost" data-inspect="${esc(i.id)}">Inspect ↗</button></td></tr>`;
          })
          .join("")
      : `<tr><td colspan="5">${activeOnly ? "No active runs." : "The journal is empty. Start a review above."}</td></tr>`,
    "rows",
  );
  renderRepairs();
  $("#older").disabled = activeOnly || rows.length < 20;
  $("#latest").disabled = activeOnly || before === null;
}
async function refresh() {
  if (busy) return;
  busy = true;
  try {
    const s = await api("/v2/snapshot");
    if (
      s.schema_version !== 2 ||
      !Array.isArray(s.active) ||
      !Array.isArray(s.recent)
    )
      throw Error("Unsupported snapshot");
    snapshot = s;
    connected = true;
    lastSeen = Date.now();
    render();
  } catch (error) {
    connected = false;
    if (snapshot) render();
    $("#connection").textContent = "Disconnected · last-known state";
    $("#connection").className = "connection";
    $("#station-state").textContent =
      "Current activity is unknown. Last response " +
      (lastSeen
        ? Math.round((Date.now() - lastSeen) / 1000) + " seconds ago."
        : "not received.");
    $("#crew").textContent =
      "Current crew state unknown; reconnect to refresh authoritative records.";
    crewSignature = "";
  } finally {
    busy = false;
  }
}
async function submit(form, fn) {
  const button = form.querySelector('button[type="submit"]');
  button.disabled = true;
  try {
    await fn();
  } catch (error) {
    notice(error.message);
  } finally {
    button.disabled = false;
  }
}
$("#target").onchange = () => {
  $("#inference").disabled = $("#target").value !== "sample";
  if ($("#inference").disabled) $("#inference").checked = false;
};
$("#review-form").onsubmit = (e) => {
  e.preventDefault();
  submit(e.currentTarget, async () => {
    const id = "review-" + crypto.randomUUID();
    await api("/v2/runs", {
      id,
      kind: "review",
      target: $("#target").value,
      profile: $("#profile").value,
      candidate: null,
      inference: $("#inference").checked,
    });
    before = null;
    notice(
      "Review queued. Temporal will dispatch the frozen build; results appear in the journal.",
    );
    await refresh();
  });
};
$("#evaluation-form").onsubmit = (e) => {
  e.preventDefault();
  submit(e.currentTarget, async () => {
    if ($("#baseline").value === $("#candidate").value)
      throw Error("Choose different baseline and candidate profiles.");
    await api("/v2/runs", {
      id: "gym-" + crypto.randomUUID(),
      kind: "evaluation",
      target: "sample",
      profile: $("#baseline").value,
      candidate: $("#candidate").value,
      inference: false,
    });
    before = null;
    notice(
      "Comparison queued: all twelve trials will be retained, including failures.",
    );
    await refresh();
  });
};
$("#duty-form").onsubmit = (e) => {
  e.preventDefault();
  submit(e.currentTarget, async () => {
    await api("/v2/duties", {
      id: "repository-watch",
      target: $("#duty-target").value,
      profile: "surveyor-v2",
      interval_seconds: Number($("#interval").value),
      enabled: true,
      generation: 0,
    });
    notice("Recurring review enabled. First tick occurs after the interval.");
    await refresh();
  });
};
$("#duty-list").onclick = async (e) => {
  const button = e.target.closest("[data-duty]");
  if (!button) return;
  const d = snapshot.duties.find((d) => d.id === button.dataset.duty);
  try {
    await api("/v2/duties", { ...d, enabled: !d.enabled });
    await refresh();
  } catch (error) {
    notice(error.message);
  }
};
$("#runs").onclick = (e) => {
  const b = e.target.closest("[data-inspect]");
  if (b) inspect(b.dataset.inspect);
};
$("#run-view").onchange = () => {
  before = null;
  if (snapshot) render();
};
$("#refresh").onclick = refresh;
$("#latest").onclick = () => {
  before = null;
  refresh();
};
$("#older").onclick = async () => {
  if (!page.length) return;
  try {
    before = page.at(-1).sequence;
    page = (await api("/v2/runs?before=" + before)).runs;
    render();
  } catch (error) {
    notice(error.message);
  }
};
$("#close").onclick = () => $("#inspector").close();
async function inspect(id) {
  selected = id;
  try {
    const r = await api("/v2/runs/" + encodeURIComponent(id));
    const i = r.input.request,
      report = r.report,
      review = report?.evidence?.review,
      summary = report?.summary;
    let html = `<h2>${esc(id)}</h2><p>${esc(pretty(i.kind))} · ${esc(i.target)} · ${esc(stamp(r.created_at))}</p>${badge(r.state)}<p>${esc(r.detail)}</p><small>Record observed ${esc(new Date().toLocaleString())}. Refresh evidence for current state.</small><div class="actions">${!terminal(r.state) ? '<button id="stop-run" class="secondary">Request stop</button>' : '<button id="repeat-run" class="secondary">Run again with current build</button>'}<button id="refresh-detail" class="ghost">Refresh evidence</button><a href="/v2/runs/${encodeURIComponent(id)}" target="_blank" rel="noopener">Raw record ↗</a></div>`;
    if (summary) {
      html += `<h3>Recorded result: ${esc(pretty(summary.outcome))}</h3><p>${esc(summary.qualification)}</p>`;
      if (i.kind === "evaluation") {
        html += `<div class="stats"><div><strong>${summary.baseline_passed} / ${summary.cases}</strong>Baseline cases passed</div><div><strong>${summary.candidate_passed} / ${summary.cases}</strong>Candidate cases passed</div><div><strong>${summary.trials}</strong>Retained trials</div></div><p>${esc(summary.uncertainty)}</p><p>Hard gates: ${esc(JSON.stringify(summary.hard_gate_failures))}</p><table><thead><tr><th>Case</th><th>Profile</th><th>Observed codes</th><th>Time</th></tr></thead><tbody>${report.evidence.trials.map((t) => `<tr><td>${esc(t.case_id)}</td><td>${esc(t.profile)}</td><td>${esc(t.report.findings.map((f) => f.code).join(", ") || "none")}</td><td>${t.report.elapsed_ms}ms</td></tr>`).join("")}</tbody></table>`;
      }
    }
    if (review) {
      html += `<div class="stats"><div><strong>${review.files_reviewed}</strong>Python files analyzed</div><div><strong>${review.findings.length}</strong>Static warnings</div><div><strong>${review.elapsed_ms}ms</strong>Analysis time</div></div><p>${review.findings.length ? "Review these warnings in context before acting." : "The configured structural checks found no warnings. This is not a safety certificate."}</p>`;
      for (const f of review.findings) {
        const source = r.snapshot.files.find((s) => s.path === f.file);
        const lines = source?.source.split("\n") || [];
        html += `<article class="finding"><strong>${esc(f.code)} · ${esc(f.file)}:${f.line}</strong><p>${esc(f.message)}</p><pre>${esc(
          lines
            .slice(Math.max(0, f.line - 2), f.line + 1)
            .map((line, k) => `${Math.max(1, f.line - 1) + k}  ${line}`)
            .join("\n"),
        )}</pre></article>`;
      }
      if (review.errors.length)
        html += `<h3>Incomplete coverage</h3><pre>${esc(JSON.stringify(review.errors, null, 2))}</pre>`;
      if (review.advisory) {
        const a = review.advisory;
        html += `<h3>Model explanation · ${esc(a.status)}</h3><p>${esc(a.qualification)}</p>${a.advice ? `<p>${esc(a.advice.summary)}</p><p>${esc(a.advice.recommendation)}</p>` : `<p>Inference did not produce valid advice: ${esc(a.failure)}. Static evidence remains available.</p>`}<small>${esc(a.requested_model)} · ${a.calls} request · ${a.elapsed_ms}ms · cost unknown</small><details><summary>Provider usage and provenance</summary><pre>${esc(JSON.stringify(a, null, 2))}</pre></details>`;
      }
    }
    html += `<h3>Durable activity trail</h3><ol class="timeline">${r.events.map((e) => `<li><strong>${esc(pretty(e.state))}</strong> · ${esc(stamp(e.at))}<br>${esc(e.detail)}</li>`).join("")}</ol><details><summary>Frozen build manifests</summary><pre>${esc(JSON.stringify(r.input.builds, null, 2))}</pre></details>${r.snapshot ? `<details><summary>Source snapshot · ${esc(r.snapshot.digest.slice(0, 16))}</summary><p>String literals and comments masked. Original content hashes retained. Source is never executed.</p><pre>${esc(JSON.stringify(r.snapshot, null, 2))}</pre></details>` : ""}`;
    $("#inspection").innerHTML = html;
    if (!$("#inspector").open) $("#inspector").showModal();
    $("#refresh-detail").onclick = () => inspect(id);
    if ($("#stop-run"))
      $("#stop-run").onclick = async () => {
        try {
          await api("/v2/runs/" + id + "/cancel", {});
          await inspect(id);
          await refresh();
        } catch (error) {
          notice(error.message);
        }
      };
    if ($("#repeat-run"))
      $("#repeat-run").onclick = async () => {
        try {
          const next = { ...i, id: i.kind + "-" + crypto.randomUUID() };
          await api("/v2/runs", next);
          await inspect(next.id);
          before = null;
          await refresh();
        } catch (error) {
          notice(error.message);
        }
      };
  } catch (error) {
    notice(error.message);
  }
}
refresh();
setInterval(refresh, 1500);

function renderRepairs() {
  const repairs = snapshot.repairs || [],
    p = snapshot.progression;
  const worker = connected && snapshot.worker.available;
  const html =
    repairs
      .slice(0, 40)
      .map(
        (r) =>
          `<article class="repair-row"><div><strong>${esc(r.input.scenario)}</strong> · ${esc(r.input.mode)}<small>${esc(r.input.id)}</small></div><div>${badge(!terminal(r.state) && !worker ? "unknown" : r.state)} ${r.summary ? badge(r.summary.outcome) : ""}<small>${esc(r.detail)}</small></div><button class="ghost" data-repair="${esc(r.input.id)}">Inspect repair ↗</button></article>`,
      )
      .join("") || "No repair missions yet.";
  if ($("#repair-list").innerHTML !== html) {
    const id = document.activeElement?.dataset?.repair;
    $("#repair-list").innerHTML = html;
    if (id)
      [...document.querySelectorAll("[data-repair]")]
        .find((b) => b.dataset.repair === id)
        ?.focus({ preventScroll: true });
  }
  if (!p) return;
  const progressionHTML = `<div class="progression-summary"><strong>${esc(p.name)} · Level ${p.level}</strong><span>${p.xp} / ${p.next_level_xp} XP</span></div><progress aria-label="Experience toward next level" value="${p.xp}" max="${p.next_level_xp}"></progress><p>${p.achievements.map(esc).join(" · ") || "No verified achievements yet."}</p><p>25 XP for each distinct verified AI repair. Repeats and deterministic controls earn no additional XP.</p><p><strong>Authority:</strong> ${esc(p.authority)}</p><details><summary>Outcome ledger (${p.credits.length}) and exact-build qualifications (${p.qualifications.length})</summary><ul>${p.credits.map((c) => `<li>+${c.xp} XP · <a href="/v3/repairs/${encodeURIComponent(c.run_id)}" target="_blank" rel="noopener">${esc(c.run_id)}</a> · ${esc(c.outcome_key)}</li>`).join("") || "<li>No credit recorded.</li>"}</ul><pre>${esc(JSON.stringify(p.qualifications, null, 2))}</pre></details>`;
  if (progressionHTML !== progressionSignature) {
    const open = $("#progression-detail details")?.open;
    $("#progression-detail").innerHTML = progressionHTML;
    if (open) $("#progression-detail details").open = true;
    progressionSignature = progressionHTML;
  }
}
$("#repair-form").onsubmit = (e) => {
  e.preventDefault();
  submit(e.currentTarget, async () => {
    await api("/v3/repairs", {
      id: "repair-" + crypto.randomUUID(),
      scenario: $("#repair-scenario").value,
      mode: $("#repair-mode").value,
    });
    notice(
      "Repair queued. Follow the retained proposal, isolated executions, and core verdict below.",
    );
    await refresh();
  });
};
$("#repair-list").onclick = (e) => {
  const id = e.target.closest("[data-repair]")?.dataset.repair;
  if (id) inspectRepair(id).catch((error) => notice(error.message));
};
async function inspectRepair(id) {
  const r = await api("/v3/repairs/" + encodeURIComponent(id));
  const dialog = $("#repair-inspector"),
    body = $("#repair-body");
  body.innerHTML = `<p class="eyebrow">SYNTHETIC TASK · REAL MICROVM EXECUTION</p><h2>${esc(r.input.scenario)}</h2><p>${esc(r.input.id)}</p><p>${badge(r.state)} ${r.summary ? badge(r.summary.outcome) : ""}</p>${repairVerdict(r)}<p>Observed ${new Date().toLocaleTimeString()}. Refresh to update.</p><p>${esc(r.task)}</p><p>${esc(r.detail)}</p><h3>Proposal</h3><p>${esc(r.proposal?.rationale || "No proposal retained.")}</p>${r.proposal ? `<a href="/v3/repairs/${encodeURIComponent(id)}/patch" target="_blank" rel="noopener">Open unified diff ↗</a><div class="source-pair"><div><h4>Original solution.py</h4><pre>${esc(r.baseline)}</pre></div><div><h4>Proposed solution.py</h4><pre>${esc(r.proposal.source)}</pre></div></div>` : ""}<details><summary>Full grading record and uncertainty</summary><pre>${esc(JSON.stringify(r.summary || { outcome: "No retained result" }, null, 2))}</pre></details><details><summary>Action ledger and raw execution observations</summary><pre>${esc(JSON.stringify(r.actions, null, 2))}</pre></details><details><summary>Inference provenance and build manifest</summary><pre>${esc(JSON.stringify({ revision: r.revision, inference: r.proposal?.inference, build: r.build, events: r.events }, null, 2))}</pre></details><p><a href="/v3/repairs/${encodeURIComponent(id)}" target="_blank" rel="noopener">Full retained record ↗</a></p>`;
  $("#repair-refresh").onclick = () =>
    inspectRepair(id).catch((error) => notice(error.message));
  $("#repair-stop").disabled =
    terminal(r.state) || r.state === "cancel_requested";
  $("#repair-stop").onclick = async () => {
    try {
      await api("/v3/repairs/" + encodeURIComponent(id) + "/cancel", {});
      await inspectRepair(id);
      await refresh();
    } catch (error) {
      $("#repair-status").textContent = error.message;
    }
  };
  $("#repair-status").textContent = "";
  if (!dialog.open) dialog.showModal();
}

function repairVerdict(r) {
  const s = r.summary;
  if (!s) return "<p>No independent verdict retained yet.</p>";
  const baseline = s.trials.find((t) => t.stage === "baseline"),
    candidate = s.trials.find((t) => t.stage === "candidate");
  return `<div class="verdict-metrics"><strong>Original ${s.baseline_passed}/${s.cases}</strong><strong>Candidate ${s.candidate_passed}/${s.cases}</strong><strong>+${s.xp_awarded} verified XP</strong></div><p>${esc(s.qualification)}</p><details><summary>Inspect ${s.cases} independent case results</summary><div class="table-wrap"><table><thead><tr><th>Input</th><th>Expected</th><th>Original</th><th>Candidate</th></tr></thead><tbody>${Array.from({ length: s.cases }, (_, i) => `<tr><td>${esc(JSON.stringify(r.actions[0]?.inputs[i]))}</td><td>${esc(JSON.stringify(baseline.expected[i]))}</td><td>${baseline.passed[i] ? "Pass" : "Fail"} · ${esc(JSON.stringify(baseline.observed?.[i]))}</td><td>${candidate.passed[i] ? "Pass" : "Fail"} · ${esc(JSON.stringify(candidate.observed?.[i]))}</td></tr>`).join("")}</tbody></table></div></details>`;
}
