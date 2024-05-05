//
//  File.swift
//  
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

public extension Request {
    /// Access mixpanel
    var mixpanel: Application.MixpanelClient {
        .init(application: application, request: self)
    }
}
