// Waydroid opens every app as its own toplevel with app_id "waydroid.<package>"
// (the desktop window is "Waydroid"). A Wayland client cannot place itself, so
// KWin puts a reopened card wherever its placement policy says. This keeps the
// last position of each app_id for the KWin session and moves the card back
// there when it opens again. Size is left alone: Android sets it from the task.
const saved = {};

function key(window) {
    const cls = String(window.resourceClass);
    return cls === "Waydroid" || cls.startsWith("waydroid.") ? cls : null;
}

// A window is mapped before its first buffer, at a placeholder size; only a
// real frame says where the card is, and only a real frame may be moved.
function sized(window) {
    const g = window.frameGeometry;
    return g.width > 50 && g.height > 50;
}

function remember(window) {
    const k = key(window);
    if (!k || window.fullScreen || window.minimized || !sized(window))
        return;
    const g = window.frameGeometry;
    saved[k] = {x: g.x, y: g.y};
}

// KWin places a new window once its size is known, which can come after our
// first move: for this long after the first real frame the saved position
// wins over any other, and nothing is recorded.
const SETTLE_MS = 1500;

function track(window) {
    const k = key(window);
    if (!k || !window.normalWindow)
        return;
    const pos = saved[k];
    let settleUntil = 0;
    const update = () => {
        if (!sized(window))
            return;
        if (pos && settleUntil === 0)
            settleUntil = Date.now() + SETTLE_MS;
        if (pos && Date.now() < settleUntil) {
            const g = window.frameGeometry;
            if (g.x !== pos.x || g.y !== pos.y)
                window.frameGeometry = {x: pos.x, y: pos.y, width: g.width, height: g.height};
            return;
        }
        remember(window);
    };
    update();
    window.frameGeometryChanged.connect(update);
    window.closed.connect(() => remember(window));
}

workspace.windowList().forEach(track);
workspace.windowAdded.connect(track);
