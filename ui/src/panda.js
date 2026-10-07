// AssembleLink's guide: a lazy, sleepy panda drawn as inline SVG.
// Poses are data attributes so CSS owns the (very slow) motion and reduced-motion can switch it off.
// "carry" is the panda plodding along with a bamboo bundle strapped to its back while tools install.

const POSES = new Set(["idle", "scan", "think", "happy", "sad", "carry", "wave"]);
const INK = "#1b2130";

const BAMBOO_BUNDLE = `
  <g class="bamboo" aria-hidden="true">
    <g transform="rotate(-26 80 120)">
      <rect x="68" y="-4" width="9" height="130" rx="4" fill="#4ade80"/>
      <rect x="68" y="26" width="9" height="3" fill="#15803d"/><rect x="68" y="64" width="9" height="3" fill="#15803d"/><rect x="68" y="98" width="9" height="3" fill="#15803d"/>
      <ellipse cx="60" cy="12" rx="13" ry="5" transform="rotate(-28 60 12)" fill="#86efac"/>
    </g>
    <g transform="rotate(24 80 120)">
      <rect x="84" y="0" width="9" height="126" rx="4" fill="#22c55e"/>
      <rect x="84" y="34" width="9" height="3" fill="#15803d"/><rect x="84" y="70" width="9" height="3" fill="#15803d"/><rect x="84" y="102" width="9" height="3" fill="#15803d"/>
      <ellipse cx="102" cy="16" rx="13" ry="5" transform="rotate(30 102 16)" fill="#4ade80"/>
    </g>
    <g>
      <rect x="76" y="-12" width="9" height="132" rx="4" fill="#34d399"/>
      <rect x="76" y="18" width="9" height="3" fill="#15803d"/><rect x="76" y="56" width="9" height="3" fill="#15803d"/><rect x="76" y="94" width="9" height="3" fill="#15803d"/>
      <ellipse cx="68" cy="0" rx="12" ry="5" transform="rotate(-34 68 0)" fill="#bbf7d0"/>
    </g>
  </g>`;

const STRAPS = `
  <g class="straps" aria-hidden="true" fill="none" stroke="#b45309" stroke-width="4" stroke-linecap="round">
    <path d="M53 92 L107 132"/><path d="M107 92 L53 132"/>
    <circle cx="80" cy="112" r="5" fill="#92400e" stroke="none"/>
  </g>`;

// Half-open, sleepy eye. `up` nudges the pupil for thinking/looking.
function sleepyEye(cx, cy, dx = 0, up = false) {
  const py = cy + (up ? 0.4 : 2);
  return `<g class="eye"><path d="M${cx - 5.2} ${cy} a5.2 5.2 0 0 0 10.4 0z" fill="#fff"/><circle class="pupil" cx="${cx + dx}" cy="${py}" r="2.3" fill="#0b1020"/><path d="M${cx - 5.8} ${cy} H${cx + 5.8}" stroke="#94a3b8" stroke-width="1.5" stroke-linecap="round"/></g>`;
}

// Content, fully closed eye (a soft upward-facing curve).
function contentEye(cx, cy) {
  return `<g class="eye"><path d="M${cx - 6} ${cy + 1} Q${cx} ${cy + 7} ${cx + 6} ${cy + 1}" stroke="#e2e8f0" stroke-width="2.4" fill="none" stroke-linecap="round"/></g>`;
}

export function pandaSvg(pose = "idle", label = "AssembleLink panda guide") {
  const p = POSES.has(pose) ? pose : "idle";
  const carry = p === "carry";
  const happy = p === "happy" || p === "wave";
  const eyes = happy
    ? contentEye(59, 67) + contentEye(101, 67)
    : p === "scan"
      ? sleepyEye(59, 67, 2) + sleepyEye(101, 67, 2)
      : p === "think"
        ? sleepyEye(59, 67, 0, true) + sleepyEye(101, 67, 0, true)
        : sleepyEye(59, 67) + sleepyEye(101, 67);
  const brows = p === "sad"
    ? `<path d="M47 56 L66 51" stroke="${INK}" stroke-width="3" stroke-linecap="round"/><path d="M113 56 L94 51" stroke="${INK}" stroke-width="3" stroke-linecap="round"/>`
    : "";
  const blush = happy || carry
    ? `<circle cx="48" cy="84" r="6" fill="#fda4af" opacity=".5"/><circle cx="112" cy="84" r="6" fill="#fda4af" opacity=".5"/>`
    : "";
  const mouth = happy
    ? `<path d="M70 86 Q80 96 90 86" stroke="${INK}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`
    : p === "sad"
      ? `<path d="M73 92 Q80 85 87 92" stroke="${INK}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`
      : `<path d="M74 86 Q80 90 86 86" stroke="${INK}" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
  const sprig = p === "idle" || carry || p === "think"
    ? `<g class="sprig" aria-hidden="true"><path d="M84 87 L113 79" stroke="#4ade80" stroke-width="3.2" stroke-linecap="round"/><ellipse cx="116" cy="78" rx="8" ry="3.2" transform="rotate(-18 116 78)" fill="#86efac"/></g>`
    : "";
  const rightArm = p === "wave"
    ? `<g class="arm r wave"><ellipse cx="130" cy="88" rx="10" ry="20" transform="rotate(-20 130 88)" fill="${INK}"/></g>`
    : p === "scan"
    ? `<g class="arm r raised"><ellipse cx="124" cy="104" rx="10" ry="19" transform="rotate(-38 124 104)" fill="${INK}"/></g><g class="lens"><circle cx="138" cy="86" r="12" fill="rgba(125,211,252,.2)" stroke="#7dd3fc" stroke-width="3.6"/><path d="M146 95 L154 105" stroke="#7dd3fc" stroke-width="4.5" stroke-linecap="round"/></g>`
    : `<g class="arm r"><ellipse cx="108" cy="116" rx="10" ry="20" transform="rotate(34 108 116)" fill="${INK}"/></g>`;
  const extra = {
    idle: `<g class="zzz" fill="#a5b4fc" font-family="Segoe UI, sans-serif" font-weight="700"><text x="124" y="34" font-size="13">z</text><text x="136" y="20" font-size="10">z</text></g>`,
    think: `<g class="thought"><circle cx="124" cy="30" r="3" fill="#cbd5e1"/><circle cx="134" cy="20" r="4.5" fill="#cbd5e1"/><circle cx="148" cy="8" r="6" fill="#cbd5e1"/></g>`,
    happy: `<g class="sparks" fill="#fde68a"><path class="s1" d="M20 44 l3 7 7 3 -7 3 -3 7 -3 -7 -7 -3 7 -3z"/><path class="s2" d="M140 52 l2.4 5.6 5.6 2.4 -5.6 2.4 -2.4 5.6 -2.4 -5.6 -5.6 -2.4 5.6 -2.4z"/></g>`,
  }[p] || "";
  return `<svg class="panda" data-pose="${p}" viewBox="0 0 160 160" role="img" aria-label="${label}" xmlns="http://www.w3.org/2000/svg">
  <ellipse class="shadow" cx="80" cy="154" rx="50" ry="5" fill="rgba(0,0,0,.35)"/>
  ${carry ? BAMBOO_BUNDLE : ""}
  <g class="figure">
    <g class="legs"><ellipse class="leg l" cx="54" cy="144" rx="19" ry="11" fill="${INK}"/><ellipse class="leg r" cx="106" cy="144" rx="19" ry="11" fill="${INK}"/></g>
    <g class="torso"><ellipse cx="80" cy="114" rx="47" ry="38" fill="#f8fafc"/><ellipse cx="80" cy="122" rx="29" ry="24" fill="#e2e8f0" opacity=".6"/></g>
    ${carry ? STRAPS : ""}
    <g class="arm l"><ellipse cx="52" cy="116" rx="10" ry="20" transform="rotate(-34 52 116)" fill="${INK}"/></g>
    ${rightArm}
    <g class="head">
      <g transform="rotate(-3 80 72)">
        <circle cx="37" cy="40" r="13" fill="${INK}"/><circle cx="123" cy="40" r="13" fill="${INK}"/>
        <circle cx="37" cy="40" r="5.5" fill="#475569" opacity=".6"/><circle cx="123" cy="40" r="5.5" fill="#475569" opacity=".6"/>
        <ellipse cx="80" cy="72" rx="51" ry="38" fill="#f8fafc"/>
        <ellipse cx="58" cy="68" rx="12" ry="14" transform="rotate(24 58 68)" fill="${INK}"/>
        <ellipse cx="102" cy="68" rx="12" ry="14" transform="rotate(-24 102 68)" fill="${INK}"/>
        <g class="eyes">${eyes}</g>
        ${brows}${blush}
        <ellipse cx="80" cy="79" rx="7.5" ry="5" fill="${INK}"/><ellipse cx="78" cy="77.4" rx="2.3" ry="1.2" fill="#64748b" opacity=".7"/>
        ${mouth}${sprig}
      </g>
    </g>
  </g>
  ${extra}
</svg>`;
}

export function pandaPoseNames() {
  return [...POSES];
}
