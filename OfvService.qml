import QtQuick
import Quickshell.Io

// State and process plumbing for the FortiVPN widget. Everything the panel
// renders is derived here; the panel itself stays declarative.
//
// Reads are unprivileged (ofv-query). Writes go through systemd or pkexec and
// raise a polkit prompt, so a mutating call can sit pending for as long as the
// user takes to type a password -- hence the generous helper-side timeouts.
Item {
  id: service
  visible: false

  property string profileFilter: ""
  property int refreshInterval: 5000
  property string queryHelper: ""
  property string depsHelper: ""

  // Dependency state. Optimistic defaults keep the panel from flashing a
  // "setup required" card during the first check on a healthy system.
  property bool depsChecked: false
  property bool hasOpenfortivpn: true
  property bool hasUnit: true
  property bool depsInstallable: true
  property string depsVersion: ""
  property string depsOutput: ""

  // State of the privileged helpers: "yes", "stale" (the plugin was updated and
  // ofv-setup has not been re-run) or "no". Until they are installed into their
  // root-owned directory there is nothing safe to hand pkexec, so import,
  // rename and delete are blocked and the panel points at ofv-setup instead.
  // Optimistic default, for the same reason the others are.
  property string helpersState: "yes"
  property string setupCommand: ""
  readonly property bool helpersReady: helpersState === "yes"

  // Kept to the backend alone: connect, disconnect and the boot toggle go
  // through systemd, not pkexec, so they still work with the helpers missing.
  readonly property bool depsOk: hasOpenfortivpn && hasUnit
  readonly property bool depsInstalling: depsInstallProcess.running

  property var profiles: []
  property var connectionInfo: ({})
  property string lastError: ""
  property string busyName: ""
  property bool queryAvailable: true

  // Import is a two-phase flow: pick a file, name it, then install it. The
  // panel drives the middle step, so the picked path is parked here.
  property string pendingImportPath: ""
  property string pendingImportName: ""

  property string listOutput: ""
  property string pickOutput: ""
  property bool listTimedOut: false
  property var listExitCode: null
  property bool listStreamFinished: false

  readonly property bool actionRunning: actionProcess.running
  readonly property bool pickRunning: pickProcess.running
  readonly property bool installRunning: installProcess.running
  readonly property bool removeRunning: removeProcess.running
  readonly property bool renameRunning: renameProcess.running
  readonly property bool anyWriteRunning: actionRunning || installRunning
    || removeRunning || renameRunning

  readonly property int connectedCount: {
    var n = 0
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) n++
    return n
  }
  readonly property string activeName: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) return profiles[i].name
    return ""
  }
  readonly property string connectingName: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].connecting) return profiles[i].name
    return ""
  }
  readonly property bool anyFailed: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].failed) return true
    return false
  }

  signal importReady(string path, string suggestedName)
  signal dependenciesInstalled()

  function boundedText(value, limit) {
    var s = String(value || "")
    return s.length > limit ? s.substring(0, limit) : s
  }

  // Strip control characters so helper output can never garble the panel.
  function boundedField(value, limit) {
    return boundedText(value, limit).replace(/[\u0000-\u001F\u007F]/g, "")
  }

  function setError(value) {
    lastError = boundedText(value, 4096).trim()
  }

  function parseProfiles(text) {
    var out = []
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length && out.length < 256; i++) {
      if (lines[i].length > 4096 || lines[i] === "") continue
      var f = lines[i].split("\t")
      if (f.length < 3) continue
      var name = boundedField(f[0], 256)
      if (name === "") continue
      if (profileFilter !== "" && name !== profileFilter) continue
      var state = boundedField(f[1], 64)
      out.push({
        name: name,
        state: state,
        active: state === "active",
        connecting: state === "activating" || state === "deactivating",
        failed: state === "failed",
        enabled: boundedField(f[2], 64) === "enabled"
      })
    }
    out.sort(function(a, b) {
      if (a.active !== b.active) return a.active ? -1 : 1
      return String(a.name).localeCompare(String(b.name))
    })
    return out
  }

  function parseDetails(text) {
    var info = ({})
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf("=")
      if (at > 0 && lines[i].length <= 4096) {
        info[boundedField(lines[i].substring(0, at), 64)] =
          boundedField(lines[i].substring(at + 1), 256)
      }
    }
    connectionInfo = info
  }

  function finalizeList() {
    if (listExitCode === null || !listStreamFinished) return
    queryAvailable = listExitCode === 0
    if (listExitCode === 0) {
      profiles = parseProfiles(listOutput)
      // Only clear a stale error when nothing is mid-flight, so a real failure
      // message survives long enough to be read.
      if (!anyWriteRunning && !pickProcess.running) setError("")
      refreshDetails()
    } else if (listTimedOut) {
      setError("Reading /etc/openfortivpn timed out.")
    } else {
      setError(listOutput === "" ? "Could not read openfortivpn profiles." : listOutput)
    }
  }

  function checkDeps() {
    if (depsHelper === "" || depsCheckProcess.running) return
    depsOutput = ""
    depsCheckProcess.command = [depsHelper, "check"]
    depsCheckProcess.running = true
  }

  function installDeps() {
    if (depsHelper === "" || depsInstallProcess.running) return
    setError("")
    depsInstallProcess.command = [depsHelper, "install"]
    depsInstallProcess.running = true
  }

  function parseDeps(text) {
    var info = ({})
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf("=")
      if (at > 0) info[boundedField(lines[i].substring(0, at), 64)] =
        boundedField(lines[i].substring(at + 1), 4096)
    }
    hasOpenfortivpn = info["openfortivpn"] === "yes"
    hasUnit = info["unit"] === "yes"
    depsInstallable = info["installable"] === "yes"
    depsVersion = info["version"] || ""
    helpersState = info["helpers"] === "yes" ? "yes"
      : info["helpers"] === "stale" ? "stale" : "no"
    var setupPath = info["setup"] || ""
    setupCommand = setupPath === "" ? "" : 'sudo "' + setupPath + '" install'
    depsChecked = true
  }

  function refresh() {
    if (queryHelper === "" || listProcess.running) return
    listOutput = ""
    listTimedOut = false
    listExitCode = null
    listStreamFinished = false
    listProcess.command = [queryHelper, "list"]
    listProcess.running = true
  }

  function refreshDetails() {
    if (connectedCount === 0) { connectionInfo = ({}); return }
    if (detailsProcess.running) return
    detailsProcess.command = [queryHelper, "details"]
    detailsProcess.running = true
  }

  function runUnit(helperPath, action, name) {
    if (name === "" || anyWriteRunning) return
    busyName = name
    setError("")
    actionProcess.command = [helperPath, action, name]
    actionProcess.running = true
  }

  function toggleConnection(helperPath, profile) {
    if (!profile || profile.connecting || anyWriteRunning) return
    runUnit(helperPath, profile.active ? "stop" : "start", profile.name)
  }

  function toggleAutostart(helperPath, profile) {
    if (!profile || anyWriteRunning) return
    runUnit(helperPath, profile.enabled ? "disable" : "enable", profile.name)
  }

  function beginImport(pickHelper) {
    if (pickRunning || installRunning) return
    setError("")
    pickOutput = ""
    pickProcess.command = [pickHelper]
    pickProcess.running = true
  }

  function cancelImport() {
    pendingImportPath = ""
    pendingImportName = ""
    setError("")
  }

  function confirmImport(installHelper, name) {
    var clean = String(name || "").trim()
    if (pendingImportPath === "" || clean === "" || installRunning) return
    setError("")
    installProcess.command = [installHelper, pendingImportPath, clean]
    installProcess.running = true
  }

  function renameProfile(renameHelper, oldName, newName) {
    var clean = String(newName || "").trim()
    if (oldName === "" || clean === "" || clean === oldName || anyWriteRunning) return
    busyName = oldName
    setError("")
    renameProcess.command = [renameHelper, oldName, clean]
    renameProcess.running = true
  }

  function removeProfile(removeHelper, name) {
    if (name === "" || anyWriteRunning) return
    busyName = name
    setError("")
    removeProcess.command = [removeHelper, name]
    removeProcess.running = true
  }

  Process {
    id: listProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.listOutput = service.boundedText(text, 262144)
        service.listStreamFinished = true
        service.finalizeList()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: listDeadline.restart()
    onExited: function(code) {
      listDeadline.stop()
      listKill.stop()
      service.listExitCode = code
      service.finalizeList()
    }
  }

  Process {
    id: depsCheckProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.depsOutput = service.boundedText(text, 8192)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code === 0) service.parseDeps(service.depsOutput)
      else service.depsChecked = true
    }
  }

  Process {
    id: depsInstallProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      if (code === 0) {
        service.setError("")
        service.dependenciesInstalled()
      }
      // Re-check either way: a partial success still changes what is present.
      service.checkDeps()
      refreshDelay.restart()
    }
  }

  Process {
    id: detailsProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.parseDetails(service.boundedText(text, 65536))
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      service.busyName = ""
      if (code === 0) service.setError("")
      refreshDelay.restart()
    }
  }

  Process {
    id: pickProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.pickOutput = service.boundedText(text, 8192)
    }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      // Exit 1 is a dismissed file chooser -- a cancel, not an error.
      if (code === 1) { service.setError(""); return }
      if (code !== 0) return
      var parts = String(service.pickOutput).trim().split("\t")
      if (parts.length < 2 || parts[0] === "") return
      service.pendingImportPath = service.boundedField(parts[0], 4096)
      service.pendingImportName = service.boundedField(parts[1], 256)
      service.importReady(service.pendingImportPath, service.pendingImportName)
    }
  }

  Process {
    id: installProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      if (code === 0) { service.cancelImport(); service.setError("") }
      refreshDelay.restart()
    }
  }

  Process {
    id: renameProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      service.busyName = ""
      if (code === 0) service.setError("")
      refreshDelay.restart()
    }
  }

  Process {
    id: removeProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      service.busyName = ""
      if (code === 0) service.setError("")
      refreshDelay.restart()
    }
  }

  // Packages do not appear and disappear on their own, so this runs once at
  // startup rather than on every poll.
  Component.onCompleted: checkDeps()

  Timer {
    interval: service.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refresh()
  }
  // Settling delay: systemd needs a moment before its state reflects the action.
  Timer { id: refreshDelay; interval: 700; onTriggered: service.refresh() }
  Timer {
    id: listDeadline
    interval: 8000
    onTriggered: {
      if (!listProcess.running) return
      service.listTimedOut = true
      listProcess.signal(15)
      listKill.restart()
    }
  }
  Timer { id: listKill; interval: 1000; onTriggered: if (listProcess.running) listProcess.signal(9) }
}
