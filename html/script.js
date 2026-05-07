'use strict';

// GTA V default ped height: 6'0" = 72 inches
const BASE_IN = 72;

let minScale     = 0.806;
let maxScale     = 1.194;
let defaultScale = 1.0;
let currentScale = 1.0;

const menu       = document.getElementById('scale-menu');
const slider     = document.getElementById('height-slider');
const impEl      = document.getElementById('height-imperial');
const metEl      = document.getElementById('height-metric');
const scaleEl    = document.getElementById('stat-scale');
const diffEl     = document.getElementById('stat-diff');
const tickMinEl  = document.getElementById('tick-min');
const tickMidEl  = document.getElementById('tick-mid');
const tickMaxEl  = document.getElementById('tick-max');
const rangeLabel = document.getElementById('slider-range-label');
const defTick    = document.getElementById('default-tick');

// ── Conversions ──────────────────────────────────────────────────────
function toInches(scale) {
    return scale * BASE_IN;
}

function fmtImperial(totalIn) {
    const ft   = Math.floor(totalIn / 12);
    let   inch = Math.round(totalIn % 12);
    if (inch === 12) return `${ft + 1}'0"`;
    return `${ft}'${inch}"`;
}

function toCm(totalIn) {
    return Math.round(totalIn * 2.54);
}

function scaleToSlider(scale) {
    return ((scale - minScale) / (maxScale - minScale)) * 1000;
}

function sliderToScale(val) {
    return minScale + (val / 1000) * (maxScale - minScale);
}

// ── Display update ───────────────────────────────────────────────────
function updateDisplay(scale) {
    currentScale = scale;

    const inches   = toInches(scale);
    const defIn    = toInches(defaultScale);
    const diffIn   = Math.round(inches - defIn);
    const progress = ((scale - minScale) / (maxScale - minScale)) * 100;

    impEl.textContent   = fmtImperial(inches);
    metEl.textContent   = toCm(inches) + ' cm';
    scaleEl.textContent = scale.toFixed(2) + '×';
    diffEl.textContent  = (diffIn >= 0 ? '+' : '') + diffIn + '"';

    // Update slider fill gradient via CSS custom property
    slider.style.setProperty('--fill', progress.toFixed(2) + '%');
    slider.value = Math.round(scaleToSlider(scale));

    // Brief glow pulse on the large number
    impEl.classList.remove('pulse');
    void impEl.offsetWidth; // reflow to restart animation
    impEl.classList.add('pulse');
    setTimeout(() => impEl.classList.remove('pulse'), 200);
}

// ── Open / Close ─────────────────────────────────────────────────────
function openMenu(data) {
    // Apply theme colour
    if (data.themeColor) {
        const hex = data.themeColor.replace('#', '');
        const r   = parseInt(hex.slice(0, 2), 16);
        const g   = parseInt(hex.slice(2, 4), 16);
        const b   = parseInt(hex.slice(4, 6), 16);
        document.documentElement.style.setProperty('--accent',     data.themeColor);
        document.documentElement.style.setProperty('--accent-rgb', `${r}, ${g}, ${b}`);
    }

    minScale     = data.minScale     ?? 0.806;
    maxScale     = data.maxScale     ?? 1.194;
    defaultScale = data.defaultScale ?? 1.0;

    // Tick labels derived from actual scale range
    const minIn = toInches(minScale);
    const defIn = toInches(defaultScale);
    const maxIn = toInches(maxScale);

    tickMinEl.textContent  = fmtImperial(minIn);
    tickMidEl.textContent  = fmtImperial(defIn) + ' avg';
    tickMaxEl.textContent  = fmtImperial(maxIn);
    rangeLabel.textContent = fmtImperial(minIn) + ' — ' + fmtImperial(maxIn);

    // Position the default-height tick mark
    const defPct = ((defaultScale - minScale) / (maxScale - minScale)) * 100;
    defTick.style.left = defPct.toFixed(2) + '%';

    updateDisplay(data.scale ?? defaultScale);

    menu.classList.remove('hidden');
    requestAnimationFrame(() =>
        requestAnimationFrame(() => menu.classList.add('visible'))
    );
}

function closeMenu() {
    menu.classList.remove('visible');
    setTimeout(() => menu.classList.add('hidden'), 340);
}

// ── Slider ───────────────────────────────────────────────────────────
slider.addEventListener('input', function () {
    updateDisplay(sliderToScale(parseFloat(this.value)));
});

// ── Buttons ──────────────────────────────────────────────────────────
document.getElementById('btn-confirm').addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/confirm`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ scale: currentScale }),
    });
    closeMenu();
});

document.getElementById('btn-reset').addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/reset`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({}),
    });
    closeMenu();
});

// ── Message handler (from Lua SendNUIMessage) ────────────────────────
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data?.type) return;
    if (data.type === 'openMenu')  openMenu(data);
    if (data.type === 'closeMenu') closeMenu();
});

// ── Escape key ───────────────────────────────────────────────────────
window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        fetch(`https://${GetParentResourceName()}/close`, {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({}),
        });
        closeMenu();
    }
});
