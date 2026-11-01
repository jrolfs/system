pragma Singleton
import Quickshell
import Quickshell.Services.Polkit

// Session-global polkit auth agent. Made once; the prompt (a separate, isolated
// scope) gets at the live request through this singleton. We NEVER check the
// password ourselves, only flow.submit() does and polkitd is the one who decides.
// The prompt has to show the real action (so a rogue app can't fake a generic one)
// and cancel on dismiss (fail closed). Only one agent registers per session, so if
// ours never shows up, something else grabbed the slot first.
Singleton {
    id: root

    readonly property var flow: agent.flow
    readonly property bool active: agent.isActive && agent.flow !== null
    readonly property bool registered: agent.isRegistered

    PolkitAgent {
        id: agent
        // path defaults to /org/quickshell/Polkit
    }
}
