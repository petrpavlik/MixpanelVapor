//
//  File.swift
//
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

extension Request {
    /// Access mixpanel
    public var mixpanel: Application.MixpanelClient {
        .init(application: application)
    }
}
