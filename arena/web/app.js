(() => {
  "use strict";

  const MISSION = Object.freeze({
    id: "mercury-1778-outbound",
    version: "v0",
    ruleset: "mercury-empirical-sail-v0",
    density: 1.025,
    bounds: {
      length: [20, 55], beam: [5, 15], draft: [2, 7], cb: [0.45, 0.75],
      displacement: [150, 1500], lb: [2.5, 5.5], bt: [1.5, 3.5],
      crew: [20, 180], closure: 0.02
    },
    fleet: { count: [3, 8], cargo: 450, budget: 1200 },
    allowed: {
      hull: ["monohull"],
      material: ["oak", "teak", "softwood"],
      propulsion: ["sail"]
    }
  });

  const OBJECTIVES = Object.freeze([
    { name: "delivered_cargo_t", direction: "maximize", aggregate: "mean", epsilon: 0.5 },
    { name: "mean_transit_days", direction: "minimize", aggregate: "mean", epsilon: 0.25 },
    { name: "total_cost_units", direction: "minimize", aggregate: "fixed", epsilon: 1 },
    { name: "loss_fraction", direction: "minimize", aggregate: "mean", epsilon: 0.001 },
    { name: "crew_casualty_fraction", direction: "minimize", aggregate: "mean", epsilon: 0.001 },
    { name: "required_freight_rate_units_per_t", direction: "minimize", aggregate: "mean", epsilon: 0.001 }
  ]);

  const SCORECARD_KEYS = Object.freeze([
    "schema_version", "evaluator_version", "evaluator_id", "run_id", "mission_id",
    "mission_version", "ruleset_id", "submission_id", "track", "mission_sha256",
    "submission_sha256", "simulation_result_sha256", "backend_version", "environment_sha256",
    "replay_algorithm", "replay_head_sha256", "replay_event_count", "season_commitment_sha256",
    "seed", "scenario_count", "feasible", "total_vessels", "total_cost_units",
    "total_nominal_cargo_t", "violations", "objectives"
  ]);

  const TRACKS = ["declared_human", "human_ai", "autonomous_agent", "exhibition"];
  const TRACK_LABELS = {
    declared_human: "Human",
    human_ai: "Human + AI",
    autonomous_agent: "Agent",
    exhibition: "Exhibition"
  };
  const TRACK_COLORS = {
    declared_human: "#315f8e",
    human_ai: "#006b64",
    autonomous_agent: "#705889",
    exhibition: "#a75a13"
  };

  const form = document.getElementById("ship-form");
  const toast = document.getElementById("toast");
  let toastTimer = 0;
  let activeTrack = "all";
  let importCounter = 0;
  let selectedScorecard = null;

  const numberFormat = new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 });
  const integerFormat = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });

  function field(name) {
    return form.elements.namedItem(name);
  }

  function numeric(name, integer = false) {
    const value = Number(field(name).value);
    if (!Number.isFinite(value)) return 0;
    return integer ? Math.trunc(value) : value;
  }

  function textValue(name) {
    return String(field(name).value || "").trim();
  }

  function inRange(value, range) {
    return Number.isFinite(value) && value >= range[0] && value <= range[1];
  }

  function format(value, digits = 2) {
    if (!Number.isFinite(value)) return "--";
    return new Intl.NumberFormat("en-US", {
      minimumFractionDigits: digits,
      maximumFractionDigits: digits
    }).format(value);
  }

  function formatPercent(value, digits = 2) {
    return Number.isFinite(value) ? `${format(value * 100, digits)}%` : "--";
  }

  function readDesign() {
    const design = {
      count: numeric("count", true),
      hull_form: textValue("hull_form"),
      material: textValue("material"),
      propulsion: textValue("propulsion"),
      length_m: numeric("length_m"),
      beam_m: numeric("beam_m"),
      draft_m: numeric("draft_m"),
      block_coefficient: numeric("block_coefficient"),
      displacement_t: numeric("displacement_t"),
      cargo_capacity_t: numeric("cargo_capacity_t"),
      sail_area_m2: numeric("sail_area_m2"),
      crew: numeric("crew", true),
      unit_cost_units: numeric("unit_cost_units")
    };
    const expected = MISSION.density * design.length_m * design.beam_m * design.draft_m * design.block_coefficient;
    const closure = expected > 0 ? Math.abs(design.displacement_t - expected) / expected : Infinity;
    return {
      ...design,
      expected,
      closure,
      lb: design.beam_m > 0 ? design.length_m / design.beam_m : Infinity,
      bt: design.draft_m > 0 ? design.beam_m / design.draft_m : Infinity,
      totalCargo: design.cargo_capacity_t * design.count,
      totalCost: design.unit_cost_units * design.count,
      totalDisplacement: design.displacement_t * design.count,
      totalCrew: design.crew * design.count,
      totalSail: design.sail_area_m2 * design.count
    };
  }

  function screenDesign(d) {
    const b = MISSION.bounds;
    return [
      gate("Hull form", MISSION.allowed.hull.includes(d.hull_form), "monohull required by this era pack"),
      gate("Material", MISSION.allowed.material.includes(d.material), "oak, teak, or softwood"),
      gate("Propulsion", MISSION.allowed.propulsion.includes(d.propulsion), "sail only"),
      gate("Length", inRange(d.length_m, b.length), `${format(d.length_m, 1)} m / 20.0-55.0 m`),
      gate("Beam", inRange(d.beam_m, b.beam), `${format(d.beam_m, 1)} m / 5.0-15.0 m`),
      gate("Draft", inRange(d.draft_m, b.draft), `${format(d.draft_m, 1)} m / 2.0-7.0 m`),
      gate("Block coefficient", inRange(d.block_coefficient, b.cb), `${format(d.block_coefficient, 2)} / 0.45-0.75`),
      gate("Displacement", inRange(d.displacement_t, b.displacement), `${format(d.displacement_t, 2)} t / 150-1,500 t`),
      gate("L / B ratio", inRange(d.lb, b.lb), `${format(d.lb, 2)} / 2.50-5.50`),
      gate("B / T ratio", inRange(d.bt, b.bt), `${format(d.bt, 2)} / 1.50-3.50`),
      gate("Displacement closure", d.closure <= b.closure, `${formatPercent(d.closure)} / max 2.00%`),
      gate("Sail area", d.propulsion !== "sail" || d.sail_area_m2 > 0, `${numberFormat.format(d.sail_area_m2)} m2 per vessel`),
      gate("Crew", inRange(d.crew, b.crew), `${integerFormat.format(d.crew)} / 20-180 per vessel`),
      gate("Fleet count", inRange(d.count, MISSION.fleet.count), `${integerFormat.format(d.count)} / 3-8 vessels`),
      gate("Nominal cargo", d.totalCargo >= MISSION.fleet.cargo, `${numberFormat.format(d.totalCargo)} t / min 450 t`),
      gate("Fleet budget", d.totalCost <= MISSION.fleet.budget, `${numberFormat.format(d.totalCost)} / max 1,200 credits`)
    ];
  }

  function gate(label, pass, detail) {
    return { label, pass: Boolean(pass), detail };
  }

  function buildSubmission() {
    const d = readDesign();
    return {
      schema_version: "yard.arena.submission.v0",
      submission_id: textValue("submission_id"),
      mission_id: MISSION.id,
      mission_version: MISSION.version,
      ruleset_id: MISSION.ruleset,
      track: textValue("track"),
      entrant: textValue("entrant"),
      provenance: {
        yard_revision: textValue("yard_revision"),
        zig_version: textValue("zig_version"),
        authoring_system: textValue("authoring_system"),
        ai_system: textValue("ai_system") || null,
        method_uri: textValue("method_uri") || null
      },
      fleet: [{
        design_id: textValue("design_id"),
        class_name: textValue("class_name"),
        count: d.count,
        hull_form: d.hull_form,
        material: d.material,
        propulsion: d.propulsion,
        length_m: d.length_m,
        beam_m: d.beam_m,
        draft_m: d.draft_m,
        block_coefficient: d.block_coefficient,
        displacement_t: d.displacement_t,
        cargo_capacity_t: d.cargo_capacity_t,
        sail_area_m2: d.sail_area_m2,
        crew: d.crew,
        unit_cost_units: d.unit_cost_units
      }]
    };
  }

  function renderBuilder() {
    const d = readDesign();
    const gates = screenDesign(d);
    const passed = gates.filter((item) => item.pass).length;

    document.getElementById("preview-class").textContent = textValue("class_name") || "Unnamed vessel class";
    document.getElementById("preview-scale").textContent = `L ${format(d.length_m, 1)} m / B ${format(d.beam_m, 1)} m / T ${format(d.draft_m, 1)} m`;
    document.getElementById("metric-expected-displacement").textContent = `${format(d.expected)} t`;
    document.getElementById("metric-closure").textContent = formatPercent(d.closure);
    document.getElementById("metric-lb").textContent = format(d.lb, 2);
    document.getElementById("metric-bt").textContent = format(d.bt, 2);
    document.getElementById("fleet-count-label").textContent = `${integerFormat.format(d.count)} ${d.count === 1 ? "vessel" : "vessels"}`;
    document.getElementById("total-cargo").textContent = `${numberFormat.format(d.totalCargo)} t`;
    document.getElementById("total-cost").textContent = `${numberFormat.format(d.totalCost)} credits`;
    document.getElementById("total-displacement").textContent = `${numberFormat.format(d.totalDisplacement)} t`;
    document.getElementById("total-crew").textContent = integerFormat.format(d.totalCrew);
    document.getElementById("total-sail").textContent = `${numberFormat.format(d.totalSail)} m2`;
    document.getElementById("gate-summary").textContent = `${passed} / ${gates.length} pass`;

    const status = document.getElementById("design-status");
    const allPass = passed === gates.length;
    status.textContent = allPass ? "SCREENING PASS" : `${gates.length - passed} GATE${gates.length - passed === 1 ? "" : "S"} FAIL`;
    status.classList.toggle("status-pass", allPass);
    status.classList.toggle("status-fail", !allPass);

    const list = document.getElementById("gate-list");
    list.replaceChildren(...gates.map((item) => {
      const li = document.createElement("li");
      li.className = item.pass ? "is-pass" : "is-fail";
      const icon = document.createElement("span");
      icon.className = "gate-icon";
      icon.setAttribute("aria-hidden", "true");
      icon.textContent = item.pass ? "OK" : "!";
      const copy = document.createElement("span");
      copy.className = "gate-copy";
      const title = document.createElement("strong");
      title.textContent = item.label;
      const detail = document.createElement("small");
      detail.textContent = item.detail;
      copy.append(title, detail);
      li.append(icon, copy);
      return li;
    }));

    document.getElementById("submission-json").textContent = JSON.stringify(buildSubmission(), null, 2);
  }

  function validateExport() {
    if (!form.checkValidity()) {
      form.reportValidity();
      return false;
    }
    const d = readDesign();
    const values = [d.count, d.length_m, d.beam_m, d.draft_m, d.block_coefficient, d.displacement_t,
      d.cargo_capacity_t, d.sail_area_m2, d.crew, d.unit_cost_units];
    if (values.some((value) => !Number.isFinite(value) || value < 0)) {
      showToast("Submission contains an invalid numeric value.", true);
      return false;
    }
    return true;
  }

  function downloadSubmission() {
    if (!validateExport()) return;
    const submission = buildSubmission();
    const blob = new Blob([`${JSON.stringify(submission, null, 2)}\n`], { type: "application/json" });
    const href = URL.createObjectURL(blob);
    const link = document.createElement("a");
    const safeId = submission.submission_id.replace(/[^a-z0-9._-]+/gi, "-") || "yard-arena-submission";
    link.href = href;
    link.download = `${safeId}.json`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(href);
    showToast("Submission JSON exported locally.");
  }

  async function copySubmission() {
    if (!validateExport()) return;
    const value = `${JSON.stringify(buildSubmission(), null, 2)}\n`;
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(value);
      } else {
        const area = document.createElement("textarea");
        area.value = value;
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.select();
        if (!document.execCommand("copy")) throw new Error("copy command refused");
        area.remove();
      }
      showToast("Submission JSON copied.");
    } catch (error) {
      showToast("Clipboard unavailable. Submission JSON remains open in the analysis panel.", true);
    }
  }

  function showToast(message, isError = false) {
    window.clearTimeout(toastTimer);
    toast.textContent = message;
    toast.classList.toggle("is-error", isError);
    toast.hidden = false;
    toastTimer = window.setTimeout(() => { toast.hidden = true; }, 3200);
  }

  function objectiveVector(cargo, days, cost, loss, casualty, freightRate) {
    const values = [cargo, days, cost, loss, casualty, freightRate];
    return OBJECTIVES.map((spec, index) => ({ ...spec, value: values[index] }));
  }

  function demo(uid, label, id, track, values, feasible = true, violation = "") {
    return {
      uid, label, submission_id: id, track, feasible, origin: "demo",
      objectives: feasible ? objectiveVector(...values) : [],
      violations: feasible ? [] : [{ code: "demo_infeasible", subject: id, detail: violation }]
    };
  }

  const demoEntries = [
    demo("d1", "Meridian 38", "demo-meridian-38", "human_ai", [510, 150, 900, 0.040, 0.008, 0.34]),
    demo("d2", "Teak Endurance", "demo-teak-endurance", "declared_human", [480, 164, 760, 0.018, 0.004, 0.31]),
    demo("d3", "Cape Runner", "demo-cape-runner", "declared_human", [455, 139, 1120, 0.060, 0.012, 0.43]),
    demo("d4", "Monsoon Carry", "demo-monsoon-carry", "autonomous_agent", [590, 175, 1180, 0.080, 0.018, 0.37]),
    demo("d5", "Windward Search 12", "demo-windward-search", "autonomous_agent", [535, 152, 1060, 0.030, 0.006, 0.35]),
    demo("d6", "Broadbeam Freight", "demo-broadbeam-freight", "human_ai", [460, 172, 980, 0.050, 0.010, 0.39]),
    demo("d7", "Steel Ghost", "demo-steel-ghost", "human_ai", [], false, "material is unavailable in this era pack"),
    demo("d8", "Overcanvassed Sprint", "demo-overcanvassed", "exhibition", [], false, "declared displacement does not close against L*B*T*Cb")
  ];
  let importedEntries = [];

  function objective(entry, name) {
    const item = entry.objectives.find((candidate) => candidate.name === name);
    return item ? item.value : null;
  }

  function dominates(left, right) {
    if (!left.feasible || !right.feasible) return false;
    let strictlyBetter = false;
    for (const spec of OBJECTIVES) {
      const a = left.objectives.find((item) => item.name === spec.name);
      const b = right.objectives.find((item) => item.name === spec.name);
      if (!a || !b || a.direction !== b.direction || a.aggregate !== b.aggregate) return false;
      const epsilon = Math.max(a.epsilon, b.epsilon);
      if (a.direction === "minimize") {
        if (a.value > b.value + epsilon) return false;
        if (a.value < b.value - epsilon) strictlyBetter = true;
      } else {
        if (a.value < b.value - epsilon) return false;
        if (a.value > b.value + epsilon) strictlyBetter = true;
      }
    }
    return strictlyBetter;
  }

  function ranksByTrack(entries) {
    const ranks = new Map();
    for (const track of TRACKS) {
      let remaining = entries.filter((entry) => entry.track === track && entry.feasible);
      let rank = 1;
      while (remaining.length) {
        const front = remaining.filter((candidate) => !remaining.some((other) => other !== candidate && dominates(other, candidate)));
        if (!front.length) break;
        for (const entry of front) ranks.set(entry.uid, rank);
        const frontIds = new Set(front.map((entry) => entry.uid));
        remaining = remaining.filter((entry) => !frontIds.has(entry.uid));
        rank += 1;
      }
    }
    return ranks;
  }

  function allEntries() {
    return [...demoEntries, ...importedEntries];
  }

  function filteredEntries(entries) {
    return activeTrack === "all" ? entries : entries.filter((entry) => entry.track === activeTrack);
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>'"]/g, (character) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", "\"": "&quot;"
    }[character]));
  }

  function valueCell(entry, name, kind = "number") {
    const value = objective(entry, name);
    if (!entry.feasible || value === null) return "&mdash;";
    if (kind === "percent") return formatPercent(value, 2);
    if (kind === "rate") return format(value, 3);
    return numberFormat.format(value);
  }

  function renderLeaderboard() {
    const entries = allEntries();
    const ranks = ranksByTrack(entries);
    const visible = filteredEntries(entries);
    const feasible = visible.filter((entry) => entry.feasible);
    const frontOne = feasible.filter((entry) => ranks.get(entry.uid) === 1);

    document.getElementById("visible-count").textContent = visible.length;
    document.getElementById("feasible-count").textContent = feasible.length;
    document.getElementById("front-count").textContent = frontOne.length;
    document.getElementById("excluded-count").textContent = visible.length - feasible.length;

    document.getElementById("count-all").textContent = entries.length;
    for (const track of TRACKS) {
      document.getElementById(`count-${track}`).textContent = entries.filter((entry) => entry.track === track).length;
    }

    const tbody = document.getElementById("leaderboard-body");
    tbody.innerHTML = visible.map((entry) => {
      const rank = ranks.get(entry.uid) || 0;
      const violation = entry.violations.map((item) => item.detail).join("; ");
      return `<tr class="${entry.feasible ? "" : "is-infeasible"}">
        <td class="entry-cell"><strong>${escapeHtml(entry.label)}<span class="origin-badge ${entry.origin === "imported" ? "origin-imported" : ""}">${entry.origin === "imported" ? "IMPORTED" : "DEMO"}</span></strong><small>${escapeHtml(entry.submission_id)}</small></td>
        <td><span class="track-badge track-${entry.track}">${escapeHtml(TRACK_LABELS[entry.track])}</span></td>
        <td><span class="feasibility-badge ${entry.feasible ? "feasible-pass" : "feasible-fail"}" title="${escapeHtml(violation || "All scorecard feasibility gates passed")}">${entry.feasible ? "FEASIBLE" : "EXCLUDED"}</span></td>
        <td>${entry.feasible ? `<span class="rank-badge ${rank === 1 ? "rank-one" : ""}">${rank}</span>` : "&mdash;"}</td>
        <td class="numeric-cell">${valueCell(entry, "delivered_cargo_t")}</td>
        <td class="numeric-cell">${valueCell(entry, "mean_transit_days")}</td>
        <td class="numeric-cell">${valueCell(entry, "total_cost_units")}</td>
        <td class="numeric-cell">${valueCell(entry, "loss_fraction", "percent")}</td>
        <td class="numeric-cell">${valueCell(entry, "crew_casualty_fraction", "percent")}</td>
        <td class="numeric-cell">${valueCell(entry, "required_freight_rate_units_per_t", "rate")}</td>
      </tr>`;
    }).join("");

    renderParetoChart(visible, ranks);
  }

  const SVG_NS = "http://www.w3.org/2000/svg";
  function svgElement(tag, attributes = {}, text = "") {
    const node = document.createElementNS(SVG_NS, tag);
    for (const [name, value] of Object.entries(attributes)) node.setAttribute(name, String(value));
    if (text) node.textContent = text;
    return node;
  }

  function projectedFront(entries) {
    const sorted = [...entries].sort((a, b) => objective(a, "mean_transit_days") - objective(b, "mean_transit_days"));
    const front = [];
    let bestCargo = -Infinity;
    for (const entry of sorted) {
      const cargo = objective(entry, "delivered_cargo_t");
      if (cargo > bestCargo) {
        front.push(entry);
        bestCargo = cargo;
      }
    }
    return front;
  }

  function renderParetoChart(entries, ranks) {
    const chart = document.getElementById("pareto-chart");
    const tooltip = document.getElementById("plot-tooltip");
    const selection = document.getElementById("plot-selection");
    chart.replaceChildren();
    chart.append(
      svgElement("title", { id: "pareto-chart-title" }, "Pareto scatter of delivered cargo versus mean transit time"),
      svgElement("desc", { id: "pareto-chart-desc" }, "Feasible scorecards plotted by delivered cargo and mean transit days. Ranks use all mission objectives within each track.")
    );
    const data = entries.filter((entry) => entry.feasible && objective(entry, "delivered_cargo_t") !== null && objective(entry, "mean_transit_days") !== null);
    const width = 920;
    const height = 390;
    const margin = { top: 20, right: 28, bottom: 55, left: 72 };
    const plotWidth = width - margin.left - margin.right;
    const plotHeight = height - margin.top - margin.bottom;

    if (!data.length) {
      chart.append(svgElement("text", { x: width / 2, y: height / 2, class: "plot-empty-label", "text-anchor": "middle" }, "No feasible scorecards in this track"));
      selection.textContent = "No feasible objective vectors are visible.";
      return;
    }

    const xValues = data.map((entry) => objective(entry, "mean_transit_days"));
    const yValues = data.map((entry) => objective(entry, "delivered_cargo_t"));
    const xRawMin = Math.min(...xValues);
    const xRawMax = Math.max(...xValues);
    const yRawMin = Math.min(...yValues);
    const yRawMax = Math.max(...yValues);
    const xPad = Math.max((xRawMax - xRawMin) * 0.12, 4);
    const yPad = Math.max((yRawMax - yRawMin) * 0.12, 12);
    const xMin = Math.max(0, xRawMin - xPad);
    const xMax = xRawMax + xPad;
    const yMin = Math.max(0, yRawMin - yPad);
    const yMax = yRawMax + yPad;
    const xScale = (value) => margin.left + ((value - xMin) / (xMax - xMin)) * plotWidth;
    const yScale = (value) => margin.top + plotHeight - ((value - yMin) / (yMax - yMin)) * plotHeight;

    for (let i = 0; i <= 5; i += 1) {
      const x = margin.left + (plotWidth * i / 5);
      const y = margin.top + (plotHeight * i / 5);
      const xValue = xMin + ((xMax - xMin) * i / 5);
      const yValue = yMax - ((yMax - yMin) * i / 5);
      chart.append(svgElement("line", { x1: x, y1: margin.top, x2: x, y2: margin.top + plotHeight, class: "plot-grid-line" }));
      chart.append(svgElement("line", { x1: margin.left, y1: y, x2: margin.left + plotWidth, y2: y, class: "plot-grid-line" }));
      chart.append(svgElement("text", { x, y: margin.top + plotHeight + 22, class: "plot-tick-label", "text-anchor": "middle" }, format(xValue, 0)));
      chart.append(svgElement("text", { x: margin.left - 10, y: y + 4, class: "plot-tick-label", "text-anchor": "end" }, format(yValue, 0)));
    }

    chart.append(svgElement("line", { x1: margin.left, y1: margin.top + plotHeight, x2: margin.left + plotWidth, y2: margin.top + plotHeight, class: "plot-axis-line" }));
    chart.append(svgElement("line", { x1: margin.left, y1: margin.top, x2: margin.left, y2: margin.top + plotHeight, class: "plot-axis-line" }));
    chart.append(svgElement("text", { x: margin.left + plotWidth / 2, y: height - 10, class: "plot-axis-label", "text-anchor": "middle" }, "MEAN TRANSIT DAYS / MINIMIZE"));
    chart.append(svgElement("text", { x: 17, y: margin.top + plotHeight / 2, class: "plot-axis-label", "text-anchor": "middle", transform: `rotate(-90 17 ${margin.top + plotHeight / 2})` }, "DELIVERED CARGO T / MAXIMIZE"));

    for (const track of TRACKS) {
      const front = projectedFront(data.filter((entry) => entry.track === track));
      if (front.length < 2) continue;
      const points = front.map((entry) => `${xScale(objective(entry, "mean_transit_days"))},${yScale(objective(entry, "delivered_cargo_t"))}`).join(" ");
      chart.append(svgElement("polyline", { points, class: "front-line", stroke: TRACK_COLORS[track] }));
    }

    for (const entry of data) {
      const x = xScale(objective(entry, "mean_transit_days"));
      const y = yScale(objective(entry, "delivered_cargo_t"));
      const group = svgElement("g", {
        class: `plot-point ${ranks.get(entry.uid) === 1 ? "front-one" : ""}`,
        tabindex: "0",
        role: "button",
        "aria-label": `${entry.label}, ${objective(entry, "delivered_cargo_t")} tonnes delivered cargo, ${objective(entry, "mean_transit_days")} mean transit days, Pareto rank ${ranks.get(entry.uid)}`
      });
      const circle = svgElement("circle", { cx: x, cy: y, r: 7, fill: TRACK_COLORS[entry.track] });
      group.append(circle);
      const show = (event) => {
        tooltip.innerHTML = `<strong>${escapeHtml(entry.label)}</strong><span>${numberFormat.format(objective(entry, "delivered_cargo_t"))} t cargo / ${numberFormat.format(objective(entry, "mean_transit_days"))} d / front ${ranks.get(entry.uid)}</span>`;
        const rect = chart.getBoundingClientRect();
        const left = event.clientX ? event.clientX - rect.left + 12 : (x / width) * rect.width + 12;
        const top = event.clientY ? event.clientY - rect.top + 10 : (y / height) * rect.height + 10;
        tooltip.style.left = `${Math.min(left, Math.max(8, rect.width - 230))}px`;
        tooltip.style.top = `${Math.max(8, top)}px`;
        tooltip.hidden = false;
      };
      const hide = () => { tooltip.hidden = true; };
      const select = () => {
        selection.innerHTML = `<strong>${escapeHtml(entry.label)}</strong> / ${escapeHtml(TRACK_LABELS[entry.track])} / front ${ranks.get(entry.uid)} / cargo ${numberFormat.format(objective(entry, "delivered_cargo_t"))} t / transit ${numberFormat.format(objective(entry, "mean_transit_days"))} d / cost ${numberFormat.format(objective(entry, "total_cost_units"))} / loss ${formatPercent(objective(entry, "loss_fraction"), 2)} / casualty ${formatPercent(objective(entry, "crew_casualty_fraction"), 2)} / freight rate ${format(objective(entry, "required_freight_rate_units_per_t"), 3)}`;
      };
      group.addEventListener("pointerenter", show);
      group.addEventListener("pointermove", show);
      group.addEventListener("pointerleave", hide);
      group.addEventListener("focus", show);
      group.addEventListener("blur", hide);
      group.addEventListener("click", select);
      group.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          select();
        }
      });
      chart.append(group);
    }
  }

  function validHash(value) {
    return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
  }

  function exactKeys(value, expected, label) {
    const actual = Object.keys(value).sort();
    const wanted = [...expected].sort();
    if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
      throw new Error(`${label} contains missing or unknown fields.`);
    }
  }

  function nonempty(value, label) {
    if (typeof value !== "string" || !value.length) throw new Error(`${label} must be a non-empty string.`);
  }

  function nonnegative(value, label, integer = false) {
    if (!Number.isFinite(value) || value < 0 || (integer && !Number.isInteger(value))) {
      throw new Error(`${label} must be a non-negative${integer ? " integer" : " number"}.`);
    }
  }

  function validateScorecard(raw) {
    if (!raw || Array.isArray(raw) || typeof raw !== "object") throw new Error("Expected one scorecard object.");
    exactKeys(raw, SCORECARD_KEYS, "Scorecard");
    if (raw.schema_version !== "yard.arena.scorecard.v0") throw new Error("schema_version must be yard.arena.scorecard.v0.");
    if (raw.mission_id !== MISSION.id || raw.mission_version !== MISSION.version || raw.ruleset_id !== MISSION.ruleset) {
      throw new Error("Scorecard belongs to a different mission identity.");
    }
    if (!TRACKS.includes(raw.track)) throw new Error("Scorecard track is not recognized.");
    for (const key of ["evaluator_version", "evaluator_id", "submission_id", "backend_version"]) nonempty(raw[key], key);
    if (typeof raw.feasible !== "boolean") throw new Error("feasible must be boolean.");
    if (!Array.isArray(raw.objectives) || !Array.isArray(raw.violations)) throw new Error("objectives and violations arrays are required.");
    nonnegative(raw.total_vessels, "total_vessels", true);
    nonnegative(raw.total_cost_units, "total_cost_units");
    nonnegative(raw.total_nominal_cargo_t, "total_nominal_cargo_t");
    nonnegative(raw.seed, "seed", true);
    nonnegative(raw.scenario_count, "scenario_count", true);
    nonnegative(raw.replay_event_count, "replay_event_count", true);
    if (raw.scenario_count < 1 || raw.replay_event_count < 1) throw new Error("scenario_count and replay_event_count must be positive.");
    if (raw.replay_algorithm !== "sha256-chain-v1") throw new Error("replay_algorithm must be sha256-chain-v1.");
    for (const key of ["run_id", "mission_sha256", "submission_sha256", "simulation_result_sha256", "environment_sha256", "replay_head_sha256", "season_commitment_sha256"]) {
      if (!validHash(raw[key])) throw new Error(`${key} must be a lowercase SHA-256 digest.`);
    }
    for (const violation of raw.violations) {
      if (!violation || Array.isArray(violation) || typeof violation !== "object") throw new Error("Each violation must be an object.");
      exactKeys(violation, ["code", "subject", "detail"], "Violation");
      for (const key of ["code", "subject", "detail"]) nonempty(violation[key], `violation.${key}`);
    }
    for (const item of raw.objectives) {
      if (!item || Array.isArray(item) || typeof item !== "object") throw new Error("Each objective must be an object.");
      exactKeys(item, ["name", "direction", "aggregate", "epsilon", "value"], `Objective ${item.name || "unknown"}`);
    }
    if (raw.feasible) {
      if (raw.objectives.length !== OBJECTIVES.length) throw new Error("Feasible scorecard must contain all six mission objectives.");
      for (const spec of OBJECTIVES) {
        const item = raw.objectives.find((candidate) => candidate.name === spec.name);
        if (!item || item.direction !== spec.direction || item.aggregate !== spec.aggregate || item.epsilon !== spec.epsilon || !Number.isFinite(item.value)) {
          throw new Error(`Invalid objective contract for ${spec.name}.`);
        }
      }
    } else if (raw.objectives.length !== 0) {
      throw new Error("Infeasible scorecard must not contain an objective vector.");
    }
  }

  function renderProvenance(scorecard) {
    selectedScorecard = scorecard;
    const values = scorecard ? {
      evaluator: `${scorecard.evaluator_id} / ${scorecard.evaluator_version}`,
      backend: scorecard.backend_version,
      run: scorecard.run_id,
      environment: scorecard.environment_sha256,
      replay: `${scorecard.replay_algorithm} / ${integerFormat.format(scorecard.replay_event_count)} events`,
      replayHead: scorecard.replay_head_sha256,
      season: scorecard.season_commitment_sha256,
      evaluation: `seed ${scorecard.seed} / ${integerFormat.format(scorecard.scenario_count)} scenarios`
    } : null;
    document.getElementById("provenance-evaluator").textContent = values?.evaluator || "--";
    document.getElementById("provenance-backend").textContent = values?.backend || "--";
    document.getElementById("provenance-run").textContent = values?.run || "--";
    document.getElementById("provenance-environment").textContent = values?.environment || "--";
    document.getElementById("provenance-replay").textContent = values?.replay || "--";
    document.getElementById("provenance-replay-head").textContent = values?.replayHead || "--";
    document.getElementById("provenance-season").textContent = values?.season || "--";
    document.getElementById("provenance-evaluation").textContent = values?.evaluation || "--";
    document.getElementById("provenance-note").textContent = scorecard
      ? `${scorecard.submission_id} passed the local scorecard contract check.`
      : "Import an evaluator scorecard to inspect its content-addressed run bindings.";
    const status = document.getElementById("provenance-status");
    status.textContent = scorecard ? "CONTRACT VALID" : "NO IMPORT";
    status.className = `proof-badge ${scorecard ? "proof-tested" : "proof-ui"}`;
  }

  async function importScorecard(file) {
    const status = document.getElementById("import-status");
    try {
      const raw = JSON.parse(await file.text());
      validateScorecard(raw);
      importCounter += 1;
      const entry = {
        uid: `import-${importCounter}`,
        label: raw.submission_id,
        submission_id: raw.submission_id,
        track: raw.track,
        feasible: raw.feasible,
        origin: "imported",
        objectives: raw.objectives.map((item) => ({ ...item })),
        violations: raw.violations.map((item) => ({ ...item })),
        scorecard: raw
      };
      importedEntries = importedEntries.filter((candidate) => candidate.submission_id !== entry.submission_id);
      importedEntries.push(entry);
      status.textContent = `${raw.submission_id} imported locally; contract valid, artifacts unverified.`;
      status.className = "import-status is-success";
      activeTrack = raw.track;
      renderProvenance(raw);
      syncTrackButtons();
      renderLeaderboard();
    } catch (error) {
      status.textContent = `Import rejected: ${error.message}`;
      status.className = "import-status is-error";
    }
  }

  function syncTrackButtons() {
    document.querySelectorAll(".filter-button").forEach((button) => {
      const active = button.dataset.track === activeTrack;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
  }

  function activateTab(tabName, focus = false) {
    document.querySelectorAll("[data-panel]").forEach((panel) => {
      panel.hidden = panel.dataset.panel !== tabName;
    });
    document.querySelectorAll("[data-tab]").forEach((button) => {
      const active = button.dataset.tab === tabName;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-selected", String(active));
      button.tabIndex = active ? 0 : -1;
      if (active && focus) button.focus();
    });
    if (tabName === "leaderboard") renderLeaderboard();
  }

  document.querySelectorAll("[data-tab]").forEach((button, index, buttons) => {
    button.addEventListener("click", () => activateTab(button.dataset.tab));
    button.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      let target = index;
      if (event.key === "ArrowLeft") target = (index - 1 + buttons.length) % buttons.length;
      if (event.key === "ArrowRight") target = (index + 1) % buttons.length;
      if (event.key === "Home") target = 0;
      if (event.key === "End") target = buttons.length - 1;
      activateTab(buttons[target].dataset.tab, true);
    });
  });

  form.addEventListener("input", renderBuilder);
  form.addEventListener("change", renderBuilder);
  document.getElementById("close-displacement").addEventListener("click", () => {
    field("displacement_t").value = readDesign().expected.toFixed(2);
    renderBuilder();
    showToast("Declared displacement closed to the seawater block estimate.");
  });
  document.getElementById("reset-builder").addEventListener("click", () => {
    form.reset();
    renderBuilder();
    showToast("Reference design restored.");
  });
  document.getElementById("copy-submission").addEventListener("click", copySubmission);
  document.getElementById("export-submission").addEventListener("click", downloadSubmission);

  document.querySelectorAll(".filter-button").forEach((button) => {
    button.addEventListener("click", () => {
      activeTrack = button.dataset.track;
      syncTrackButtons();
      renderLeaderboard();
    });
  });
  document.getElementById("scorecard-file").addEventListener("change", (event) => {
    const [file] = event.target.files;
    if (file) importScorecard(file);
    event.target.value = "";
  });
  document.getElementById("clear-imports").addEventListener("click", () => {
    importedEntries = [];
    selectedScorecard = null;
    activeTrack = "all";
    syncTrackButtons();
    document.getElementById("import-status").textContent = "Local imports cleared; demo entries remain.";
    document.getElementById("import-status").className = "import-status";
    renderProvenance(null);
    renderLeaderboard();
  });

  const merchantmanImage = document.getElementById("merchantman-image");
  merchantmanImage.addEventListener("error", () => {
    merchantmanImage.classList.add("is-missing");
    document.getElementById("merchantman-fallback").hidden = false;
  });

  renderBuilder();
  renderLeaderboard();
  renderProvenance(selectedScorecard);
})();
