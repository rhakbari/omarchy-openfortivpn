import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
// IpcHandler is provided by Quickshell.Io.
import Quickshell.Io
import qs.Commons
import qs.Ui

// OpenFortiVPN bar widget.
//
// Profiles are the *.conf files in /etc/openfortivpn; each one is an instance of
// the packaged openfortivpn@.service template. Connecting is therefore just
// `systemctl start openfortivpn@<name>`, which routes authorization through
// polkit -- the shell's own polkit agent renders the prompt. Nothing here is
// setuid and no polkit rule is installed.
Panel {
  id: root
  moduleName: "rhakbari.openfortivpn"
  ipcTarget: "rhakbari.openfortivpn"
  manageIpc: false

  readonly property var profiles: service.profiles
  readonly property string lastError: service.lastError
  readonly property string busyName: service.busyName
  readonly property var connectionInfo: service.connectionInfo
  readonly property int connectedCount: service.connectedCount
  readonly property string activeName: service.activeName
  readonly property string connectingName: service.connectingName
  readonly property bool anyFailed: service.anyFailed

  property string pendingDeleteName: ""
  property string importName: ""
  property string renameOldName: ""
  property string renameName: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string profileFilter: String(settings.profile || "").trim()
  readonly property bool showLabel: settings.showLabel === true
  readonly property int refreshInterval: Math.max(2, Math.min(300,
    parseInt(String(settings.refreshIntervalSec || 5), 10) || 5)) * 1000

  // Supplementary-plane Nerd Font glyphs. Each codepoint was checked against
  // the font fontconfig resolves `monospace` to, so none of these render tofu.
  readonly property string iconConnected: "󰦝"      // U+F099D shield-lock
  readonly property string iconDisconnected: "󰦜"   // U+F099C shield-off-outline
  readonly property string iconFailed: "󰀦"         // U+F0026 alert-circle
  readonly property string iconRefresh: "󰑐"        // U+F0450 refresh
  readonly property string iconImport: "󰋺"         // U+F02FA import
  readonly property string iconDelete: "󰆴"         // U+F01B4 delete
  readonly property string iconBoot: "󰚥"           // U+F06A5 power-plug
  readonly property string iconEdit: "󰏫"           // U+F03EB pencil
  readonly property string iconInstall: "󰉆"        // U+F0246 tray-arrow-down

  readonly property bool setupRequired: service.depsChecked && !service.depsOk

  readonly property string barIcon: setupRequired ? iconFailed
    : connectedCount > 0 ? iconConnected
    : anyFailed ? iconFailed
    : iconDisconnected
  readonly property color stateColor: connectedCount > 0 ? accent
    : anyFailed ? urgent
    : dim

  readonly property string statusLine: setupRequired ? "Setup required"
    : !service.queryAvailable ? "openfortivpn unavailable"
    : connectingName !== "" ? "Connecting · " + connectingName
    : connectedCount > 0 ? "Connected · " + activeName
    : anyFailed ? "Last connection failed"
    : profiles.length > 0 ? "Disconnected"
    : "No profiles installed"

  readonly property string tooltip: setupRequired
    ? "OpenFortiVPN: openfortivpn is not installed"
    : connectedCount > 0 ? "OpenFortiVPN: " + activeName + " connected"
    : profiles.length > 0 ? "OpenFortiVPN: disconnected" : "OpenFortiVPN: no profiles"

  function refresh() { service.refresh() }

  // Resolve bundled helpers relative to this file so the plugin works from any
  // plugin directory, including paths containing spaces.
  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  function toggleConnection(profile) {
    service.toggleConnection(bundledPath("ofv-unit"), profile)
  }
  function toggleAutostart(profile) {
    service.toggleAutostart(bundledPath("ofv-unit"), profile)
  }
  function beginImport() {
    service.beginImport(bundledPath("ofv-pick"))
  }
  function confirmImport() {
    service.confirmImport(bundledPath("ofv-install"), importName)
  }
  function cancelImport() {
    service.cancelImport()
    importName = ""
  }
  function installDeps() { service.installDeps() }

  function requestRename(profile) {
    cancelImport()
    cancelDelete()
    renameOldName = profile.name
    renameName = profile.name
    service.setError("")
    Qt.callLater(function() { renameField.forceActiveFocus(); renameField.selectAll() })
  }
  function cancelRename() {
    renameOldName = ""
    renameName = ""
  }
  function confirmRename() {
    if (!renameNameValid) return
    service.renameProfile(bundledPath("ofv-rename"), renameOldName, renameName)
    cancelRename()
  }

  function requestDelete(profile) {
    cancelImport()
    cancelRename()
    pendingDeleteName = profile.name
  }
  function cancelDelete() { pendingDeleteName = "" }
  function confirmDelete() {
    if (pendingDeleteName === "") return
    service.removeProfile(bundledPath("ofv-remove"), pendingDeleteName)
    pendingDeleteName = ""
  }

  // A profile name becomes a systemd instance and a filename, so it is held to
  // the same charset the helper scripts validate against.
  readonly property bool importNameValid: /^[A-Za-z0-9._-]+$/.test(importName.trim())
    && importName.trim() !== "." && importName.trim() !== ".."

  // A rename must also not collide with a profile that already exists.
  readonly property bool renameNameValid: {
    var n = renameName.trim()
    if (!/^[A-Za-z0-9._-]+$/.test(n) || n === "." || n === "..") return false
    if (n === renameOldName) return false
    for (var i = 0; i < profiles.length; i++) if (profiles[i].name === n) return false
    return true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: if (opened) { refresh(); Qt.callLater(function() { keys.forceActiveFocus() }) }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string { return root.tooltip }
  }

  OfvService {
    id: service
    profileFilter: root.profileFilter
    refreshInterval: root.refreshInterval
    queryHelper: root.bundledPath("ofv-query")
    depsHelper: root.bundledPath("ofv-deps")
    onDependenciesInstalled: root.refresh()
    onImportReady: function(path, suggestedName) {
      root.importName = suggestedName
      Qt.callLater(function() { importField.forceActiveFocus(); importField.selectAll() })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltip
    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.barIcon
            color: root.connectedCount > 0 ? root.accent
              : root.anyFailed ? root.urgent
              : (root.bar ? root.bar.foreground : Color.foreground)
            opacity: root.connectedCount > 0 || root.anyFailed ? 1 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showLabel && root.connectedCount > 0
            text: root.activeName
            textFormat: Text.PlainText
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
    onPressed: function(code) { if (code === Qt.LeftButton) root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      // Modal overlays own the keyboard while they are up.
      blocked: service.pendingImportPath !== "" || root.pendingDeleteName !== ""
        || root.renameOldName !== ""
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "i" || t === "I") root.beginImport()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          // ------------------------------------------------------------ hero
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, refreshBtn.height)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.barIcon
              color: root.stateColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: refreshBtn.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "OpenFortiVPN"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.statusLine.toUpperCase()
                textFormat: Text.PlainText
                color: root.connectedCount > 0 ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Rectangle {
              id: refreshBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.cornerRadius > 0 ? Style.space(6) : Style.space(3)
              color: refreshMouse.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                : "transparent"
              border.width: 1
              border.color: root.dim
              Text {
                anchors.centerIn: parent
                text: root.iconRefresh
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ----------------------------------------------------------- error
          Rectangle {
            visible: root.lastError !== ""
            width: parent.width
            height: errorText.implicitHeight + Style.space(16)
            radius: Style.cornerRadius > 0 ? Style.space(5) : Style.space(3)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45)

            Text {
              id: errorText
              anchors.centerIn: parent
              width: parent.width - Style.space(18)
              text: root.lastError
              textFormat: Text.PlainText
              color: root.urgent
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ------------------------------------------------ setup required
          //
          // Omarchy's plugin system has no install hook, so a freshly installed
          // plugin checks for its own dependency and offers to install it here
          // rather than failing cryptically at connect time.
          Rectangle {
            visible: root.setupRequired
            width: parent.width
            implicitHeight: setupColumn.implicitHeight + Style.space(26)
            radius: Style.cornerRadius > 0 ? Style.space(6) : Style.space(3)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.40)

            Column {
              id: setupColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(28)
              spacing: Style.space(9)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "openfortivpn is not installed"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: service.depsInstallable
                  ? "This widget drives the openfortivpn package and its systemd unit. Install it to get started."
                  : "This widget needs the openfortivpn package. Install it with your distribution's package manager."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              OfvActionButton {
                visible: service.depsInstallable
                width: parent.width
                foreground: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                iconText: root.iconInstall
                label: service.depsInstalling ? "Installing…" : "Install openfortivpn"
                enabled: !service.depsInstalling
                onActivated: root.installDeps()
              }
            }
          }

          // ------------------------------------------------ live tunnel info
          Column {
            visible: !root.setupRequired && root.connectedCount > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader { text: "TUNNEL"; foreground: root.foreground; fontFamily: root.fontFamily }

            OfvInfoRow {
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              label: "Interface"; value: root.connectionInfo["interface"] || "—"
            }
            OfvInfoRow {
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              label: "Address"; value: root.connectionInfo["address"] || "—"
            }
            OfvInfoRow {
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              label: "Gateway"; value: root.connectionInfo["gateway"] || "—"
            }
            OfvInfoRow {
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              label: "DNS"; value: root.connectionInfo["dns"] || "—"
            }

            Item { width: 1; height: Style.space(2) }
            PanelSeparator { width: parent.width; foreground: root.foreground }
          }

          // -------------------------------------------------------- profiles
          PanelSectionHeader {
            visible: !root.setupRequired && root.profiles.length > 0
            text: "PROFILES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.setupRequired ? [] : root.profiles

            delegate: Rectangle {
              id: card
              required property var modelData
              readonly property var profile: modelData
              readonly property bool busy: root.busyName === profile.name

              width: content.width
              implicitHeight: cardRow.implicitHeight + Style.space(18)
              radius: Style.cornerRadius > 0 ? Style.space(6) : Style.space(3)
              color: profile.active
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.07)
                : cardMouse.containsMouse
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                  : "transparent"
              border.width: 1
              border.color: profile.active
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
                : profile.failed
                  ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.40)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
              opacity: card.busy ? 0.55 : 1

              Behavior on color { ColorAnimation { duration: 110 } }
              Behavior on opacity { NumberAnimation { duration: 110 } }

              MouseArea { id: cardMouse; anchors.fill: parent; hoverEnabled: true }

              RowLayout {
                id: cardRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.topMargin: Style.space(9)
                anchors.bottomMargin: Style.space(9)
                spacing: Style.space(10)

                // Status dot -- the fastest read of state in the whole panel.
                Rectangle {
                  Layout.alignment: Qt.AlignVCenter
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: width / 2
                  color: profile.active ? root.accent
                    : profile.failed ? root.urgent
                    : profile.connecting ? root.foreground
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)

                  SequentialAnimation on opacity {
                    running: profile.connecting
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 620 }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 620 }
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Text {
                    Layout.fillWidth: true
                    text: profile.name
                    textFormat: Text.PlainText
                    color: root.foreground
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: profile.active
                  }
                  Text {
                    Layout.fillWidth: true
                    text: {
                      if (profile.active) return "Connected" + (profile.enabled ? " · starts at boot" : "")
                      if (profile.connecting) return "Working…"
                      if (profile.failed) return "Failed"
                      return profile.enabled ? "Disconnected · starts at boot" : "Disconnected"
                    }
                    textFormat: Text.PlainText
                    color: profile.failed ? root.urgent : root.dim
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                OfvPill {
                  Layout.alignment: Qt.AlignVCenter
                  foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                  accentColor: root.accent; urgentColor: root.urgent
                  label: profile.active ? "Disconnect" : (profile.connecting ? "…" : "Connect")
                  tone: profile.active ? "normal" : "accent"
                  filled: !profile.active && !profile.connecting
                  enabled: !service.anyWriteRunning && !profile.connecting
                  onActivated: root.toggleConnection(profile)
                }

                OfvPill {
                  Layout.alignment: Qt.AlignVCenter
                  foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                  accentColor: root.accent; urgentColor: root.urgent
                  label: root.iconBoot
                  tone: profile.enabled ? "accent" : "normal"
                  enabled: !service.anyWriteRunning
                  onActivated: root.toggleAutostart(profile)
                }

                OfvPill {
                  Layout.alignment: Qt.AlignVCenter
                  foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                  accentColor: root.accent; urgentColor: root.urgent
                  label: root.iconEdit
                  enabled: !service.anyWriteRunning
                  onActivated: root.requestRename(profile)
                }

                OfvPill {
                  Layout.alignment: Qt.AlignVCenter
                  foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                  accentColor: root.accent; urgentColor: root.urgent
                  label: root.iconDelete
                  tone: "urgent"
                  enabled: !service.anyWriteRunning
                  onActivated: root.requestDelete(profile)
                }
              }
            }
          }

          // ----------------------------------------------------- empty state
          Rectangle {
            visible: !root.setupRequired && root.profiles.length === 0
            width: parent.width
            implicitHeight: emptyColumn.implicitHeight + Style.space(28)
            radius: Style.cornerRadius > 0 ? Style.space(6) : Style.space(3)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

            Column {
              id: emptyColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(32)
              spacing: Style.space(6)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.profileFilter !== ""
                  ? "No profile named “" + root.profileFilter + "”"
                  : "No profiles yet"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Import a .conf your admin gave you. It is installed to /etc/openfortivpn, readable only by root."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          OfvActionButton {
            visible: !root.setupRequired
            width: parent.width
            foreground: root.foreground
            dim: root.dim
            fontFamily: root.fontFamily
            iconText: root.iconImport
            label: service.pickRunning ? "Choose a file…"
              : service.installRunning ? "Installing…"
              : "Import profile"
            enabled: !service.pickRunning && !service.installRunning
            onActivated: root.beginImport()
          }
        }
      }

      // ------------------------------------------------- import name overlay
      Rectangle {
        visible: service.pendingImportPath !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)

        MouseArea { anchors.fill: parent }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(340))
          height: importColumn.implicitHeight + Style.space(30)
          radius: Style.cornerRadius > 0 ? Style.space(8) : Style.space(3)
          color: Color.popups.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Column {
            id: importColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(30)
            spacing: Style.space(11)

            Text {
              width: parent.width
              text: "Name this profile"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Becomes /etc/openfortivpn/" + (root.importName.trim() || "…") + ".conf "
                + "and the systemd unit openfortivpn@" + (root.importName.trim() || "…") + "."
              textFormat: Text.PlainText
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: importField
              width: parent.width
              placeholderText: "Profile name"
              text: root.importName
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: root.importName = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelImport(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (root.importNameValid) root.confirmImport()
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.importName !== "" && !root.importNameValid
              width: parent.width
              text: "Use letters, digits, dot, dash or underscore only."
              color: root.urgent
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.lastError !== ""
              width: parent.width
              text: root.lastError
              textFormat: Text.PlainText
              color: root.urgent
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              OfvPill {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                accentColor: root.accent; urgentColor: root.urgent
                label: "Cancel"
                onActivated: root.cancelImport()
              }
              OfvPill {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                accentColor: root.accent; urgentColor: root.urgent
                label: service.installRunning ? "Installing…" : "Install"
                tone: "accent"
                filled: true
                enabled: root.importNameValid && !service.installRunning
                onActivated: root.confirmImport()
              }
            }
          }
        }
      }

      // ------------------------------------------------------ rename overlay
      Rectangle {
        visible: root.renameOldName !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)

        MouseArea { anchors.fill: parent }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(340))
          height: renameColumn.implicitHeight + Style.space(30)
          radius: Style.cornerRadius > 0 ? Style.space(8) : Style.space(3)
          color: Color.popups.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Column {
            id: renameColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(30)
            spacing: Style.space(11)

            Text {
              width: parent.width
              text: "Rename profile"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Renames the config to /etc/openfortivpn/"
                + (root.renameName.trim() || "…") + ".conf. The tunnel is briefly "
                + "dropped and reconnected if it is up, and a start-at-boot setting "
                + "is carried over."
              textFormat: Text.PlainText
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: renameField
              width: parent.width
              placeholderText: "Profile name"
              text: root.renameName
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: root.renameName = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelRename(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (root.renameNameValid) root.confirmRename()
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.renameName.trim() !== "" && !root.renameNameValid
                && root.renameName.trim() !== root.renameOldName
              width: parent.width
              text: /^[A-Za-z0-9._-]+$/.test(root.renameName.trim())
                ? "A profile with that name already exists."
                : "Use letters, digits, dot, dash or underscore only."
              color: root.urgent
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.lastError !== ""
              width: parent.width
              text: root.lastError
              textFormat: Text.PlainText
              color: root.urgent
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              OfvPill {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                accentColor: root.accent; urgentColor: root.urgent
                label: "Cancel"
                onActivated: root.cancelRename()
              }
              OfvPill {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                accentColor: root.accent; urgentColor: root.urgent
                label: service.renameRunning ? "Renaming…" : "Rename"
                tone: "accent"
                filled: true
                enabled: root.renameNameValid && !service.anyWriteRunning
                onActivated: root.confirmRename()
              }
            }
          }
        }
      }

      // ------------------------------------------------ delete confirm overlay
      Rectangle {
        visible: root.pendingDeleteName !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)

        MouseArea { anchors.fill: parent }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(320))
          height: deleteColumn.implicitHeight + Style.space(30)
          radius: Style.cornerRadius > 0 ? Style.space(8) : Style.space(3)
          color: Color.popups.background
          border.width: 1
          border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45)

          Column {
            id: deleteColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(30)
            spacing: Style.space(11)

            Text {
              width: parent.width
              text: "Delete “" + root.pendingDeleteName + "”?"
              textFormat: Text.PlainText
              color: root.foreground
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Disconnects the tunnel, clears its boot setting, and removes the config from /etc/openfortivpn. This cannot be undone."
              textFormat: Text.PlainText
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              OfvPill {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                accentColor: root.accent; urgentColor: root.urgent
                label: "Cancel"
                onActivated: root.cancelDelete()
              }
              OfvPill {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                accentColor: root.accent; urgentColor: root.urgent
                label: "Delete"
                tone: "urgent"
                filled: true
                enabled: !service.anyWriteRunning
                onActivated: root.confirmDelete()
              }
            }
          }
        }
      }
    }
  }
}
