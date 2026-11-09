import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Claude Code profile switcher. Shows the active key/endpoint profile,
// click to pick another from the popup, middle-click for a quick swap.
// The companion CLI (bin/skal-swap, resolved relative to this file) owns all
// state: it rewrites the managed ANTHROPIC_* env in ~/.claude/settings.json
// and moves Claude logins between config dirs; this widget only reads
// `skal-swap status --json` / `fleet --json` and watches the two files
// involved (settings.json + profiles.conf), so it stays in sync no matter
// what changed them — menu click, terminal, or manual edit.
//
// The popup lists this machine and every host in hosts.conf. Each row is a
// profile: click switches that machine to it, the play button opens a
// terminal running claude on it without switching anything (`skal-swap run`),
// so several Claude plans can run side by side.
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
  property var fleetJson: null
  property string lastCurrent: ""
  property bool armed: false
  // Minute clock for the reset countdowns in the popup.
  property real now: Date.now()

  readonly property var profiles: (statusJson && statusJson.profiles) ? statusJson.profiles : []
  readonly property var currentProfile: {
    if (!statusJson || !statusJson.current_known) return null
    for (var i = 0; i < profiles.length; i++)
      if (profiles[i].id === statusJson.current) return profiles[i]
    return null
  }
  // Claude sessions running here on profiles other than the current one
  // (launched with the play button or `skal-swap run`).
  readonly property int sideSessions: {
    var n = 0
    for (var i = 0; i < profiles.length; i++)
      if (!currentProfile || profiles[i].id !== currentProfile.id) n += profiles[i].sessions || 0
    return n
  }
  // The bar injects fixedEdge into widgets that declare it, so the widget
  // keeps its footing when it grows (label changes, +N appearing).
  property string fixedEdge: "center"

  // Panel exposes barForeground with the same fallback this used to spell
  // out by hand; vertical bars are compact (28px), where first-party text
  // widgets fall back to icon-only forms.
  readonly property color foreground: root.barForeground
  readonly property bool barVertical: bar ? bar.vertical : false
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string labelBase: {
    if (!statusJson) return "…"
    if (!currentProfile) return "custom"
    if (labelStyle === "Icon" || root.barVertical) return ""
    return labelStyle === "Host" ? currentProfile.host : currentProfile.name
  }

  // One entry per machine for the popup. This machine always comes from
  // the fast local status/usage reads; other hosts from the last fleet
  // snapshot (which also reports the ones that can't be reached).
  readonly property var hostList: {
    var list = [{ name: "local", local: true, ok: true, error: null,
                  status: root.statusJson, usageMap: root.usageById }]
    var hosts = (fleetJson && fleetJson.hosts) ? fleetJson.hosts : []
    for (var i = 0; i < hosts.length; i++) {
      var h = hosts[i]
      if (h.local) continue
      var map = {}
      var entries = (h.usage && h.usage.entries) ? h.usage.entries : []
      for (var j = 0; j < entries.length; j++) map[entries[j].id] = entries[j]
      list.push({ name: h.name, local: false, ok: h.ok, error: h.error,
                  dest: h.dest, status: h.status, usageMap: map })
    }
    return list
  }

  implicitWidth: content.implicitWidth + Style.space(10)
  implicitHeight: button.implicitHeight

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshUsage() {
    if (!usageProc.running) usageProc.running = true
  }

  function refreshFleet() {
    if (!fleetProc.running) fleetProc.running = true
  }

  // CLI argv prefix for a machine: remote hosts go through `@<host>`.
  function cliFor(hostName) {
    return hostName === "local" ? [cli] : [cli, "@" + hostName]
  }

  function inTerminal(hostName, args) {
    var argv = cliFor(hostName).concat(args)
    var cmd = "xdg-terminal-exec"
    for (var i = 0; i < argv.length; i++) cmd += " " + Util.shellQuote(argv[i])
    root.bar.run(cmd)
  }

  // When a usage window resets: a countdown inside the next day ("3h 12m"),
  // the weekday and time past that ("Tue 12 PM"), which reads better for
  // weekly windows. Takes `now` so bindings re-evaluate as the clock ticks.
  function resetLabel(at, now) {
    if (!at) return ""
    var t = Date.parse(at)
    if (!(t > now)) return ""
    if (t - now < 86400000) return humanUntil(t, now)
    var d = new Date(t)
    return Qt.formatDateTime(d, d.getMinutes() === 0 ? "ddd h AP" : "ddd h:mm AP")
  }

  function humanUntil(then, now) {
    var s = Math.floor((then - now) / 1000)
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

  function useProfile(hostName, id, name) {
    if (useProc.running) return
    useProc.pendingName = name || id
    useProc.hostName = hostName
    useProc.command = cliFor(hostName).concat(["use", id])
    useProc.running = true
  }

  function launchProfile(hostName, id, yolo) {
    inTerminal(hostName, yolo ? ["run", "-y", id] : ["run", id])
    // The new session shows up in the counts once claude is running.
    launchRefresh.restart()
  }

  // A herdr tab running claude on the profile, on that machine's herdr
  // server; the local herdr window comes up afterwards (remote machines show
  // there under their saved SSH machine).
  function launchHerdr(hostName, id, name, yolo) {
    if (herdrProc.running) return
    herdrProc.hostName = hostName
    herdrProc.pendingName = name || id
    herdrProc.command = cliFor(hostName).concat(yolo ? ["herdr", "-y", id] : ["herdr", id])
    herdrProc.running = true
  }

  function quickSwap() {
    swapProc.running = true
  }

  // The contract entry for shell-driven refreshes: status is cheap and
  // always safe; usage and fleet only matter while the picker is open.
  function refresh() {
    refreshStatus()
    if (root.opened) { refreshUsage(); refreshFleet() }
  }

  // Keyboard nav: the popup's profile rows flattened in display order
  // (machines in hostList order, each machine's profiles in file order).
  readonly property var selectableRows: {
    var rows = []
    var hosts = root.hostList
    for (var i = 0; i < hosts.length; i++) {
      var st = hosts[i].status
      var ps = (st && st.profiles) ? st.profiles : []
      for (var j = 0; j < ps.length; j++)
        rows.push({ host: hosts[i].name, profile: ps[j],
                    active: !!(st && st.current === ps[j].id) })
    }
    return rows
  }
  property int selectedIndex: -1

  onSelectableRowsChanged: {
    if (root.selectedIndex >= root.selectableRows.length)
      root.selectedIndex = root.selectableRows.length - 1
  }

  function initialSelection() {
    for (var i = 0; i < root.selectableRows.length; i++)
      if (root.selectableRows[i].active) return i
    return root.selectableRows.length > 0 ? 0 : -1
  }

  function isRowSelected(hostName, profileId) {
    var row = root.selectedIndex >= 0 ? root.selectableRows[root.selectedIndex] : null
    return !!row && row.host === hostName && row.profile.id === profileId
  }

  function moveSelection(dy) {
    if (root.selectableRows.length === 0) return
    root.selectedIndex = Math.min(Math.max(0, root.selectedIndex + dy),
                                  root.selectableRows.length - 1)
  }

  // Enter/Space on the selected row: same behavior as clicking it.
  function activateSelected() {
    var r = root.selectedIndex >= 0 ? root.selectableRows[root.selectedIndex] : null
    if (!r) return
    var needsLogin = r.profile.oauth && !((r.profile.login || {}).logged_in)
    root.close()
    if (needsLogin) root.inTerminal(r.host, ["login", r.profile.id])
    else if (!r.active) root.useProfile(r.host, r.profile.id, r.profile.name)
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
    id: fleetProc
    command: [root.cli, "fleet"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.fleetJson = JSON.parse(text || "null") }
        catch (e) {}
      }
    }
  }

  Process {
    id: useProc
    property string pendingName: ""
    property string hostName: "local"
    command: [root.cli, "status", "--json"] // placeholder until first use
    stderr: StdioCollector { id: useErr; waitForEnd: true }
    onExited: function(code) {
      root.refreshStatus()
      if (useProc.hostName !== "local") root.refreshFleet()
      if (code !== 0) {
        var why = String(useErr.text || "").trim().split("\n").pop().replace(/^skal-swap: /, "")
        Util.execArgv(["omarchy-notification-send", "-g", root.glyph, "-u", "normal",
                       "-r", "212", "Profile switch failed",
                       why || useProc.pendingName])
      } else if (useProc.hostName !== "local") {
        Util.execArgv(["omarchy-notification-send", "-g", root.glyph, "-u", "low",
                       "-r", "211", useProc.hostName + " → " + useProc.pendingName,
                       "restart its running claude sessions to pick it up"])
      }
    }
  }

  Process {
    id: herdrProc
    property string hostName: "local"
    property string pendingName: ""
    command: [root.cli, "status", "--json"] // placeholder until first launch
    stdout: StdioCollector { id: herdrOut; waitForEnd: true }
    stderr: StdioCollector { id: herdrErr; waitForEnd: true }
    onExited: function(code) {
      var where = herdrProc.hostName === "local" ? "herdr" : "herdr on " + herdrProc.hostName
      if (code === 0) {
        Util.execArgv([root.cli, "herdr-show"])
        Util.execArgv(["omarchy-notification-send", "-g", root.glyph, "-u", "low",
                       "-r", "213", herdrProc.pendingName + " → " + where,
                       String(herdrOut.text || "").trim().split("\n").pop()])
      } else {
        var why = String(herdrErr.text || "").trim().split("\n").pop().replace(/^skal-swap: /, "")
        Util.execArgv(["omarchy-notification-send", "-g", root.glyph, "-u", "normal",
                       "-r", "213", "Couldn't start " + herdrProc.pendingName + " in " + where,
                       why || "unknown error"])
      }
      launchRefresh.restart()
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

  Timer {
    id: launchRefresh
    interval: 4000
    onTriggered: { root.refreshStatus(); root.refreshFleet() }
  }

  // Watchers give instant refresh, but editors that save via rename (sed -i,
  // helix, …) strand an inode watcher silently. A slow poll re-syncs the
  // label even then; status --json is a cheap local read.
  Timer { interval: 20000; repeat: true; running: true; onTriggered: root.refreshStatus() }

  // Other hosts are an ssh round trip each, so they're only polled while
  // the popup is open.
  Timer { interval: 30000; repeat: true; running: root.opened; onTriggered: root.refreshFleet() }

  // Usage windows move on hour scales; the CLI serves its disk cache
  // instantly and refetches only past the TTL, so a refresh every few
  // minutes is plenty while the picker sits open.
  Timer { interval: 300000; repeat: true; running: root.opened; onTriggered: root.refreshUsage() }

  Timer {
    interval: 60000; repeat: true; running: root.opened
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

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
    tooltipText: {
      if (!root.currentProfile) return "Claude Code profile"
      var t = root.currentProfile.name + " · " + root.currentProfile.host
      if (root.sideSessions > 0)
        t += " · " + root.sideSessions + " more session" + (root.sideSessions === 1 ? "" : "s") + " on other profiles"
      return t
    }

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

    // Sessions on other profiles: a small count after the name, so a plan
    // running in the background is visible without opening the popup.
    Text {
      visible: root.sideSessions > 0
      text: "+" + root.sideSessions
      color: Util.alpha(root.foreground, 0.65)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // KeyboardPanel (layer-shell) rather than PopupCard (xdg-popup): the
  // compositor renders the xdg-popup surface translucent on some setups,
  // while the layer-shell card paints solid — same as the kit's own
  // dropdowns. Also brings keyboard focus, so Esc closes the picker.
  //
  // Layout: the title and the footer controls are pinned; only the machine
  // and profile list between them scrolls. The card asks for what the list
  // needs, capped to the screen, so the footer never falls off the bottom.
  KeyboardPanel {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(340)
    readonly property real chromeHeight: topBar.implicitHeight + bottomBar.implicitHeight
    readonly property real screenCap: Math.round((screenH > 0 ? screenH : 1000) * 0.8)
    contentHeight: fittedContentHeight(chromeHeight + listColumn.implicitHeight,
                                       Math.min(Style.space(720), screenCap))

    onOpenChanged: if (open) {
      root.refreshUsage(); root.refreshFleet(); flick.contentY = 0
      root.selectedIndex = root.initialSelection()
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    // Pinned: title.
    Column {
      id: topBar
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right

      Row {
        width: parent.width
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
          text: "Claude Code profiles"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Item { width: parent.width; height: Style.space(5) }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(Commons.Color.muted, 0.55)
      }
    }

    // Scrolls: one section per machine, its header and its profiles.
    Flickable {
      id: flick
      anchors.top: topBar.bottom
      anchors.bottom: bottomBar.top
      anchors.left: parent.left
      anchors.right: parent.right
      contentWidth: width
      contentHeight: listColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

      Column {
        id: listColumn
        width: flick.width - (flick.contentHeight > flick.height ? Style.space(8) : 0)
        spacing: Style.space(2)

        Repeater {
          model: root.hostList

        delegate: Column {
          id: hostSection
          width: listColumn.width
          spacing: Style.space(2)

          readonly property var hostData: modelData
          readonly property string hostName: hostData.name
          readonly property var hostStatus: hostData.status
          readonly property var hostProfiles: (hostStatus && hostStatus.profiles) ? hostStatus.profiles : []
          
          Item { width: parent.width; height: Style.space(6) }

          // Machine header: name, address, and this machine's login button.
          Item {
            width: parent.width
            height: Style.space(22)

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: addButton.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              clip: true

              Text {
                text: hostSection.hostData.local ? "This machine" : hostSection.hostName
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                text: {
                  var hn = hostSection.hostStatus ? hostSection.hostStatus.hostname : ""
                  if (hostSection.hostData.local) return hn || ""
                  return hostSection.hostData.dest && hostSection.hostData.dest !== hostSection.hostName
                         ? hostSection.hostData.dest : (hn || "")
                }
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            // Log another Claude plan into this machine (prompts for an id
            // in the terminal; the browser handles the rest).
            Rectangle {
              id: addButton
              visible: hostSection.hostData.ok && !!hostSection.hostStatus
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: visible ? addText.implicitWidth + Style.space(12) : 0
              height: Style.space(20)
              radius: Style.cornerRadius
              color: addMouse.containsMouse ? Util.alpha(Commons.Color.accent, 0.18) : "transparent"

              Text {
                id: addText
                anchors.centerIn: parent
                text: "+ log in a plan"
                color: addMouse.containsMouse ? Commons.Color.accent : Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.close()
                  root.inTerminal(hostSection.hostName, ["login"])
                }
              }
            }
          }

          Text {
            visible: !hostSection.hostData.ok || (!hostSection.hostStatus && !hostSection.hostData.local)
            width: parent.width
            leftPadding: Style.space(8)
            text: hostSection.hostData.ok ? "connecting…" : ("⚠ " + (hostSection.hostData.error || "unreachable"))
            color: hostSection.hostData.ok ? Commons.Color.muted : Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Repeater {
            model: hostSection.hostProfiles

            delegate: Item {
              id: row
              width: hostSection.width
              height: rowBody.implicitHeight + Style.space(12) + (alibabaHost ? Style.space(28) : 0)

              readonly property color rowFg: root.barForeground
              readonly property var prof: modelData
              readonly property bool active: hostSection.hostStatus && hostSection.hostStatus.current === prof.id
              readonly property bool selected: root.isRowSelected(hostSection.hostName, prof.id)
              onSelectedChanged: if (selected) row.bringIntoView()

              function bringIntoView() {
                var y = row.mapToItem(flick, 0, 0).y
                if (y < flick.contentY + Style.space(6))
                  flick.contentY = Math.max(0, y - Style.space(6))
                else if (y + row.height > flick.contentY + flick.height - Style.space(6))
                  flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                            y + row.height - flick.height + Style.space(6))
              }
              readonly property var login: prof.login || null
              readonly property bool needsLogin: prof.oauth && !(login && login.logged_in)
              readonly property var usageInfo: prof.usage_id ? (hostSection.hostData.usageMap[prof.usage_id] || null) : null
              // Alibaba publishes no usage API for token plans — the console is
              // the only place quota exists, so each alibaba row links to it.
              readonly property bool alibabaHost: {
                var h = prof.host || ""
                return h.indexOf("maas.aliyuncs.com") >= 0 || h.indexOf("dashscope") >= 0
              }
              // Progress-bar metrics (max 3), one per window with a percent.
              readonly property var barMetrics: {
                if (!usageInfo || !usageInfo.metrics) return []
                var withPercent = []
                for (var i = 0; i < usageInfo.metrics.length; i++)
                  if (usageInfo.metrics[i].percent != null) withPercent.push(usageInfo.metrics[i])
                return withPercent.slice(0, 3)
              }
              // Footer line. Claude logins: the account. Providers: the plan
              // name ("GLM Coding Max"). Resets sit on each meter instead. Key
              // material is never rendered in the menu.
              readonly property string detailLine: {
                if (needsLogin) return "not logged in here · click to log in"
                var parts = []
                if (login && login.email) parts.push(login.email)
                else if (usageInfo && usageInfo.plan && !prof.oauth) parts.push(usageInfo.plan)
                if (login && login.expired) parts.push("token expired · launch to refresh")
                else if (usageInfo && usageInfo.error && prof.oauth) parts.push(usageInfo.error)
                return parts.join(" · ")
              }

              Item {
                id: contentZone
                width: parent.width
                height: rowBody.implicitHeight + Style.space(12)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: (rowMouse.containsMouse || playMouse.containsMouse || row.selected)
                         ? Util.alpha(row.rowFg, 0.08) : "transparent"
                }

                // Active marker: accent pill down the left edge.
                Rectangle {
                  visible: row.active
                  width: 3
                  radius: width / 2
                  color: Commons.Color.accent
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.close()
                    if (row.needsLogin) root.inTerminal(hostSection.hostName, ["login", row.prof.id])
                    else if (!row.active) root.useProfile(hostSection.hostName, row.prof.id, row.prof.name)
                  }
                }

                // Left+right anchors give the column a definite width, so the
                // child Texts can bind width to it without a binding loop.
                Column {
                  id: rowBody
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: herdrButton.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  // Title line: provider mark (assets/providers/<icon>.svg,
                  // from the CLI's host mapping or the profile's `icon =` key)
                  // inline with the name, tinted to the theme (accent while
                  // active), then the plan badge and running-session count.
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
                        colorizationColor: row.active ? Commons.Color.accent : row.rowFg
                        opacity: row.needsLogin ? 0.45 : 1.0
                      }
                    }

                    Text {
                      id: nameText
                      width: Math.min(implicitWidth, parent.width - providerMark.width - parent.spacing
                                      - (planPill.visible ? planPill.width + parent.spacing : 0)
                                      - (sessionText.visible ? sessionText.implicitWidth + parent.spacing : 0))
                      anchors.verticalCenter: parent.verticalCenter
                      text: row.prof.name
                      color: row.needsLogin ? Commons.Color.muted : (row.active ? Commons.Color.accent : row.rowFg)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: row.active
                      elide: Text.ElideRight
                    }

                    // Plan badge: "Max 20x", "Pro", … for Claude logins.
                    Rectangle {
                      id: planPill
                      visible: !!(row.login && row.login.plan)
                      anchors.verticalCenter: parent.verticalCenter
                      width: planText.implicitWidth + Style.space(10)
                      height: planText.implicitHeight + Style.space(2)
                      radius: height / 2
                      color: "transparent"
                      border.width: 1
                      border.color: Util.alpha(row.active ? Commons.Color.accent : row.rowFg, 0.5)

                      Text {
                        id: planText
                        anchors.centerIn: parent
                        text: row.login && row.login.plan ? row.login.plan : ""
                        color: row.active ? Commons.Color.accent : row.rowFg
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      id: sessionText
                      visible: (row.prof.sessions || 0) > 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: "● " + row.prof.sessions
                      color: Commons.Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // One meter line per usage window (session, weekly, and a
                  // model-scoped weekly where the plan has one): progress
                  // bar, its label and percentage, and when it resets.
                  // Urgent past 80%.
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
                          width: barStack.width - pctText.width - resetText.width - parent.spacing * 2
                          anchors.verticalCenter: parent.verticalCenter
                          fraction: Util.clamp((modelData.percent || 0) / 100, 0, 1)
                          warn: (modelData.percent || 0) > 80
                        }

                        Text {
                          id: pctText
                          width: Math.max(implicitWidth, Style.space(70))
                          horizontalAlignment: Text.AlignRight
                          anchors.verticalCenter: parent.verticalCenter
                          text: {
                            var label = String(modelData.label || "").replace(/\s*\(.*\)$/, "")
                            return (label ? label + " " : "") + modelData.percent + "%"
                          }
                          color: (modelData.percent || 0) > 80 ? Commons.Color.urgent : row.rowFg
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }

                        // Fixed width so the bars above and below line up.
                        Text {
                          id: resetText
                          width: Math.max(implicitWidth, Style.space(64))
                          horizontalAlignment: Text.AlignRight
                          anchors.verticalCenter: parent.verticalCenter
                          text: root.resetLabel(modelData.reset_at, root.now)
                          color: Commons.Color.muted
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
                    color: Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // herdr: a tab in that machine's herdr running claude on this
                // profile. Only where herdr is installed.
                Rectangle {
                  id: herdrButton
                  visible: !row.needsLogin && !!(hostSection.hostStatus && hostSection.hostStatus.herdr)
                  width: visible ? Style.space(26) : 0
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  anchors.right: playButton.left
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  color: herdrMouse.containsMouse ? Util.alpha(Commons.Color.accent, 0.18) : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "󰆍"
                    color: herdrMouse.containsMouse ? Commons.Color.accent : Util.alpha(row.rowFg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: herdrMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                      root.close()
                      root.launchHerdr(hostSection.hostName, row.prof.id, row.prof.name,
                                       mouse.button === Qt.RightButton)
                    }
                  }
                }

                // Launch: a terminal running claude on this profile, on this
                // machine or over ssh, without switching anything.
                Rectangle {
                  id: playButton
                  visible: !row.needsLogin
                  width: visible ? Style.space(26) : 0
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  color: playMouse.containsMouse ? Util.alpha(Commons.Color.accent, 0.18) : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "󰐊"
                    color: playMouse.containsMouse ? Commons.Color.accent : Util.alpha(row.rowFg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                      root.close()
                      root.launchProfile(hostSection.hostName, row.prof.id,
                                         mouse.button === Qt.RightButton)
                    }
                  }
                }
              }

              // Alibaba rows: the console link under the entry.
              Item {
                visible: row.alibabaHost
                height: visible ? Style.space(28) : 0
                width: parent.width
                anchors.bottom: parent.bottom

                Rectangle {
                  id: consolePlate
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: consoleMouse.containsMouse ? Util.alpha(Commons.Color.muted, 0.15) : "transparent"
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(38)
                  anchors.verticalCenter: consolePlate.verticalCenter
                  text: "quota in Alibaba console  ↗"
                  color: consoleMouse.containsMouse ? row.rowFg : Commons.Color.muted
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
          Text {
            visible: !!(hostSection.hostStatus && hostSection.hostStatus.current_known === false)
            leftPadding: Style.space(8)
            text: "⚠ active key matches no profile"
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

        }
        }

        Item { width: listColumn.width; height: Style.space(4) }
      }
    }

    // Pinned: footer controls.
    Column {
      id: bottomBar
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(2)

      Rectangle { width: parent.width; height: 1; color: Util.alpha(Commons.Color.muted, 0.3) }

      Rectangle {
        width: parent.width
        height: Style.space(30)
        radius: Style.cornerRadius
        color: editMouse.containsMouse ? Util.alpha(editFg, 0.08) : "transparent"
        readonly property color editFg: root.barForeground

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
        width: parent.width
        leftPadding: Style.space(8)
        text: "click: switch · 󰐊 terminal · 󰆍 herdr · right-click: skip permissions"
        color: Commons.Color.muted
        font.pixelSize: Style.font.caption
        font.family: root.fontFamily
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
    color: Util.alpha(Commons.Color.muted, 0.4)

    Rectangle {
      width: Math.max(parent.height, Math.round(parent.width * parent.fraction))
      height: parent.height
      radius: parent.radius
      color: parent.warn ? Commons.Color.urgent : Commons.Color.accent
    }
  }
}
