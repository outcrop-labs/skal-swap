import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Claude Code API profile switcher. Shows the active key/endpoint profile,
// click to pick another from the popup, middle-click for a quick swap.
// The companion CLI (bin/skal-swap, resolved relative to this file) owns all
// state: it rewrites the managed ANTHROPIC_* env in ~/.claude/settings.json;
// this widget only reads `skal-swap status --json` and watches the two files
// involved (settings.json + profiles.conf), so it stays in sync no matter
// what changed them — menu click, terminal, or manual edit.
//
// Settings live inline on the bar layout entry in shell.json:
//   { "id": "skal.swap", "labelStyle": "Name", "glyph": "󰌆" }
//
// IPC is deliberately not registered (manageIpc: false): a bar widget is
// instantiated once per monitor and only one copy could own the target —
// the CLI/hotkey path (`skal-swap swap`) is the machine-wide interface.
Panel {
  id: root

  manageIpc: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string settingsPath: home + "/.claude/settings.json"
  readonly property string profilesPath: home + "/.config/skal.swap/profiles.conf"
  // Resolve the CLI next to this QML file so the plugin works straight
  // after clone, with no PATH install; fall back to a PATH lookup.
  readonly property string cli: {
    var u = Qt.resolvedUrl("bin/skal-swap").toString()
    return u.indexOf("file://") === 0 ? u.substring(7) : "skal-swap"
  }

  property string glyph: String(setting("glyph", "󰌆"))
  property string labelStyle: String(setting("labelStyle", "Name")) // Name | Host | Icon
  property string iconMode: String(setting("icon", "Logo")) // Logo | Glyph | None

  property var statusJson: null
  property var usageById: ({})
  property string lastCurrent: ""
  property bool armed: false

  readonly property var profiles: (statusJson && statusJson.profiles) ? statusJson.profiles : []
  readonly property var currentProfile: {
    if (!statusJson || !statusJson.current_known) return null
    for (var i = 0; i < profiles.length; i++)
      if (profiles[i].id === statusJson.current) return profiles[i]
    return null
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string labelBase: {
    if (!statusJson) return "…"
    if (!currentProfile) return "custom"
    if (labelStyle === "Icon") return ""
    return labelStyle === "Host" ? currentProfile.host : currentProfile.name
  }

  implicitWidth: content.implicitWidth + Style.space(10)
  implicitHeight: button.implicitHeight

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshUsage() {
    if (!usageProc.running) usageProc.running = true
  }

  // Earliest upcoming window reset across an account's metrics, as an
  // epoch-ms timestamp (0 when none are known).
  function nearestReset(metrics) {
    if (!metrics) return 0
    var best = 0
    var now = Date.now()
    for (var i = 0; i < metrics.length; i++) {
      var at = metrics[i].reset_at
      if (!at) continue
      var t = Date.parse(at)
      if (t > now && (best === 0 || t < best)) best = t
    }
    return best
  }

  function humanUntil(then) {
    var s = Math.floor((then - Date.now()) / 1000)
    if (s <= 0) return ""
    var d = Math.floor(s / 86400); s -= d * 86400
    var h = Math.floor(s / 3600); s -= h * 3600
    var m = Math.floor(s / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }

  function announce(name) {
    // Default app-name is deliberate: omarchy-action is the notification
    // daemon's DND-bypass identity for user-action confirmations.
    Util.execArgv(["omarchy-notification-send", "-g", glyph, "-u", "low",
                   "-r", "211", "Claude Code → " + name,
                   "restart running claude sessions to pick it up"])
  }

  function useProfile(id, name) {
    useProc.pendingName = name || id
    useProc.command = [cli, "use", id]
    useProc.running = true
  }

  function quickSwap() {
    swapProc.running = true
  }

  Component.onCompleted: {
    refreshStatus()
    // Warm the usage cache in the background so the first popup open paints
    // instantly instead of waiting on the multi-account fetch.
    refreshUsage()
  }

  // Announce profile changes from ANY source (menu, terminal, manual edit)
  // — the watcher is the single authority. The grace window keeps shell
  // startup from toasting the state it just loaded.
  Timer { interval: 3000; running: true; onTriggered: root.armed = true }

  onStatusJsonChanged: {
    if (!statusJson) return
    var cur = statusJson.current || ""
    if (root.armed && root.lastCurrent !== "" && cur !== root.lastCurrent && cur !== "") {
      // Look the name up in the fresh statusJson itself — the
      // currentProfile binding may not have re-evaluated yet when read
      // synchronously inside this handler.
      var name = "unknown profile"
      var list = statusJson.profiles || []
      for (var i = 0; i < list.length; i++)
        if (list[i].id === cur) name = list[i].name
      announce(name)
    }
    root.lastCurrent = cur
  }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.statusJson = JSON.parse(text || "null") }
        catch (e) { root.statusJson = null }
      }
    }
  }

  Process {
    id: useProc
    property string pendingName: ""
    command: [root.cli, "status", "--json"] // placeholder until first use
    onExited: function(code) {
      root.refreshStatus()
      if (code !== 0) {
        Util.execArgv(["omarchy-notification-send", "-g", root.glyph, "-u", "normal",
                       "-r", "212", "Profile switch failed",
                       root.useProc.pendingName])
      }
    }
  }

  Process {
    id: swapProc
    command: [root.cli, "swap"]
    onExited: function(code) { root.refreshStatus() }
  }

  Process {
    id: usageProc
    command: [root.cli, "usage", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = {}
        try {
          var parsed = JSON.parse(text || "null")
          var entries = (parsed && parsed.entries) ? parsed.entries : []
          for (var i = 0; i < entries.length; i++) map[entries[i].id] = entries[i]
        } catch (e) {}
        root.usageById = map
      }
    }
  }

  // Atomic CLI writes can fire several watcher events; debounce to one read.
  Timer { id: refresh; interval: 150; onTriggered: root.refreshStatus() }

  // Watchers give instant refresh, but editors that save via rename (sed -i,
  // helix, …) strand an inode watcher silently. A slow poll re-syncs the
  // label even then; status --json is a cheap local read.
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.refreshStatus() }

  // Usage windows move on hour scales; the CLI serves its disk cache
  // instantly and refetches only past the TTL, so a refresh every few
  // minutes is plenty while the picker sits open.
  Timer { interval: 300000; repeat: true; running: root.opened; onTriggered: root.refreshUsage() }

  FileView {
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: refresh.restart()
  }

  FileView {
    path: root.profilesPath
    watchChanges: true
    printErrors: false
    onFileChanged: refresh.restart()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    keepSpace: true
    tooltipText: root.currentProfile
      ? root.currentProfile.name + " · " + root.currentProfile.host
      : "Claude Code profile"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.quickSwap()
      else if (b === Qt.LeftButton) root.toggle()
    }
  }

  // Icon + label render above the textless button (clicks still reach it —
  // this row holds no mouse areas), so the Claude logomark and the profile
  // name can be laid out as one centered row. The mark is colorized to the
  // bar foreground so it follows the theme like any text glyph.
  Row {
    id: content
    anchors.centerIn: parent
    spacing: (iconMode === "None" || labelBase === "") ? 0 : Style.space(4)

    Item {
      visible: root.iconMode === "Logo"
      width: visible ? Math.round(Style.font.body * 1.5) : 0
      height: width

      Image {
        id: logoProvider
        anchors.fill: parent
        anchors.margins: 2
        source: Qt.resolvedUrl("assets/claude.svg")
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectFit
      }

      MultiEffect {
        anchors.fill: logoProvider
        source: logoProvider
        autoPaddingEnabled: false
        colorization: 1.0
        colorizationColor: root.foreground
      }
    }

    Text {
      visible: root.iconMode === "Glyph"
      text: root.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      text: root.labelBase
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  // KeyboardPanel (layer-shell) rather than PopupCard (xdg-popup): the
  // compositor renders the xdg-popup surface translucent on some setups,
  // while the layer-shell card paints solid — same as the kit's own
  // dropdowns. Also brings keyboard focus, so Esc closes the picker.
  KeyboardPanel {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(300)
    contentHeight: fittedContentHeight(menuColumn.implicitHeight, Style.space(440))

    onOpenChanged: if (open) root.refreshUsage()

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      Keys.onEscapePressed: root.close()
    }

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(2)

      Row {
        width: menuColumn.width
        spacing: Style.space(4)

        Item {
          width: Style.font.caption * 1.2
          height: width
          anchors.verticalCenter: parent.verticalCenter

          Image {
            id: headerProvider
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/claude.svg")
            sourceSize: Qt.size(48, 48)
            fillMode: Image.PreserveAspectFit
          }

          MultiEffect {
            anchors.fill: parent
            source: headerProvider
            autoPaddingEnabled: false
        colorization: 1.0
            colorizationColor: root.foreground
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Claude Code profile"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Item { width: menuColumn.width; height: Style.space(5) }

      Rectangle {
        width: menuColumn.width
        height: 1
        color: Util.alpha(Color.muted, 0.55)
      }

      Item { width: menuColumn.width; height: Style.space(5) }

      Repeater {
        model: root.profiles

        delegate: Rectangle {
          id: row
          width: menuColumn.width
          color: "transparent"
          height: (usageInfo ? Style.space(68) : Style.space(30))
                + (alibabaHost ? Style.space(30) : 0)

          readonly property color rowFg: root.bar ? root.bar.barForeground : Color.foreground
          readonly property var prof: modelData
          readonly property bool active: root.statusJson && root.statusJson.current === prof.id
          readonly property var usageInfo: prof.usage_id ? (root.usageById[prof.usage_id] || null) : null
          // Alibaba publishes no usage API for token plans — the console is
          // the only place quota exists, so each alibaba row links to it.
          readonly property bool alibabaHost: {
            var h = prof.host || ""
            return h.indexOf("maas.aliyuncs.com") >= 0 || h.indexOf("dashscope") >= 0
          }
          // Progress-bar metrics (max 2), one per window with a percent.
          readonly property var barMetrics: {
            if (!usageInfo || !usageInfo.metrics) return []
            var withPercent = []
            for (var i = 0; i < usageInfo.metrics.length; i++)
              if (usageInfo.metrics[i].percent != null) withPercent.push(usageInfo.metrics[i])
            return withPercent.slice(0, 2)
          }
          // Footer line: "GLM Coding Max · resets in 3h 55m" — plan name
          // plus the nearest upcoming window reset. Hidden when there is
          // no usage data; key material is never rendered in the menu.
          readonly property string detailLine: {
            if (!usageInfo) return ""
            var parts = []
            if (usageInfo.plan) parts.push(usageInfo.plan)
            var reset = root.nearestReset(usageInfo.metrics)
            if (reset > 0) parts.push("resets in " + root.humanUntil(reset))
            return parts.join(" · ")
          }

          // Zone 1: the profile entry itself, sized exactly like every
          // other row so content alignment never shifts.
          Item {
            id: contentZone
            width: parent.width
            height: row.usageInfo ? Style.space(68) : Style.space(30)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: rowMouse.containsMouse ? Util.alpha(row.rowFg.color, 0.08) : "transparent"
            }

            // Active marker: accent pill down the left edge.
            Rectangle {
              visible: row.active
              width: 3
              radius: width / 2
              color: Color.accent
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.topMargin: Style.space(4)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
            }

            // Left+right anchors give the column a definite width, so the
            // child Texts can bind width to it without a binding loop.
            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              // Title line: provider mark (assets/providers/<icon>.svg,
              // from the CLI's host mapping or the profile's `icon =` key)
              // inline with the name, tinted to the theme — accent while
              // active.
              Row {
                width: parent.width
                spacing: Style.space(6)

                Item {
                  id: providerMark
                  width: Style.space(22)
                  height: width
                  anchors.verticalCenter: parent.verticalCenter

                  // A couple of pixels of breathing room on every edge —
                  // marks that paint to the SVG edge (the Z.AI border)
                  // otherwise meet the effect's texture boundary.
                  Image {
                    id: providerProvider
                    anchors.fill: parent
                    anchors.margins: 2
                    source: Qt.resolvedUrl("assets/providers/" + (row.prof.icon || "claude") + ".svg")
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                  }

                  MultiEffect {
                    anchors.fill: providerProvider
                    source: providerProvider
                    autoPaddingEnabled: false
                    colorization: 1.0
                    colorizationColor: row.active ? Color.accent : row.rowFg
                  }
                }

                Text {
                  width: parent.width - providerMark.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.prof.name
                  color: row.active ? Color.accent : row.rowFg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: row.active
                  elide: Text.ElideRight
                }
              }

              // One meter line per usage window (session, weekly) under the
              // name: progress bar plus its percentage, labeled by the
              // window's initial. Urgent fill past 80%.
              Column {
                id: barStack
                width: parent.width
                spacing: Style.space(4)
                visible: row.barMetrics.length > 0

                Repeater {
                  model: row.barMetrics

                  Row {
                    spacing: Style.space(6)

                    UsageBar {
                      width: barStack.width - pctText.implicitWidth - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter
                      fraction: Util.clamp((modelData.percent || 0) / 100, 0, 1)
                      warn: (modelData.percent || 0) > 80
                    }

                    Text {
                      id: pctText
                      anchors.verticalCenter: parent.verticalCenter
                      text: {
                        var label = String(modelData.label || "")
                        var initial = (label.match(/[A-Za-z]/) || [""])[0]
                        return initial ? initial + " " + modelData.percent + "%"
                                       : modelData.percent + "%"
                      }
                      color: (modelData.percent || 0) > 80 ? Color.urgent : row.rowFg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: row.detailLine
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.close()
                if (!row.active) root.useProfile(row.prof.id, row.prof.name)
              }
            }
          }

          // Zone 2 (alibaba rows): breathing room, then the console link.
          Item {
            visible: row.alibabaHost
            height: visible ? Style.space(30) : 0
            width: parent.width
            anchors.bottom: parent.bottom

            Rectangle {
              id: consolePlate
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Style.space(24)
              radius: Style.cornerRadius
              color: consoleMouse.containsMouse ? Util.alpha(Color.muted, 0.15) : "transparent"
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(26)
              anchors.verticalCenter: consolePlate.verticalCenter
              text: "quota in Alibaba console  ↗"
              color: consoleMouse.containsMouse ? row.rowFg : Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: consoleMouse
              anchors.fill: consolePlate
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Util.execDetached(
                "xdg-open https://bailian.console.aliyun.com/?#/efm/subscription/overview")
            }
          }
        }
      }

      // Live token matches no profile (manual edit / new key).
      Rectangle {
        width: menuColumn.width
        height: root.statusJson && root.statusJson.current_known === false ? Style.space(24) : 0
        visible: height > 0
        color: "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "⚠ active key matches no profile"
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.muted, 0.3) }

      Rectangle {
        width: menuColumn.width
        height: Style.space(30)
        radius: Style.cornerRadius
        color: editMouse.containsMouse ? Util.alpha(editFg.color, 0.08) : "transparent"
        readonly property color editFg: root.bar ? root.bar.barForeground : Color.foreground

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Edit profiles"
          color: parent.editFg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: editMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.close()
            root.bar.run("xdg-terminal-exec " + Util.shellQuote(root.cli) + " edit")
          }
        }
      }

      Text {
        width: menuColumn.width
        leftPadding: Style.space(8)
        text: "restart running sessions to apply a switch"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

    }
  }

  // Thin progress meter for one usage window (session, weekly). Track in
  // muted, fill in the accent — urgent once the window passes 80%.
  component UsageBar: Rectangle {
    property real fraction: 0
    property bool warn: false

    width: Style.space(28)
    height: Math.max(3, Style.space(2))
    radius: height / 2
    color: Util.alpha(Color.muted, 0.4)

    Rectangle {
      width: Math.max(parent.height, Math.round(parent.width * parent.fraction))
      height: parent.height
      radius: parent.radius
      color: parent.warn ? Color.urgent : Color.accent
    }
  }
}
