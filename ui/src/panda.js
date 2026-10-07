// AssembleLink's guide: an original panda drawn as inline SVG.
// Poses are plain data attributes so CSS owns every animation (and reduced-motion can switch them off).
// "carry" is the panda with a bamboo bundle strapped to its back; it appears while tools are installing.

const POSES = new Set(["idle", "scan", "think", "happy", "sad", "carry"]);

const BAMBOO_BUNDLE = `
  <g class="bamboo" aria-hidden="true">
    <g transform="rotate(-24 80 118)">
      <rect x="70" y="-6" width="9" height="128" rx="4" fill="#4ade80"/>
      <rect x="70" y="22" width="9" height="3" fill="#15803d"/><rect x="70" y="58" width="9" height="3" fill="#15803d"/><rect x="70" y="94" width="9" height="3" fill="#15803d"/>
      <ellipse class="leaf" cx="62" cy="10" rx="13" ry="5" transform="rotate(-28 62 10)" fill="#86efac"/>
    </g>
    <g transform="rotate(22 80 118)">
      <rect x="82" y="-2" width="9" height="124" rx="4" fill="#22c55e"/>
      <rect x="82" y="30" width="9" height="3" fill="#15803d"/><rect x="82" y="66" width="9" height="3" fill="#15803d"/><rect x="82" y="100" width="9" height="3" fill="#15803d"/>
      <ellipse class="leaf" cx="100" cy="14" rx="13" ry="5" transform="rotate(30 100 14)" fill="#4ade80"/>
      <ellipse class="leaf late" cx="98" cy="40" rx="11" ry="4" transform="rotate(24 98 40)" fill="#86efac"/>
    </g>
    <g>
      <rect x="76" y="-12" width="9" height="130" rx="4" fill="#34d399"/>
      <rect x="76" y="16" width="9" height="3" fill="#15803d"/><rect x="76" y="54" width="9" height="3" fill="#15803d"/><rect x="76" y="92" width="9" height="3" fill="#15803d"/>
      <ellipse class="leaf" cx="68" cy="-2" rx="12" ry="5" transform="rotate(-34 68 -2)" fill="#bbf7d0"/>
    </g>
  </g>`;

const BAMBOO_STRAPS = `
  <g class="straps" aria-hidden="true" fill="none" stroke="#b45309" stroke-width="5" stroke-linecap="round">
    <path d="M52 92 Q58 118 76 138"/><path d="M108 92 Q102 118 84 138"/>
    <rect x="68" y="104" width="24" height="8" rx="3" fill="#92400e" stroke="none"/>
  </g>`;

export function pandaSvg(pose = "idle", label = "AssembleLink panda guide") {
  const p = POSES.has(pose) ? pose : "idle";
  const carry = p === "carry";
  const mouth = {
    happy: `<path d="M68 82 Q80 98 92 82 Q80 88 68 82Z" fill="#7f1d1d"/><path d="M68 82 Q80 98 92 82" stroke="#1b2130" stroke-width="2.2" fill="none" stroke-linecap="round"/>`,
    sad: `<path d="M72 90 Q80 83 88 90" stroke="#1b2130" stroke-width="2.4" fill="none" stroke-linecap="round"/>`,
    scan: `<ellipse cx="80" cy="86" rx="4" ry="3.4" fill="#1b2130"/>`,
    think: `<path d="M73 87 Q80 86 87 88" stroke="#1b2130" stroke-width="2.4" fill="none" stroke-linecap="round"/>`,
  }[p] || `<path d="M72 83 Q80 90 88 83" stroke="#1b2130" stroke-width="2.4" fill="none" stroke-linecap="round"/>`;
  const brows = p === "sad"
    ? `<path d="M50 48 L66 53" stroke="#1b2130" stroke-width="3" stroke-linecap="round"/><path d="M110 48 L94 53" stroke="#1b2130" stroke-width="3" stroke-linecap="round"/>`
    : "";
  const cheeks = p === "happy" || carry
    ? `<circle cx="52" cy="82" r="6" fill="#fda4af" opacity=".55"/><circle cx="108" cy="82" r="6" fill="#fda4af" opacity=".55"/>`
    : "";
  const extra = {
    scan: `<g class="lens"><circle cx="128" cy="96" r="13" fill="rgba(125,211,252,.22)" stroke="#7dd3fc" stroke-width="4"/><path d="M137 106 L148 118" stroke="#7dd3fc" stroke-width="5" stroke-linecap="round"/></g>`,
    think: `<g class="thought"><circle cx="124" cy="30" r="3" fill="#cbd5e1"/><circle cx="134" cy="20" r="4.5" fill="#cbd5e1"/><circle cx="148" cy="8" r="6" fill="#cbd5e1"/></g>`,
    happy: `<g class="sparks" fill="#fde68a"><path class="s1" d="M18 40 l3 7 7 3 -7 3 -3 7 -3 -7 -7 -3 7 -3z"/><path class="s2" d="M140 52 l2.4 5.6 5.6 2.4 -5.6 2.4 -2.4 5.6 -2.4 -5.6 -5.6 -2.4 5.6 -2.4z"/></g>`,
  }[p] || "";
  return `<svg class="panda" data-pose="${p}" viewBox="0 0 160 160" role="img" aria-label="${label}" xmlns="http://www.w3.org/2000/svg">
  <ellipse class="shadow" cx="80" cy="153" rx="42" ry="5" fill="rgba(0,0,0,.35)"/>
  ${carry ? BAMBOO_BUNDLE : ""}
  <g class="figure">
    <g class="legs"><ellipse class="leg l" cx="53" cy="140" rx="16" ry="12" fill="#1b2130"/><ellipse class="leg r" cx="107" cy="140" rx="16" ry="12" fill="#1b2130"/></g>
    <g class="torso"><ellipse cx="80" cy="112" rx="40" ry="36" fill="#f8fafc"/><ellipse cx="80" cy="118" rx="24" ry="22" fill="#e2e8f0" opacity=".55"/></g>
    ${carry ? BAMBOO_STRAPS : ""}
    <g class="arm l"><ellipse cx="42" cy="108" rx="11" ry="22" transform="rotate(14 42 108)" fill="#1b2130"/></g>
    <g class="arm r"><ellipse cx="118" cy="108" rx="11" ry="22" transform="rotate(-14 118 108)" fill="#1b2130"/></g>
    <g class="head">
      <circle cx="40" cy="34" r="14" fill="#1b2130"/><circle cx="120" cy="34" r="14" fill="#1b2130"/>
      <circle cx="40" cy="34" r="6" fill="#475569" opacity=".6"/><circle cx="120" cy="34" r="6" fill="#475569" opacity=".6"/>
      <ellipse cx="80" cy="66" rx="47" ry="41" fill="#f8fafc"/>
      <ellipse cx="59" cy="63" rx="12" ry="15" transform="rotate(22 59 63)" fill="#1b2130"/>
      <ellipse cx="101" cy="63" rx="12" ry="15" transform="rotate(-22 101 63)" fill="#1b2130"/>
      <g class="eyes">
        <g class="eye l"><circle cx="60" cy="63" r="5.2" fill="#fff"/><circle class="pupil" cx="60.5" cy="63.5" r="2.6" fill="#0b1020"/><circle cx="59.2" cy="62" r="1" fill="#fff"/></g>
        <g class="eye r"><circle cx="100" cy="63" r="5.2" fill="#fff"/><circle class="pupil" cx="99.5" cy="63.5" r="2.6" fill="#0b1020"/><circle cx="98.2" cy="62" r="1" fill="#fff"/></g>
      </g>
      ${brows}${cheeks}
      <ellipse cx="80" cy="76" rx="7" ry="5" fill="#1b2130"/><ellipse cx="78" cy="74.4" rx="2.2" ry="1.2" fill="#64748b" opacity=".7"/>
      ${mouth}
    </g>
  </g>
  ${extra}
</svg>`;
}

export function pandaPoseNames() {
  return [...POSES];
}
