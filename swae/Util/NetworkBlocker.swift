//
//  NetworkBlocker.swift
//  swae
//
//  Blocks all network requests at the URLProtocol level
//

import Foundation

class NetworkBlocker: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        // Block the request by returning an error
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "Network access is disabled"]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }
    
    override func stopLoading() {
        // Nothing to stop
    }
}
