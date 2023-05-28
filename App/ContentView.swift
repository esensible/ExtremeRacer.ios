import SwiftUI

struct ContentView: View {
    @ObservedObject var locationManager = LocationManager()
    private var httpServer =  HTTPServer()
    private var speechManager = SpeechManager()
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            if let location = locationManager.currentLocation {
                Text("Heading: \(location.heading)")
                Text("Speed: \(location.speed) m/s")
            }
        }
        .padding()
        .onAppear {
            locationManager.requestLocationPermission()
            locationManager.addDelegate(Race.state)
            locationManager.addDelegate(speechManager)
            httpServer.startHTTPServer()
            speechManager.configureAudioSession()
            Race.state.setDelegate(httpServer)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
