import Foundation

/// Privileged helper tool for controlling AWDL interface
/// Usage: AWDLControlHelper <interface> <up|down>
///
/// This tool should be installed at /Library/PrivilegedHelperTools/com.awdlcontrol.helper
/// with setuid root permissions to allow network interface control without prompting

func main() {
    guard CommandLine.arguments.count == 3 else {
        print("Usage: AWDLControlHelper <interface> <up|down>")
        exit(1)
    }

    let interface = CommandLine.arguments[1]
    let command = CommandLine.arguments[2]

    // Validate interface name to prevent command injection
    guard interface.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil else {
        print("Error: Invalid interface name")
        exit(1)
    }

    // Validate command
    guard command == "up" || command == "down" else {
        print("Error: Command must be 'up' or 'down'")
        exit(1)
    }

    // Execute ifconfig command
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    task.arguments = [interface, command]

    do {
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
            print("Successfully set \(interface) \(command)")
            exit(0)
        } else {
            print("Error: ifconfig command failed")
            exit(1)
        }
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

main()
