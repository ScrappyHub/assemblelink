// Static, calm scenery for the Inventory Room (the panda's office). Only the panda moves.
export function roomSvg() {
  const book = (x, y, w, h, c) => `<rect x="${x}" y="${y - h}" width="${w}" height="${h}" rx="2" fill="${c}"/><rect x="${x + 3}" y="${y - h + 6}" width="${w - 6}" height="3" fill="rgba(255,255,255,.25)"/>`;
  return `<svg class="roomScene" viewBox="0 0 900 340" preserveAspectRatio="xMidYMid slice" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="ofWall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#17233d"/><stop offset="1" stop-color="#0f1a2f"/></linearGradient>
    <radialGradient id="ofLamp" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fde68a" stop-opacity=".5"/><stop offset="1" stop-color="#fde68a" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="900" height="340" fill="url(#ofWall)"/>
  <rect y="286" width="900" height="54" fill="#0a1120"/><rect y="284" width="900" height="4" fill="#26365a"/>
  <ellipse cx="240" cy="318" rx="170" ry="18" fill="#12304a" opacity=".8"/>
  <g transform="translate(40 36)"><rect width="150" height="130" rx="10" fill="#0b1830" stroke="#2d3b59" stroke-width="5"/><path d="M75 0 V130 M0 65 H150" stroke="#2d3b59" stroke-width="5"/><circle cx="112" cy="38" r="15" fill="#e2e8f0" opacity=".9"/><circle cx="118" cy="33" r="13" fill="#0b1830"/><g stroke="#2f7d5b" stroke-width="6" stroke-linecap="round" opacity=".8"><path d="M30 130 V60"/><path d="M54 130 V78"/><path d="M30 92 q16 -6 26 -20" fill="none"/></g></g>
  <g transform="translate(520 40)"><rect width="330" height="14" rx="4" fill="#2a3855"/>${book(14,0,18,64,"#34d399")}${book(36,0,14,52,"#60a5fa")}${book(54,0,20,70,"#fbbf24")}${book(78,0,16,58,"#a78bfa")}${book(98,0,18,66,"#f87171")}${book(190,0,22,56,"#60a5fa")}${book(216,0,16,68,"#34d399")}${book(236,0,20,60,"#fbbf24")}${book(260,0,18,72,"#a78bfa")}</g>
  <g transform="translate(520 150)"><rect width="330" height="14" rx="4" fill="#2a3855"/>${book(20,0,20,60,"#fbbf24")}${book(44,0,16,70,"#f87171")}${book(64,0,18,54,"#34d399")}${book(120,0,22,66,"#60a5fa")}${book(146,0,16,58,"#a78bfa")}<rect x="210" y="-46" width="46" height="46" rx="4" fill="#3b4a66"/><rect x="216" y="-40" width="34" height="34" rx="3" fill="#0b1830"/></g>
  <g transform="translate(800 0)"><path d="M0 0 V70" stroke="#3b4a66" stroke-width="3"/><circle cx="0" cy="96" r="52" fill="url(#ofLamp)"/><path d="M-14 74 h28 l-6 24 h-16z" fill="#fbbf24"/></g>
  <g transform="translate(470 262)"><rect x="-12" y="0" width="24" height="24" rx="4" fill="#7a4f1d"/><g stroke="#34d399" stroke-width="5" stroke-linecap="round"><path d="M0 0 V-42"/><path d="M-8 0 V-30"/><path d="M8 0 V-34"/></g></g>
</svg>`;
}

// The panda in his office chair, glasses on, bamboo in mouth, reading a scroll he unrolls for each topic.
export function readerSvg(topic = "INVENTORY", count = "", pull = false) {
  const INK = "#1b2130";
  return `<svg class="panda reader" data-pose="read" viewBox="0 0 320 330" role="img" aria-label="Panda reading a scroll in an office chair" xmlns="http://www.w3.org/2000/svg">
  <g class="chair" aria-hidden="true">
    <rect x="92" y="52" width="136" height="170" rx="44" fill="#2a3752" stroke="#44577d" stroke-width="3"/>
    <rect x="58" y="176" width="22" height="12" rx="6" fill="#33425f"/><rect x="240" y="176" width="22" height="12" rx="6" fill="#33425f"/>
    <ellipse cx="160" cy="244" rx="92" ry="20" fill="#3a4a6b" stroke="#4d618a" stroke-width="2"/>
    <rect x="153" y="252" width="14" height="38" fill="#2a3752"/>
    <path d="M160 292 L96 312 M160 292 L224 312 M160 292 V316" stroke="#2a3752" stroke-width="8" stroke-linecap="round"/>
    <circle cx="94" cy="316" r="8" fill="#1d283e"/><circle cx="226" cy="316" r="8" fill="#1d283e"/><circle cx="160" cy="320" r="8" fill="#1d283e"/>
  </g>
  <g class="figure">
    <g class="legs"><ellipse cx="118" cy="244" rx="28" ry="14" fill="${INK}"/><ellipse cx="202" cy="244" rx="28" ry="14" fill="${INK}"/></g>
    <g class="torso"><ellipse cx="160" cy="196" rx="62" ry="52" fill="#f8fafc"/></g>
    <g class="head">
      <circle cx="108" cy="70" r="18" fill="${INK}"/><circle cx="212" cy="70" r="18" fill="${INK}"/>
      <ellipse cx="160" cy="108" rx="68" ry="50" fill="#f8fafc"/>
      <ellipse cx="132" cy="106" rx="16" ry="19" transform="rotate(24 132 106)" fill="${INK}"/>
      <ellipse cx="188" cy="106" rx="16" ry="19" transform="rotate(-24 188 106)" fill="${INK}"/>
      <g class="eyes"><path d="M125 104 a7 7 0 0 0 14 0z" fill="#fff"/><circle cx="132" cy="108" r="3" fill="#0b1020"/><path d="M124 104 H140" stroke="#94a3b8" stroke-width="2" stroke-linecap="round"/><path d="M181 104 a7 7 0 0 0 14 0z" fill="#fff"/><circle cx="188" cy="108" r="3" fill="#0b1020"/><path d="M180 104 H196" stroke="#94a3b8" stroke-width="2" stroke-linecap="round"/></g>
      <g class="glasses" fill="rgba(125,211,252,.16)" stroke="#fbbf24" stroke-width="3.2"><circle cx="132" cy="106" r="19"/><circle cx="188" cy="106" r="19"/><path d="M151 104 q9 -6 18 0" fill="none"/><path d="M113 102 L100 98 M207 102 L220 98" fill="none" stroke-linecap="round"/></g>
      <ellipse cx="160" cy="124" rx="9" ry="6" fill="${INK}"/><ellipse cx="157.5" cy="122" rx="3" ry="1.6" fill="#64748b" opacity=".7"/>
      <path d="M152 134 Q160 139 168 134" stroke="${INK}" stroke-width="2.6" fill="none" stroke-linecap="round"/>
      <g class="sprig"><path d="M166 135 L204 125" stroke="#4ade80" stroke-width="4" stroke-linecap="round"/><ellipse cx="210" cy="123" rx="10" ry="4" transform="rotate(-18 210 123)" fill="#86efac"/></g>
    </g>
    <g class="heldScroll ${pull ? "pull" : ""}">
      <rect class="paper" x="100" y="176" width="120" height="82" rx="5" fill="#f4e4bd" stroke="#c9ad6a" stroke-width="1.5"/>
      <rect x="92" y="168" width="136" height="12" rx="6" fill="#b9833f"/><rect x="92" y="254" width="136" height="12" rx="6" fill="#b9833f"/>
      <g class="scrollText" fill="#5b4320" text-anchor="middle" font-family="Segoe UI, sans-serif" font-weight="700"><text x="160" y="203" font-size="11.5" letter-spacing="1">${String(topic).replace(/[<>&"']/g, "")}</text><text x="160" y="238" font-size="30">${String(count).replace(/[<>&"']/g, "")}</text></g>
    </g>
    <ellipse class="paw l" cx="100" cy="214" rx="12" ry="14" fill="${INK}"/><ellipse class="paw r" cx="220" cy="214" rx="12" ry="14" fill="${INK}"/>
  </g>
</svg>`;
}

// Grass for the panda dock. `front` draws only the blades that overlap his feet.
export function grassSvg(front = false) {
  const blade = (x, h, lean, c) => `<path d="M${x} 60 Q${x + lean / 2} ${60 - h * 0.6} ${x + lean} ${60 - h}" stroke="${c}" stroke-width="3" fill="none" stroke-linecap="round"/>`;
  const greens = ["#22c55e", "#16a34a", "#4ade80", "#15803d"];
  let blades = "";
  const n = front ? 26 : 34;
  for (let i = 0; i < n; i++) {
    const x = 4 + i * (front ? 6.8 : 5.2);
    const h = front ? 14 + ((i * 7) % 12) : 20 + ((i * 11) % 18);
    const lean = ((i * 5) % 9) - 4;
    blades += blade(x, h, lean, greens[i % 4]);
  }
  const flowers = front ? "" : `<g><circle cx="26" cy="30" r="4" fill="#f9a8d4"/><circle cx="26" cy="30" r="1.6" fill="#fde68a"/><path d="M26 34 V58" stroke="#16a34a" stroke-width="2"/><circle cx="150" cy="26" r="4" fill="#fde68a"/><circle cx="150" cy="26" r="1.6" fill="#f59e0b"/><path d="M150 30 V58" stroke="#16a34a" stroke-width="2"/><circle cx="168" cy="38" r="3.4" fill="#fff"/><circle cx="168" cy="38" r="1.4" fill="#fbbf24"/><path d="M168 41 V58" stroke="#16a34a" stroke-width="2"/></g>`;
  const mound = front ? "" : `<ellipse cx="95" cy="62" rx="94" ry="16" fill="#14532d"/><ellipse cx="95" cy="58" rx="90" ry="13" fill="#166534"/>`;
  return `<svg class="grass ${front ? "front" : "back"}" viewBox="0 0 190 64" preserveAspectRatio="none" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">${mound}${blades}${flowers}</svg>`;
}
