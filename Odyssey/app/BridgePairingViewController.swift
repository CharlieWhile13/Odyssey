//
//  BridgePairingViewController.swift
//  Odyssey
//
//  Created by Amy While on 24/11/2020.
//  Copyright © 2020 coolstar. All rights reserved.
//

import UIKit
import Network

enum PairingError {
    case wifi
    case networkError
    case noneFound
    case bridgeConnectionError
    case bridgeError
    
    var error: String {
        switch self {
        case.wifi: return "Not on WiFi"
        case.networkError: return "Network Error"
        case.noneFound: return "No Bridges Found"
        case.bridgeConnectionError: return "Bridge Connectivity Error"
        case.bridgeError: return "Unknown Error with Bridge"
        }
    }
}

struct DiscoveredBridge {
    var displayName: String!
    var ip: String!
    var paired: Bool!
    var ignore: Bool!
    
    init(displayName: String?, ip: String?, paired: Bool?, ignore: Bool?) {
        self.displayName = displayName
        self.ip = ip
        self.paired = paired
        self.ignore = ignore
    }
}

class BridgePairingViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var rescan: UIButton!
    @IBOutlet weak var errorLabel: UILabel!
    
    let monitor = NWPathMonitor()
    
    var discoveredBridges = [DiscoveredBridge]()
    var timer: Timer?
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        monitor.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.setup()
    }
    
    func setup() {
        self.errorLabel.isHidden = true
        self.errorLabel.adjustsFontSizeToFitWidth = true
        self.rescan.isHidden = true
        self.rescan.layer.borderColor = UIColor.label.cgColor
        
        self.setupNetworkChecking()
        
        //Make it transparent
        self.tableView.backgroundColor = .none
        //Removes cells that don't exist
        self.tableView.tableFooterView = UIView()
        //Disable the seperator lines, make it look nice :)
        self.tableView.separatorStyle = UITableViewCell.SeparatorStyle.none
        //Disable the scroll indicators
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.showsHorizontalScrollIndicator = false
        //Register the cell from nib
        self.tableView.register(UINib(nibName: "BridgeCell", bundle: nil), forCellReuseIdentifier: "Shade.BridgeCell")
        //Set the delegate/source
        self.tableView.delegate = self
        self.tableView.dataSource = self
        //Bouncy Boi
        self.tableView.alwaysBounceVertical = false
    }
    
    
    func setupNetworkChecking() {
        monitor.pathUpdateHandler = { path in
            self.isOnNetwork(path)
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    func isOnNetwork(_ path: NWPath) {
        DispatchQueue.main.async {
            if !(path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)) {
                self.errorWith(PairingError.wifi.error)
                self.rescan.isHidden = true
            } else {
                self.loadup()
                self.queryBridges()
            }
        }
    }
    
    func errorWith(_ reason: String) {
        self.errorLabel.text = reason
        self.errorLabel.isHidden = false
        self.rescan.isHidden = false
    }
    
    @objc func attemptPairing() {
        let body = [
                "devicetype" : "Odyssey#\(UIDevice.current.name)"
            ]
        let bodyString = NetworkManager.shared.generateStringFromDict(body)
        
        for (index, bridge) in self.discoveredBridges.enumerated() {
            if bridge.paired || bridge.ignore { continue }
            if let url = URL(string: "http://\(bridge.ip!)/api") {
                NetworkManager.shared.request(url: url, method: "POST", headers: nil, jsonbody: bodyString, completion: { (success, dict) -> Void in
                    DispatchQueue.main.async {
                        if success {
                            if dict.count != 1 {
                                self.errorWith(PairingError.bridgeError.error)
                                return
                            }
                            let response = dict.first
                            if let error = response?["error"] as? [String : Any] {
                                if let description = error["description"] {
                                    if description as! String == "link button not pressed" {
                                        let bridge = self.discoveredBridges[index]
                                        self.discoveredBridges[index].displayName = "Press Button : \(bridge.ip!)"
                                        self.tableView.reloadData()
                                        self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.attemptPairing), userInfo: nil, repeats: false)
                                    } else {
                                        return
                                    }
                                }
                            } else if let success = response?["success"] as? [String : Any] {
                                if let username = success["username"] as? String {
                                    BridgeManager.shared.addBridge(ip: bridge.ip!, username: username)
                                    let bridge = self.discoveredBridges[index]
                                    self.discoveredBridges[index].displayName = "Paired : \(bridge.ip!)"
                                    self.discoveredBridges[index].paired = true
                                    LightManager.shared.grabLightsFromBridge()
                                    self.tableView.reloadData()
                                } else {
                                    self.errorWith(PairingError.bridgeError.error)
                                    self.timer?.invalidate()
                                    return
                                }
                            }
                        } else {
                            self.discoveredBridges.remove(at: index)
                            var hasFound = false
                            for bridge in self.discoveredBridges {
                                if bridge.paired {
                                    hasFound = true
                                }
                            }
                            
                            self.tableView.reloadData()
                        }
                    }
                })
            }
        }
    }
    
    func queryBridges() {
        let surl = "https://discovery.meethue.com"
        
        if let url = URL(string: surl) {
            NetworkManager.shared.request(url: url, method: "GET", headers: nil, jsonbody: nil, completion: { (success, dict) -> Void in
                DispatchQueue.main.async {
                    if success {
                        self.discoveredBridges.removeAll()
                        if dict.count == 0 {
                            self.errorWith(PairingError.noneFound.error)
                            return
                        }
                        self.loadup()

                        for bridge in dict {
                            let ip = bridge["internalipaddress"] as? String ?? ""
                            var found = false
                            for bridges in BridgeManager.shared.bridges {
                                if !found {
                                    if bridges.ip == ip {
                                        let bridgeObject = DiscoveredBridge(displayName: "Paired : \(ip)", ip: ip, paired: true, ignore: false)
                                        self.discoveredBridges.append(bridgeObject)
                                        found = true
                                    }
                                }
                            }
                            
                            if !found {
                                let bridgeObject = DiscoveredBridge(displayName: ip, ip: ip, paired: false, ignore: false)
                                self.discoveredBridges.append(bridgeObject)
                            }
                        }
                                            
                        self.rescan.isHidden = false
                        self.tableView.reloadData()
                        self.attemptPairing()
                        
                    } else {
                        self.errorWith(PairingError.networkError.error)
                    }
                }
            })
        }
    }
    
    func loadup() {
        self.errorLabel.isHidden = true
        self.rescan.isHidden = true
    }
    
    func createErrorAlert(_ title: String, _ text: String) {
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func rescan(_ sender: Any) {
        self.timer?.invalidate()
        self.queryBridges()
    }
}

extension BridgePairingViewController : UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        //Make it invisible when you press it
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension BridgePairingViewController : UITableViewDataSource {

    //This is just meant to be
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.discoveredBridges.count
    }
    
    //This is what handles all the images and text etc, using the class mainScreenTableCells
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Shade.BridgeCell", for: indexPath) as! BridgeCell
        
        cell.label.text = self.discoveredBridges[indexPath.row].displayName
        cell.hueImageView.image = UIImage(named: "BridgeIcon")
        cell.minHeight = 50
        
        return cell
    }
}
