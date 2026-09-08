import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Claude Code API profile switcher. Shows the active key/endpoint profile,
// click to pick another from the popup, middle-click for a quick swap.
// The companion CLI (bin/skal-ccs, resolved relative to this file) owns all
// state: it rewrites the managed ANTHROPIC_* env in ~/.claude/settings.json;
// this widget only reads `skal-ccs status --json` and watches the two files
// involved (settings.json + profiles.conf), so it stays in sync no matter
// what changed them — menu click, terminal, or manual edit.
//
// Settings live inline on the bar layout entry in shell.json:
//   { "id": "skal.claude-code-switcher", "labelStyle": "Name", "glyph": "󰌆" }
//
// IPC is deliberately not registered (manageIpc: false): a bar widget is
// instantiated once per monitor and only one copy could own the target —
// the CLI/hotkey path (`skal-ccs swap`) is the machine-wide interface.
Panel {
  id: root

  manageIpc: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string settingsPath: home + "/.claude/settings.json"
  readonly property string profilesPath: home + "/.config/skal.claude-code-switcher/profiles.conf"
  // Resolve the CLI next to this QML file so the plugin works straight
  // after clone, with no PATH install; fall back to a PATH lookup.
  readonly property string cli: {
    var u = Qt.resolvedUrl("bin/skal-ccs").toString()
    return u.indexOf("file://") === 0 ? u.substring(7) : "skal-ccs"
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

  Component.onCompleted: refreshStatus()

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
      width: visible ? Math.round(Style.font.body * 1.3) : 0
      height: width

      Image {
        id: logoProvider
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/claude.svg")
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectFit
      }

      MultiEffect {
        anchors.fill: parent
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

  PopupCard {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    triggerMode: "click"
    contentWidth: Style.space(228)
    contentHeight: fittedContentHeight(menuColumn.implicitHeight, Style.space(340))

    onOpenChanged: if (open && !usageProc.running) usageProc.running = true

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
            colorizationColor: Color.muted
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Claude Code profile"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Repeater {
        model: root.profiles

        delegate: Rectangle {
          width: menuColumn.width
          height: Style.space(30)
          radius: Style.cornerRadius
          color: rowMouse.containsMouse
            ? Util.alpha(rowFg.color, 0.08)
            : "transparent"

          readonly property color rowFg: root.bar ? root.bar.barForeground : Color.foreground
          readonly property var prof: modelData
          readonly property bool active: root.statusJson && root.statusJson.current === prof.id
          readonly property var usage: prof.usage_id ? (root.usageById[prof.usage_id] || null) : null

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.active ? "" : "·"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(26)
            anchors.right: usageText.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: prof.name
            color: parent.active ? Color.accent : parent.rowFg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: usageText
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.usage
              ? (parent.usage.percent != null ? parent.usage.percent + "%" : "")
              : (parent.prof.token_prefix || "")
            color: parent.usage && parent.usage.percent > 80 ? Color.urgent : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.close()
              if (!parent.active) root.useProfile(parent.prof.id, parent.prof.name)
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

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "restart sessions after a switch"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
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
    }
  }
}
