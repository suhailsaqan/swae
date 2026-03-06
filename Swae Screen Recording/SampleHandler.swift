//
//  SampleHandler.swift
//  Swae Screen Recording
//
//  Created by Suhail Saqan on 8/21/25.
//

import ReplayKit

class SampleHandler: RPBroadcastSampleHandler {
    var sampleBufferSender = SampleBufferSender()

    override func broadcastStarted(withSetupInfo _: [String: NSObject]?) {
        sampleBufferSender.start(appGroup: swaeAppGroup)
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        sampleBufferSender.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        switch type {
        case .video:
            sampleBufferSender.send(sampleBuffer, type)
        case .audioApp:
            sampleBufferSender.send(sampleBuffer, type)
        default:
            break
        }
    }
}
