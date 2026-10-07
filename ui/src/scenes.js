// Static, calm scenery for the Inventory Room. No animation here: the panda is the only thing that moves.
export function roomSvg() {
  const jar = (x, y, c, h = 34) => `<rect x="${x}" y="${y - h}" width="26" height="${h}" rx="6" fill="${c}" opacity=".85"/><rect x="${x + 3}" y="${y - h - 6}" width="20" height="7" rx="3" fill="#3b4a66"/>`;
  const box = (x, y, w, h, c) => `<rect x="${x}" y="${y - h}" width="${w}" height="${h}" rx="4" fill="${c}"/><rect x="${x + 5}" y="${y - h + 8}" width="${w - 10}" height="5" rx="2" fill="rgba(255,255,255,.22)"/>`;
  return `<svg class="roomScene" viewBox="0 0 900 250" preserveAspectRatio="xMidYMid slice" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="rmWall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16213a"/><stop offset="1" stop-color="#0e1729"/></linearGradient>
    <radialGradient id="rmGlow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fde68a" stop-opacity=".55"/><stop offset="1" stop-color="#fde68a" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="900" height="250" fill="url(#rmWall)"/>
  <rect y="214" width="900" height="36" fill="#0a1120"/><rect y="212" width="900" height="3" fill="#24324f"/>
  <g transform="translate(640 36)"><rect width="150" height="120" rx="10" fill="#0b1830" stroke="#2d3b59" stroke-width="4"/><path d="M75 0 V120 M0 60 H150" stroke="#2d3b59" stroke-width="4"/><circle cx="112" cy="34" r="14" fill="#e2e8f0" opacity=".9"/><circle cx="118" cy="30" r="12" fill="#0b1830"/><g stroke="#2f7d5b" stroke-width="5" stroke-linecap="round" opacity=".8"><path d="M30 120 V54"/><path d="M52 120 V70"/><path d="M30 80 q14 -6 24 -18" fill="none"/></g></g>
  <g><rect x="40" y="96" width="460" height="7" rx="3" fill="#2a3855"/>${jar(62, 96, "#34d399")}${box(104, 96, 38, 40, "#4f7cff")}${jar(158, 96, "#fbbf24", 44)}${box(196, 96, 46, 30, "#a78bfa")}${jar(262, 96, "#f87171", 30)}${box(300, 96, 40, 44, "#34d399")}${jar(356, 96, "#60a5fa", 38)}${box(394, 96, 56, 28, "#fbbf24")}</g>
  <g><rect x="40" y="170" width="460" height="7" rx="3" fill="#2a3855"/>${box(60, 170, 52, 36, "#60a5fa")}${jar(128, 170, "#a78bfa", 40)}${box(168, 170, 40, 46, "#f87171")}${jar(224, 170, "#34d399", 32)}${box(262, 170, 60, 30, "#4f7cff")}${jar(338, 170, "#fbbf24", 42)}${box(378, 170, 44, 38, "#34d399")}</g>
  <g transform="translate(560 0)"><path d="M0 0 V34" stroke="#3b4a66" stroke-width="3"/><circle cx="0" cy="62" r="46" fill="url(#rmGlow)"/><rect x="-11" y="34" width="22" height="30" rx="6" fill="#fbbf24"/><rect x="-14" y="30" width="28" height="7" rx="3" fill="#3b4a66"/></g>
</svg>`;
}
