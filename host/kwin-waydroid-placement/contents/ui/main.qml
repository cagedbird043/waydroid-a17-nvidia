// Waydroid opens every app as its own toplevel with app_id "waydroid.<package>"
// (the desktop window is "Waydroid"). A Wayland client cannot place itself, so
// KWin puts a reopened card wherever its placement policy says. This keeps the
// last position of each app_id in ~/.config/kwin-waydroid-placement.conf and
// moves the card back there when it opens again. Size is left alone: Android
// sets it from the task.
import QtQuick
import QtCore
import org.kde.kwin

Item {
    id: root

    // KWin places a new window once its size is known, which can come after
    // our first move: for this long after the first real frame the saved
    // position wins over any other, and nothing is recorded.
    readonly property int settleMs: 1500

    Settings {
        id: store
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwin-waydroid-placement.conf"
        category: "Positions"
    }

    function key(window) {
        const cls = String(window.resourceClass);
        return cls === "Waydroid" || cls.startsWith("waydroid.") ? cls : null;
    }

    // A window is mapped before its first buffer, at a placeholder size; only
    // a real frame says where the card is, and only a real frame may be moved.
    function sized(window) {
        const g = window.frameGeometry;
        return g.width > 50 && g.height > 50;
    }

    function saved(k) {
        const v = String(store.value(k, "")).split(",");
        return v.length === 2 ? {x: Number(v[0]), y: Number(v[1])} : null;
    }

    function remember(window) {
        const k = key(window);
        if (!k || window.fullScreen || window.minimized || !sized(window))
            return;
        const g = window.frameGeometry;
        const v = Math.round(g.x) + "," + Math.round(g.y);
        if (store.value(k, "") !== v)
            store.setValue(k, v);
    }

    function track(window) {
        const k = key(window);
        if (!k || !window.normalWindow)
            return;
        const pos = saved(k);
        let settleUntil = 0;
        const update = () => {
            if (!sized(window))
                return;
            if (pos && settleUntil === 0)
                settleUntil = Date.now() + root.settleMs;
            if (pos && Date.now() < settleUntil) {
                const g = window.frameGeometry;
                if (g.x !== pos.x || g.y !== pos.y)
                    window.frameGeometry = Qt.rect(pos.x, pos.y, g.width, g.height);
                return;
            }
            remember(window);
        };
        update();
        window.frameGeometryChanged.connect(update);
        window.closed.connect(() => remember(window));
    }

    Connections {
        target: Workspace
        function onWindowAdded(window) { root.track(window); }
    }

    Component.onCompleted: Workspace.windows.forEach(track)
}
