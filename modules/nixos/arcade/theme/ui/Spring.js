.pragma library

// The desktop shell's spring (modules/home/linux/desktop/shell/theme/Theme.qml,
// springCurve), unchanged: the step response of a damped harmonic oscillator,
// sampled and handed to Qt as a cubic bezier spline, so motion starts from rest,
// overshoots a touch and settles instead of creeping up on its target.
//
// zeta is the damping ratio: 1 settles with no overshoot, lower overshoots and
// eases back. Eight segments is the shell's ceiling, because Qt's spline solver
// has crashed on an overshooting curve cut much finer than that.
function curve(zeta, segments) {
    var n = segments || 8;
    var z = Math.max(0.4, Math.min(1.0, zeta));
    var w = 6.5 / z;
    var under = z < 0.999;
    var wd = under ? w * Math.sqrt(1 - z * z) : 0;
    var k = under ? (z * w / wd) : 0;

    function value(t) {
        return under ? 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + k * Math.sin(wd * t))
                     : 1 - (1 + w * t) * Math.exp(-w * t);
    }
    function slope(t) {
        return under ? (w * w / wd) * Math.exp(-z * w * t) * Math.sin(wd * t)
                     : w * w * t * Math.exp(-w * t);
    }

    var points = [];
    var h = 1 / n;
    for (var i = 0; i < n; i++) {
        var last = i === n - 1;
        var t0 = i * h;
        var t1 = last ? 1 : (i + 1) * h;
        var y0 = value(t0);
        var y1 = last ? 1 : value(t1);
        var s0 = slope(t0);
        var s1 = last ? 0 : slope(t1);
        points.push(t0 + h / 3, y0 + s0 * h / 3,
                    t1 - h / 3, y1 - s1 * h / 3,
                    t1, y1);
    }
    return points;
}
