import QtQuick 2.15
import QtQuick.Window 2.15
import "."

// A floating glass surface, the shell's island and panels in Qt 5: the blurred
// backdrop seen through a translucent pane, a faint light rim, and one soft
// shadow underneath.
//
// On the desktop Hyprland does the blur behind the shell's windows. gamescope
// blurs nothing, so Backdrop.qml keeps a blurred copy of itself and the pane
// samples it at its own screen position (gl_FragCoord), which keeps the two
// lined up through any move or transform without tracking geometry. That only
// holds while the pane draws straight to the window, so nothing above a Pane
// may set layer.enabled.
Item {
    id: root

    property real radius: Theme.rLg
    property color tint: Theme.base
    property color rim: Theme.rim
    property bool shadow: true
    // Backdrop.blurred
    property var backdrop: null

    ShaderEffect {
        readonly property real spread: Theme.shadowBlur

        visible: root.shadow
        x: -spread
        y: -spread + Theme.shadowY
        width: root.width + 2 * spread
        height: root.height + 2 * spread

        property size box: Qt.size(root.width, root.height)
        property real radius: Math.min(root.radius, Math.min(root.width, root.height) / 2)
        property real blur: spread
        property color color: Theme.shadow
        property size pixelSize: Qt.size(width, height)

        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform highp vec2 box;
            uniform highp float radius;
            uniform highp float blur;
            uniform lowp vec4 color;
            uniform highp vec2 pixelSize;

            highp float roundedBox(highp vec2 p, highp vec2 halfSize, highp float r) {
                highp vec2 q = abs(p) - halfSize + vec2(r);
                return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
            }

            void main() {
                highp vec2 p = qt_TexCoord0 * pixelSize - pixelSize * 0.5;
                highp float d = roundedBox(p, box * 0.5, radius);
                highp float a = 1.0 - smoothstep(-blur * 0.35, blur * 0.65, d);
                gl_FragColor = color * (a * a) * qt_Opacity;
            }"
    }

    ShaderEffect {
        anchors.fill: parent

        property variant source: root.backdrop
        property real radius: Math.min(root.radius, Math.min(width, height) / 2)
        property color tint: root.tint
        property color rim: root.rim
        property real rimWidth: Theme.hairlineWidth
        property size pixelSize: Qt.size(width, height)
        property size screen: Qt.size(Theme.screenWidth * Screen.devicePixelRatio,
                                      Theme.screenHeight * Screen.devicePixelRatio)
        property real vibrancy: Theme.station.vibrancy

        // Colours arrive premultiplied, so a tint or the rim composites over
        // the backdrop as `c + under * (1 - c.a)`.
        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform lowp float qt_Opacity;
            uniform sampler2D source;
            uniform highp float radius;
            uniform lowp vec4 tint;
            uniform lowp vec4 rim;
            uniform highp float rimWidth;
            uniform highp vec2 pixelSize;
            uniform highp vec2 screen;
            uniform highp float vibrancy;

            highp float roundedBox(highp vec2 p, highp vec2 halfSize, highp float r) {
                highp vec2 q = abs(p) - halfSize + vec2(r);
                return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
            }

            void main() {
                highp vec2 p = qt_TexCoord0 * pixelSize - pixelSize * 0.5;
                highp float d = roundedBox(p, pixelSize * 0.5, radius);
                highp float inside = clamp(0.5 - d, 0.0, 1.0);

                highp vec2 uv = vec2(gl_FragCoord.x / screen.x, 1.0 - gl_FragCoord.y / screen.y);
                lowp vec3 under = texture2D(source, uv).rgb;
                lowp float l = dot(under, vec3(0.2126, 0.7152, 0.0722));
                under = clamp(mix(vec3(l), under, 1.0 + vibrancy), 0.0, 1.0);

                lowp vec3 c = tint.rgb + under * (1.0 - tint.a);
                highp float ring = inside * clamp(d + rimWidth + 0.5, 0.0, 1.0);
                c = rim.rgb * ring + c * (1.0 - rim.a * ring);

                gl_FragColor = vec4(c, 1.0) * inside * qt_Opacity;
            }"
    }
}
