let address=ServerAddress(CommandLine.arguments[1])!,session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
var started=false,finished=false
func publish(_ attached:Bool){client.sendPosition(SIMD3<Float>(100,100,20),heading:0,moving:false,running:false,support:attached ? ("platform-fixture",SIMD3(0.126,-0.236,1.006)):nil)}
client.onConnectionState={state in if state == .ready && !started{started=true;publish(true)}}
client.onStatus={text in
 if text=="SUPPORT ATTACHED" {publish(false)}
 if text=="SUPPORT COMPLETE" {finished=true;client.disconnect()}
}
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{client.connect()}
}.resume()
let deadline=Date().addingTimeInterval(20)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
precondition(finished,"Actual native support backend did not complete")
print("PASS actual native support WebSocket: guest handshake, rounded attachment, detach")
