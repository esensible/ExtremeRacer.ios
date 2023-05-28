import GCDWebServer

class HTTPServer: SyncDelegate {
    private let webServer = GCDWebServer()
    private var longPollClients: [([String: Any]) -> Void] = []

    init() {
    }
    
    func startHTTPServer() {
        addHandler(method: "GET", path: "/sync", sync: false, handler: syncHandler)
        addHandler(method: "POST", path: "/event", handler: eventHandler)
        addHandler(method: "POST", path: "/log", handler: logHandler)

        let subdir = Bundle.main.resourceURL!.appendingPathComponent("dist").path
        webServer.addGETHandler(forBasePath: "/app/", directoryPath: subdir, indexFilename: "index.html", cacheAge: 0, allowRangeRequests: true)

        DispatchQueue.global(qos: .background).async {
            do {
                try self.webServer.start(options: [
                    "BindToLocalhost": false,
                    "Port": 8080,
                    "AutomaticallySuspendInBackground": false
                ])
            } catch {
                print("Error starting the HTTP server: \(error)")
            }
        }
    }
    
    func eventHandler(_ json: [String: Any], _ _: [String: String]) -> (Int, [String: Any]) {
        Race.state.handleEvent(event: json)
        return (200, ["status": "success"])
    }

    func logHandler(_ json: [String: Any], _ _: [String: String]) -> (Int, [String: Any]) {
        print("Device: \(json)")
        return (200, ["status": "success"])
    }

    
    func syncHandler(_ json: [String: Any], _ queryParams: [String: String]) -> (Int, [String: Any]) {
        let stateString = queryParams["state"]
        let state = Int(stateString ?? "") ?? 0
        let deviceTimeString = queryParams["timestamp"]
        let deviceTime = Int(deviceTimeString ?? "") ?? 0
        var response: (Int, [String: Any]) = (500, [:])

        let now = Int(Date().timeIntervalSince1970 * 1000)
        print("time offset: \(now - deviceTime)")
        if deviceTime != 0 && abs(now - deviceTime) > 20 {
            let timezoneOffset = Int(TimeZone.current.secondsFromGMT(for: Date()))
            return (200, ["state": -1, "offset": now - deviceTime, "tzOffset": timezoneOffset])
        }
        
        let (newState, update) = Race.state.getUpdates(state)
        
        if (newState == state) {
            let semaphore = DispatchSemaphore(value: 0)
            
            self.longPollClients.append({ data in
                response = (200, data)
                semaphore.signal()
            })
            
            if semaphore.wait(timeout: .now() + .seconds(5)) == .timedOut {
                response = (408, ["error": "Request timed out"])
            }
        } else {
            response = (200, [
                "state": newState,
                "update": update
            ])
        }
        return response
    }

    func sync(_ state: Int, _ update: [String: Any]) {
        for (callback) in longPollClients {
            callback([
                "state": state,
                "update": update
            ])
        }
        longPollClients.removeAll()
    }
       
    private func addHandler(method: String, path: String, sync: Bool = true, handler: @escaping ([String: Any], [String: String]) -> (Int, [String: Any])) {
        if !sync {
            webServer.addHandler(forMethod: method, path: path, request: GCDWebServerDataRequest.self, asyncProcessBlock: { (request, completionBlock) in
                let dataRequest = request as! GCDWebServerDataRequest
                let jsonObject = try? JSONSerialization.jsonObject(with: dataRequest.data, options: []) as? [String: Any]
                let json = jsonObject ?? [:]
                let queryParams = dataRequest.query ?? [:]

                DispatchQueue.global(qos: .background).async {
                    let (statusCode, responseData) = handler(json, queryParams)
                    
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: responseData, options: []) else {
                        let errorResponse = GCDWebServerDataResponse()
                        errorResponse.statusCode = 500
                        completionBlock(errorResponse)
                        return
                    }
                    
                    let response = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
                    response.statusCode = statusCode
                    completionBlock(response)
                }
            })
        } else {
            webServer.addHandler(forMethod: method, path: path, request: GCDWebServerDataRequest.self) { request in
                let dataRequest = request as! GCDWebServerDataRequest
                let jsonObject = try? JSONSerialization.jsonObject(with: dataRequest.data, options: []) as? [String: Any]
                let json = jsonObject ?? [:]
                let queryParams = dataRequest.query ?? [:]

                let (statusCode, responseData) = handler(json, queryParams)
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: responseData, options: []) else {
                    let errorResponse = GCDWebServerDataResponse()
                    errorResponse.statusCode = 500
                    return errorResponse
                }
                
                let response = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
                response.statusCode = statusCode
                return response
            }
        }
    }

}
