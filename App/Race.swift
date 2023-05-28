import Foundation

fileprivate class VersionedDict {
    var store: [String: (Int, Any)] = [:]
    private var currentState: Int = 1

    init(_ initialState: [String: Any]) {
        store = initialState.mapValues { (currentState, $0) }
    }
    
    func update(_ newState: [String: Any], _ reset: Bool = false) {
        currentState += 1
        if reset {
            store = newState.mapValues { (currentState, $0) }
        } else {
            for (key, value) in newState {
                if let (_, currentValue) = store[key], currentValue as? NSObject == value as? NSObject {
                    continue
                }
                store[key] = (currentState, value)
            }
        }
    }

    func getUpdates(_ state: Int) -> (Int, [String: Any]) {
        guard state < currentState else {
            return (currentState, [:])
        }
        let state = (state == -1) ? (currentState - 1) : state
        
        var updates = [String: Any]()
        for (key, value) in store {
            let (version, actualValue) = value
            if version > state {
                updates[key] = actualValue
            }
        }
        return (currentState, updates)
    }
}

protocol SyncDelegate: AnyObject {
    func sync(_ state: Int, _ response: [String: Any])
}

class Race: LocationUpdateDelegate {
    static let state = Race()

    private var currentLocation: Location?
    private enum State: Int {
        case STATE_INIT = 0
        case STATE_IDLE = 1
        case STATE_SEQ = 2
        case STATE_RACE = 3
    }
    private var startTimeout: Timer?
    private var delegate: SyncDelegate?
    private var stateStore = VersionedDict(["state": State.STATE_INIT.rawValue])

    func setDelegate(_ delegate: SyncDelegate) {
        self.delegate = delegate
    }
    
    func handleEvent(event: [String: Any]) {
        let now = Date().timeIntervalSince1970 * 1000

        print(event)
        switch event["event"] as? String {
        case "setup/push_off":
            stateStore.update(["state": State.STATE_IDLE.rawValue], true)

        case "idle/seq":
            guard let eventTimestamp = event["timestamp"] as? Double,
                  let eventSeconds = event["seconds"] as? Double else {
                print("Error: Invalid event timestamp or seconds")
                return
            }
            let startTime = eventTimestamp + eventSeconds * 1000
            let delta = startTime - now
            DispatchQueue.main.async {
                self.startTimeout = Timer.scheduledTimer(withTimeInterval: delta / 1000, repeats: false) { _ in
                    print("we are here")
                    self.raceStart()
                }
            }
            
            stateStore.update([
                "state": State.STATE_SEQ.rawValue,
                "startTime": startTime
            ], true)

        case "seq/bump":
            startTimeout?.invalidate()
//            assert(state["state"] as? Int == State.STATE_SEQ.rawValue)
            
            guard let eventSeconds = event["seconds"] as? Double,
                  let eventTimestamp = event["timestamp"] as? Double else {
                print("Error: Invalid event seconds or timestamp")
                return
            }
            let startTimeVer = stateStore.store["startTime"] ?? (0, 0.0 as Any)
            let startTime = startTimeVer.1 as? Double ?? 0.0
            
            let newStartTime = eventSeconds == 0 ?
                (startTime - eventTimestamp).truncatingRemainder(dividingBy: 60000) :
                startTime - eventSeconds * 1000

            if newStartTime <= now + 500 {
                stateStore.update([
                    "state": State.STATE_RACE.rawValue,
                    "startTime": newStartTime
                ], true)
            } else {
                let delta = newStartTime - now
                print("bumped to: \(delta)")
                stateStore.update(["startTime": newStartTime])
                DispatchQueue.main.async {
                    self.startTimeout = Timer.scheduledTimer(withTimeInterval: delta / 1000, repeats: false) { _ in
                        self.raceStart()
                    }
                }
            }
        case "race/finish":
//            assert(state["state"] as? Int == State.STATE_RACE.rawValue)
            stateStore.update(["state": State.STATE_IDLE.rawValue], true)
        case "line/stbd":
            break
        case "line/port":
            break
        default:
            print("Unknown event: \(String(describing: event["event"]))")
            assert(false)
        }
        let (version, update) = stateStore.getUpdates(-1)
        delegate?.sync(version, update)
    }
    
    
    func raceStart() {
        let startTimeVer = stateStore.store["startTime"] ?? (0, 0.0 as Any)
        let startTime = startTimeVer.1 as? Double ?? 0.0

        stateStore.update([
            "state": State.STATE_RACE.rawValue,
            "startTime": startTime
        ], true)
        print("RACE!!")
        let (version, update) = stateStore.getUpdates(-1)
        delegate?.sync(version, update)
    }
    
    func getUpdates(_ state: Int)  -> (Int, [String: Any]) {
        return stateStore.getUpdates(state)
    }

    // LocationUpdateDelegate method
    func didUpdateLocation(location: Location) {
        if (location.speed == -1) {
            return
        }
        
        stateStore.update([
//            "heading": String(format: "%.0f", location.heading),
            "heading": String(format: "%.f", location.horizontalAccuracy),
            "speed": String(format: "%.1f", location.speed)
        ])
        let (version, update) = stateStore.getUpdates(-1)
        delegate?.sync(version, update)
    }

}
