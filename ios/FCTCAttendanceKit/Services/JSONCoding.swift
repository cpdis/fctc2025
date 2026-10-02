//
//  JSONCoding.swift
//  FCTCAttendanceKit
//
//  One encoder and one decoder for the stored JSON blobs and the shared-guest
//  payloads (audit CA-21). The model properties that decode them run on every
//  render, and a fresh coder per read was the hottest frame in a sample.
//  Both coders use the default strategies; a payload that needs its own
//  strategies keeps its own instance (see SheetAPI).
//

import Foundation

public enum JSONCoding {
    public static let encoder = JSONEncoder()
    public static let decoder = JSONDecoder()
}
