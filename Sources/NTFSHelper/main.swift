import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: helperMachServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
