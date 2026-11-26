.pragma library

// Control-center layout engine. Pure functions over plain data, no QML in here, so the
// whole thing can be exercised from node (see the harness in the notes) — this is the one
// part of the editor that can't be verified by dragging things around on screen.
//
// MODEL: a grid `cols` cells wide (square cells, the row height follows the cell width),
// at most `maxRows` tall. An item is {key, x, y, w, h} in cell units. Placement is FREE —
// like iOS 18 / macOS Tahoe: gaps are allowed and persist — with iOS-style DISPLACEMENT:
// dropping onto occupied cells shoves whatever was there to the next free footprint in
// reading order. `tidy()` is the Android behaviour on demand: pack everything in reading
// order, no holes. Sizes are snapped to what each control supports (`sizes` per registry
// entry; a width of 0 means "full width" and resolves to `cols`).

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

// Cells are square, so the cell size follows the column count, and how many ROWS fit is
// really a pixel budget: the panel has to stay on screen. Narrower grids (bigger cells)
// hold fewer rows — which is why a column count the current layout can't survive gets
// refused rather than silently dropping controls.
function cellSize(contentW, cols, gap) { return (contentW - (cols - 1) * gap) / cols; }
function maxRowsFor(contentW, cols, gap, maxPx) {
    const cell = cellSize(contentW, cols, gap);
    return Math.max(2, Math.floor((maxPx + gap) / (cell + gap)));
}

// resolve a registry size ([w,h], w=0 → full width) for a grid `cols` wide
function resolveSize(sz, cols) {
    return [sz[0] === 0 ? cols : Math.min(sz[0], cols), sz[1]];
}

function sizesFor(reg, cols) {
    // de-dup after resolution (a "full" entry and an explicit one can collide at some widths)
    const out = [], seen = {};
    for (let i = 0; i < reg.sizes.length; i++) {
        const s = resolveSize(reg.sizes[i], cols);
        const k = s[0] + "x" + s[1];
        if (!seen[k]) { seen[k] = true; out.push(s); }
    }
    return out;
}

// nearest supported size to a requested (w,h); ties prefer the larger area (growing feels
// right when you drag outward), then the wider one
function snapSize(reg, cols, w, h) {
    const opts = sizesFor(reg, cols);
    let best = null, bestD = Infinity;
    for (let i = 0; i < opts.length; i++) {
        const o = opts[i];
        const d = (o[0] - w) * (o[0] - w) + (o[1] - h) * (o[1] - h);
        if (d < bestD || (d === bestD && best && o[0] * o[1] > best[0] * best[1])) { best = o; bestD = d; }
    }
    return best || resolveSize(reg.def, cols);
}

function overlaps(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

// does a w×h footprint at (x,y) fit inside the grid and clear of every item except `skip`?
function fits(items, cols, maxRows, x, y, w, h, skip) {
    if (x < 0 || y < 0 || x + w > cols || y + h > maxRows) return false;
    const box = { x: x, y: y, w: w, h: h };
    for (let i = 0; i < items.length; i++) {
        const it = items[i];
        if (it.key === skip) continue;
        if (overlaps(box, it)) return false;
    }
    return true;
}

// first free footprint in reading order, scanning from (fromX, fromY); null if none
function firstFree(items, cols, maxRows, w, h, skip, fromX, fromY) {
    let sx = fromX || 0, sy = fromY || 0;
    for (let y = sy; y + h <= maxRows; y++) {
        for (let x = (y === sy ? sx : 0); x + w <= cols; x++) {
            if (fits(items, cols, maxRows, x, y, w, h, skip)) return { x: x, y: y };
        }
    }
    return null;
}

function clone(items) { return items.map(it => ({ key: it.key, x: it.x, y: it.y, w: it.w, h: it.h })); }

function readingOrder(items) {
    return clone(items).sort((a, b) => a.y - b.y || a.x - b.x);
}

// Put `key` at (x,y) with size (w,h). Anything it lands on is displaced to the next free
// footprint in reading order (searched from the displaced item's own position forward,
// then from the top if nothing's left below it). Returns a NEW items array, or null if
// the footprint itself is out of bounds. Displaced items that fit nowhere are dropped —
// the caller (the editor) treats a shrinking result as "doesn't fit" and refuses.
function place(items, cols, maxRows, key, x, y, w, h) {
    if (x < 0 || y < 0 || x + w > cols || y + h > maxRows) return null;
    const rest = clone(items).filter(it => it.key !== key);
    const me = { key: key, x: x, y: y, w: w, h: h };
    const stay = rest.filter(it => !overlaps(me, it));
    const moved = readingOrder(rest.filter(it => overlaps(me, it)));
    const out = stay.concat([me]);
    for (let i = 0; i < moved.length; i++) {
        const it = moved[i];
        let spot = firstFree(out, cols, maxRows, it.w, it.h, null, it.x, it.y)
                || firstFree(out, cols, maxRows, it.w, it.h, null, 0, 0);
        if (!spot) continue;
        out.push({ key: it.key, x: spot.x, y: spot.y, w: it.w, h: it.h });
    }
    return out;
}

// Android-style reflow on demand: keep reading order, pack first-fit with no holes
function tidy(items, cols, maxRows) {
    const ordered = readingOrder(items);
    const out = [];
    for (let i = 0; i < ordered.length; i++) {
        const it = ordered[i];
        const spot = firstFree(out, cols, maxRows, it.w, it.h, null, 0, 0);
        if (!spot) continue;
        out.push({ key: it.key, x: spot.x, y: spot.y, w: it.w, h: it.h });
    }
    return out;
}

function rows(items) {
    let r = 0;
    for (let i = 0; i < items.length; i++) r = Math.max(r, items[i].y + items[i].h);
    return r;
}

// Validate a stored layout against the registry: unknown keys dropped, duplicates dropped,
// sizes snapped to supported ones, anything out of bounds or overlapping re-placed at the
// first free footprint. Idempotent on a good layout.
// Controls that have been renamed. A layout stored before the rename still carries the old
// key, and normalize drops keys the registry does not know, so map them on the way in rather
// than letting someone's tile quietly vanish from their grid. The next write persists the
// new key, so this only ever has to carry one generation.
const RENAMED = { peace: "focus" };

function normalize(items, registry, cols, maxRows) {
    const byKey = {};
    for (let i = 0; i < registry.length; i++) byKey[registry[i].key] = registry[i];
    const out = [];
    const seen = {};
    const src = Array.isArray(items) ? items : [];
    for (let i = 0; i < src.length; i++) {
        const it = src[i];
        if (!it || typeof it.key !== "string") continue;
        const key = RENAMED[it.key] || it.key;
        if (!byKey[key] || seen[key]) continue;
        seen[key] = true;
        const reg = byKey[key];
        const sz = snapSize(reg, cols, it.w | 0, it.h | 0);
        let x = it.x | 0, y = it.y | 0;
        if (!fits(out, cols, maxRows, x, y, sz[0], sz[1], null)) {
            const spot = firstFree(out, cols, maxRows, sz[0], sz[1], null, 0, 0);
            if (!spot) continue;
            x = spot.x; y = spot.y;
        }
        out.push({ key: key, x: x, y: y, w: sz[0], h: sz[1] });
    }
    return out;
}

// The default mosaic (the Tahoe-style arrangement), tidied for the given width so it still
// reads correctly on a 5- or 9-column grid.
function defaults(registry, cols, maxRows) {
    const order = ["wifi", "media", "bluetooth", "focus", "nightlight", "gamemode", "lock", "display", "sound", "notifications"];
    const byKey = {};
    for (let i = 0; i < registry.length; i++) byKey[registry[i].key] = registry[i];
    const out = [];
    for (let i = 0; i < order.length; i++) {
        const reg = byKey[order[i]];
        if (!reg) continue;
        const sz = resolveSize(reg.def, cols);
        const spot = firstFree(out, cols, maxRows, sz[0], sz[1], null, 0, 0);
        if (!spot) continue;
        out.push({ key: reg.key, x: spot.x, y: spot.y, w: sz[0], h: sz[1] });
    }
    return out;
}
