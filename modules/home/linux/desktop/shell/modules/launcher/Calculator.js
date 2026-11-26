.pragma library

// Safe arithmetic evaluator behind the launcher's calculator mode. Recursive-descent
// parser over a fixed grammar, NOT raw eval, so whatever someone types in can never
// execute arbitrary JS. Handles + - * / % ^, unary +/-, parentheses, a whitelist of
// functions, and a handful of constants.

var FUNCS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs,
    sin: Math.sin, cos: Math.cos, tan: Math.tan,
    asin: Math.asin, acos: Math.acos, atan: Math.atan,
    log: Math.log10, ln: Math.log, exp: Math.exp,
    floor: Math.floor, ceil: Math.ceil, round: Math.round
};
var CONSTS = { pi: Math.PI, e: Math.E, tau: 2 * Math.PI };

function evaluate(input) {
    var s = input;
    var i = 0;

    function ws() { while (i < s.length && s[i] === ' ') i++; }

    function parseExpr() { // + -
        var v = parseTerm();
        for (;;) {
            ws();
            var c = s[i];
            if (c === '+') { i++; v += parseTerm(); }
            else if (c === '-') { i++; v -= parseTerm(); }
            else break;
        }
        return v;
    }

    function parseTerm() { // * / %
        var v = parseFactor();
        for (;;) {
            ws();
            var c = s[i];
            if (c === '*') { i++; v *= parseFactor(); }
            else if (c === '/') { i++; v /= parseFactor(); }
            else if (c === '%') { i++; v %= parseFactor(); }
            else break;
        }
        return v;
    }

    function parseFactor() { // unary +/-, then power (right-assoc)
        ws();
        var c = s[i];
        if (c === '+') { i++; return parseFactor(); }
        if (c === '-') { i++; return -parseFactor(); }
        var v = parseBase();
        ws();
        if (s[i] === '^') { i++; v = Math.pow(v, parseFactor()); }
        return v;
    }

    function parseBase() {
        ws();
        var c = s[i];
        if (c === '(') {
            i++;
            var v = parseExpr();
            ws();
            if (s[i] !== ')') throw new Error("expected ')'");
            i++;
            return v;
        }
        var rest = s.slice(i);
        var num = /^[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?/.exec(rest);
        if (num) { i += num[0].length; return parseFloat(num[0]); }
        var id = /^[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
        if (id) {
            var name = id[0].toLowerCase();
            i += id[0].length;
            ws();
            if (s[i] === '(') {
                i++;
                var arg = parseExpr();
                ws();
                if (s[i] !== ')') throw new Error("expected ')'");
                i++;
                if (!(name in FUNCS)) throw new Error("unknown function '" + name + "'");
                return FUNCS[name](arg);
            }
            if (name in CONSTS) return CONSTS[name];
            throw new Error("unknown name '" + name + "'");
        }
        throw new Error("unexpected '" + (c || "end of input") + "'");
    }

    var result = parseExpr();
    ws();
    if (i !== s.length) throw new Error("trailing input");
    if (typeof result !== "number" || !isFinite(result)) throw new Error("not a finite number");
    return result;
}

// Hands back { ok: true, value } or { ok: false, error }.
function tryEval(input) {
    try {
        return { ok: true, value: evaluate(input) };
    } catch (err) {
        return { ok: false, error: String((err && err.message) || err) };
    }
}
