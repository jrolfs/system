.pragma library

const vulgar = { "½": 1 / 2, "⅓": 1 / 3, "⅔": 2 / 3, "¼": 1 / 4, "¾": 3 / 4 };

// How much of the screen's width a label names: "7⁄12", "⅔", "two thirds", "half".
function share(l) {
    const typed = l.match(/(\d+)\s*[⁄\/]\s*(\d+)/);
    if (typed && Number(typed[2]) > 0) return Number(typed[1]) / Number(typed[2]);
    for (const glyph in vulgar) if (l.indexOf(glyph) >= 0) return vulgar[glyph];
    if (l.indexOf("two thirds") >= 0) return 2 / 3;
    if (l.indexOf("third") >= 0) return 1 / 3;
    if (l.indexOf("half") >= 0) return 1 / 2;
    return 0;
}

// Where a window-mode bind puts the window, read off its label ("Left half", "Right 5⁄12",
// "Top right", "Top of its column", "Gapped full", "Center (floating)") as fractions of the
// screen, or null when the label names no region.
function region(label) {
    const l = String(label).toLowerCase();
    const has = word => l.indexOf(word) >= 0;
    const left = has("left"), right = has("right"), top = has("top"), bottom = has("bottom");
    const middle = has("centre") || has("center") || has("middle");
    const w = share(l);

    if ((left || right) && (top || bottom))
        return { x: right ? 0.5 : 0, y: bottom ? 0.5 : 0, w: 0.5, h: 0.5 };
    if (w > 0 && (left || right))
        return { x: right ? 1 - w : 0, y: 0, w, h: 1 };
    if (w > 0 && middle)
        return { x: (1 - w) / 2, y: 0, w, h: 1 };
    if (top || bottom)
        return { x: 0, y: bottom ? 0.5 : 0, w: 1, h: 0.5 };
    if (has("gapped"))
        return { x: 0.06, y: 0.08, w: 0.88, h: 0.84 };
    if (has("maximi") || has("fill") || has("full"))
        return { x: 0, y: 0, w: 1, h: 1 };
    if (middle)
        return { x: 0.2, y: 0.15, w: 0.6, h: 0.7 };
    return null;
}
