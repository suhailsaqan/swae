//
//  Constants.swift
//  swae
//
//  Created by Suhail Saqan on 1/20/25.
//

import Logboard

public let swaeIdentifier = "com.suhail.swae"
nonisolated(unsafe) let elogger = LBLogger.with(swaeIdentifier)

// MARK: - Zap Stream Core
public let defaultZapStreamCoreBaseUrl = "https://api-core.zap.stream"
public let defaultZapStreamCoreRtmpUrl = "\(defaultZapStreamCoreBaseUrl)/rtmp"
public let zapStreamCoreRtmpIngestBasic = "rtmp://in.core.zap.stream:1935/basic"
public let zapStreamCoreRtmpIngestGood = "rtmp://in.core.zap.stream:1935/good"
