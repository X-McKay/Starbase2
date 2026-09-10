(() => {
  const section = document.createElement("section");
  section.id = "field-agents"; section.className = "card";
  section.innerHTML = `<span class="eyebrow">FIELD CREW / READ-ONLY DUTIES</span>
    <h2>Watchkeeper &amp; PR Reviewer</h2>
    <p>Observe scoped cluster workloads or prepare a local PR review draft. No cluster changes or GitHub publication.</p>
    <form id="field-form"><label>Configured target <select id="field-target"></select></label>
    <label class="check"><input id="field-inference" type="checkbox"> Add unverified AI advice (authorized targets only)</label>
    <button id="field-submit">Start observation</button></form>
    <p id="field-notice" role="status"></p><div id="field-history"></div>
    <h3>Watched repositories</h3>
    <p>GitHub owner/repository. Checks up to 10 recently updated open PRs for changed Python findings. No publication or automatic AI calls. Pausing/removing stops future dispatch; active runs have separate Stop controls.</p>
    <form id="watch-form"><label>Repository <input id="watch-repository" placeholder="owner/repository" maxlength="201" required></label>
    <label>Check every (seconds) <input id="watch-interval" type="number" min="30" max="86400" value="300" required></label>
    <button id="watch-save">Watch repository</button></form><div id="repository-watches"></div>
    <details><summary>Removed watches (history retained)</summary><div id="removed-watches"></div></details>
    <h3>Recurring observation</h3>
    <p>Uses the selected target. Optional AI reasoning shares its daily limit and minimum interval with manual observations. Skipped reasoning never stops observation. Pausing stops future dispatch; stop an active run separately.</p>
    <form id="field-duty-form"><label>Duty ID <input id="field-duty-id" pattern="[a-zA-Z0-9-]{1,40}" maxlength="40" required></label>
    <label>Interval in seconds <input id="field-duty-interval" type="number" min="30" max="86400" value="300" required></label>
    <label class="check"><input id="field-duty-inference" type="checkbox"> Request recurring AI reasoning within target limits</label>
    <button id="field-duty-submit">Enable or update duty</button></form><div id="field-duties"></div>
    <h3>Reviewed agent memory</h3><p>Approve a sourced observation for future recall, or revoke it. Memory never grants permission.</p>
    <div id="field-memory"></div><pre id="field-evidence" style="white-space:pre-wrap;overflow-wrap:anywhere"></pre>`;
  document.querySelector("main").append(section);
  const target = section.querySelector("#field-target");
  const submit = section.querySelector("#field-submit");
  const notice = section.querySelector("#field-notice");
  const evidence = section.querySelector("#field-evidence");
  let snapshot = null, busy = false, refreshing = false, signature = "";
  const button = (parent, title, fn) => {
    const b = document.createElement("button"); b.type = "button"; b.textContent = title;
    b.onclick = () => fn().catch(e => notice.textContent = e.message); parent.append(b); return b;
  };
  async function post(path, body) {
    const response = await fetch(path, {method:"POST",credentials:"same-origin",
      headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
    if (!response.ok) throw Error("Request rejected or unavailable; refresh before retrying.");
    return response.json();
  }
  section.querySelector("#field-form").onsubmit = async e => {
    e.preventDefault(); if (busy || !snapshot) return;
    const build = snapshot.builds.find(b => b.digest === target.value); if (!build) return;
    busy = true; submit.disabled = true;
    const id = crypto.randomUUID();
    try {
      await post("/v4/runs",{id,agent:build.manifest.agent,target:build.manifest.target.id,
        inference:section.querySelector("#field-inference").checked});
      notice.textContent = "Queued " + id; await refresh();
    } catch (e) {
      notice.textContent = e.message + " Request ID: " + id + ". Check history for an accepted run.";
    } finally { busy=false; submit.disabled=!snapshot?.enabled; }
  };
  section.querySelector("#field-duty-form").onsubmit = async e => {
    e.preventDefault(); if (!snapshot || !snapshot.enabled || busy) return;
    const build = snapshot.builds.find(b=>b.digest===target.value); if (!build) return;
    const id=section.querySelector("#field-duty-id").value;
    const previous=snapshot.duties.find(d=>d.id===id);
    busy=true;
    try {
      await post("/v4/duties",{id,agent:build.manifest.agent,target:build.manifest.target.id,
        interval_seconds:Number(section.querySelector("#field-duty-interval").value),enabled:true,
        inference:section.querySelector("#field-duty-inference").checked,
        generation:previous ? previous.generation+1 : 0});
      notice.textContent="Duty saved. First observation follows its interval."; await refresh();
    } catch(e) { notice.textContent=e.message+" Check the duty list before retrying."; }
    finally { busy=false; }
  };
  section.querySelector("#field-duty-id").oninput = () => {
    const old=snapshot?.duties.find(d=>d.id===section.querySelector("#field-duty-id").value);
    if(old) section.querySelector("#field-duty-inference").checked=old.inference===true;
  };
  section.querySelector("#watch-form").onsubmit = async e => {
    e.preventDefault(); if (!snapshot?.enabled || busy) return;
    const repository=section.querySelector("#watch-repository").value.trim().toLowerCase();
    const old=snapshot.repositories.find(w=>w.config.repository===repository);
    busy=true;
    try {
      await post("/v4/repositories",{repository,interval_seconds:Number(section.querySelector("#watch-interval").value),enabled:true,removed:false,generation:old?old.config.generation+1:0});
      notice.textContent="Watch saved. First check follows the interval; use Observe now after the worker registers it.";
      await refresh();
    } catch(e) { notice.textContent=e.message+" Refresh the watch list before retrying."; }
    finally {busy=false;}
  };
  function showEvidence(run) {
    evidence.replaceChildren();
    const title=document.createElement("h3"); title.textContent=run.input.target+" · "+run.state; evidence.append(title);
    const summary=document.createElement("p"); summary.textContent=run.detail+" · "+(!run.snapshot?"No source captured":run.snapshot.data?.simulation?"SYNTHETIC":"Retained source")+" · "+new Date(run.updated_at*1000).toLocaleString(); evidence.append(summary);
    for(const f of run.report?.findings || []) {const p=document.createElement("p");p.textContent=f.code+" · "+f.subject+":"+f.line+" — "+f.summary+" "+f.recommendation;evidence.append(p);}
    for(const c of run.report?.coverage || []) {const p=document.createElement("p");p.textContent="Coverage limit: "+c;evidence.append(p);}
    const budget=run.inference_budget;
    if(budget) {const p=document.createElement("p");p.textContent="AI admission: "+budget.status+" · "+budget.reason+" · "+budget.used+"/"+budget.limit+" reserved this UTC day";evidence.append(p);}
    const advice=run.report?.advisory;
    if(advice) {const p=document.createElement("p");p.textContent="AI advice: "+advice.status+" · "+(advice.reason || advice.advice?.summary || "No explanation retained")+(advice.advice?.recommendation?" · "+advice.advice.recommendation:"");evidence.append(p);}
    const raw=document.createElement("details"), label=document.createElement("summary"), pre=document.createElement("pre");label.textContent="Source, revisions and full evidence";pre.textContent=JSON.stringify(run,null,2);raw.append(label,pre);evidence.append(raw);
  }
  async function refresh() {
    if (refreshing) return;
    refreshing=true;
    try {
      const response = await fetch("/v4/snapshot"); if (!response.ok) throw Error("Unavailable");
      snapshot = await response.json(); submit.disabled=busy || !snapshot.enabled;
      section.querySelector("#field-duty-submit").disabled=busy || !snapshot.enabled;
      section.querySelector("#watch-save").disabled=busy || !snapshot.enabled;
      const sig = JSON.stringify({...snapshot,observed_at:0,freshnessMinute:Math.floor(Date.now()/60000)});
      if (sig===signature) return; signature=sig;
      const selected=target.value; target.replaceChildren();
      const seen=new Set();
      for (const b of snapshot.builds) {
        const m=b.manifest, key=m.agent+"/"+m.target.id;
        if (m.target.id.startsWith("repo-")) continue;
        if (seen.has(key)) continue; seen.add(key);
        const option=document.createElement("option"); option.value=b.digest;
        option.textContent=m.agent+" · "+m.target.id+(m.target.kind==="fixture"?" · SYNTHETIC":" · LIVE SOURCE");
        target.append(option);
      }
      if ([...target.options].some(o=>o.value===selected)) target.value=selected;
      const history=section.querySelector("#field-history"); history.replaceChildren();
      for (const run of snapshot.runs.slice(0,20)) {
        const row=document.createElement("p");
        row.textContent=run.input.agent+" · "+run.input.target+" · "+run.state+" ";
        button(row,"Inspect evidence",async()=>{const r=await fetch("/v4/runs/"+encodeURIComponent(run.input.id)); if(!r.ok) throw Error("Evidence unavailable"); showEvidence(await r.json());});
        if (!["completed","failed","cancelled"].includes(run.state))
          button(row,"Stop",async()=>{await post("/v4/runs/"+encodeURIComponent(run.input.id)+"/cancel",{});await refresh();});
        history.append(row);
      }
      const watches=section.querySelector("#repository-watches"), removed=section.querySelector("#removed-watches"); watches.replaceChildren(); removed.replaceChildren();
      for (const w of snapshot.repositories || []) {
        const c=w.config, row=document.createElement("p");
        const last=snapshot.runs.find(r=>r.input.target===w.id);
        const stale=last && Date.now()/1000-last.updated_at>c.interval_seconds*2+480;
        row.textContent=c.repository+" · "+(c.removed?"removed":c.enabled?"watch enabled":"paused")+" · every "+c.interval_seconds+"s · "+(last?(stale?"STALE · ":"")+last.state+" · "+new Date(last.updated_at*1000).toLocaleString():"not yet observed")+" ";
        const edit=async patch=>{await post("/v4/repositories",{...c,...patch,generation:c.generation+1});await refresh();};
        button(row,c.removed?"Restore":c.enabled?"Pause":"Resume",()=>edit({enabled:!c.enabled,removed:false})).disabled=!snapshot.enabled&&!c.enabled;
        if(!c.removed) button(row,"Remove",()=>edit({enabled:false,removed:true}));
        if(last) button(row,"Latest findings",async()=>{const r=await fetch("/v4/runs/"+encodeURIComponent(last.input.id));if(!r.ok)throw Error("Evidence unavailable");showEvidence(await r.json());});
        const registered=snapshot.builds.some(b=>b.manifest.target.id===w.id);
        if(c.enabled&&!c.removed) button(row,"Observe now",async()=>{const id=crypto.randomUUID();await post("/v4/runs",{id,agent:"reviewer",target:w.id,inference:false});await refresh();}).disabled=!snapshot.enabled||!registered;
        (c.removed?removed:watches).append(row);
      }
      if(!snapshot.repositories?.some(w=>!w.config.removed)) watches.textContent="No repositories watched. Add an explicit repository above.";
      const duties=section.querySelector("#field-duties"); duties.replaceChildren();
      for (const d of snapshot.duties) {
        if(d.id.startsWith("repo-")) continue;
        const row=document.createElement("p");
        row.textContent=d.id+" · "+d.agent+" / "+d.target+" · every "+d.interval_seconds+"s · "+(d.enabled?"enabled":"paused")+" ";
        row.append(document.createTextNode(d.inference?"AI requested within target limits ":"AI off "));
        button(row,"Edit",async()=>{
          section.querySelector("#field-duty-id").value=d.id;
          section.querySelector("#field-duty-interval").value=d.interval_seconds;
          section.querySelector("#field-duty-inference").checked=d.inference===true;
          const build=snapshot.builds.find(b=>b.manifest.target.id===d.target&&b.manifest.agent===d.agent);
          if(build) target.value=build.digest;
        });
        const toggle=button(row,d.enabled?"Pause":"Resume",async()=>{
          await post("/v4/duties",{...d,enabled:!d.enabled,generation:d.generation+1}); await refresh();
        }); toggle.disabled=!snapshot.enabled && !d.enabled; duties.append(row);
      }
      const memories=section.querySelector("#field-memory"); memories.replaceChildren();
      for (const m of snapshot.memory.slice(0,100)) {
        const row=document.createElement("p");
        row.textContent=m.agent+" · "+m.target+" · "+m.finding.summary+" · "+m.decision+" · revision "+m.revision+" ";
        button(row,"Source",async()=>{
          const r=await fetch("/v4/runs/"+encodeURIComponent(m.source_run));
          if (!r.ok) throw Error("Source unavailable"); showEvidence(await r.json());
        });
        for (const decision of (m.decision==="approve"?["revoke"]:["approve","reject"]))
          button(row,decision,async()=>{await post("/v4/memory/review",{id:m.id,revision:m.revision,decision});await refresh();});
        memories.append(row);
      }
    } catch {
      snapshot=null; signature=""; submit.disabled=true;
      section.querySelectorAll("button").forEach(b=>b.disabled=true);
      section.querySelector("#field-duty-submit").disabled=true;
      notice.textContent="Field crew disconnected. Retained results are last-known; commands unavailable.";
    } finally { refreshing=false; }
  }
  refresh(); setInterval(refresh,3000);
})();
