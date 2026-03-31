//
//  WebSocketFactory.swift
//  Multisig
//
//  Created by Mouaz on 2/22/23.
//  Copyright © 2023 Gnosis Ltd. All rights reserved.
//

import Foundation
import Starscream
import WalletConnectRelay

/// Wraps Starscream's WebSocket to conform to WebSocketConnecting without extending the imported type.
private final class StarscreamWebSocketAdapter: WebSocketConnecting {
    private let socket: WebSocket

    init(url: URL) {
        socket = WebSocket(url: url)
    }

    var isConnected: Bool { socket.isConnected }
    var onConnect: (() -> Void)? { get { socket.onConnect } set { socket.onConnect = newValue } }
    var onDisconnect: ((Error?) -> Void)? { get { socket.onDisconnect } set { socket.onDisconnect = newValue } }
    var onText: ((String) -> Void)? { get { socket.onText } set { socket.onText = newValue } }
    var request: URLRequest { get { socket.request } set { socket.request = newValue } }

    func connect() { socket.connect() }
    func disconnect() { socket.disconnect() }
    func write(string: String, completion: (() -> Void)?) { socket.write(string: string, completion: completion) }
}

struct SocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        StarscreamWebSocketAdapter(url: url)
    }
}
