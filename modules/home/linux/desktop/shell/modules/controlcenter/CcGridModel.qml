import QtQuick

// A ListModel of placed controls, synced BY KEY from Config.ccItems. Config republishes a
// brand-new array on every layout write, and handing that straight to a Repeater rebuilds
// every delegate (patterns.md #3): cards would blink mid-edit, and a drag in the editor
// would lose its delegate right under the pointer. Syncing in place means an unchanged
// control keeps its delegate and a moved one just gets new coordinates, which is exactly
// what the Behaviors on x/y then animate.
//
// Roles are gx/gy/gw/gh (cells) and ckey, deliberately NOT x/y/width/height/key so they
// can never shadow the delegate item's own properties.
ListModel {
    function sync(items) {
        const seen = {};
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            seen[it.key] = true;
            let idx = -1;
            for (let j = 0; j < count; j++) if (get(j).ckey === it.key) { idx = j; break; }
            if (idx < 0) { append({ ckey: it.key, gx: it.x, gy: it.y, gw: it.w, gh: it.h }); continue; }
            const cur = get(idx);
            if (cur.gx !== it.x) setProperty(idx, "gx", it.x);
            if (cur.gy !== it.y) setProperty(idx, "gy", it.y);
            if (cur.gw !== it.w) setProperty(idx, "gw", it.w);
            if (cur.gh !== it.h) setProperty(idx, "gh", it.h);
        }
        for (let j = count - 1; j >= 0; j--) if (!seen[get(j).ckey]) remove(j);
    }
}
