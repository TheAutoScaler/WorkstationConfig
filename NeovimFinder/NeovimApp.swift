import AppKit
import CoreServices
import Darwin
import Foundation

private let bundleIdentifier = "me.lochhead.NeovimFinder"
private let supportedContentTypes = [
    "net.daringfireball.markdown",
    "public.plain-text",
]

private let ghosttyAppleScript = """
on run argv
    set helperCommand to item 1 of argv
    set filesEnvironment to item 2 of argv
    set pathEnvironment to item 3 of argv
    set environmentList to {filesEnvironment, pathEnvironment}
    tell application "Ghostty"
        set surfaceConfig to new surface configuration
        set command of surfaceConfig to helperCommand
        set environment variables of surfaceConfig to environmentList
        set wait after command of surfaceConfig to false
        set createdWindow to new window with configuration surfaceConfig
        activate window createdWindow
    end tell
end run
"""

private func loginShellPath() -> String? {
    let shellExecutable = ProcessInfo.processInfo.environment["NEOVIM_FINDER_SHELL"]
        ?? "/opt/homebrew/bin/bash"
    guard FileManager.default.isExecutableFile(atPath: shellExecutable) else { return nil }

    let marker = "__NEOVIM_FINDER_PATH__"
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: shellExecutable)
    // The user's Bash setup adds developer tool paths from interactive startup
    // files. This shell has no terminal and exits after printing PATH, so it
    // cannot interfere with Ghostty's foreground process group.
    process.arguments = ["-lic", "printf '\(marker)%s' \"$PATH\""]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0,
              let markerRange = output.range(of: marker, options: .backwards) else { return nil }
        let path = String(output[markerRange.upperBound...])
        guard !path.isEmpty else { return nil }
        return path
    } catch {
        return nil
    }
}

private func runNeovimInsideGhostty() -> Never {
    let neovimExecutable = ProcessInfo.processInfo.environment["NEOVIM_FINDER_NVIM"]
        ?? "/opt/homebrew/bin/nvim"

    guard let encodedFiles = ProcessInfo.processInfo.environment["NEOVIM_FINDER_FILES"],
          let fileData = Data(base64Encoded: encodedFiles),
          let files = try? JSONDecoder().decode([String].self, from: fileData) else {
        FileHandle.standardError.write(Data("Invalid Neovim Finder file payload.\n".utf8))
        exit(4)
    }

    // Replace the Ghostty foreground helper instead of spawning a child.
    // A child can be placed behind Ghostty's foreground process group and be
    // suspended by terminal job control as soon as Neovim accesses the TTY.
    let arguments = [neovimExecutable, "--"] + files
    let copiedArguments = arguments.map { strdup($0) }
    defer { copiedArguments.forEach { free($0) } }
    var argumentPointers: [UnsafeMutablePointer<CChar>?] = copiedArguments.map { $0 }
    argumentPointers.append(nil)

    _ = argumentPointers.withUnsafeMutableBufferPointer { buffer in
        execv(neovimExecutable, buffer.baseAddress!)
    }
    let message = String(cString: strerror(errno))
    FileHandle.standardError.write(Data("Unable to execute Neovim: \(message)\n".utf8))
    exit(5)
}

private struct NeovimLaunch {
    let process: Process
}

private func prepareNeovimLaunch(files: [String]) throws -> NeovimLaunch {
    let osascriptExecutable = ProcessInfo.processInfo.environment["NEOVIM_FINDER_OSASCRIPT_EXECUTABLE"]
        ?? "/usr/bin/osascript"
    let ghosttyApplication = ProcessInfo.processInfo.environment["NEOVIM_FINDER_GHOSTTY_APP"]
        ?? "/Applications/Ghostty.app"

    guard FileManager.default.fileExists(atPath: ghosttyApplication) else {
        throw NSError(
            domain: bundleIdentifier,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Ghostty was not found at \(ghosttyApplication)."]
        )
    }

    let helperExecutable = Bundle.main.executablePath ?? "/Applications/Neovim.app/Contents/MacOS/Neovim"
    let helperCommand = "\(helperExecutable) --ghostty-launch"
    let encodedFiles = try JSONEncoder().encode(files).base64EncodedString()
    let resolvedPath = loginShellPath()
        ?? ProcessInfo.processInfo.environment["PATH"]
        ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    let process = Process()
    let forceAppleScript = ProcessInfo.processInfo.environment["NEOVIM_FINDER_FORCE_APPLESCRIPT"] == "1"
    let ghosttyIsRunning = !NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.mitchellh.ghostty"
    ).isEmpty

    if ghosttyIsRunning || forceAppleScript {
        process.executableURL = URL(fileURLWithPath: osascriptExecutable)
        process.arguments = [
            "-e", ghosttyAppleScript,
            "--", helperCommand, "NEOVIM_FINDER_FILES=\(encodedFiles)", "PATH=\(resolvedPath)",
        ]
    } else {
        // On a cold start AppleScript causes Ghostty to create its normal
        // initial shell window in addition to the requested Neovim window.
        // Native -e mode creates only the editor surface and automatically
        // exits the isolated Ghostty instance when Neovim finishes.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "app=$1; files=$2; editor_path=$3; helper=$4; if test -n \"$editor_path\"; then /usr/bin/open -na \"$app\" --env \"NEOVIM_FINDER_FILES=$files\" --env \"PATH=$PATH\" --env \"NEOVIM_FINDER_NVIM=$editor_path\" --args -e \"$helper\" --ghostty-launch; else /usr/bin/open -na \"$app\" --env \"NEOVIM_FINDER_FILES=$files\" --env \"PATH=$PATH\" --args -e \"$helper\" --ghostty-launch; fi; ghostty_pid=''; attempts=0; while test $attempts -lt 50; do ghostty_pid=$(/usr/bin/pgrep -n -x ghostty); test -n \"$ghostty_pid\" && break; attempts=$((attempts + 1)); /bin/sleep 0.1; done; test -z \"$ghostty_pid\" && exit 7; attempts=0; while test $attempts -lt 50; do /usr/bin/pgrep -P \"$ghostty_pid\" >/dev/null && break; attempts=$((attempts + 1)); /bin/sleep 0.1; done; while /usr/bin/pgrep -P \"$ghostty_pid\" >/dev/null; do /bin/sleep 0.2; done; /bin/kill -TERM \"$ghostty_pid\" 2>/dev/null || true",
            "neovim-finder-launch",
            ghosttyApplication,
            encodedFiles,
            ProcessInfo.processInfo.environment["NEOVIM_FINDER_NVIM"] ?? "",
            helperExecutable,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(["PATH": resolvedPath]) { _, new in new }
    }
    // Do not attach a Pipe here. Ghostty may inherit the descriptor when it
    // creates the terminal surface, so waiting for EOF can keep this helper
    // alive indefinitely even though osascript has already exited.
    process.standardError = FileHandle.standardError
    return NeovimLaunch(process: process)
}

private func registerAsDefaultEditor() -> Int32 {
    for contentType in supportedContentTypes {
        let status = LSSetDefaultRoleHandlerForContentType(
            contentType as CFString,
            .all,
            bundleIdentifier as CFString
        )
        guard status == noErr else {
            FileHandle.standardError.write(
                Data("Failed to register \(contentType): OSStatus \(status)\n".utf8)
            )
            return status
        }
    }
    return 0
}

private func checkDefaultEditorRegistration() -> Int32 {
    for contentType in supportedContentTypes {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            contentType as CFString,
            .all
        )?.takeRetainedValue() as String? else {
            FileHandle.standardError.write(
                Data("No default editor is registered for \(contentType).\n".utf8)
            )
            return 1
        }

        guard handler == bundleIdentifier else {
            FileHandle.standardError.write(
                Data("Unexpected editor for \(contentType): \(handler)\n".utf8)
            )
            return 1
        }
    }
    return 0
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedFiles = false
    private var activeLaunch: NeovimLaunch?

    private func beginLaunch(files: [String], sender: NSApplication, replyToFinder: Bool) {
        do {
            let launch = try prepareNeovimLaunch(files: files)
            activeLaunch = launch
            try launch.process.run()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                launch.process.waitUntilExit()
                DispatchQueue.main.async {
                    let succeeded = launch.process.terminationReason == .exit
                        && launch.process.terminationStatus == 0
                    if !succeeded {
                        NSAlert(error: NSError(
                            domain: bundleIdentifier,
                            code: Int(launch.process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Ghostty automation failed with status \(launch.process.terminationStatus)."]
                        )).runModal()
                    }
                    if replyToFinder {
                        sender.reply(toOpenOrPrint: succeeded ? .success : .failure)
                    }
                    self?.activeLaunch = nil
                    sender.terminate(nil)
                }
            }
        } catch {
            NSAlert(error: error).runModal()
            if replyToFinder {
                sender.reply(toOpenOrPrint: .failure)
            }
            activeLaunch = nil
            sender.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder normally delivers application(_:openFiles:) immediately after launch.
        // If the app itself was opened, start an empty Neovim session instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.openedFiles else { return }
            self.beginLaunch(files: [], sender: NSApp, replyToFinder: false)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        openedFiles = true
        beginLaunch(files: filenames, sender: sender, replyToFinder: true)
    }
}

if CommandLine.arguments.dropFirst().first == "--register-defaults" {
    exit(registerAsDefaultEditor())
}

if CommandLine.arguments.dropFirst().first == "--ghostty-launch" {
    runNeovimInsideGhostty()
}

if CommandLine.arguments.dropFirst().first == "--check-defaults" {
    exit(checkDefaultEditorRegistration())
}

if CommandLine.arguments.dropFirst().first == "--launch" {
    do {
        let launch = try prepareNeovimLaunch(files: Array(CommandLine.arguments.dropFirst(2)))
        try launch.process.run()
        launch.process.waitUntilExit()
        exit(launch.process.terminationStatus)
    } catch {
        FileHandle.standardError.write(Data("Unable to launch Ghostty: \(error)\n".utf8))
        exit(6)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
