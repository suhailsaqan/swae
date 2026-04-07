//
//  HLSResolutionDetector.swift
//  swae
//
//  Lightweight HLS manifest parser that extracts video resolution
//  from #EXT-X-STREAM-INF lines without creating an AVPlayer.
//

import Foundation

struct HLSResolutionDetector {

    struct Resolution {
        let width: Int
        let height: Int
        var isPortrait: Bool { height > width }
        var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }
    }

    /// Fetches the HLS master playlist and parses the highest RESOLUTION= tag.
    /// Completes on a background thread. Timeout: 5 seconds.
    /// Returns nil if the URL is not HLS, the fetch fails, or no RESOLUTION is found.
    static func detect(from url: URL, completion: @escaping (Resolution?) -> Void) {
        let urlString = url.absoluteString.lowercased()
        guard urlString.contains("m3u8") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .returnCacheDataElseLoad

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let manifest = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }

            var bestResolution: Resolution?
            var bestPixelCount = 0

            for line in manifest.components(separatedBy: .newlines) {
                guard line.hasPrefix("#EXT-X-STREAM-INF"),
                      let resRange = line.range(of: "RESOLUTION=") else { continue }

                let afterRes = line[resRange.upperBound...]
                let resString = afterRes.prefix(while: { $0 != "," && $0 != "\n" && $0 != " " })
                let parts = resString.split(separator: "x")
                guard parts.count == 2,
                      let w = Int(parts[0]), let h = Int(parts[1]),
                      w > 0, h > 0 else { continue }

                let pixels = w * h
                if pixels > bestPixelCount {
                    bestPixelCount = pixels
                    bestResolution = Resolution(width: w, height: h)
                }
            }
            completion(bestResolution)
        }.resume()
    }
}
