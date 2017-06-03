//
//  BitstampExchange.swift
//  CoinTicker
//
//  Created by Alec Ananian on 5/30/17.
//  Copyright © 2017 Alec Ananian. All rights reserved.
//

import Foundation
import Alamofire
import Starscream

class BitstampExchange: Exchange {
    
    private struct Constants {
        static let WebSocketURL = URL(string: "wss://ws.pusherapp.com/app/de504dc5763aeef9ff52?protocol=7")!
        static let TickerAPIPath = "https://www.bitstamp.net/api/v2/ticker/%{productId}/"
    }
    
    private var socket = WebSocket(url: Constants.WebSocketURL)
    
    init(delegate: ExchangeDelegate) {
        super.init(site: .bitstamp, delegate: delegate, currencyMatrix: [
            .bitcoin: [.usd, .eur],
            .ripple: [.usd, .eur, .bitcoin]
        ])
        
        socket.callbackQueue = DispatchQueue(label: "com.alecananian.cointicker.bitstamp-socket", qos: .utility, attributes: [.concurrent])
    }
    
    override func start() {
        let productId = "\(baseCurrency.code)\(displayCurrency.code)".lowercased()
        
        let queue = DispatchQueue(label: "com.alecananian.cointicker.bitstamp-http", qos: .utility, attributes: [.concurrent])
        Alamofire.request(Constants.TickerAPIPath.replacingOccurrences(of: "%{productId}", with: productId)).response(queue: queue, responseSerializer: DataRequest.jsonResponseSerializer()) { [unowned self] (response) in
            if let tickerData = response.result.value as? [String: Any], let priceString = tickerData["last"] as? String, let price = Double(priceString) {
                self.delegate.exchange(self, didUpdatePrice: price)
            }
        }
        
        socket.onConnect = { [unowned self] in
            var channelName = "live_trades"
            if productId != "btcusd" {
                channelName += "_\(productId)"
            }
            
            let eventParams: [String: Any] = [
                "event": "pusher:subscribe",
                "data": [
                    "channel": channelName
                ]
            ]
            
            do {
                let eventJSON = try JSONSerialization.data(withJSONObject: eventParams, options: [])
                if let eventString = String(data: eventJSON, encoding: .utf8) {
                    self.socket.write(string: eventString)
                }
            } catch {
                print(error)
            }
        }
        
        socket.onText = { [unowned self] (text: String) in
            if let responseData = text.data(using: .utf8, allowLossyConversion: false) {
                do {
                    if let responseJSON = try JSONSerialization.jsonObject(with: responseData, options: .mutableContainers) as? [String: Any] {
                        if let type = responseJSON["event"] as? String, type == "trade" {
                            if let data = (responseJSON["data"] as? String)?.data(using: .utf8), let subResponseJSON = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                                if let priceNumber = subResponseJSON["price"] as? NSNumber {
                                    self.delegate.exchange(self, didUpdatePrice: priceNumber.doubleValue)
                                }
                            }
                        }
                    }
                } catch {
                    print(error)
                }
            }
        }
        
        socket.connect()
    }
    
    override func stop() {
        socket.disconnect()
    }

}
