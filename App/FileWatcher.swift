import Dispatch
import Foundation
import Darwin

final class FileWatcher {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(
        url: URL,
        queue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        self.descriptor = descriptor
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler(handler: handler)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
