import SwiftUI

#if canImport(UIKit)
    import SafariServices

    /// A web page in Safari inside the app, for a trailer on the web. Only `https` pages are ever passed in.
    struct WebPageView: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> SFSafariViewController {
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = false
            return SFSafariViewController(url: url, configuration: configuration)
        }

        func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    }
#else
    /// A web page, opened in the default browser on platforms without Safari's view.
    struct WebPageView: View {
        let url: URL

        var body: some View {
            Link(url.absoluteString, destination: url)
        }
    }
#endif
